//! Servers over SFTP, FTP(S) and WebDAV: an address read, a connection
//! made (its questions to the user come as `NetworkQuestion` events and
//! go back through [`answer_network_question`]), the connections open and
//! their state (`ConnectionChanged`), items made and renamed on a server,
//! and the operations whose source or destination is on one.
//!
//! A location on a server carries the server's key (`sftp://me@host:22`)
//! and a path; listings, the viewer's ranges and operations find the open
//! connection by that key, and fail with `NotConnected` when there is
//! none, for the interface to connect and try again.

use std::path::PathBuf;
use std::sync::atomic::Ordering;
use std::sync::Arc;

use ferryx_ops::transfer::{self, Side, Transfer};
use ferryx_vfs::remote::connection::{self, AuthMethod, ConnState, ConnectSpec};
use ferryx_vfs::remote::prompt::{self, Answer, Question};
use ferryx_vfs::remote::{self, address, never, Protocol, ServerAddress};
use flutter_rust_bridge::frb;

use crate::api::types::{
    ApiResult, AppEvent, AppEventKind, ConflictPolicyView, EntryView, FerryxError, FerryxErrorKind,
    OpKindView, OpRequestView,
};
use crate::{app, tasks};

// ─── Types ───

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProtocolView {
    Sftp,
    Ftp,
    Ftps,
    Dav,
    Davs,
}

impl ProtocolView {
    #[frb(ignore)]
    pub fn to_vfs(self) -> Protocol {
        match self {
            ProtocolView::Sftp => Protocol::Sftp,
            ProtocolView::Ftp => Protocol::Ftp,
            ProtocolView::Ftps => Protocol::Ftps,
            ProtocolView::Dav => Protocol::Dav,
            ProtocolView::Davs => Protocol::Davs,
        }
    }

    #[frb(ignore)]
    pub fn of(protocol: Protocol) -> ProtocolView {
        match protocol {
            Protocol::Sftp => ProtocolView::Sftp,
            Protocol::Ftp => ProtocolView::Ftp,
            Protocol::Ftps => ProtocolView::Ftps,
            Protocol::Dav => ProtocolView::Dav,
            Protocol::Davs => ProtocolView::Davs,
        }
    }
}

/// How an SSH server is logged in to; FTP and WebDAV take a password.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AuthMethodView {
    /// The agent, the default keys, the server's prompts, a password.
    Auto,
    Password,
    /// The key file `ConnectRequestView::key_path` (the default ones when
    /// none is given).
    Key,
    Agent,
}

/// An address as read: its parts, its key and how it reads.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ServerAddressView {
    pub protocol: ProtocolView,
    pub host: String,
    pub port: i64,
    pub user: String,
    /// The folder to open; empty for the server's own start.
    pub path: String,
    /// A password written into the address, for this connection only.
    pub password: Option<String>,
    /// `sftp://me@host:22`: what every location on the server carries.
    pub key: String,
    /// `sftp://me@host`.
    pub display: String,
}

impl ServerAddressView {
    fn of(address: &ServerAddress) -> ServerAddressView {
        ServerAddressView {
            protocol: ProtocolView::of(address.protocol),
            host: address.host.clone(),
            port: i64::from(address.port),
            user: address.user.clone(),
            path: address.path.clone(),
            password: address.password.clone(),
            key: address.key(),
            display: address.display_root(),
        }
    }
}

/// What to connect to. Its `Debug` leaves the password out.
#[derive(Clone, PartialEq, Eq)]
pub struct ConnectRequestView {
    pub protocol: ProtocolView,
    pub host: String,
    /// 0 for the protocol's own.
    pub port: i64,
    pub user: String,
    /// The folder to open; empty for the server's own start.
    pub path: String,
    /// A password known already (typed into the address).
    pub password: Option<String>,
    pub auth: AuthMethodView,
    pub key_path: Option<String>,
}

