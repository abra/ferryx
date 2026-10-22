//! An SFTP server over a temporary folder: russh's server side for SSH,
//! russh-sftp's for the file protocol, the folder's files for the files.
//! It logs in by password (or a client key, or a one-time code asked for
//! by keyboard-interactive), and can cut its connection after so many
//! bytes read, as a dropped network would.

use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use russh::keys::{PrivateKey, PublicKey};
use russh::server::{Auth, ChannelOpenHandle, Msg, Server as _, Session};
use russh::{Channel, ChannelId, MethodKind, MethodSet};
use russh_sftp::protocol::{
    Attrs, Data, File, FileAttributes, Handle, Name, OpenFlags, Status, StatusCode, Version,
};
use tempfile::TempDir;
use tokio::net::TcpListener;

use crate::server_runtime;

/// How the server behaves.
#[derive(Clone)]
pub struct SftpOptions {
    pub user: String,
    pub password: String,
    /// The host key it shows (OpenSSH format).
    pub host_key: &'static str,
    /// Client keys it takes (OpenSSH public key lines).
    pub client_keys: Vec<&'static str>,
    /// After the password, a one-time code asked for by
    /// keyboard-interactive (as a server with two factors does).
    pub one_time_code: Option<String>,
    /// Logging in by password goes through keyboard-interactive only (a
    /// PAM server's way).
    pub password_by_prompt: bool,
    /// The connection is cut once this many bytes were read from it.
    pub drop_after_bytes: Option<u64>,
}

impl Default for SftpOptions {
    fn default() -> Self {
        SftpOptions {
            user: "me".to_string(),
            password: "secret".to_string(),
            host_key: crate::HOST_KEY,
            client_keys: Vec::new(),
            one_time_code: None,
            password_by_prompt: false,
            drop_after_bytes: None,
        }
    }
}

/// A running server; dropped, it stops and its folder goes.
pub struct SftpServer {
    pub port: u16,
    pub root: TempDir,
    /// Logins accepted so far (each connection logs in once).
    pub logins: Arc<AtomicUsize>,
    stop: Option<tokio::sync::oneshot::Sender<()>>,
}

impl SftpServer {
    pub fn start(options: SftpOptions) -> SftpServer {
        let root = tempfile::tempdir().expect("a folder to serve");
        let logins = Arc::new(AtomicUsize::new(0));
        let runtime = server_runtime();
        let listener = runtime.block_on(TcpListener::bind("127.0.0.1:0")).expect("a port");
        let port = listener.local_addr().expect("an address").port();
        let config = Arc::new(russh::server::Config {
            keys: vec![PrivateKey::from_openssh(options.host_key).expect("a host key")],
            auth_rejection_time: Duration::from_millis(10),
            auth_rejection_time_initial: Some(Duration::ZERO),
            methods: MethodSet::from(
                &[MethodKind::Password, MethodKind::PublicKey, MethodKind::KeyboardInteractive][..],
            ),
            inactivity_timeout: Some(Duration::from_secs(60)),
            ..Default::default()
        });
        let mut server = TestServer {
            root: root.path().to_path_buf(),
            options: Arc::new(options),
            logins: logins.clone(),
        };
        let (stop, stopped) = tokio::sync::oneshot::channel::<()>();
        runtime.spawn(async move {
            let running = server.run_on_socket(config, &listener);
            tokio::select! {
                _ = running => {}
                _ = stopped => {}
            }
        });
        SftpServer { port, root, logins, stop: Some(stop) }
    }

    /// A path under the served folder.
    pub fn path(&self, path: &str) -> PathBuf {
        self.root.path().join(path.trim_start_matches('/'))
    }
}

impl Drop for SftpServer {
    fn drop(&mut self) {
        if let Some(stop) = self.stop.take() {
            let _ = stop.send(());
        }
    }
}

#[derive(Clone)]
struct TestServer {
    root: PathBuf,
    options: Arc<SftpOptions>,
    logins: Arc<AtomicUsize>,
}

impl russh::server::Server for TestServer {
    type Handler = Connection;

    fn new_client(&mut self, _: Option<SocketAddr>) -> Connection {
        Connection {
            root: self.root.clone(),
            options: self.options.clone(),
            logins: self.logins.clone(),
            channels: HashMap::new(),
            password_ok: false,
        }
    }
}

