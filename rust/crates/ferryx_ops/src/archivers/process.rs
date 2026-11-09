use std::io::{Read, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::thread;
use std::time::Duration;

use crate::{Abort, OpContext};

pub enum Failure {
    Aborted(Abort),
    Message(String),
}

type Feed<'a> = Box<dyn FnOnce(ChildStdin) -> std::io::Result<()> + Send + 'a>;
type Consume<'a> = Box<dyn FnOnce(ChildStdout) -> std::io::Result<()> + Send + 'a>;

#[derive(Default)]
pub struct Pipes<'a> {
    pub input: Option<Stdio>,
    pub output: Option<Stdio>,
    pub feed: Option<Feed<'a>>,
    pub consume: Option<Consume<'a>>,
}

struct Running {
    child: Child,
    finished: bool,
    #[cfg(windows)]
    job: Option<std::os::windows::io::OwnedHandle>,
}

impl Running {
    fn signal(&self, signal: i32) {
        #[cfg(unix)]
        // Each worker owns a process group; cancellation includes compressors
        // started by tar, without touching Ferryx's own process group.
        unsafe {
            libc::kill(-(self.child.id() as i32), signal);
        }
        #[cfg(not(unix))]
        let _ = signal;
    }
}

impl Drop for Running {
    fn drop(&mut self) {
        if !self.finished {
            #[cfg(unix)]
            self.signal(libc::SIGKILL);
            let _ = self.child.kill();
            let _ = self.child.wait();
        }
    }
}

fn tail(mut stream: impl Read) -> String {
    const LIMIT: usize = 8192;
    let mut kept = Vec::new();
    let mut chunk = [0; 2048];
    while let Ok(count) = stream.read(&mut chunk) {
        if count == 0 {
            break;
        }
        kept.extend_from_slice(&chunk[..count]);
        if kept.len() > LIMIT {
            kept.drain(..kept.len() - LIMIT);
        }
    }
    String::from_utf8_lossy(&kept).into_owned()
}

pub fn execute(ctx: &OpContext, command: Command, password: Option<&str>) -> Result<(), Failure> {
    execute_with_pipes(ctx, command, password, Pipes::default())
}

pub fn execute_with_pipes<'a>(
    ctx: &'a OpContext,
    mut command: Command,
    password: Option<&str>,
    pipes: Pipes<'a>,
) -> Result<(), Failure> {
    let Pipes { input, output, feed, consume } = pipes;
    command
        .stdin(input.unwrap_or_else(Stdio::piped))
        .stdout(output.unwrap_or_else(Stdio::piped))
        .stderr(Stdio::piped());
    command.env("LC_ALL", "C.UTF-8");
    for key in [
        "TAR_OPTIONS",
        "ZIPOPT",
        "UNZIP",
        "UNZIPOPT",
        "RAR",
        "UNRAR",
        "GZIP",
        "PIGZ",
        "BZIP",
        "BZIP2",
        "XZ_DEFAULTS",
        "XZ_OPT",
        "ZSTD_CLEVEL",
        "ZSTD_NBTHREADS",
        "LZ4_CLEVEL",
        "LZ4_NBTHREADS",
    ] {
        command.env_remove(key);
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000); // CREATE_NO_WINDOW
    }
    let child = command.spawn().map_err(|e| Failure::Message(e.to_string()))?;
    let mut running = Running {
        child,
        finished: false,
        #[cfg(windows)]
        job: None,
    };
    #[cfg(windows)]
    {
        running.job = Some(windows_job(&running.child).map_err(|e| Failure::Message(e.to_string()))?);
    }
    let stdout = running.child.stdout.take();
    let stderr = running.child.stderr.take().expect("piped stderr");
    thread::scope(|scope| {
        let out = stdout.map(|stdout| {
            scope.spawn(move || match consume {
                Some(consume) => consume(stdout).map(|_| String::new()),
                None => Ok(tail(stdout)),
            })
        });
        let err = scope.spawn(move || tail(stderr));
        let input = running.child.stdin.take();
        let writer = match (input, feed) {
            (Some(input), Some(feed)) => Some(scope.spawn(move || feed(input))),
            (Some(mut input), None) => {
                if let Some(password) = password {
                    // 7-Zip reads an unadorned -p password from stdin, twice when
                    // creating. Never expose it in process arguments or logs.
                    let _ = writeln!(input, "{password}\n{password}");
                }
                None
            }
            _ => None,
        };
        #[cfg(unix)]
        let mut suspended = false;
        let outcome = loop {
            #[cfg(unix)]
            if ctx.is_paused() && !suspended {
                running.signal(libc::SIGSTOP);
                suspended = true;
            }
            if let Err(abort) = ctx.check() {
                break Err(Failure::Aborted(abort));
            }
            #[cfg(unix)]
            if suspended {
                running.signal(libc::SIGCONT);
                suspended = false;
            }
            match running.child.try_wait() {
                Ok(Some(status)) => {
                    running.finished = true;
                    break Ok(status);
                }
                Ok(None) => thread::sleep(Duration::from_millis(30)),
                Err(e) => break Err(Failure::Message(e.to_string())),
            }
        };
        // Stop the process before joining its output readers on cancellation.
        drop(running);
        let output = out
            .map(|worker| {
                worker.join().unwrap_or_else(|_| Err(std::io::Error::other("Archive output reader panicked")))
            })
            .unwrap_or_else(|| Ok(String::new()));
        let error = err.join().unwrap_or_default();
        let written = writer
            .map(|worker| {
                worker.join().unwrap_or_else(|_| Err(std::io::Error::other("Archive input writer panicked")))
            })
            .unwrap_or(Ok(()));
        let status = outcome?;
        if status.success() {
            ctx.check().map_err(Failure::Aborted)?;
            written.map_err(|e| Failure::Message(e.to_string()))?;
            output.map_err(|e| Failure::Message(e.to_string()))?;
            return Ok(());
        }
        let mut message =
            if error.trim().is_empty() { output.unwrap_or_else(|e| e.to_string()) } else { error };
        if let Some(secret) = password.filter(|p| !p.is_empty()) {
            message = message.replace(secret, "[redacted]");
        }
        if message.trim().is_empty() {
            message = format!("Archiver exited with {status}");
        }
        Err(Failure::Message(message.trim().to_string()))
    })
}

#[cfg(windows)]
fn windows_job(child: &Child) -> std::io::Result<std::os::windows::io::OwnedHandle> {
    use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
    use windows_sys::Win32::System::JobObjects::*;
    // Closing the job terminates descendants too, including tar compressors.
    unsafe {
        let handle = CreateJobObjectW(std::ptr::null(), std::ptr::null());
        if handle.is_null() {
            return Err(std::io::Error::last_os_error());
        }
        let owned = OwnedHandle::from_raw_handle(handle);
        let mut info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if SetInformationJobObject(
            handle,
            JobObjectExtendedLimitInformation,
            (&info as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast(),
            std::mem::size_of_val(&info) as u32,
        ) == 0
            || AssignProcessToJobObject(handle, child.as_raw_handle()) == 0
        {
            return Err(std::io::Error::last_os_error());
        }
        Ok(owned)
    }
}
