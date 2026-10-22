//! A real shell in a real pseudo-terminal: output, input, size, the
//! shell's state, the folder it is told to go to, flow control, its end.
#![cfg(unix)]

use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use ferryx_term::{Event, Session, SessionConfig, ShellState, TermErrorKind, BATCH_LIMIT};

const TIMEOUT: Duration = Duration::from_secs(10);

/// A session of `/bin/sh` with an empty home, and what it has said.
struct Shell {
    session: Session,
    events: mpsc::Receiver<Event>,
    output: String,
    states: Vec<ShellState>,
    exited: Option<Option<i32>>,
    batches: usize,
    _home: tempfile::TempDir,
}

impl Shell {
    fn start(folder: Option<&Path>) -> Shell {
        let home = tempfile::tempdir().unwrap();
        let session = Session::spawn(SessionConfig {
            shell: Some("/bin/sh".into()),
            folder: folder.map(Path::to_path_buf),
            cols: 80,
            rows: 24,
            locale: None,
            env: vec![
                ("HOME".into(), home.path().to_string_lossy().into_owned()),
                ("ENV".into(), String::new()),
                ("PS1".into(), "$ ".into()),
            ],
        })
        .expect("shell starts");
        let (tx, events) = mpsc::channel();
        session.attach(Box::new(move |event| {
            let _ = tx.send(event);
        }));
        Shell {
            session,
            events,
            output: String::new(),
            states: Vec::new(),
            exited: None,
            batches: 0,
            _home: home,
        }
    }

    /// Takes events, acknowledging output, until `done` holds.
    fn until(&mut self, what: &str, done: impl Fn(&Shell) -> bool) {
        let deadline = Instant::now() + TIMEOUT;
        while !done(self) {
            let left = deadline.saturating_duration_since(Instant::now());
            match self.events.recv_timeout(left) {
                Ok(Event::Output(bytes)) => {
                    assert!(bytes.len() <= BATCH_LIMIT);
                    self.batches += 1;
                    self.output.push_str(&String::from_utf8_lossy(&bytes));
                    self.session.ack();
                }
                Ok(Event::State(state)) => self.states.push(state),
                Ok(Event::Exited(code)) => self.exited = Some(code),
                Err(_) => panic!("timed out waiting for {what}; output so far: {:?}", self.output),
            }
        }
    }

    fn type_line(&self, line: &str) {
        self.session.write(format!("{line}\r").into_bytes()).unwrap();
    }

    fn wait_output(&mut self, needle: &str) {
        self.until(needle, |s| s.output.contains(needle));
    }

    /// Waits for a state at the prompt in `folder`.
    fn wait_idle_in(&mut self, folder: &Path) {
        let folder = folder.to_path_buf();
        self.until("the prompt there", |s| {
            s.states.last().is_some_and(|st| st.idle == Some(true) && st.folder.as_deref() == Some(&folder))
        });
    }
}

fn canonical(path: &Path) -> PathBuf {
    path.canonicalize().unwrap()
}

#[test]
fn echoes_what_is_typed() {
    let mut shell = Shell::start(None);
    shell.type_line("echo fe''rryx-$((6*7))");
    shell.wait_output("ferryx-42");
}

#[test]
fn starts_in_the_folder_and_reports_it_at_the_prompt() {
    let dir = tempfile::tempdir().unwrap();
    let mut shell = Shell::start(Some(dir.path()));
    shell.wait_idle_in(&canonical(dir.path()));
    assert_eq!(shell.session.state().idle, Some(true));
}

#[test]
fn follows_cd_typed_in_the_shell() {
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    let mut shell = Shell::start(Some(first.path()));
    shell.wait_idle_in(&canonical(first.path()));
    shell.type_line(&format!("cd '{}'", second.path().display()));
    shell.wait_idle_in(&canonical(second.path()));
}

#[test]
fn busy_while_a_program_runs_idle_after() {
    let dir = tempfile::tempdir().unwrap();
    let mut shell = Shell::start(Some(dir.path()));
    shell.wait_idle_in(&canonical(dir.path()));
    shell.type_line("sleep 1");
    shell.until("the program in front", |s| s.session.state().idle == Some(false));
    shell.until("the prompt again", |s| {
        let busy = s.states.iter().position(|st| st.idle == Some(false));
        busy.is_some_and(|at| s.states[at..].iter().any(|st| st.idle == Some(true)))
    });
}

