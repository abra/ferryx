//! A WebDAV server over a temporary folder: dav-server on hyper, behind
//! HTTP Basic authentication, over plain HTTP or TLS.

use std::convert::Infallible;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use base64::Engine;
use dav_server::body::Body;
use dav_server::fakels::FakeLs;
use dav_server::localfs::LocalFs;
use dav_server::DavHandler;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use rustls::ServerConfig;
use tempfile::TempDir;
use tokio::net::TcpListener;

use crate::server_runtime;

/// How the server behaves.
#[derive(Clone)]
pub struct DavOptions {
    /// `None`: no login asked.
    pub user: Option<String>,
    pub password: String,
    /// Served over TLS with this certificate.
    pub tls: Option<Arc<ServerConfig>>,
}

impl Default for DavOptions {
    fn default() -> Self {
        DavOptions { user: Some("me".into()), password: "secret".into(), tls: None }
    }
}

/// A running server; dropped, it stops and its folder goes.
pub struct DavServer {
    pub port: u16,
    pub root: TempDir,
    /// Requests refused for want of the right login.
    pub refused: Arc<AtomicUsize>,
    stop: Option<tokio::sync::oneshot::Sender<()>>,
}

impl DavServer {
    pub fn start(options: DavOptions) -> DavServer {
        let root = tempfile::tempdir().expect("a folder to serve");
        let runtime = server_runtime();
        let listener = runtime.block_on(TcpListener::bind("127.0.0.1:0")).expect("a port");
        let port = listener.local_addr().expect("an address").port();
        let handler = DavHandler::builder()
            .filesystem(LocalFs::new(root.path(), false, false, false))
            .locksystem(FakeLs::new())
            .build_handler();
        let refused = Arc::new(AtomicUsize::new(0));
        let (stop, mut stopped) = tokio::sync::oneshot::channel::<()>();
        let expected = options.user.as_ref().map(|user| {
            let pair = format!("{user}:{}", options.password);
            format!("Basic {}", base64::engine::general_purpose::STANDARD.encode(pair))
        });
        let acceptor = options.tls.clone().map(tokio_rustls::TlsAcceptor::from);
        let counter = refused.clone();
        runtime.spawn(async move {
            loop {
                let accepted = tokio::select! {
                    accepted = listener.accept() => accepted,
                    _ = &mut stopped => break,
                };
                let Ok((stream, _)) = accepted else { continue };
                let handler = handler.clone();
                let expected = expected.clone();
                let counter = counter.clone();
                let acceptor = acceptor.clone();
                tokio::spawn(async move {
                    let service = service_fn(move |request: Request<hyper::body::Incoming>| {
                        let handler = handler.clone();
                        let expected = expected.clone();
                        let counter = counter.clone();
                        async move {
                            let given = request
                                .headers()
                                .get("authorization")
                                .and_then(|v| v.to_str().ok())
                                .map(str::to_string);
                            if let Some(expected) = expected {
                                if given.as_deref() != Some(expected.as_str()) {
                                    counter.fetch_add(1, Ordering::SeqCst);
                                    let response = Response::builder()
                                        .status(StatusCode::UNAUTHORIZED)
                                        .header("WWW-Authenticate", "Basic realm=\"test\"")
                                        .body(Body::from("login, please"))
                                        .expect("a response");
                                    return Ok::<_, Infallible>(response);
                                }
                            }
                            Ok::<_, Infallible>(handler.handle(request).await)
                        }
                    });
                    match acceptor {
                        Some(acceptor) => {
                            if let Ok(tls) = acceptor.accept(stream).await {
                                let _ =
                                    http1::Builder::new().serve_connection(TokioIo::new(tls), service).await;
                            }
                        }
                        None => {
                            let _ =
                                http1::Builder::new().serve_connection(TokioIo::new(stream), service).await;
                        }
                    }
                });
            }
        });
        DavServer { port, root, refused, stop: Some(stop) }
    }

    pub fn path(&self, path: &str) -> PathBuf {
        self.root.path().join(path.trim_start_matches('/'))
    }
}

impl Drop for DavServer {
    fn drop(&mut self) {
        if let Some(stop) = self.stop.take() {
            let _ = stop.send(());
        }
    }
}