struct Connection {
    root: PathBuf,
    options: Arc<SftpOptions>,
    logins: Arc<AtomicUsize>,
    channels: HashMap<ChannelId, Channel<Msg>>,
    /// The password was right; a one-time code may still be due.
    password_ok: bool,
}

impl Connection {
    fn accept(&self) -> Auth {
        self.logins.fetch_add(1, Ordering::SeqCst);
        Auth::Accept
    }
}

impl russh::server::Handler for Connection {
    type Error = russh::Error;

    async fn auth_password(&mut self, user: &str, password: &str) -> Result<Auth, Self::Error> {
        if self.options.password_by_prompt || user != self.options.user || password != self.options.password {
            return Ok(Auth::reject());
        }
        if self.options.one_time_code.is_some() {
            self.password_ok = true;
            return Ok(Auth::Reject {
                proceed_with_methods: Some(MethodSet::from(&[MethodKind::KeyboardInteractive][..])),
                partial_success: true,
            });
        }
        Ok(self.accept())
    }

    async fn auth_publickey(&mut self, user: &str, key: &PublicKey) -> Result<Auth, Self::Error> {
        let known = self
            .options
            .client_keys
            .iter()
            .filter_map(|line| line.split_whitespace().nth(1))
            .filter_map(|b64| russh::keys::parse_public_key_base64(b64).ok())
            .any(|k| k.key_data() == key.key_data());
        if user == self.options.user && known {
            Ok(self.accept())
        } else {
            Ok(Auth::reject())
        }
    }

    async fn auth_keyboard_interactive<'a>(
        &'a mut self,
        user: &str,
        _submethods: &str,
        response: Option<russh::server::Response<'a>>,
    ) -> Result<Auth, Self::Error> {
        if user != self.options.user {
            return Ok(Auth::reject());
        }
        let (prompt, expected) = if self.options.password_by_prompt && !self.password_ok {
            ("Password: ", self.options.password.clone())
        } else if let Some(code) = &self.options.one_time_code {
            ("Verification code: ", code.clone())
        } else {
            return Ok(Auth::reject());
        };
        match response {
            None => Ok(Auth::Partial {
                name: "".into(),
                instructions: "".into(),
                prompts: vec![(prompt.into(), false)].into(),
            }),
            Some(mut answers) => {
                let given =
                    answers.next().map(|b| String::from_utf8_lossy(&b).into_owned()).unwrap_or_default();
                if given != expected {
                    return Ok(Auth::reject());
                }
                if self.options.password_by_prompt
                    && !self.password_ok
                    && self.options.one_time_code.is_some()
                {
                    self.password_ok = true;
                    return Ok(Auth::Partial {
                        name: "".into(),
                        instructions: "".into(),
                        prompts: vec![("Verification code: ".into(), true)].into(),
                    });
                }
                Ok(self.accept())
            }
        }
    }

    async fn channel_open_session(
        &mut self,
        channel: Channel<Msg>,
        reply: ChannelOpenHandle,
        _session: &mut Session,
    ) -> Result<(), Self::Error> {
        self.channels.insert(channel.id(), channel);
        reply.accept().await;
        Ok(())
    }

    async fn subsystem_request(
        &mut self,
        id: ChannelId,
        name: &str,
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        let Some(channel) = self.channels.remove(&id) else { return Ok(()) };
        if name != "sftp" {
            session.channel_failure(id)?;
            return Ok(());
        }
        session.channel_success(id)?;
        let files = Files {
            root: self.root.clone(),
            handles: HashMap::new(),
            next: 1,
            read: Arc::new(AtomicU64::new(0)),
            drop_after: self.options.drop_after_bytes,
            session: session.handle(),
        };
        tokio::spawn(russh_sftp::server::run(channel.into_stream(), files));
        Ok(())
    }
}

enum Open {
    File(fs::File),
    Dir { entries: Vec<File>, sent: bool },
}

/// The SFTP side, over the served folder.
struct Files {
    root: PathBuf,
    handles: HashMap<String, Open>,
    next: u64,
    read: Arc<AtomicU64>,
    drop_after: Option<u64>,
    session: russh::server::Handle,
}

