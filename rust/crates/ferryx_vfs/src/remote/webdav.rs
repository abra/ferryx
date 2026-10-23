//! WebDAV (RFC 4918) over HTTP and HTTPS, through `reqwest` on rustls:
//! `PROPFIND` lists (parsed with `quick-xml`), `GET` reads (with a `Range`
//! for a part), `PUT` writes as a stream, `MKCOL`, `MOVE`, `COPY` and
//! `DELETE` do the rest. HTTP is stateless: the client keeps its own pool
//! of connections and drops idle ones, so "lost" here only means the
//! server stopped answering.
//!
//! Logging in is HTTP Basic (over HTTPS it is as safe as the connection;
//! over plain HTTP the interface says it is not). The server stamps what
//! it receives with its own time: WebDAV has no standard way to set it.

use std::collections::HashMap;
use std::io;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use bytes::Bytes;
use chrono::DateTime;
use ferryx_core::entry::{Entry, EntryKind};
use parking_lot::Mutex;
use quick_xml::events::Event;
use quick_xml::Reader;
use reqwest::header::{HeaderValue, CONTENT_LENGTH, RANGE};
use reqwest::{Client, Method, RequestBuilder, Response, StatusCode};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;

use super::address::{join, name, normalize, ServerAddress};
use super::connection::{ConnectSpec, Notifier};
use super::entries::{entry, RemoteMeta};
use super::prompt::{self, Question};
use super::runtime::{self, run, timed_out, Stop, CONNECT_TIMEOUT, REQUEST_TIMEOUT};
use super::{secrets, tls, RemoteCaps, RemoteFs, RemoteRead, RemoteWrite};
use crate::error::{VfsError, VfsErrorKind, VfsResult};

/// The properties a listing asks for.
const PROPFIND_BODY: &str = r#"<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:creationdate/></d:prop></d:propfind>"#;

/// Chunks a write keeps in flight to the request.
const QUEUED_CHUNKS: usize = 8;

/// One server over WebDAV.
pub struct DavFs {
    address: ServerAddress,
    client: Mutex<Client>,
    password: Mutex<Option<String>>,
    notifier: Notifier,
    lost: AtomicBool,
    home: String,
}

impl DavFs {
    /// Checks that the address's folder answers, asking for a password
    /// when the server wants one.
    pub fn connect(spec: &ConnectSpec, notifier: Notifier, stop: Stop) -> VfsResult<DavFs> {
        let address = ServerAddress { password: None, ..spec.address.clone() };
        let home = if spec.address.path.is_empty() { "/".to_string() } else { normalize(&spec.address.path) };
        let fs = DavFs {
            client: Mutex::new(new_client()?),
            password: Mutex::new(spec.address.password.clone()),
            address,
            notifier,
            lost: AtomicBool::new(false),
            home,
        };
        fs.log_in(stop)?;
        Ok(fs)
    }

    /// Asks for the home folder until the server lets the user in: with
    /// the address's password, the keychain's, then the user's.
    fn log_in(&self, stop: Stop) -> VfsResult<()> {
        let server = self.address.key();
        let mut keychain_tried = false;
        let mut keychain_had = false;
        let mut asked: Option<(String, bool)> = None;
        for _ in 0..6 {
            match self.propfind(&self.home, "0", stop) {
                Ok(_) => {
                    if let Some((password, remember)) = asked {
                        if remember {
                            let _ = secrets::store().set(&server, &password);
                        } else if keychain_had {
                            // The keychain's one is wrong and the new one
                            // is not to be kept: forget it.
                            let _ = secrets::store().delete(&server);
                        }
                    }
                    return Ok(());
                }
                Err(error) if error.kind == VfsErrorKind::AuthFailed => {
                    if self.address.user.is_empty() {
                        return Err(VfsError::new(
                            VfsErrorKind::AuthFailed,
                            None,
                            format!("{} asks for a login: add a user name to the address", self.address.host),
                        ));
                    }
                    // The request carried a password, and it was refused.
                    let refused = self.password.lock().is_some();
                    let stored = if keychain_tried {
                        None
                    } else {
                        keychain_tried = true;
                        secrets::store().get(&server)
                    };
                    let next = match stored {
                        Some(stored) => {
                            keychain_had = true;
                            stored
                        }
                        None => self.ask(refused, &mut asked, stop)?,
                    };
                    *self.password.lock() = Some(next);
                }
                Err(error) => return Err(error),
            }
        }
        Err(VfsError::new(
            VfsErrorKind::AuthFailed,
            None,
            format!("{}@{} did not accept the login", self.address.user, self.address.host),
        ))
    }