#[test]
fn change_directory_types_cd_at_the_prompt_only() {
    let start = tempfile::tempdir().unwrap();
    let target = tempfile::tempdir().unwrap();
    let odd = target.path().join("it's a \"folder\" $HOME");
    std::fs::create_dir(&odd).unwrap();
    let mut shell = Shell::start(Some(start.path()));
    shell.wait_idle_in(&canonical(start.path()));

    // Asked while a program runs, it is left alone.
    shell.type_line("sleep 1");
    shell.until("the program in front", |s| s.session.state().idle == Some(false));
    assert!(!shell.session.change_directory(odd.to_str().unwrap()).unwrap());
    shell.until("the prompt again", |s| s.session.state().idle == Some(true));

    assert!(shell.session.change_directory(odd.to_str().unwrap()).unwrap());
    // Reported as the interface spelled it.
    shell.wait_idle_in(&odd);
    // Already there: nothing more is typed.
    assert!(!shell.session.change_directory(odd.to_str().unwrap()).unwrap());
    // A folder that is not there, or a name with a newline, is not typed.
    assert!(!shell.session.change_directory("/no/such/folder").unwrap());
    assert!(!shell.session.change_directory("/tmp\nrm -rf ~").unwrap());
}

#[test]
fn reports_the_spelling_it_was_given_for_the_same_folder() {
    let real = tempfile::tempdir().unwrap();
    let links = tempfile::tempdir().unwrap();
    let link = links.path().join("link");
    std::os::unix::fs::symlink(real.path(), &link).unwrap();
    let mut shell = Shell::start(Some(links.path()));
    shell.wait_idle_in(&canonical(links.path()));
    assert!(shell.session.change_directory(link.to_str().unwrap()).unwrap());
    shell.wait_idle_in(&link);
}

#[test]
fn resizing_reaches_the_program() {
    let mut shell = Shell::start(None);
    shell.session.resize(101, 37).unwrap();
    shell.type_line("stty size");
    shell.wait_output("37 101");
}

#[test]
fn a_flood_arrives_whole_in_bounded_batches() {
    let mut shell = Shell::start(None);
    shell.type_line("yes ferryx | head -n 200000; echo flood-$((1+1))");
    let started = Instant::now();
    shell.wait_output("flood-2\r\n");
    let lines = shell.output.matches("ferryx\r\n").count();
    assert_eq!(lines, 200_000);
    // Far fewer events than reads: batched, never one per line.
    assert!(shell.batches < 1000, "{} batches", shell.batches);
    eprintln!("200000 lines in {:?}, {} batches", started.elapsed(), shell.batches);
}

#[test]
fn output_waits_for_acknowledgement() {
    let mut shell = Shell::start(None);
    shell.type_line("yes | head -n 100000; echo held-$((2+2))");
    // Take two batches without acknowledging them: nothing more comes.
    let mut held = 0;
    let deadline = Instant::now() + TIMEOUT;
    while held < 2 && Instant::now() < deadline {
        if let Ok(Event::Output(_)) = shell.events.recv_timeout(Duration::from_millis(500)) {
            held += 1;
        }
    }
    assert_eq!(held, 2);
    let quiet = shell.events.recv_timeout(Duration::from_millis(300));
    assert!(!matches!(quiet, Ok(Event::Output(_))), "output without credit");
    shell.session.ack();
    shell.session.ack();
    shell.wait_output("held-4");
}

#[test]
fn exit_ends_the_session_with_its_code() {
    let mut shell = Shell::start(None);
    shell.type_line("exit 3");
    shell.until("the end", |s| s.exited.is_some());
    assert_eq!(shell.exited, Some(Some(3)));
    assert!(shell.session.has_exited());
    assert_eq!(shell.session.write(b"echo late\r".to_vec()).unwrap_err().kind, TermErrorKind::Closed);
}

#[test]
fn closing_hangs_up_a_running_program() {
    let mut shell = Shell::start(None);
    shell.type_line("sleep 30");
    shell.until("the program in front", |s| s.session.state().idle == Some(false));
    let started = Instant::now();
    shell.session.close();
    shell.until("the end", |s| s.exited.is_some());
    assert!(started.elapsed() < Duration::from_secs(5));
}

#[test]
fn a_missing_shell_is_reported() {
    let error = match Session::spawn(SessionConfig {
        shell: Some("/no/such/shell".into()),
        cols: 80,
        rows: 24,
        ..SessionConfig::default()
    }) {
        Ok(_) => panic!("started a missing shell"),
        Err(error) => error,
    };
    assert_eq!(error.kind, TermErrorKind::NotFound);
}
