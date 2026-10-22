//! The terminal through the bridge: a shell started, typed into, resized,
//! followed to another folder, ended and closed.
#![cfg(unix)]

use std::path::Path;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use ferryx_api::api::terminal::*;
use ferryx_api::api::types::FerryxErrorKind;

const TIMEOUT: Duration = Duration::from_secs(10);

/// A `/bin/sh` session and its events, as the interface would see them.
struct Flow {
    id: i64,
    events: mpsc::Receiver<TerminalEvent>,
    output: String,
    last_state: Option<(Option<bool>, Option<String>)>,
    exit: Option<Option<i32>>,
}

impl Flow {
    fn start(folder: &Path) -> Flow {
        let id = terminal_start(TerminalStartView {
            shell: Some("/bin/sh".into()),
            folder: Some(folder.to_string_lossy().into_owned()),
            cols: 80,
            rows: 24,
            locale: Some("en_US".into()),
        })
        .expect("shell starts");
        let (tx, events) = mpsc::channel();
        terminal_listen(id, move |event| {
            let _ = tx.send(event);
        })
        .unwrap();
        Flow { id, events, output: String::new(), last_state: None, exit: None }
    }

    fn until(&mut self, what: &str, done: impl Fn(&Flow) -> bool) {
        let deadline = Instant::now() + TIMEOUT;
        while !done(self) {
            let event = self
                .events
                .recv_timeout(deadline.saturating_duration_since(Instant::now()))
                .unwrap_or_else(|_| panic!("timed out waiting for {what}: {:?}", self.output));
            match event.kind {
                TerminalEventKind::Output => {
                    self.output.push_str(&String::from_utf8_lossy(&event.output));
                    terminal_ack(self.id);
                }
                TerminalEventKind::State => self.last_state = Some((event.idle, event.folder)),
                TerminalEventKind::Exited => self.exit = Some(event.exit_code),
            }
        }
    }

    fn type_line(&self, line: &str) {
        terminal_write(self.id, format!("{line}\r").into_bytes()).unwrap();
    }

    fn at_prompt_in(&mut self, folder: &str) {
        let folder = folder.to_string();
        self.until("the prompt", |f| f.last_state == Some((Some(true), Some(folder.clone()))));
    }
}

fn canonical(path: &Path) -> String {
    path.canonicalize().unwrap().to_string_lossy().into_owned()
}

#[test]
fn a_session_from_start_to_end() {
    let start = tempfile::tempdir().unwrap();
    let other = tempfile::tempdir().unwrap();
    let mut flow = Flow::start(start.path());

    flow.at_prompt_in(&canonical(start.path()));
    let state = terminal_state(flow.id).unwrap();
    assert_eq!(state.idle, Some(true));
    assert_eq!(state.folder, Some(canonical(start.path())));

    flow.type_line("echo bridge-$((40+2))");
    flow.until("the echo", |f| f.output.contains("bridge-42"));

    terminal_resize(flow.id, 120, 40).unwrap();
    flow.type_line("stty size");
    flow.until("the new size", |f| f.output.contains("40 120"));

    // The panel went elsewhere: the shell follows.
    let target = other.path().to_string_lossy().into_owned();
    assert!(terminal_change_directory(flow.id, target.clone()).unwrap());
    flow.at_prompt_in(&target);

    // A cd typed in the shell is reported back.
    flow.type_line(&format!("cd '{}'", start.path().display()));
    flow.at_prompt_in(&canonical(start.path()));

    flow.type_line("exit 7");
    flow.until("the end", |f| f.exit.is_some());
    assert_eq!(flow.exit, Some(Some(7)));
    assert_eq!(terminal_write(flow.id, b"x".to_vec()).unwrap_err().kind, FerryxErrorKind::NotFound);

    terminal_close(flow.id);
    assert_eq!(terminal_state(flow.id).unwrap_err().kind, FerryxErrorKind::NotFound);
}

#[test]
fn closing_a_busy_session_ends_it() {
    let dir = tempfile::tempdir().unwrap();
    let mut flow = Flow::start(dir.path());
    flow.type_line("sleep 30");
    flow.until("the program in front", |f| terminal_state(f.id).unwrap().idle == Some(false));
    let started = Instant::now();
    terminal_close(flow.id);
    flow.until("the end", |f| f.exit.is_some());
    assert!(started.elapsed() < Duration::from_secs(5));
}

#[test]
fn a_bad_shell_is_a_typed_error() {
    let error = terminal_start(TerminalStartView {
        shell: Some("/no/such/shell".into()),
        folder: None,
        cols: 80,
        rows: 24,
        locale: None,
    })
    .unwrap_err();
    assert_eq!(error.kind, FerryxErrorKind::NotFound);
    assert_eq!(error.path.as_deref(), Some("/no/such/shell"));
}

#[test]
fn unknown_sessions_are_not_found() {
    assert_eq!(terminal_write(-1, b"x".to_vec()).unwrap_err().kind, FerryxErrorKind::NotFound);
    assert_eq!(terminal_resize(-1, 80, 24).unwrap_err().kind, FerryxErrorKind::NotFound);
    terminal_ack(-1);
    terminal_close(-1);
}

#[test]
fn the_default_shell_is_named() {
    let shell = terminal_default_shell();
    assert!(Path::new(&shell).is_absolute(), "{shell}");
}
