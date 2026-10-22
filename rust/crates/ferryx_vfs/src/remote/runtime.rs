//! The asynchronous runtime the network code runs on, owned by the core,
//! and the one way the rest of it waits for a server: with a deadline and
//! a question, asked every few tens of milliseconds, whether to stop.
//!
//! Listings and operations call in from their own threads (the bridge's
//! workers, an operation's thread) and block there; the runtime's two
//! workers drive the sockets, the SSH sessions and HTTP meanwhile. A call
//! must never come from one of the runtime's own threads.

use std::future::Future;
use std::sync::LazyLock;
use std::time::Duration;

use tokio::runtime::Runtime;

use crate::error::{VfsError, VfsErrorKind, VfsResult};

/// Asked while a call waits: `true` stops it with [`VfsErrorKind::Cancelled`].
/// A listing replaced by another, an operation cancelled.
pub type Stop<'a> = &'a (dyn Fn() -> bool + Sync);

/// A [`Stop`] that never stops.
pub fn never() -> bool {
    false
}

/// How long one request may take before the server counts as gone.
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// How long reaching a server and greeting it may take.
pub const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);

/// How often a waiting call asks whether to stop.
const STOP_POLL: Duration = Duration::from_millis(40);

static RUNTIME: LazyLock<Runtime> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .thread_name("ferryx-net")
        .enable_all()
        .build()
        .expect("the network runtime starts")
});

/// The runtime, started on first use.
pub fn runtime() -> &'static Runtime {
    &RUNTIME
}

/// Runs `future` to its end on the calling thread, the runtime's workers
/// doing the I/O; fails with [`VfsErrorKind::TimedOut`] after `timeout`
/// and with [`VfsErrorKind::Cancelled`] as soon as `stop` says so.
pub fn run<T>(future: impl Future<Output = VfsResult<T>>, timeout: Duration, stop: Stop) -> VfsResult<T> {
    runtime().block_on(with_limits(future, timeout, stop))
}

/// [`run`] without a deadline: for a wait that is the user's (a question
/// answered in a dialog) or bounded by the server's own timeouts.
pub fn run_unbounded<T>(future: impl Future<Output = VfsResult<T>>, stop: Stop) -> VfsResult<T> {
    runtime().block_on(with_stop(future, stop))
}

/// `future` with a deadline and a stop, for code already inside the
/// runtime.
pub async fn with_limits<T>(
    future: impl Future<Output = VfsResult<T>>,
    timeout: Duration,
    stop: Stop<'_>,
) -> VfsResult<T> {
    match tokio::time::timeout(timeout, with_stop(future, stop)).await {
        Ok(result) => result,
        Err(_) => Err(timed_out()),
    }
}

async fn with_stop<T>(future: impl Future<Output = VfsResult<T>>, stop: Stop<'_>) -> VfsResult<T> {
    if stop() {
        return Err(VfsError::cancelled());
    }
    tokio::pin!(future);
    let mut tick = tokio::time::interval(STOP_POLL);
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        tokio::select! {
            result = &mut future => return result,
            _ = tick.tick() => {
                if stop() {
                    return Err(VfsError::cancelled());
                }
            }
        }
    }
}

pub fn timed_out() -> VfsError {
    VfsError::new(VfsErrorKind::TimedOut, None, "the server did not answer in time")
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::Instant;

    use super::*;

    #[test]
    fn a_slow_call_times_out_and_a_stop_ends_it_at_once() {
        let slow = async {
            tokio::time::sleep(Duration::from_secs(5)).await;
            Ok(1)
        };
        let started = Instant::now();
        let error = run(slow, Duration::from_millis(100), &never).unwrap_err();
        assert_eq!(error.kind, VfsErrorKind::TimedOut);
        assert!(started.elapsed() < Duration::from_secs(2));

        let flag = AtomicBool::new(false);
        let stop = || flag.load(Ordering::SeqCst);
        let started = Instant::now();
        std::thread::scope(|scope| {
            scope.spawn(|| {
                std::thread::sleep(Duration::from_millis(80));
                flag.store(true, Ordering::SeqCst);
            });
            let slow = async {
                tokio::time::sleep(Duration::from_secs(5)).await;
                Ok(1)
            };
            let error = run(slow, Duration::from_secs(10), &stop).unwrap_err();
            assert_eq!(error.kind, VfsErrorKind::Cancelled);
        });
        assert!(started.elapsed() < Duration::from_secs(2));
        assert_eq!(run(async { Ok(2) }, Duration::from_secs(1), &never).unwrap(), 2);
    }
}
