//! Work the dialogs start on threads of their own (comparisons,
//! checksums, duplicate searches): ids, cancel flags, the event batching
//! they share, and the results kept for the panels' content comparison.
//! Also the journal records the bridge makes itself (renames, new items).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, LazyLock};
use std::time::{Duration, Instant};

use ferryx_ops::journal::{Change, StepKind, StepRecord};
use parking_lot::Mutex;

use crate::app;

/// How long results gather before an event carries them.
pub const BATCH: Duration = Duration::from_millis(80);

/// Rows at most in one event.
pub const BATCH_ROWS: usize = 500;

/// Indexes of the pairs a content comparison found different.
pub type Differences = Arc<Mutex<Vec<usize>>>;

static NEXT: AtomicI64 = AtomicI64::new(1);
static CANCELS: LazyLock<Mutex<HashMap<i64, Arc<AtomicBool>>>> = LazyLock::new(Default::default);
/// The pairs found different by a content comparison, by operation id.
static DIFFERENCES: LazyLock<Mutex<HashMap<i64, Differences>>> = LazyLock::new(Default::default);

/// A new task: its id and its cancel flag.
pub fn begin() -> (i64, Arc<AtomicBool>) {
    let id = NEXT.fetch_add(1, Ordering::SeqCst);
    let cancel = Arc::new(AtomicBool::new(false));
    CANCELS.lock().insert(id, cancel.clone());
    (id, cancel)
}

pub fn cancel(id: i64) {
    if let Some(flag) = CANCELS.lock().get(&id) {
        flag.store(true, Ordering::SeqCst);
    }
}

pub fn end(id: i64) {
    CANCELS.lock().remove(&id);
}

// ─── Network ───

/// The cancel flag of the task `id` begun earlier, if it is still on.
pub fn flag(id: i64) -> Option<Arc<AtomicBool>> {
    CANCELS.lock().get(&id).cloned()
}

/// Keeps where the content comparison `op` puts the pairs that differ.
pub fn keep_differences(op: i64, differing: Differences) {
    DIFFERENCES.lock().insert(op, differing);
}

/// The pairs operation `op` found different, once; empty for an unknown
/// id.
pub fn take_differences(op: i64) -> Vec<usize> {
    DIFFERENCES.lock().remove(&op).map(|d| std::mem::take(&mut *d.lock())).unwrap_or_default()
}

pub fn reset() {
    CANCELS.lock().clear();
    DIFFERENCES.lock().clear();
}

/// When the next event is due: every [`BATCH`], or when rows pile up.
pub struct Pacer {
    last: Instant,
}

impl Default for Pacer {
    fn default() -> Self {
        Pacer::new()
    }
}

impl Pacer {
    /// The first event is due at once, so the dialog shows the start.
    pub fn new() -> Pacer {
        Pacer { last: Instant::now().checked_sub(BATCH).unwrap_or_else(Instant::now) }
    }

    pub fn due(&self, pending: usize) -> bool {
        pending >= BATCH_ROWS || self.last.elapsed() >= BATCH
    }

    pub fn sent(&mut self) {
        self.last = Instant::now();
    }
}

/// Records a step the bridge made itself (a rename, a new item).
pub fn record(kind: StepKind, paths: &[PathBuf], changes: Vec<Change>) {
    app::runner().journal().record(StepRecord::for_paths(kind, paths, changes));
}

/// The topmost folder `path`'s making would create: the first of its
/// ancestors (or itself) that is missing.
pub fn first_missing(path: &Path) -> Option<PathBuf> {
    path.ancestors().take_while(|a| a.symlink_metadata().is_err()).last().map(Path::to_path_buf)
}
