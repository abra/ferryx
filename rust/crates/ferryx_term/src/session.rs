//! One shell in a pseudo-terminal, with three threads of its own:
//!
//! - the reader takes the shell's output in chunks into a bounded channel;
//! - the pump gathers the chunks into batches ([`Batcher`]) and sends them
//!   to the listener while it has credit, probes the shell's state when the
//!   output goes quiet, and reaps the shell when it ends;
//! - the writer types what the interface sends, in order.
//!
//! Flow control: each batch spends a credit and the interface gives it back
//! ([`Session::ack`]) once it has parsed the batch. Without credit the pump
//! stops taking chunks, the channel fills, the reader stops reading and the
//! kernel's buffer stops the program writing, as a real terminal does: a
//! command that floods output can never flood the interface.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crossbeam_channel::{bounded, unbounded, Receiver, SendTimeoutError, Sender};
use parking_lot::{Condvar, Mutex};
use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize};

use crate::batch::{Batcher, Next};
use crate::error::{TermError, TermErrorKind};
use crate::process;
use crate::pty_io::{InputSink, OutputSource};
use crate::shell;

/// At most one batch per this long while output flows.
pub const WINDOW: Duration = Duration::from_millis(10);
/// At most this many bytes per batch.
pub const BATCH_LIMIT: usize = 64 * 1024;
/// Batches the listener may have in hand before it acknowledges one.
pub const CREDITS: u32 = 2;
/// The state is probed this long after the output stops…
const QUIET: Duration = Duration::from_millis(40);
/// …and this often while nothing happens.
const POLL: Duration = Duration::from_millis(400);
/// The longest wait of a thread before it looks at the stop flag.
const SLICE: Duration = Duration::from_millis(100);
const READ_CHUNK: usize = 64 * 1024;
/// Chunks read ahead of the pump: 2 MiB at most.
const READ_AHEAD: usize = 32;
/// How long a shell that has exited may leave its terminal open (a
/// background job holding it) before the session ends anyway.
const EXIT_GRACE: Duration = Duration::from_millis(300);
/// How long a closed session's shell has to end on SIGHUP before SIGKILL.
const KILL_GRACE: Duration = Duration::from_millis(1000);

/// What a session runs, where, and how large.
#[derive(Clone, Debug, Default)]
pub struct SessionConfig {
    /// The shell from the settings; the user's shell when `None` or empty.
    pub shell: Option<String>,
    /// The folder the shell starts in; the home folder when missing.
    pub folder: Option<PathBuf>,
    pub cols: u16,
    pub rows: u16,
    /// The system's language and region (`ru_RU`), for `LANG` when the
    /// environment names no locale.
    pub locale: Option<String>,
    /// Variables set last, over everything else (tests make the shell's
    /// home a temporary folder).
    pub env: Vec<(String, String)>,
}

/// The shell as the system sees it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ShellState {
    /// Whether the shell itself is in front, waiting at its prompt, rather
    /// than a program it runs; `None` where the system cannot tell.
    pub idle: Option<bool>,
    /// The shell's current folder, spelled as the interface last asked for
    /// it when it is the same folder (`/tmp`, not `/private/tmp`).
    pub folder: Option<PathBuf>,
}

/// What a session tells its listener.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Event {
    /// Output to show; acknowledge it with [`Session::ack`].
    Output(Vec<u8>),
    /// The shell's state changed.
    State(ShellState),
    /// The shell ended: its exit code, `None` when a signal ended it.
    Exited(Option<i32>),
}

pub type Listener = Box<dyn Fn(Event) + Send + Sync>;

/// A running shell. Dropping it closes the session.
pub struct Session {
    inner: Arc<Inner>,
}

struct Inner {
    master: Mutex<Box<dyn MasterPty + Send>>,
    /// Input for the writer thread; taken when the session ends.
    input: Mutex<Option<Sender<Vec<u8>>>>,
    program: PathBuf,
    shell_pid: Option<u32>,
    listener: Mutex<Option<Listener>>,
    credits: Mutex<u32>,
    credit_changed: Condvar,
    /// Set by [`Session::close`].
    closing: AtomicBool,
    /// Tells the reader and writer to stop.
    stop: AtomicBool,
    exited: AtomicBool,
    /// The folder last typed, as the interface spelled it and as the
    /// system resolves it.
    alias: Mutex<Option<(String, PathBuf)>>,
}

