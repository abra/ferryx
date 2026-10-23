//! The servers Ferryx is connected to, one per key (protocol, user, host
//! and port): every listing and operation on a server goes through its
//! [`Server`]. Each protocol keeps its own connections behind it (an SSH
//! session, a pool of FTP control connections, an HTTP client), opens them
//! again when one drops, and closes idle ones; the state a person sees
//! (connected, lost, closed) goes to one listener.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, LazyLock, Once};
use std::time::Duration;

use parking_lot::{Mutex, RwLock};

use super::address::ServerAddress;
use super::runtime::Stop;
use super::{ftp, prompt, sftp, webdav, Protocol, RemoteFs};
use crate::error::{VfsError, VfsErrorKind, VfsResult};

/// How a user proves who they are to an SSH server; FTP and WebDAV always
/// take a password.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum AuthMethod {
    /// As OpenSSH: the agent's keys, the default key files, then the
    /// server's prompts and a password.
    #[default]
    Auto,
    Password,
    /// A key file; the default ones (`~/.ssh/id_ed25519`, `id_ecdsa`,
    /// `id_rsa`) when none is named.
    Key(Option<PathBuf>),
    /// The keys of the SSH agent (`SSH_AUTH_SOCK`).
    Agent,
}

/// What to connect to, and how.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConnectSpec {
    pub address: ServerAddress,
    pub auth: AuthMethod,
}

/// A connection's state as the interface shows it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConnState {
    Connected,
    /// It dropped; the next call opens it again, or fails and says why.
    Lost,
    /// The user disconnected.
    Closed,
}

pub type StateListener = Arc<dyn Fn(&str, ConnState) + Send + Sync>;

/// One server and its connections.
pub struct Server {
    key: String,
    address: ServerAddress,
    fs: Box<dyn RemoteFs>,
    state: Mutex<ConnState>,
}

impl Server {
    /// `sftp://me@host:22`.
    pub fn key(&self) -> &str {
        &self.key
    }

    pub fn address(&self) -> &ServerAddress {
        &self.address
    }

    pub fn fs(&self) -> &dyn RemoteFs {
        self.fs.as_ref()
    }

    pub fn state(&self) -> ConnState {
        *self.state.lock()
    }

    /// `path` on this server as a person reads it.
    pub fn display_url(&self, path: &str) -> String {
        self.address.display_url(path)
    }
}

/// Tells the registry what became of a server's connections; given to
/// each protocol when its server connects.
#[derive(Clone, Debug)]
pub struct Notifier {
    key: String,
}

impl Notifier {
    pub fn new(key: &str) -> Notifier {
        Notifier { key: key.to_string() }
    }

    pub fn key(&self) -> &str {
        &self.key
    }

    /// A connection dropped.
    pub fn lost(&self) {
        set_state(&self.key, ConnState::Lost);
    }

    /// A connection is open again.
    pub fn restored(&self) {
        set_state(&self.key, ConnState::Connected);
    }
}

#[derive(Default)]
struct Registry {
    servers: HashMap<String, Arc<Server>>,
    /// One connection attempt per key at a time.
    connecting: HashMap<String, Arc<Mutex<()>>>,
}

static REGISTRY: LazyLock<Mutex<Registry>> = LazyLock::new(Default::default);
static LISTENER: LazyLock<RwLock<Option<StateListener>>> = LazyLock::new(Default::default);
static REAPER: Once = Once::new();

/// How often idle connections are looked for.
const REAP_EVERY: Duration = Duration::from_secs(15);

/// The one listener of state changes; a later call replaces it.
pub fn set_listener(listener: Option<StateListener>) {
    *LISTENER.write() = listener;
}

fn notify(key: &str, state: ConnState) {
    let listener = LISTENER.read().clone();
    if let Some(listener) = listener {
        listener(key, state);
    }
}

fn set_state(key: &str, state: ConnState) {
    let server = REGISTRY.lock().servers.get(key).cloned();
    let Some(server) = server else { return };
    let changed = {
        let mut current = server.state.lock();
        let changed = *current != state && *current != ConnState::Closed;
        if changed {
            *current = state;
        }
        changed
    };
    if changed {
        notify(key, state);
    }
}

/// Connects to `spec`'s server, or answers the connection already open to
/// it (opened again first when it dropped). Questions (a host key, a
/// password) go to the user through [`prompt`] meanwhile.
pub fn connect(spec: ConnectSpec, stop: Stop) -> VfsResult<Arc<Server>> {
    let key = spec.address.key();
    let gate = REGISTRY.lock().connecting.entry(key.clone()).or_default().clone();
    let _attempt = gate.lock();
    let existing = REGISTRY.lock().servers.get(&key).cloned();
    if let Some(server) = existing {
        if server.state() == ConnState::Lost {
            server.fs.reconnect(stop)?;
            set_state(&key, ConnState::Connected);
        }
        return Ok(server);
    }
    let notifier = Notifier::new(&key);
    let fs: Box<dyn RemoteFs> = match spec.address.protocol {
        Protocol::Sftp => Box::new(sftp::SftpFs::connect(&spec, notifier, stop)?),
        Protocol::Ftp | Protocol::Ftps => Box::new(ftp::FtpFs::connect(&spec, notifier, stop)?),
        Protocol::Dav | Protocol::Davs => Box::new(webdav::DavFs::connect(&spec, notifier, stop)?),
    };
    let mut address = spec.address.clone();
    address.password = None;
    let server = Arc::new(Server { key: key.clone(), address, fs, state: Mutex::new(ConnState::Connected) });
    REGISTRY.lock().servers.insert(key.clone(), server.clone());
    start_reaper();
    notify(&key, ConnState::Connected);
    Ok(server)
}

/// The server open under `key`; [`VfsErrorKind::NotConnected`] when there
/// is none.
pub fn get(key: &str) -> VfsResult<Arc<Server>> {
    REGISTRY.lock().servers.get(key).cloned().ok_or_else(|| not_connected(key))
}

/// No connection to `key`; the message names the server as it reads.
pub fn not_connected(key: &str) -> VfsError {
    let shown = super::address::parse_key(key).map(|a| a.display_root()).unwrap_or_else(|_| key.to_string());
    VfsError::new(VfsErrorKind::NotConnected, None, shown)
}

/// Closes every connection to the server `key`. Operations under way on
/// it keep the server until they end; listings on it fail from now on.
pub fn disconnect(key: &str) {
    let server = REGISTRY.lock().servers.remove(key);
    prompt::withdraw(key);
    if let Some(server) = server {
        *server.state.lock() = ConnState::Closed;
        server.fs.close();
        notify(key, ConnState::Closed);
    }
}

/// Every server open, with its state.
pub fn servers() -> Vec<(String, ConnState)> {
    let mut out: Vec<(String, ConnState)> =
        REGISTRY.lock().servers.values().map(|s| (s.key.clone(), s.state())).collect();
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

/// Closes every server (the tests start clean).
pub fn disconnect_all() {
    let keys: Vec<String> = REGISTRY.lock().servers.keys().cloned().collect();
    for key in keys {
        disconnect(&key);
    }
}

fn start_reaper() {
    REAPER.call_once(|| {
        let _ = std::thread::Builder::new().name("ferryx-net-reaper".into()).spawn(|| loop {
            std::thread::sleep(REAP_EVERY);
            let servers: Vec<Arc<Server>> = REGISTRY.lock().servers.values().cloned().collect();
            for server in servers {
                server.fs.reap_idle();
            }
        });
    });
}
