//! A folder watched for changes, reported once per burst with the names
//! of the items that changed.

use std::collections::HashSet;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use crossbeam_channel::{bounded, Receiver, RecvTimeoutError};
use notify::{RecommendedWatcher, RecursiveMode, Watcher as _};
use parking_lot::Mutex;

use crate::error::{VfsError, VfsErrorKind, VfsResult};

/// How long a burst of events is let settle before one notification.
pub const SETTLE: Duration = Duration::from_millis(250);

/// The longest a burst is let run before it is reported anyway: a folder
/// written to without a pause (a download) still shows its rows.
pub const MOST_WAIT: Duration = Duration::from_secs(1);

/// More names than this in one burst read faster as the whole folder.
pub const MOST_NAMES: usize = 2048;

/// What changed in a watched folder since the last report.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum Changes {
    #[default]
    Nothing,
    /// The items of these names were made, changed or removed.
    Names(HashSet<OsString>),
    /// Anything may have: the folder itself changed, the system dropped
    /// events, or too many items changed to name.
    Everything,
}

impl Changes {
    pub fn add_name(&mut self, name: OsString) {
        match self {
            Changes::Everything => {}
            Changes::Nothing => *self = Changes::Names(HashSet::from([name])),
            Changes::Names(names) => {
                names.insert(name);
                if names.len() > MOST_NAMES {
                    *self = Changes::Everything;
                }
            }
        }
    }

    /// Both reports in one.
    pub fn merge(&mut self, other: Changes) {
        match other {
            Changes::Nothing => {}
            Changes::Everything => *self = Changes::Everything,
            Changes::Names(names) => {
                for name in names {
                    self.add_name(name);
                }
            }
        }
    }
}

/// Watches one folder (not its subfolders) and calls `on_change` after
/// each burst of events, from a thread of its own. Dropped, it stops.
pub struct FolderWatcher {
    _watcher: RecommendedWatcher,
    stop: crossbeam_channel::Sender<()>,
}

impl FolderWatcher {
    pub fn new(path: &Path, on_change: Arc<dyn Fn(Changes) + Send + Sync>) -> VfsResult<FolderWatcher> {
        let pending = Arc::new(Mutex::new(Changes::Nothing));
        // Rung on each event; one ring waiting is enough.
        let (bell_tx, bell_rx) = bounded::<()>(1);
        let (stop_tx, stop_rx) = bounded::<()>(1);
        let folder: PathBuf = path.to_path_buf();
        // The system names items by the folder's real path.
        let real = std::fs::canonicalize(path).unwrap_or_else(|_| folder.clone());
        let noted = pending.clone();
        let mut watcher = RecommendedWatcher::new(
            move |result: notify::Result<notify::Event>| {
                let mut changes = noted.lock();
                match result {
                    Ok(event) if !event.need_rescan() => {
                        for path in &event.paths {
                            match path.file_name() {
                                Some(name) if path != &folder && path != &real => {
                                    changes.add_name(name.to_os_string())
                                }
                                _ => *changes = Changes::Everything,
                            }
                        }
                    }
                    _ => *changes = Changes::Everything,
                }
                drop(changes);
                let _ = bell_tx.try_send(());
            },
            notify::Config::default(),
        )
        .map_err(|e| watch_error(path, e))?;
        watcher.watch(path, RecursiveMode::NonRecursive).map_err(|e| watch_error(path, e))?;
        let watched: PathBuf = path.to_path_buf();
        thread::Builder::new()
            .name(format!("watch {}", watched.display()))
            .spawn(move || settle_loop(bell_rx, stop_rx, pending, on_change))
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

/// Waits for an event, then for the burst to end (or to run too long),
/// then reports what it changed once.
fn settle_loop(
    bell: Receiver<()>,
    stop: Receiver<()>,
    pending: Arc<Mutex<Changes>>,
    on_change: Arc<dyn Fn(Changes) + Send + Sync>,
) {
    loop {
        crossbeam_channel::select! {
            recv(stop) -> _ => return,
            recv(bell) -> ring => {
                if ring.is_err() { return; }
            }
        }
        let deadline = Instant::now() + MOST_WAIT;
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                break;
            }
            match bell.recv_timeout(SETTLE.min(left)) {
                Ok(()) => continue,
                Err(RecvTimeoutError::Timeout) => break,
                Err(RecvTimeoutError::Disconnected) => return,
            }
        }
        if stop.try_recv().is_ok() {
            return;
        }
        let changes = std::mem::take(&mut *pending.lock());
        if changes != Changes::Nothing {
            on_change(changes);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn wait_until(mut done: impl FnMut() -> bool) {
        let start = Instant::now();
        while !done() && start.elapsed() < Duration::from_secs(5) {
            thread::sleep(Duration::from_millis(20));
        }
    }

    #[test]
    fn reports_a_change_once_per_burst_with_its_names() {
        let dir = tempfile::tempdir().unwrap();
        let count = Arc::new(AtomicUsize::new(0));
        let seen = Arc::new(Mutex::new(Changes::Nothing));
        let (counted, noted) = (count.clone(), seen.clone());
        let watcher = FolderWatcher::new(
            dir.path(),
            Arc::new(move |changes| {
                noted.lock().merge(changes);
                counted.fetch_add(1, Ordering::SeqCst);
            }),
        )
        .unwrap();
        thread::sleep(Duration::from_millis(300));
        for i in 0..5 {
            std::fs::write(dir.path().join(format!("f{i}")), b"x").unwrap();
        }
        wait_until(|| count.load(Ordering::SeqCst) > 0);
        thread::sleep(SETTLE * 2);
        let n = count.load(Ordering::SeqCst);
        assert!((1..=2).contains(&n), "reported {n} times");
        let expected: HashSet<OsString> = (0..5).map(|i| OsString::from(format!("f{i}"))).collect();
        assert_eq!(*seen.lock(), Changes::Names(expected));
        drop(watcher);
    }

    #[test]
    fn a_folder_written_to_without_a_pause_is_still_reported() {
        let dir = tempfile::tempdir().unwrap();
        let first = Arc::new(Mutex::new(None::<Instant>));
        let noted = first.clone();
        let watcher = FolderWatcher::new(
            dir.path(),
            Arc::new(move |_| {
                noted.lock().get_or_insert_with(Instant::now);
            }),
        )
        .unwrap();
        thread::sleep(Duration::from_millis(300));
        let start = Instant::now();
        // A write every 50 ms for 2.5 s never lets the burst settle.
        while start.elapsed() < Duration::from_millis(2500) && first.lock().is_none() {
            std::fs::write(dir.path().join("growing"), start.elapsed().as_millis().to_string()).unwrap();
            thread::sleep(Duration::from_millis(50));
        }
        let at = first.lock().expect("never reported while the writes went on");
        assert!(at - start < MOST_WAIT + Duration::from_millis(700), "reported after {:?}", at - start);
        drop(watcher);
    }

    #[test]
    fn too_many_names_or_an_unknown_change_read_as_everything() {
        let mut changes = Changes::Nothing;
        for i in 0..=MOST_NAMES {
            changes.add_name(OsString::from(i.to_string()));
        }
        assert_eq!(changes, Changes::Everything);
        let mut few = Changes::Nothing;
        few.add_name("a".into());
        few.merge(Changes::Names(HashSet::from(["b".into()])));
        assert_eq!(few, Changes::Names(HashSet::from(["a".into(), "b".into()])));
        few.merge(Changes::Everything);
        assert_eq!(few, Changes::Everything);
    }
}
