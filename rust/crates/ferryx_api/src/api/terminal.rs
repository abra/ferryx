//! The integrated terminal: a shell per session in a pseudo-terminal
//! (`ferryx_term`). A session's output, state and end come on its own
//! stream ([`terminal_events`]), not the app's event stream: output is
//! high-volume and flow-controlled by [`terminal_ack`].

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, LazyLock};

use ferryx_term::{Event, Session, SessionConfig, ShellState, TermError, TermErrorKind};
use flutter_rust_bridge::frb;
use parking_lot::Mutex;

use crate::api::types::{ApiResult, FerryxError, FerryxErrorKind};
use crate::frb_generated::StreamSink;

/// What a session runs, where and how large.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TerminalStartView {
    /// The shell from the settings; the user's own when `None` or empty.
    pub shell: Option<String>,
    /// The folder to start in; the home folder when missing.
    pub folder: Option<String>,
    pub cols: u16,
    pub rows: u16,
    /// The system's language and region (`ru_RU`), for `LANG` when the
    /// environment names no locale.
    pub locale: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TerminalEventKind {
    /// `output` to show; [`terminal_ack`] once it is parsed.
    Output,
    /// The shell's state changed: `idle`, `folder`.
    State,
    /// The shell ended: `exit_code`, `None` when a signal ended it.
    Exited,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TerminalEvent {
    pub kind: TerminalEventKind,
    pub output: Vec<u8>,
    pub idle: Option<bool>,
    pub folder: Option<String>,
    pub exit_code: Option<i32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TerminalStateView {
    /// The shell waits at its prompt (`None` where the system cannot tell).
    pub idle: Option<bool>,
    pub folder: Option<String>,
}

static SESSIONS: LazyLock<Mutex<HashMap<i64, Arc<Session>>>> = LazyLock::new(Default::default);
static NEXT_ID: AtomicI64 = AtomicI64::new(1);

/// The session `id`; the lock is not held while it is used.
fn session(id: i64) -> ApiResult<Arc<Session>> {
    SESSIONS
        .lock()
        .get(&id)
        .cloned()
        .ok_or_else(|| FerryxError::new(FerryxErrorKind::NotFound, "No such terminal session"))
}

/// Starts a shell and answers the session's id; its output waits for
/// [`terminal_events`].
pub fn terminal_start(options: TerminalStartView) -> ApiResult<i64> {
    let session = Session::spawn(SessionConfig {
        shell: options.shell,
        folder: options.folder.map(PathBuf::from),
        cols: options.cols,
        rows: options.rows,
        locale: options.locale,
        env: Vec::new(),
    })?;
    let id = NEXT_ID.fetch_add(1, Ordering::SeqCst);
    SESSIONS.lock().insert(id, Arc::new(session));
    Ok(id)
}

/// The session's events from now on; output starts flowing. An unknown
/// session's stream closes at once.
pub fn terminal_events(id: i64, sink: StreamSink<TerminalEvent>) {
    if let Ok(session) = session(id) {
        session.attach(Box::new(move |event| {
            // A closed sink only means the listener went away.
            let _ = sink.add(TerminalEvent::from(event));
        }));
    }
}

/// Types `data` (UTF-8 text, escape sequences) into the shell. Sync, so
/// keystrokes keep their order; it only queues them for the writer.
#[frb(sync)]
pub fn terminal_write(id: i64, data: Vec<u8>) -> ApiResult<()> {
    Ok(session(id)?.write(data)?)
}

/// The view's size in character cells.
#[frb(sync)]
pub fn terminal_resize(id: i64, cols: u16, rows: u16) -> ApiResult<()> {
    Ok(session(id)?.resize(cols, rows)?)
}

/// One `Output` event has been parsed: the next may come.
#[frb(sync)]
pub fn terminal_ack(id: i64) {
    if let Ok(session) = session(id) {
        session.ack();
    }
}

/// The shell's state now.
#[frb(sync)]
pub fn terminal_state(id: i64) -> ApiResult<TerminalStateView> {
    Ok(TerminalStateView::from(session(id)?.state()))
}

/// Types `cd -- '<folder>'` and Return when the shell waits at its prompt
/// somewhere else; answers whether it did.
pub fn terminal_change_directory(id: i64, folder: String) -> ApiResult<bool> {
    Ok(session(id)?.change_directory(&folder)?)
}

/// Hangs up the shell and forgets the session.
pub fn terminal_close(id: i64) {
    let session = SESSIONS.lock().remove(&id);
    if let Some(session) = session {
        session.close();
    }
}

/// The shell a session runs when the settings name none.
#[frb(sync)]
pub fn terminal_default_shell() -> String {
    ferryx_term::shell::default_shell().to_string_lossy().into_owned()
}

/// Sends the session's events to `listener` instead of a Dart stream: the
/// flows under `tests/` read them. Not part of the bridge.
#[frb(ignore)]
pub fn terminal_listen(id: i64, listener: impl Fn(TerminalEvent) + Send + Sync + 'static) -> ApiResult<()> {
    session(id)?.attach(Box::new(move |event| listener(TerminalEvent::from(event))));
    Ok(())
}

/// Closes every session. Not part of the bridge.
#[frb(ignore)]
pub fn terminal_close_all() {
    let sessions: Vec<_> = SESSIONS.lock().drain().map(|(_, s)| s).collect();
    for session in sessions {
        session.close();
    }
}

impl From<Event> for TerminalEvent {
    fn from(event: Event) -> Self {
        let empty = TerminalEvent {
            kind: TerminalEventKind::Output,
            output: Vec::new(),
            idle: None,
            folder: None,
            exit_code: None,
        };
        match event {
            Event::Output(output) => TerminalEvent { output, ..empty },
            Event::State(state) => {
                let view = TerminalStateView::from(state);
                TerminalEvent {
                    kind: TerminalEventKind::State,
                    idle: view.idle,
                    folder: view.folder,
                    ..empty
                }
            }
            Event::Exited(exit_code) => TerminalEvent { kind: TerminalEventKind::Exited, exit_code, ..empty },
        }
    }
}

impl From<ShellState> for TerminalStateView {
    fn from(state: ShellState) -> Self {
        TerminalStateView { idle: state.idle, folder: state.folder.map(|f| f.to_string_lossy().into_owned()) }
    }
}

impl From<TermError> for FerryxError {
    fn from(error: TermError) -> Self {
        let kind = match error.kind {
            TermErrorKind::NotFound => FerryxErrorKind::NotFound,
            TermErrorKind::PermissionDenied => FerryxErrorKind::PermissionDenied,
            TermErrorKind::Unsupported => FerryxErrorKind::Unsupported,
            // Input to a shell that has ended: the session is gone.
            TermErrorKind::Closed => FerryxErrorKind::NotFound,
            TermErrorKind::Io => FerryxErrorKind::Io,
        };
        FerryxError { kind, message: error.message, path: error.path }
    }
}