impl Files {
    fn local(&self, path: &str) -> PathBuf {
        let mut out = self.root.clone();
        for part in path.split('/') {
            match part {
                "" | "." => {}
                ".." => {
                    if out != self.root {
                        out.pop();
                    }
                }
                other => out.push(other),
            }
        }
        out
    }

    fn handle(&mut self, open: Open) -> String {
        let id = format!("h{}", self.next);
        self.next += 1;
        self.handles.insert(id.clone(), open);
        id
    }
}

fn ok(id: u32) -> Status {
    Status { id, status_code: StatusCode::Ok, error_message: "Ok".into(), language_tag: "en-US".into() }
}

fn code(error: std::io::Error) -> StatusCode {
    match error.kind() {
        std::io::ErrorKind::NotFound => StatusCode::NoSuchFile,
        std::io::ErrorKind::PermissionDenied => StatusCode::PermissionDenied,
        _ => StatusCode::Failure,
    }
}

pub(crate) fn attrs_of(meta: &fs::Metadata) -> FileAttributes {
    let seconds = |time: std::io::Result<std::time::SystemTime>| {
        time.ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_secs() as u32)
    };
    #[cfg(unix)]
    let (mode, uid, gid) = {
        use std::os::unix::fs::MetadataExt;
        (meta.mode(), Some(meta.uid()), Some(meta.gid()))
    };
    #[cfg(not(unix))]
    let (mode, uid, gid) = {
        let kind = if meta.is_dir() {
            0o040755
        } else if meta.file_type().is_symlink() {
            0o120777
        } else {
            0o100644
        };
        (kind, None, None)
    };
    FileAttributes {
        size: Some(meta.len()),
        uid,
        user: None,
        gid,
        group: None,
        permissions: Some(mode),
        atime: seconds(meta.accessed()),
        mtime: seconds(meta.modified()),
    }
}

fn normalize(path: &str) -> String {
    let mut parts: Vec<&str> = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            other => parts.push(other),
        }
    }
    format!("/{}", parts.join("/"))
}

impl russh_sftp::server::Handler for Files {
    type Error = StatusCode;

    fn unimplemented(&self) -> Self::Error {
        StatusCode::OpUnsupported
    }

    async fn init(
        &mut self,
        _version: u32,
        _extensions: HashMap<String, String>,
    ) -> Result<Version, Self::Error> {
        Ok(Version::new())
    }

    async fn realpath(&mut self, id: u32, path: String) -> Result<Name, Self::Error> {
        let path = if path == "." || path.is_empty() { "/".to_string() } else { normalize(&path) };
        Ok(Name { id, files: vec![File::dummy(path)] })
    }

    async fn opendir(&mut self, id: u32, path: String) -> Result<Handle, Self::Error> {
        let local = self.local(&path);
        let mut entries =
            vec![File::new(".", FileAttributes::dummy()), File::new("..", FileAttributes::dummy())];
        for item in fs::read_dir(&local).map_err(code)? {
            let item = item.map_err(code)?;
            let meta = fs::symlink_metadata(item.path()).map_err(code)?;
            entries.push(File::new(item.file_name().to_string_lossy(), attrs_of(&meta)));
        }
        Ok(Handle { id, handle: self.handle(Open::Dir { entries, sent: false }) })
    }

    async fn readdir(&mut self, id: u32, handle: String) -> Result<Name, Self::Error> {
        match self.handles.get_mut(&handle) {
            Some(Open::Dir { entries, sent }) => {
                // A hundred at a time, as OpenSSH sends them.
                if *sent && entries.is_empty() {
                    return Err(StatusCode::Eof);
                }
                *sent = true;
                let take = entries.len().min(100);
                let files: Vec<File> = entries.drain(..take).collect();
                if files.is_empty() {
                    return Err(StatusCode::Eof);
                }
                Ok(Name { id, files })
            }
            _ => Err(StatusCode::Failure),
        }
    }