impl Session {
    /// Starts the shell. Output waits until a listener is
    /// [attached](Session::attach).
    pub fn spawn(config: SessionConfig) -> Result<Session, TermError> {
        let program = shell::resolve_shell(config.shell.as_deref())?;
        let size = pty_size(config.cols, config.rows);
        let pair = native_pty_system()
            .openpty(size)
            .map_err(|e| TermError::new(TermErrorKind::Unsupported, format!("No pseudo-terminal: {e}")))?;
        let command = command_for(&program, &config);
        let child = pair.slave.spawn_command(command).map_err(|e| {
            TermError::io("Could not start the shell", e).with_path(program.to_string_lossy())
        })?;
        // The child has its own copies; ours would keep the terminal open
        // after the shell ends.
        drop(pair.slave);
        let shell_pid = child.process_id();
        let (source, sink) = io_for(pair.master.as_ref())?;

        let (input_tx, input_rx) = unbounded::<Vec<u8>>();
        let inner = Arc::new(Inner {
            master: Mutex::new(pair.master),
            input: Mutex::new(Some(input_tx)),
            program,
            shell_pid,
            listener: Mutex::new(None),
            credits: Mutex::new(0),
            credit_changed: Condvar::new(),
            closing: AtomicBool::new(false),
            stop: AtomicBool::new(false),
            exited: AtomicBool::new(false),
            alias: Mutex::new(None),
        });

        let (output_tx, output_rx) = bounded::<Vec<u8>>(READ_AHEAD);
        let name = |what: &str| format!("terminal {what} {}", shell_pid.unwrap_or_default());
        let reader = inner.clone();
        spawn_thread(name("reader"), move || read_loop(source, output_tx, &reader))?;
        let writer = inner.clone();
        spawn_thread(name("writer"), move || write_loop(sink, input_rx, &writer))?;
        let pump = inner.clone();
        spawn_thread(name("pump"), move || pump_loop(&pump, output_rx, child))?;
        Ok(Session { inner })
    }

    /// Sends every event to `listener` from now on and lets output flow.
    pub fn attach(&self, listener: Listener) {
        *self.inner.listener.lock() = Some(listener);
        *self.inner.credits.lock() = CREDITS;
        self.inner.credit_changed.notify_all();
    }

    /// The listener has parsed one [`Event::Output`].
    pub fn ack(&self) {
        let mut credits = self.inner.credits.lock();
        *credits = (*credits + 1).min(CREDITS);
        self.inner.credit_changed.notify_all();
    }

    /// Types `data` into the shell, after what was typed before.
    pub fn write(&self, data: Vec<u8>) -> Result<(), TermError> {
        if data.is_empty() {
            return Ok(());
        }
        let input = self.inner.input.lock();
        match input.as_ref() {
            Some(tx) if !self.inner.exited.load(Ordering::SeqCst) => tx.send(data).map_err(|_| closed()),
            _ => Err(closed()),
        }
    }

    /// The view's size in character cells.
    pub fn resize(&self, cols: u16, rows: u16) -> Result<(), TermError> {
        if self.inner.exited.load(Ordering::SeqCst) {
            return Ok(());
        }
        self.inner
            .master
            .lock()
            .resize(pty_size(cols, rows))
            .map_err(|e| TermError::io("Could not resize", e))
    }

    /// The shell's state now.
    pub fn state(&self) -> ShellState {
        self.inner.probe()
    }

    /// Types `cd` to `folder` when the shell waits at its prompt and is
    /// somewhere else; answers whether it did. A folder that does not
    /// exist, or whose name a line cannot carry, is left alone.
    pub fn change_directory(&self, folder: &str) -> Result<bool, TermError> {
        if self.inner.exited.load(Ordering::SeqCst) {
            return Err(closed());
        }
        let Some(line) = shell::cd_line(folder) else { return Ok(false) };
        let Ok(target) = std::fs::canonicalize(folder) else { return Ok(false) };
        if !target.is_dir() {
            return Ok(false);
        }
        let state = self.inner.probe();
        *self.inner.alias.lock() = Some((folder.to_string(), target.clone()));
        if state.idle != Some(true) {
            return Ok(false);
        }
        let current = self.inner.shell_pid.and_then(process::folder_of);
        if current.as_deref() == Some(target.as_path()) {
            return Ok(false);
        }
        self.write(line.into_bytes())?;
        Ok(true)
    }

    /// The shell program.
    pub fn program(&self) -> &Path {
        &self.inner.program
    }

    pub fn has_exited(&self) -> bool {
        self.inner.exited.load(Ordering::SeqCst)
    }