    fn ask(&self, retry: bool, asked: &mut Option<(String, bool)>, stop: Stop) -> VfsResult<String> {
        let answer = prompt::ask_blocking(
            Question::Password { server: self.address.key(), user: self.address.user.clone(), retry },
            stop,
        );
        if stop() {
            return Err(VfsError::cancelled());
        }
        match (answer.accept, answer.text()) {
            (true, Some(text)) => {
                *asked = Some((text.to_string(), answer.remember));
                Ok(text.to_string())
            }
            _ => Err(VfsError::cancelled()),
        }
    }

    fn request(&self, method: Method, path: &str) -> RequestBuilder {
        let builder = self.client.lock().request(method, self.address.http_url(path));
        let password = self.password.lock().clone();
        if self.address.user.is_empty() {
            builder
        } else {
            builder.basic_auth(&self.address.user, password)
        }
    }

    /// Sends a request built by `build`; a server that stopped answering
    /// is reported lost, and back when it answers.
    fn send_raw(
        &self,
        path: &str,
        stop: Stop,
        build: impl FnOnce() -> RequestBuilder,
    ) -> VfsResult<Response> {
        let request = build();
        let sent =
            run(async { request.send().await.map_err(|e| http_error(&e, path)) }, REQUEST_TIMEOUT, stop);
        match &sent {
            Ok(_) => {
                if self.lost.swap(false, Ordering::SeqCst) {
                    self.notifier.restored();
                }
            }
            Err(error) => {
                if error.is_connection_error() && !self.lost.swap(true, Ordering::SeqCst) {
                    self.notifier.lost();
                }
            }
        }
        sent
    }

    /// [`DavFs::send_raw`], an answer other than a success turned into an
    /// error of its kind.
    fn send(&self, path: &str, stop: Stop, build: impl FnOnce() -> RequestBuilder) -> VfsResult<Response> {
        check(self.send_raw(path, stop, build)?, path)
    }

    fn propfind(&self, path: &str, depth: &'static str, stop: Stop) -> VfsResult<Vec<DavRow>> {
        let target = collection_path(path);
        let response = self.send(path, stop, || {
            self.request(Method::from_bytes(b"PROPFIND").expect("a valid method"), &target)
                .header("Depth", depth)
                .header("Content-Type", "application/xml; charset=utf-8")
                .body(PROPFIND_BODY)
        })?;
        let text =
            run(async { response.text().await.map_err(|e| http_error(&e, path)) }, REQUEST_TIMEOUT, stop)?;
        parse_multistatus(&text)
            .map_err(|why| VfsError::remote(VfsErrorKind::Io, Some(path), format!("{path}: {why}")))
    }

    fn destination(&self, path: &str) -> VfsResult<HeaderValue> {
        HeaderValue::from_str(&self.address.http_url(path)).map_err(|_| {
            VfsError::remote(VfsErrorKind::InvalidName, Some(path), format!("“{path}” is not a valid name"))
        })
    }
}

impl RemoteFs for DavFs {
    fn home(&self) -> String {
        self.home.clone()
    }

    fn caps(&self) -> RemoteCaps {
        RemoteCaps { set_modified: false, server_copy: true, recursive_delete: true }
    }

    fn list(&self, dir: &str, stop: Stop) -> VfsResult<Vec<Entry>> {
        let own = normalize(dir);
        Ok(self
            .propfind(dir, "1", stop)?
            .into_iter()
            .filter(|row| normalize(&row.path) != own)
            .filter_map(|row| {
                let name = name(&row.path).to_string();
                (!name.is_empty()).then(|| entry(&name, join(&own, &name), row.meta))
            })
            .collect())
    }

    fn stat(&self, path: &str, stop: Stop) -> VfsResult<Option<Entry>> {
        match self.propfind(path, "0", stop) {
            Ok(rows) => Ok(rows.into_iter().next().map(|row| entry(name(path), path.to_string(), row.meta))),
            Err(error) if error.kind == VfsErrorKind::NotFound => Ok(None),
            Err(error) => Err(error),
        }
    }