impl std::fmt::Debug for ConnectRequestView {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConnectRequestView")
            .field("protocol", &self.protocol)
            .field("host", &self.host)
            .field("port", &self.port)
            .field("user", &self.user)
            .field("path", &self.path)
            .field("password", &self.password.as_ref().map(|_| "…"))
            .field("auth", &self.auth)
            .field("key_path", &self.key_path)
            .finish()
    }
}

impl ConnectRequestView {
    fn to_spec(&self) -> ApiResult<ConnectSpec> {
        let host = self.host.trim();
        if host.is_empty() || host.chars().any(|c| c.is_whitespace() || c.is_control() || c == '/') {
            return Err(FerryxError::new(FerryxErrorKind::InvalidName, format!("“{host}” is not a host")));
        }
        let protocol = self.protocol.to_vfs();
        let port = match self.port {
            0 => protocol.default_port(),
            port => u16::try_from(port).ok().filter(|p| *p > 0).ok_or_else(|| {
                FerryxError::new(FerryxErrorKind::InvalidName, format!("{port} is not a port"))
            })?,
        };
        let mut address = ServerAddress::new(protocol, host, self.user.trim());
        address.port = port;
        address.path = address::normalize(self.path.trim());
        address.password = self.password.clone().filter(|p| !p.is_empty());
        let auth = match self.auth {
            AuthMethodView::Auto => AuthMethod::Auto,
            AuthMethodView::Password => AuthMethod::Password,
            AuthMethodView::Agent => AuthMethod::Agent,
            AuthMethodView::Key => {
                AuthMethod::Key(self.key_path.as_deref().filter(|p| !p.is_empty()).map(expand_home))
            }
        };
        Ok(ConnectSpec { address, auth })
    }
}

/// `~/…` as the home folder's.
fn expand_home(path: &str) -> PathBuf {
    match path.strip_prefix("~/") {
        Some(rest) => ferryx_vfs::system::home_dir().join(rest),
        None => PathBuf::from(path),
    }
}

/// A connection made.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConnectionView {
    /// The server's key: what its locations carry.
    pub server: String,
    /// `sftp://me@host`.
    pub display: String,
    /// The folder to open first: the address's, else the server's start.
    pub home: String,
    pub protocol: ProtocolView,
    /// Whether what crosses the network is encrypted.
    pub secure: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConnectionStateView {
    Connected,
    /// It dropped; the next call tries again.
    Lost,
    /// The user disconnected.
    Closed,
}

