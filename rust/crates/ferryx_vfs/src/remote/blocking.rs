//! Blocking socket calls a stop cuts short. FTP talks through
//! `suppaftp`'s blocking calls, which only a timeout would otherwise end:
//! a connection attempt is left to finish on a thread of its own, and a
//! call waiting on a connected socket has the socket shut under it.

use std::io;
use std::net::{Shutdown, SocketAddr, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use super::runtime::Stop;

/// How often a blocked call looks at its stop.
pub(crate) const POLL: Duration = Duration::from_millis(50);

/// Connects to `target` within `timeout`. A stop gives up at once with
/// [`io::ErrorKind::Interrupted`]; the attempt ends on its own thread and
/// closes what it opened.
pub(crate) fn connect(target: SocketAddr, timeout: Duration, stop: Stop) -> io::Result<TcpStream> {
    let (sender, receiver) = mpsc::channel();
    thread::Builder::new().name("ferryx-connect".into()).spawn(move || {
        let _ = sender.send(TcpStream::connect_timeout(&target, timeout));
    })?;
    loop {
        match receiver.recv_timeout(POLL) {
            Ok(result) => return result,
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if stop() {
                    return Err(io::Error::new(io::ErrorKind::Interrupted, "stopped"));
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                return Err(io::Error::other("the connection attempt ended"));
            }
        }
    }
}

/// Runs `work`, which blocks on the socket `handle` is a handle on (a
/// `try_clone`); a stop meanwhile shuts the socket down, so `work` fails
/// at once instead of when a timeout ends it. The socket is no use after
/// that: its caller drops it. Without a handle `work` runs unwatched.
pub(crate) fn watched<T>(handle: Option<TcpStream>, stop: Stop, work: impl FnOnce() -> T) -> T {
    let Some(handle) = handle else { return work() };
    let done = AtomicBool::new(false);
    thread::scope(|scope| {
        let watcher = scope.spawn(|| {
            while !done.load(Ordering::Acquire) {
                if stop() {
                    let _ = handle.shutdown(Shutdown::Both);
                    return;
                }
                thread::park_timeout(POLL);
            }
        });
        let result = work();
        done.store(true, Ordering::Release);
        watcher.thread().unpark();
        result
    })
}

#[cfg(test)]
mod tests {
    use std::io::Read;
    use std::net::TcpListener;
    use std::sync::atomic::AtomicBool;
    use std::time::Instant;

    use super::*;

    #[test]
    fn a_stop_ends_a_read_that_waits_for_a_silent_server() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let target = listener.local_addr().unwrap();
        let flag = AtomicBool::new(false);
        let stop = || flag.load(Ordering::SeqCst);
        let mut socket = connect(target, Duration::from_secs(5), &stop).unwrap();
        let _peer = listener.accept().unwrap();
        let started = Instant::now();
        thread::scope(|scope| {
            scope.spawn(|| {
                thread::sleep(Duration::from_millis(100));
                flag.store(true, Ordering::SeqCst);
            });
            let read = watched(socket.try_clone().ok(), &stop, || socket.read(&mut [0u8; 16]));
            // Shut down: the read ends with nothing (or an error), never data.
            assert!(read.map(|n| n == 0).unwrap_or(true));
        });
        assert!(started.elapsed() < Duration::from_secs(2));
    }

    #[test]
    fn work_that_ends_on_its_own_ends_without_waiting_for_the_watcher() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let socket = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let started = Instant::now();
        for _ in 0..20 {
            assert_eq!(watched(socket.try_clone().ok(), &|| false, || 7), 7);
        }
        // Twenty calls, none of them a poll interval long.
        assert!(started.elapsed() < POLL * 10);
    }
}