    fn read_range(&self, path: &str, offset: u64, len: usize, stop: Stop) -> VfsResult<Vec<u8>> {
        if len == 0 {
            return Ok(Vec::new());
        }
        let range = format!("bytes={offset}-{}", offset + len as u64 - 1);
        let response = self.send_raw(path, stop, || self.request(Method::GET, path).header(RANGE, range))?;
        // 416: the range starts past the end.
        if response.status() == StatusCode::RANGE_NOT_SATISFIABLE {
            return Ok(Vec::new());
        }
        let response = check(response, path)?;
        // A server that ignores the range sends the whole file: skip to
        // the part asked for.
        let mut skip = if response.status() == StatusCode::PARTIAL_CONTENT { 0 } else { offset };
        let mut reader =
            DavReader { response: Some(response), pending: Bytes::new(), path: path.to_string() };
        let mut out = Vec::with_capacity(len);
        let mut buffer = vec![0u8; 64 * 1024];
        while out.len() < len {
            let n = reader.read(&mut buffer, stop)?;
            if n == 0 {
                break;
            }
            let mut chunk = &buffer[..n];
            if skip > 0 {
                let dropped = (skip as usize).min(chunk.len());
                chunk = &chunk[dropped..];
                skip -= dropped as u64;
            }
            let room = len - out.len();
            out.extend_from_slice(&chunk[..chunk.len().min(room)]);
        }
        Ok(out)
    }

    fn open_read<'a>(&'a self, path: &str, stop: Stop) -> VfsResult<Box<dyn RemoteRead + 'a>> {
        let response = self.send(path, stop, || self.request(Method::GET, path))?;
        Ok(Box::new(DavReader { response: Some(response), pending: Bytes::new(), path: path.to_string() }))
    }

    fn create<'a>(
        &'a self,
        path: &str,
        size: Option<u64>,
        _stop: Stop,
    ) -> VfsResult<Box<dyn RemoteWrite + 'a>> {
        let (sender, receiver) = mpsc::channel::<Result<Bytes, io::Error>>(QUEUED_CHUNKS);
        let body = futures_util::stream::unfold(receiver, |mut receiver| async move {
            receiver.recv().await.map(|chunk| (chunk, receiver))
        });
        let mut request = self.request(Method::PUT, path).body(reqwest::Body::wrap_stream(body));
        if let Some(size) = size {
            request = request.header(CONTENT_LENGTH, size);
        }
        let shown = path.to_string();
        let task = runtime::runtime().spawn(async move {
            let response = request.send().await.map_err(|e| http_error(&e, &shown))?;
            check(response, &shown).map(|_| ())
        });
        Ok(Box::new(DavWriter { sender: Some(sender), task: Some(task), path: path.to_string() }))
    }

    fn mkdir(&self, path: &str, stop: Stop) -> VfsResult<()> {
        let response = self.send_raw(path, stop, || {
            self.request(Method::from_bytes(b"MKCOL").expect("a valid method"), &collection_path(path))
        })?;
        // 405: something is there already.
        if response.status() == StatusCode::METHOD_NOT_ALLOWED {
            return Err(VfsError::remote(
                VfsErrorKind::AlreadyExists,
                Some(path),
                format!("{path} already exists"),
            ));
        }
        check(response, path).map(|_| ())
    }

    fn rename(&self, from: &str, to: &str, stop: Stop) -> VfsResult<()> {
        let destination = self.destination(to)?;
        let response = self.send_raw(from, stop, || {
            self.request(Method::from_bytes(b"MOVE").expect("a valid method"), from)
                .header("Destination", destination)
                .header("Overwrite", "F")
        })?;
        taken(response, from, to)
    }

    fn remove_file(&self, path: &str, stop: Stop) -> VfsResult<()> {
        self.send(path, stop, || self.request(Method::DELETE, path)).map(|_| ())
    }

    fn remove_dir(&self, path: &str, stop: Stop) -> VfsResult<()> {
        self.send(path, stop, || self.request(Method::DELETE, &collection_path(path))).map(|_| ())
    }

    fn copy(&self, from: &str, to: &str, stop: Stop) -> VfsResult<()> {
        let destination = self.destination(to)?;
        let response = self.send_raw(from, stop, || {
            self.request(Method::from_bytes(b"COPY").expect("a valid method"), from)
                .header("Destination", destination)
                .header("Depth", "infinity")
                .header("Overwrite", "F")
        })?;
        taken(response, from, to)
    }

    fn reconnect(&self, stop: Stop) -> VfsResult<()> {
        *self.client.lock() = new_client()?;
        self.propfind(&self.home, "0", stop).map(|_| ())
    }

    fn close(&self) {
        if let Ok(client) = new_client() {
            // The old client's pool goes with it.
            *self.client.lock() = client;
        }
    }
}

