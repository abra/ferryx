//! A folder watched for changes, reported once per burst.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use crossbeam_channel::{bounded, Receiver, RecvTimeoutError, Sender};
use notify::{RecommendedWatcher, RecursiveMode, Watcher as _};

use crate::error::{VfsError, VfsErrorKind, VfsResult};

/// How long a burst of events is let settle before one notification.
pub const SETTLE: Duration = Duration::from_millis(250);

/// Watches one folder (not its subfolders) and calls `on_change` after
/// each burst of events, from a thread of its own. Dropped, it stops.
pub struct FolderWatcher {
    _watcher: RecommendedWatcher,
    stop: Sender<()>,
}

impl FolderWatcher {
    pub fn new(path: &Path, on_change: Arc<dyn Fn() + Send + Sync>) -> VfsResult<FolderWatcher> {
        let (events_tx, events_rx) = bounded::<()>(64);
        let (stop_tx, stop_rx) = bounded::<()>(1);
        let mut watcher = RecommendedWatcher::new(
            move |result: notify::Result<notify::Event>| {
                if result.is_ok() {
                    // A full queue already means "something changed".
                    let _ = events_tx.try_send(());
                }
            },
            notify::Config::default(),
        )
        .map_err(|e| watch_error(path, e))?;
        watcher.watch(path, RecursiveMode::NonRecursive).map_err(|e| watch_error(path, e))?;
        let watched: PathBuf = path.to_path_buf();
        thread::Builder::new()
            .name(format!("watch {}", watched.display()))
            .spawn(move || settle_loop(events_rx, stop_rx, on_change))
            .map_err(|e| VfsError::new(VfsErrorKind::Io, Some(&watched), e.to_string()))?;
        Ok(FolderWatcher { _watcher: watcher, stop: stop_tx })
    }
}

impl Drop for FolderWatcher {
    fn drop(&mut self) {
        let _ = self.stop.try_send(());
    }
}

fn watch_error(path: &Path, error: notify::Error) -> VfsError {
    let kind = match error.kind {
        notify::ErrorKind::PathNotFound => VfsErrorKind::NotFound,
        notify::ErrorKind::Io(ref io) if io.kind() == std::io::ErrorKind::PermissionDenied => {
            VfsErrorKind::PermissionDenied
        }
        _ => VfsErrorKind::Io,
    };
    VfsError::new(kind, Some(path), error.to_string())
}

/// Waits for an event, then for the burst to end, then reports once.
fn settle_loop(events: Receiver<()>, stop: Receiver<()>, on_change: Arc<dyn Fn() + Send + Sync>) {
    loop {
        crossbeam_channel::select! {
            recv(stop) -> _ => return,
            recv(events) -> event => {
                if event.is_err() { return; }
            }
        }
        loop {
            match events.recv_timeout(SETTLE) {
                Ok(()) => continue,
                Err(RecvTimeoutError::Timeout) => break,
                Err(RecvTimeoutError::Disconnected) => return,
            }
        }
        if stop.try_recv().is_ok() {
            return;
        }
        on_change();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Instant;

    #[test]
    fn reports_a_change_once_per_burst() {
        let dir = tempfile::tempdir().unwrap();
        let count = Arc::new(AtomicUsize::new(0));
        let seen = count.clone();
        let watcher = FolderWatcher::new(
            dir.path(),
            Arc::new(move || {
                seen.fetch_add(1, Ordering::SeqCst);
            }),
        )
        .unwrap();
        thread::sleep(Duration::from_millis(300));
        for i in 0..5 {
            std::fs::write(dir.path().join(format!("f{i}")), b"x").unwrap();
        }
        let start = Instant::now();
        while count.load(Ordering::SeqCst) == 0 && start.elapsed() < Duration::from_secs(5) {
            thread::sleep(Duration::from_millis(50));
        }
        thread::sleep(SETTLE * 2);
        let n = count.load(Ordering::SeqCst);
        assert!((1..=2).contains(&n), "reported {n} times");
        drop(watcher);
    }
}