    /// Hangs up the shell and what runs in front of it; the pump reaps
    /// them (SIGKILL after a grace) and the threads end. Idempotent.
    pub fn close(&self) {
        let inner = &self.inner;
        if inner.closing.swap(true, Ordering::SeqCst) {
            return;
        }
        if !inner.exited.load(Ordering::SeqCst) {
            inner.hang_up();
        }
        inner.input.lock().take();
        inner.credit_changed.notify_all();
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.close();
    }
}

impl Inner {
    fn emit(&self, event: Event) {
        if let Some(listener) = self.listener.lock().as_ref() {
            listener(event);
        }
    }

    /// Waits up to `timeout` for a listener with credit; whether there is.
    fn wait_credit(&self, timeout: Duration) -> bool {
        let mut credits = self.credits.lock();
        if *credits == 0 {
            self.credit_changed.wait_for(&mut credits, timeout);
        }
        *credits > 0
    }

    fn spend_credit(&self) {
        let mut credits = self.credits.lock();
        *credits = credits.saturating_sub(1);
    }

    fn probe(&self) -> ShellState {
        let idle = self.foreground().map(|group| self.shell_pid.is_some_and(|pid| pid as i64 == group));
        let folder = self.shell_pid.and_then(process::folder_of).map(|folder| match &*self.alias.lock() {
            Some((spelled, resolved)) if *resolved == folder => PathBuf::from(spelled),
            _ => folder,
        });
        ShellState { idle, folder }
    }

    /// The terminal's foreground process group.
    #[cfg(unix)]
    fn foreground(&self) -> Option<i64> {
        self.master.lock().process_group_leader().map(i64::from)
    }

    #[cfg(not(unix))]
    fn foreground(&self) -> Option<i64> {
        None
    }

    #[cfg(unix)]
    fn hang_up(&self) {
        let shell = self.shell_pid.and_then(|pid| libc::pid_t::try_from(pid).ok());
        // SAFETY: plain signal sends to processes this session started.
        unsafe {
            if let Some(group) = self.foreground().and_then(|g| libc::pid_t::try_from(g).ok()) {
                if Some(group) != shell {
                    libc::killpg(group, libc::SIGHUP);
                }
            }
            if let Some(pid) = shell {
                libc::kill(pid, libc::SIGHUP);
            }
        }
    }

    #[cfg(not(unix))]
    fn hang_up(&self) {
        // The pump terminates the process; ConPTY closes with it.
    }
}

fn closed() -> TermError {
    TermError::new(TermErrorKind::Closed, "The shell has exited")
}

fn pty_size(cols: u16, rows: u16) -> PtySize {
    PtySize { rows: rows.clamp(1, 1000), cols: cols.clamp(1, 1000), pixel_width: 0, pixel_height: 0 }
}

fn spawn_thread(name: String, body: impl FnOnce() + Send + 'static) -> Result<(), TermError> {
    std::thread::Builder::new()
        .name(name)
        .spawn(body)
        .map(drop)
        .map_err(|e| TermError::io("Could not start a thread", e))
}

/// The shell as a login shell (`-zsh` as its name, as Terminal.app runs
/// it), in `folder`, with a terminal type programs know and a UTF-8 locale.
fn command_for(program: &Path, config: &SessionConfig) -> CommandBuilder {
    #[cfg(unix)]
    let mut command = {
        // The default program is `$SHELL` run as a login shell.
        let mut command = CommandBuilder::new_default_prog();
        command.env("SHELL", program);
        command
    };
    #[cfg(windows)]
    let mut command = {
        let mut command = CommandBuilder::new(program);
        let name = program.file_name().map(|n| n.to_string_lossy().to_lowercase()).unwrap_or_default();
        if name.starts_with("pwsh") || name.starts_with("powershell") {
            command.arg("-NoLogo");
        }
        command
    };
    if let Some(folder) = &config.folder {
        command.cwd(folder);
    }
    for key in shell::FOREIGN_VARIABLES {
        command.env_remove(key);
    }
    command.env("TERM", "xterm-256color");
    command.env("COLORTERM", "truecolor");
    command.env("TERM_PROGRAM", "Ferryx");
    command.env("TERM_PROGRAM_VERSION", env!("CARGO_PKG_VERSION"));
    let has_locale =
        shell::has_locale(|key| command.get_env(key).and_then(|v| v.to_str()).map(str::to_string));
    if !has_locale {
        command.env("LANG", shell::utf8_locale(config.locale.as_deref(), shell::locale_exists));
    }
    for (key, value) in &config.env {
        command.env(key, value);
    }
    command
}