/// A `MOVE` or `COPY` answered: 412 Precondition Failed says the
/// destination is taken.
fn taken(response: Response, from: &str, to: &str) -> VfsResult<()> {
    if response.status() == StatusCode::PRECONDITION_FAILED {
        return Err(VfsError::remote(VfsErrorKind::AlreadyExists, Some(to), format!("{to} already exists")));
    }
    check(response, from).map(|_| ())
}

/// A folder's address ends with a slash (servers redirect without it).
fn collection_path(path: &str) -> String {
    if path.ends_with('/') {
        path.to_string()
    } else {
        format!("{path}/")
    }
}

fn new_client() -> VfsResult<Client> {
    // The TLS configuration even for plain HTTP: reqwest builds one either
    // way, and there is no process-wide crypto provider to build it from.
    let config = tls::client_config()?;
    Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .read_timeout(REQUEST_TIMEOUT)
        .pool_idle_timeout(Duration::from_secs(60))
        .user_agent(concat!("Ferryx/", env!("CARGO_PKG_VERSION")))
        // A redirect to another host would take the password along.
        .redirect(reqwest::redirect::Policy::none())
        .use_preconfigured_tls((*config).clone())
        .build()
        .map_err(|e| VfsError::new(VfsErrorKind::Io, None, format!("HTTP: {e}")))
}

/// The answer, or its status as an error of the matching kind.
fn check(response: Response, path: &str) -> VfsResult<Response> {
    let status = response.status();
    if status.is_success() || status.as_u16() == 207 {
        return Ok(response);
    }
    let kind = match status.as_u16() {
        401 => VfsErrorKind::AuthFailed,
        403 | 423 => VfsErrorKind::PermissionDenied,
        404 | 409 | 410 => VfsErrorKind::NotFound,
        301 | 302 | 307 | 308 => VfsErrorKind::Unsupported,
        _ => VfsErrorKind::Io,
    };
    let reason = status.canonical_reason().unwrap_or("");
    Err(VfsError::remote(kind, Some(path), format!("{path}: {} {reason}", status.as_u16())))
}

fn http_error(error: &reqwest::Error, path: &str) -> VfsError {
    if tls::is_certificate_error(error) {
        return VfsError::remote(
            VfsErrorKind::CertificateInvalid,
            Some(path),
            tls::certificate_message(error),
        );
    }
    let kind = if error.is_timeout() {
        VfsErrorKind::TimedOut
    } else if error.is_connect() {
        VfsErrorKind::HostUnreachable
    } else if error.is_request() || error.is_body() {
        VfsErrorKind::ConnectionLost
    } else {
        VfsErrorKind::Io
    };
    // reqwest names the whole URL; the path is enough.
    let mut text = error.to_string();
    if let Some(url) = error.url() {
        text = text.replace(&format!(" for url ({url})"), "");
    }
    let mut cause = std::error::Error::source(error);
    while let Some(inner) = cause {
        text = format!("{text}: {inner}");
        cause = inner.source();
    }
    VfsError::remote(kind, Some(path), format!("{path}: {text}"))
}

/// A file being read: the response's body, chunk by chunk.
struct DavReader {
    response: Option<Response>,
    pending: Bytes,
    path: String,
}

impl RemoteRead for DavReader {
    fn read(&mut self, out: &mut [u8], stop: Stop) -> VfsResult<usize> {
        while self.pending.is_empty() {
            let Some(response) = self.response.as_mut() else { return Ok(0) };
            let path = self.path.clone();
            match run(
                async { response.chunk().await.map_err(|e| http_error(&e, &path)) },
                REQUEST_TIMEOUT,
                stop,
            )? {
                Some(chunk) => self.pending = chunk,
                None => {
                    self.response = None;
                    return Ok(0);
                }
            }
        }
        let n = out.len().min(self.pending.len());
        out[..n].copy_from_slice(&self.pending[..n]);
        let _ = self.pending.split_to(n);
        Ok(n)
    }
}