impl ConnectionStateView {
    fn of(state: ConnState) -> ConnectionStateView {
        match state {
            ConnState::Connected => ConnectionStateView::Connected,
            ConnState::Lost => ConnectionStateView::Lost,
            ConnState::Closed => ConnectionStateView::Closed,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ServerStateView {
    pub server: String,
    pub display: String,
    pub state: ConnectionStateView,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NetworkQuestionKindView {
    /// An SSH key no known_hosts file has: trust it?
    HostKey,
    Password,
    /// A key file's passphrase.
    Passphrase,
    /// The server's own prompts.
    KeyboardInteractive,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PromptView {
    pub text: String,
    /// What is typed may show (a one-time code), else it is hidden.
    pub echo: bool,
}

/// A question a connection asks; only the fields of its kind are set.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NetworkQuestionView {
    pub id: i64,
    pub kind: NetworkQuestionKindView,
    pub server: String,
    pub host: String,
    pub port: i64,
    pub user: String,
    /// `ssh-ed25519`…
    pub algorithm: String,
    /// `SHA256:…`.
    pub fingerprint: String,
    pub key_path: String,
    /// The password or passphrase given before was refused.
    pub retry: bool,
    pub name: String,
    pub instructions: String,
    pub prompts: Vec<PromptView>,
}

impl NetworkQuestionView {
    fn of(id: u64, question: &Question) -> NetworkQuestionView {
        let mut view = NetworkQuestionView {
            id: id as i64,
            kind: NetworkQuestionKindView::Password,
            server: question.server().to_string(),
            host: String::new(),
            port: 0,
            user: String::new(),
            algorithm: String::new(),
            fingerprint: String::new(),
            key_path: String::new(),
            retry: false,
            name: String::new(),
            instructions: String::new(),
            prompts: Vec::new(),
        };
        match question {
            Question::HostKey { host, port, algorithm, fingerprint, .. } => {
                view.kind = NetworkQuestionKindView::HostKey;
                view.host = host.clone();
                view.port = i64::from(*port);
                view.algorithm = algorithm.clone();
                view.fingerprint = fingerprint.clone();
            }
            Question::Password { user, retry, .. } => {
                view.user = user.clone();
                view.retry = *retry;
            }
            Question::Passphrase { key_path, retry, .. } => {
                view.kind = NetworkQuestionKindView::Passphrase;
                view.key_path = key_path.clone();
                view.retry = *retry;
            }
            Question::KeyboardInteractive { name, instructions, prompts, .. } => {
                view.kind = NetworkQuestionKindView::KeyboardInteractive;
                view.name = name.clone();
                view.instructions = instructions.clone();
                view.prompts = prompts
                    .iter()
                    .map(|(text, echo)| PromptView { text: text.clone(), echo: *echo })
                    .collect();
            }
        }
        if let Ok(address) = address::parse_key(&view.server) {
            if view.host.is_empty() {
                view.host = address.host;
                view.port = i64::from(address.port);
            }
        }
        view
    }
}

/// What a `ConnectionChanged`, `NetworkQuestion` or
/// `NetworkQuestionWithdrawn` event says.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NetworkEventView {
    pub server: String,
    pub state: Option<ConnectionStateView>,
    pub question: Option<NetworkQuestionView>,
    pub question_id: i64,
}

/// An operation with a server on one side or both: the sources on
/// `source_server` (on disk when `None`), the destination folder on
/// `destination_server`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NetworkOpRequestView {
    /// `Copy`, `Move`, `Delete` or `CalcSizes`.
    pub kind: OpKindView,
    pub sources: Vec<String>,
    pub source_server: Option<String>,
    pub destination: Option<String>,
    pub destination_server: Option<String>,
    pub new_name: Option<String>,
    pub conflicts: ConflictPolicyView,
    /// Modification times kept where the receiving side can set them.
    pub preserve_attributes: bool,
}

// ─── Events ───

/// Sends the connections' states and questions as events. Called when
/// the event stream is set up.
#[frb(ignore)]
pub fn install_listeners() {
    connection::set_listener(Some(Arc::new(|server, state| {
        app::emit(AppEvent {
            network: Some(NetworkEventView {
                server: server.to_string(),
                state: Some(ConnectionStateView::of(state)),
                question: None,
                question_id: 0,
            }),
            ..AppEvent::of(AppEventKind::ConnectionChanged, None)
        });
    })));
    prompt::set_listener(
        Some(Arc::new(|id, question| {
            app::emit(AppEvent {
                network: Some(NetworkEventView {
                    server: question.server().to_string(),
                    state: None,
                    question: Some(NetworkQuestionView::of(id, question)),
                    question_id: id as i64,
                }),
                ..AppEvent::of(AppEventKind::NetworkQuestion, None)
            });
        })),
        Some(Arc::new(|id| {
            app::emit(AppEvent {
                network: Some(NetworkEventView {
                    server: String::new(),
                    state: None,
                    question: None,
                    question_id: id as i64,
                }),
                ..AppEvent::of(AppEventKind::NetworkQuestionWithdrawn, None)
            });
        })),
    );
}

// ─── Addresses and connections ───

/// Reads an address as typed (`sftp://me@host:2222/srv`, `ftp://host`,
/// `https://…` for WebDAV, `me@host` as `default_protocol`).
#[frb(sync)]
pub fn parse_server_address(text: String, default_protocol: ProtocolView) -> ApiResult<ServerAddressView> {
    let address = ServerAddress::parse(&text, default_protocol.to_vfs())?;
    Ok(ServerAddressView::of(&address))
}

/// The key a connection made from `request` would have.
#[frb(sync)]
pub fn server_key(request: ConnectRequestView) -> ApiResult<String> {
    Ok(request.to_spec()?.address.key())
}

/// A new connection attempt's id, for [`connect_server`] and
/// [`cancel_connect`].
#[frb(sync)]
pub fn begin_connect() -> i64 {
    tasks::begin().0
}

/// Connects (or answers the connection open to the same server and
/// user); questions come as events meanwhile. A cancelled attempt fails
/// with `Cancelled`.
pub fn connect_server(attempt: i64, request: ConnectRequestView) -> ApiResult<ConnectionView> {
    let spec = request.to_spec()?;
    let cancel = tasks::flag(attempt).unwrap_or_default();
    let result = connection::connect(spec.clone(), &|| cancel.load(Ordering::SeqCst));
    tasks::end(attempt);
    if result.as_ref().is_err_and(|e| e.kind == ferryx_vfs::VfsErrorKind::Cancelled) {
        // Its questions no longer wait.
        prompt::withdraw(&spec.address.key());
    }
    let server = result?;
    let home = if spec.address.path.is_empty() { server.fs().home() } else { spec.address.path.clone() };
    Ok(ConnectionView {
        server: server.key().to_string(),
        display: server.address().display_root(),
        home,
        protocol: ProtocolView::of(server.address().protocol),
        secure: server.address().protocol.is_secure(),
    })
}

/// Gives up the attempt `attempt`; its questions are withdrawn.
#[frb(sync)]
pub fn cancel_connect(attempt: i64) {
    tasks::cancel(attempt);
}

/// Closes every connection to `server`; its questions are withdrawn.
pub fn disconnect_server(server: String) {
    connection::disconnect(&server);
}

/// Every server open, with its state.
#[frb(sync)]
pub fn list_servers() -> Vec<ServerStateView> {
    connection::servers()
        .into_iter()
        .map(|(server, state)| ServerStateView {
            display: address::parse_key(&server).map(|a| a.display_root()).unwrap_or_else(|_| server.clone()),
            server,
            state: ConnectionStateView::of(state),
        })
        .collect()
}

/// The user's answer to the question `id`: `accept` false is Cancel;
/// `texts` the password, the passphrase or the prompts' answers;
/// `remember` keeps a password in the system's keychain, a host key in
/// Ferryx's known_hosts.
#[frb(sync)]
pub fn answer_network_question(id: i64, accept: bool, texts: Vec<String>, remember: bool) {
    prompt::answer(id as u64, Answer { accept, texts, remember });
}

/// Forgets the password the keychain keeps for `server`.
pub fn forget_server_password(server: String) -> ApiResult<()> {
    Ok(remote::secrets::store().delete(&server)?)
}

// ─── Items on a server ───

fn server_of(server: &str) -> ApiResult<Arc<remote::Server>> {
    Ok(connection::get(server)?)
}

fn valid_name(name: &str) -> ApiResult<()> {
    if name.is_empty() || name == "." || name == ".." || name.contains('/') || name.contains('\0') {
        return Err(FerryxError::new(FerryxErrorKind::InvalidName, format!("“{name}” is not a valid name")));
    }
    Ok(())
}

/// Makes the folder at `path` on `server`.
pub fn remote_make_folder(server: String, path: String) -> ApiResult<()> {
    valid_name(address::name(&path))?;
    Ok(server_of(&server)?.fs().mkdir(&path, &never)?)
}

/// Makes an empty file at `path` on `server`; one there already is an
/// error.
pub fn remote_make_file(server: String, path: String) -> ApiResult<()> {
    valid_name(address::name(&path))?;
    let server = server_of(&server)?;
    if server.fs().stat(&path, &never)?.is_some() {
        return Err(FerryxError::new(FerryxErrorKind::AlreadyExists, format!("{path} already exists")));
    }
    let writer = server.fs().create(&path, Some(0), &never)?;
    Ok(writer.finish(&never)?)
}

/// Renames the item at `path` on `server` to `new_name`; answers its new
/// path.
pub fn remote_rename(server: String, path: String, new_name: String) -> ApiResult<String> {
    valid_name(&new_name)?;
    let dir = address::parent(&path).unwrap_or_else(|| "/".to_string());
    let target = address::join(&dir, &new_name);
    server_of(&server)?.fs().rename(&path, &target, &never)?;
    Ok(target)
}

/// The item at `path` on `server`, if there is one.
pub fn remote_stat(server: String, path: String) -> ApiResult<Option<EntryView>> {
    Ok(server_of(&server)?.fs().stat(&path, &never)?.as_ref().map(EntryView::from))
}

/// The first free name in `dir` on `server` for a new item: `name`, else
/// `name 2`…
pub fn remote_free_name(server: String, dir: String, name: String) -> ApiResult<String> {
    let rows = server_of(&server)?.fs().list(&dir, &never)?;
    let taken: std::collections::HashSet<&str> = rows.iter().map(|e| e.name.as_str()).collect();
    if !taken.contains(name.as_str()) {
        return Ok(name);
    }
    let (stem, ext) = ferryx_core::entry::split_name(&name);
    for n in 2.. {
        let candidate = if ext.is_empty() { format!("{stem} {n}") } else { format!("{stem} {n}.{ext}") };
        if !taken.contains(candidate.as_str()) {
            return Ok(candidate);
        }
    }
    unreachable!()
}

/// A new folder in the temporary folder for a copy of a server's file to
/// open with an application (an operation copies it there).
pub fn remote_temp_folder(server: String) -> ApiResult<String> {
    let host = address::parse_key(&server).map(|a| a.host).unwrap_or_else(|_| "server".to_string());
    let hash = server.bytes().fold(0u64, |h, b| h.wrapping_mul(1099511628211).wrapping_add(u64::from(b)));
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or_default();
    let dir = std::env::temp_dir().join("Ferryx").join(format!("{host}-{hash:x}")).join(format!("{stamp:x}"));
    std::fs::create_dir_all(&dir).map_err(|e| ferryx_vfs::VfsError::io(&e, &dir))?;
    Ok(dir.to_string_lossy().into_owned())
}

// ─── Operations ───

/// Starts an operation with a server on one side or both; its progress
/// comes as `OperationProgress` events, its sources and destination named
/// `<server key><path>`. Not on the undo journal.
pub fn start_network_operation(request: NetworkOpRequestView) -> ApiResult<i64> {
    let side = |server: &Option<String>| -> ApiResult<Side> {
        Ok(match server {
            Some(key) => Side::Remote(server_of(key)?),
            None => Side::Native,
        })
    };
    let from = side(&request.source_server)?;
    let to = match &request.destination {
        Some(dir) => Some((side(&request.destination_server)?, dir.clone())),
        None => None,
    };
    let shown = OpRequestView {
        kind: request.kind,
        sources: Vec::new(),
        archive: None,
        destination: None,
        new_name: None,
        conflicts: request.conflicts,
        preserve_attributes: request.preserve_attributes,
        verify: false,
        password: None,
        into_folders: false,
    }
    .to_ops();
    let kind = shown.kind;
    if !matches!(
        kind,
        ferryx_ops::OpKind::Copy
            | ferryx_ops::OpKind::Move
            | ferryx_ops::OpKind::Delete
            | ferryx_ops::OpKind::CalcSizes
    ) {
        return Err(FerryxError::new(
            FerryxErrorKind::Unsupported,
            format!("{kind:?} does not reach a server"),
        ));
    }
    let job = Transfer {
        kind,
        from,
        sources: request.sources.clone(),
        to,
        new_name: request.new_name.clone(),
        options: shown.options,
    };
    let id = app::runner().start_job(
        job.shown_as(),
        ferryx_ops::runner::Journaling::Off,
        Box::new(move |ctx| transfer::run(ctx, &job)),
    );
    Ok(id as i64)
}