#[cfg(unix)]
fn io_for(master: &dyn MasterPty) -> Result<(impl OutputSource, impl InputSink), TermError> {
    let fd = master
        .as_raw_fd()
        .ok_or_else(|| TermError::new(TermErrorKind::Unsupported, "The terminal has no descriptor"))?;
    crate::pty_io::source_and_sink(fd).map_err(|e| TermError::io("Could not open the terminal", e))
}

#[cfg(windows)]
fn io_for(master: &dyn MasterPty) -> Result<(impl OutputSource, impl InputSink), TermError> {
    let reader = master.try_clone_reader().map_err(|e| TermError::io("Could not read the terminal", e))?;
    let writer = master.take_writer().map_err(|e| TermError::io("Could not write the terminal", e))?;
    Ok((crate::pty_io::BlockingSource(reader), crate::pty_io::BlockingSink(writer)))
}

fn read_loop(mut source: impl OutputSource, tx: Sender<Vec<u8>>, inner: &Inner) {
    let mut buf = vec![0u8; READ_CHUNK];
    loop {
        let n = match source.read(&mut buf, &inner.stop) {
            Ok(0) | Err(_) => return,
            Ok(n) => n,
        };
        let mut chunk = buf[..n].to_vec();
        loop {
            match tx.send_timeout(chunk, SLICE) {
                Ok(()) => break,
                Err(SendTimeoutError::Timeout(back)) if !inner.stop.load(Ordering::SeqCst) => chunk = back,
                Err(_) => return,
            }
        }
    }
}

fn write_loop(mut sink: impl InputSink, rx: Receiver<Vec<u8>>, inner: &Inner) {
    while let Ok(data) = rx.recv() {
        if sink.write_all(&data, &inner.stop).is_err() {
            return;
        }
    }
}

fn pump_loop(inner: &Inner, rx: Receiver<Vec<u8>>, mut child: Box<dyn Child + Send + Sync>) {
    let mut batcher = Batcher::new(WINDOW, BATCH_LIMIT);
    let mut last_state: Option<ShellState> = None;
    let mut probe_at = Instant::now() + POLL;
    let mut shell_ended: Option<(Instant, Option<i32>)> = None;
    while !inner.closing.load(Ordering::SeqCst) {
        if !inner.wait_credit(SLICE) {
            continue;
        }
        let wait = probe_at.saturating_duration_since(Instant::now()).clamp(Duration::from_millis(1), POLL);
        match batcher.next(&rx, wait) {
            Next::Batch(bytes) => {
                inner.spend_credit();
                inner.emit(Event::Output(bytes));
                probe_at = Instant::now() + QUIET;
            }
            Next::Idle => {
                if Instant::now() >= probe_at {
                    let state = inner.probe();
                    if last_state.as_ref() != Some(&state) {
                        inner.emit(Event::State(state.clone()));
                        last_state = Some(state);
                    }
                    probe_at = Instant::now() + POLL;
                }
                // A background job may hold the terminal open after the
                // shell has gone; the shell's end ends the session then.
                match shell_ended {
                    None => {
                        if let Ok(Some(status)) = child.try_wait() {
                            shell_ended = Some((Instant::now(), exit_code(&status)));
                        }
                    }
                    Some((at, _)) if at.elapsed() >= EXIT_GRACE => break,
                    Some(_) => {}
                }
            }
            Next::Closed => break,
        }
    }
    inner.stop.store(true, Ordering::SeqCst);
    let code = match shell_ended {
        Some((_, code)) => code,
        None => reap(inner, child.as_mut()),
    };
    inner.exited.store(true, Ordering::SeqCst);
    inner.input.lock().take();
    inner.emit(Event::Exited(code));
}

/// Waits for the shell to end, hanging it up first when the session was
/// closed while it ran, and kills it if it will not go.
fn reap(inner: &Inner, child: &mut (dyn Child + Send + Sync)) -> Option<i32> {
    let deadline = Instant::now() + KILL_GRACE;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return exit_code(&status),
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(10)),
            Ok(None) => {
                if !inner.closing.load(Ordering::SeqCst) {
                    // The terminal closed under a shell that still runs.
                    inner.hang_up();
                }
                let _ = child.kill();
                return child.wait().ok().and_then(|status| exit_code(&status));
            }
            Err(_) => return None,
        }
    }
}

fn exit_code(status: &portable_pty::ExitStatus) -> Option<i32> {
    match status.signal() {
        Some(_) => None,
        None => i32::try_from(status.exit_code()).ok(),
    }
}