/// A file being written: chunks go to the request's body as it is sent.
struct DavWriter {
    sender: Option<mpsc::Sender<Result<Bytes, io::Error>>>,
    task: Option<JoinHandle<VfsResult<()>>>,
    path: String,
}

impl DavWriter {
    /// The request's own failure, once it gave up taking chunks.
    fn outcome(&mut self, stop: Stop) -> VfsResult<()> {
        let Some(task) = self.task.take() else { return Ok(()) };
        let path = self.path.clone();
        run(
            async move {
                match task.await {
                    Ok(result) => result,
                    Err(_) => Err(VfsError::remote(
                        VfsErrorKind::ConnectionLost,
                        Some(&path),
                        format!("{path}: the upload stopped"),
                    )),
                }
            },
            REQUEST_TIMEOUT,
            stop,
        )
    }
}

impl RemoteWrite for DavWriter {
    fn write_all(&mut self, data: &[u8], stop: Stop) -> VfsResult<()> {
        let Some(sender) = self.sender.as_ref() else { return self.outcome(stop) };
        let chunk = Bytes::copy_from_slice(data);
        let sent = run(async { Ok(sender.send(Ok(chunk)).await.is_ok()) }, REQUEST_TIMEOUT, stop)?;
        if !sent {
            self.sender = None;
            self.outcome(stop)?;
            return Err(VfsError::remote(
                VfsErrorKind::ConnectionLost,
                Some(&self.path),
                format!("{}: the upload stopped", self.path),
            ));
        }
        Ok(())
    }

    fn finish(mut self: Box<Self>, stop: Stop) -> VfsResult<()> {
        self.sender = None;
        match self.outcome(stop) {
            Err(error) if error.kind == VfsErrorKind::TimedOut => Err(timed_out()),
            other => other,
        }
    }
}

impl Drop for DavWriter {
    fn drop(&mut self) {
        if let Some(task) = self.task.take() {
            task.abort();
        }
    }
}

// ─── PROPFIND ───

/// One `<response>` of a multistatus answer.
#[derive(Clone, Debug)]
struct DavRow {
    /// The `href`, decoded: a path on the server.
    path: String,
    meta: RemoteMeta,
}