    async fn open(
        &mut self,
        id: u32,
        filename: String,
        flags: OpenFlags,
        _attrs: FileAttributes,
    ) -> Result<Handle, Self::Error> {
        let local = self.local(&filename);
        let file = OpenOptions::new()
            .read(flags.contains(OpenFlags::READ))
            .write(flags.contains(OpenFlags::WRITE))
            .create(flags.contains(OpenFlags::CREATE))
            .truncate(flags.contains(OpenFlags::TRUNCATE))
            .open(&local)
            .map_err(code)?;
        Ok(Handle { id, handle: self.handle(Open::File(file)) })
    }

    async fn read(&mut self, id: u32, handle: String, offset: u64, len: u32) -> Result<Data, Self::Error> {
        let Some(Open::File(file)) = self.handles.get_mut(&handle) else { return Err(StatusCode::Failure) };
        file.seek(SeekFrom::Start(offset)).map_err(code)?;
        let mut data = vec![0u8; len as usize];
        let mut filled = 0;
        while filled < data.len() {
            let n = file.read(&mut data[filled..]).map_err(code)?;
            if n == 0 {
                break;
            }
            filled += n;
        }
        if filled == 0 {
            return Err(StatusCode::Eof);
        }
        data.truncate(filled);
        let total = self.read.fetch_add(filled as u64, Ordering::SeqCst) + filled as u64;
        if self.drop_after.is_some_and(|limit| total >= limit) {
            // The network goes: the whole connection is cut.
            let session = self.session.clone();
            tokio::spawn(async move {
                let _ =
                    session.disconnect(russh::Disconnect::ByApplication, "dropped".into(), "en".into()).await;
            });
            return Err(StatusCode::ConnectionLost);
        }
        Ok(Data { id, data })
    }

    async fn write(
        &mut self,
        id: u32,
        handle: String,
        offset: u64,
        data: Vec<u8>,
    ) -> Result<Status, Self::Error> {
        let Some(Open::File(file)) = self.handles.get_mut(&handle) else { return Err(StatusCode::Failure) };
        file.seek(SeekFrom::Start(offset)).map_err(code)?;
        file.write_all(&data).map_err(code)?;
        Ok(ok(id))
    }

    async fn close(&mut self, id: u32, handle: String) -> Result<Status, Self::Error> {
        self.handles.remove(&handle);
        Ok(ok(id))
    }

    async fn lstat(&mut self, id: u32, path: String) -> Result<Attrs, Self::Error> {
        let meta = fs::symlink_metadata(self.local(&path)).map_err(code)?;
        Ok(Attrs { id, attrs: attrs_of(&meta) })
    }

    async fn stat(&mut self, id: u32, path: String) -> Result<Attrs, Self::Error> {
        let meta = fs::metadata(self.local(&path)).map_err(code)?;
        Ok(Attrs { id, attrs: attrs_of(&meta) })
    }

    async fn setstat(&mut self, id: u32, path: String, attrs: FileAttributes) -> Result<Status, Self::Error> {
        if let Some(mtime) = attrs.mtime {
            let time = filetime::FileTime::from_unix_time(i64::from(mtime), 0);
            filetime::set_file_mtime(self.local(&path), time).map_err(code)?;
        }
        Ok(ok(id))
    }

    async fn mkdir(&mut self, id: u32, path: String, _attrs: FileAttributes) -> Result<Status, Self::Error> {
        fs::create_dir(self.local(&path)).map_err(code)?;
        Ok(ok(id))
    }

    async fn rmdir(&mut self, id: u32, path: String) -> Result<Status, Self::Error> {
        fs::remove_dir(self.local(&path)).map_err(code)?;
        Ok(ok(id))
    }

    async fn remove(&mut self, id: u32, filename: String) -> Result<Status, Self::Error> {
        fs::remove_file(self.local(&filename)).map_err(code)?;
        Ok(ok(id))
    }

    async fn rename(&mut self, id: u32, from: String, to: String) -> Result<Status, Self::Error> {
        let target = self.local(&to);
        if target.symlink_metadata().is_ok() {
            return Err(StatusCode::Failure);
        }
        fs::rename(self.local(&from), target).map_err(code)?;
        Ok(ok(id))
    }

    async fn readlink(&mut self, id: u32, path: String) -> Result<Name, Self::Error> {
        let target = fs::read_link(self.local(&path)).map_err(code)?;
        Ok(Name { id, files: vec![File::dummy(target.to_string_lossy())] })
    }
}