/// Reads a `207 Multi-Status` answer: each response's path and the
/// properties of its `200` propstat. Namespace prefixes are ignored (one
/// server writes `D:`, another `d:`, Apache `lp1:`).
fn parse_multistatus(text: &str) -> Result<Vec<DavRow>, String> {
    let mut reader = Reader::from_str(text);
    reader.config_mut().trim_text(true);
    let mut rows = Vec::new();
    let mut stack: Vec<String> = Vec::new();
    let mut href = String::new();
    let mut text_now = String::new();
    let mut props: HashMap<&'static str, String> = HashMap::new();
    let mut collection = false;
    let mut good: Option<(HashMap<&'static str, String>, bool)> = None;
    loop {
        let event = reader.read_event().map_err(|e| e.to_string())?;
        match event {
            Event::Start(start) => {
                let local = String::from_utf8_lossy(start.local_name().as_ref()).to_ascii_lowercase();
                match local.as_str() {
                    "response" => {
                        href.clear();
                        good = None;
                    }
                    "propstat" => {
                        props.clear();
                        collection = false;
                    }
                    "collection" if stack.last().is_some_and(|s| s == "resourcetype") => collection = true,
                    _ => {}
                }
                text_now.clear();
                stack.push(local);
            }
            Event::Empty(empty) => {
                let local = String::from_utf8_lossy(empty.local_name().as_ref()).to_ascii_lowercase();
                if local == "collection" && stack.last().is_some_and(|s| s == "resourcetype") {
                    collection = true;
                }
            }
            Event::Text(t) => text_now.push_str(&t.decode().map_err(|e| e.to_string())?),
            Event::CData(t) => text_now.push_str(&t.decode().map_err(|e| e.to_string())?),
            Event::GeneralRef(r) => {
                if r.is_char_ref() {
                    if let Ok(Some(c)) = r.resolve_char_ref() {
                        text_now.push(c);
                    }
                } else if let Ok(name) = r.decode() {
                    if let Some(resolved) = quick_xml::escape::resolve_predefined_entity(&name) {
                        text_now.push_str(resolved);
                    }
                }
            }
            Event::End(_) => {
                let Some(local) = stack.pop() else { continue };
                let value = std::mem::take(&mut text_now);
                let in_prop = stack.last().is_some_and(|s| s == "prop");
                match local.as_str() {
                    "href" if stack.last().is_some_and(|s| s == "response") => href = value,
                    "getcontentlength" if in_prop => {
                        props.insert("length", value);
                    }
                    "getlastmodified" if in_prop => {
                        props.insert("modified", value);
                    }
                    "creationdate" if in_prop => {
                        props.insert("created", value);
                    }
                    "status" if stack.last().is_some_and(|s| s == "propstat") => {
                        if value.split_whitespace().nth(1) == Some("200") {
                            good = Some((props.clone(), collection));
                        }
                    }
                    "response" => {
                        let (found, is_dir) = good.take().unwrap_or_default();
                        rows.push(DavRow { path: href_path(&href), meta: meta_of(&found, is_dir) });
                    }
                    _ => {}
                }
            }
            Event::Eof => break,
            _ => {}
        }
    }
    Ok(rows)
}

fn meta_of(props: &HashMap<&'static str, String>, collection: bool) -> RemoteMeta {
    RemoteMeta {
        kind: Some(if collection { EntryKind::Directory } else { EntryKind::File }),
        size: props.get("length").and_then(|v| v.trim().parse().ok()),
        modified_ms: props
            .get("modified")
            .and_then(|v| DateTime::parse_from_rfc2822(v.trim()).ok())
            .map(|t| t.timestamp_millis()),
        created_ms: props
            .get("created")
            .and_then(|v| DateTime::parse_from_rfc3339(v.trim()).ok())
            .map(|t| t.timestamp_millis()),
        ..Default::default()
    }
}

/// An `href` as a path: an absolute URL loses its scheme and host; the
/// rest is decoded.
fn href_path(href: &str) -> String {
    let path = match href.find("://") {
        Some(at) => {
            let rest = &href[at + 3..];
            rest.find('/').map(|slash| &rest[slash..]).unwrap_or("/")
        }
        None => href,
    };
    normalize(&percent_encoding::percent_decode_str(path).decode_utf8_lossy())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_multistatus_answer() {
        let xml = r#"<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:lp1="DAV:">
  <D:response>
    <D:href>/dav/a%20b/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype>
      <lp1:getlastmodified>Tue, 02 Jan 2024 03:04:05 GMT</lp1:getlastmodified></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status></D:propstat>
  </D:response>
  <D:response>
    <D:href>https://host.example/dav/a%20b/%C3%BC%26.txt</D:href>
    <D:propstat><D:prop><D:resourcetype/><D:getcontentlength>12</D:getcontentlength>
      <D:creationdate>2024-01-01T00:00:00Z</D:creationdate></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status></D:propstat>
    <D:propstat><D:prop><D:getetag/></D:prop><D:status>HTTP/1.1 404 Not Found</D:status></D:propstat>
  </D:response>
  <d:response xmlns:d="DAV:"><d:href>/dav/a%20b/R&amp;D</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection></d:collection></d:resourcetype></d:prop>
    <d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
</D:multistatus>"#;
        let rows = parse_multistatus(xml).unwrap();
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].path, "/dav/a b");
        assert_eq!(rows[0].meta.kind, Some(EntryKind::Directory));
        assert_eq!(rows[0].meta.modified_ms, Some(1_704_164_645_000));
        assert_eq!(rows[1].path, "/dav/a b/ü&.txt");
        assert_eq!(rows[1].meta.kind, Some(EntryKind::File));
        assert_eq!(rows[1].meta.size, Some(12));
        assert_eq!(rows[1].meta.created_ms, Some(1_704_067_200_000));
        assert_eq!(rows[2].path, "/dav/a b/R&D");
        assert_eq!(rows[2].meta.kind, Some(EntryKind::Directory));
        assert!(parse_multistatus("<a><b></a>").is_err());
    }

    #[test]
    fn paths_and_folders() {
        assert_eq!(collection_path("/a"), "/a/");
        assert_eq!(collection_path("/a/"), "/a/");
        assert_eq!(href_path("http://h:8080"), "/");
        assert_eq!(href_path("/x/y/"), "/x/y");
    }
}
