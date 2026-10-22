//! The journal of reversible steps: what each change to the files did,
//! so that it can be undone and redone.
//!
//! A step is a list of [`Change`]s as they happened. Undoing a step
//! applies the inverse of each change, last first, and what that undo did
//! is itself a step, kept for redo; redoing is the same walk over it.
//! Creating and trashing are each other's inverse (an item made is
//! trashed; an item trashed is put back), a move is undone by the move
//! back, and an overwritten item is lost for good.
//!
//! The runner records the operations it runs; the bridge records renames
//! and the items it creates. New steps empty the redo stack; the undo
//! stack keeps [`Journal::CAPACITY`] steps.

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use ferryx_vfs::trash::TrashReceipt;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};

/// What the user did, for "Undo Move of 3 items".
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum StepKind {
    Copy,
    Move,
    Trash,
    Rename,
    CreateFolder,
    CreateFile,
    CreateLink,
    Duplicate,
    Compress,
    Extract,
    Synchronize,
}

/// A file's size and modification time when a step made it, to tell the
/// user it changed since.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Fingerprint {
    pub size: u64,
    pub modified_ms: Option<i64>,
}

impl Fingerprint {
    /// The fingerprint of a file; `None` for a folder or a missing item.
    pub fn of(path: &Path) -> Option<Fingerprint> {
        let meta = std::fs::symlink_metadata(path).ok()?;
        if meta.is_dir() {
            return None;
        }
        Some(Fingerprint {
            size: meta.len(),
            modified_ms: meta.modified().ok().and_then(ferryx_vfs::native::system_time_ms),
        })
    }
}

/// One change to one item.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Change {
    /// An item the step made (a copy, a new folder, an archive); undone
    /// by moving it to the trash.
    Created { path: PathBuf, fingerprint: Option<Fingerprint> },
    /// An item that moved or was renamed; undone by the move back.
    Moved { from: PathBuf, to: PathBuf },
    /// An item moved to the trash; undone by putting it back.
    Trashed { receipt: TrashReceipt },
    /// An empty folder a move removed after taking its items; undone by
    /// making it again.
    FolderRemoved { path: PathBuf },
    /// An item the step replaced: its earlier contents are gone, so this
    /// part cannot be undone.
    Overwritten { path: PathBuf },
}

/// One reversible step.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Step {
    pub id: u64,
    pub kind: StepKind,
    /// How many items the user acted on.
    pub items: u64,
    /// The first of them, by name.
    pub first_name: String,
    pub changes: Vec<Change>,
    pub at_ms: i64,
    /// More changes happened than are kept: the step is on record but
    /// cannot be undone.
    pub truncated: bool,
}

impl Step {
    pub fn summary(&self) -> StepSummary {
        StepSummary {
            id: self.id,
            kind: self.kind,
            items: self.items,
            first_name: self.first_name.clone(),
            partial: self.changes.iter().any(|c| matches!(c, Change::Overwritten { .. })),
            at_ms: self.at_ms,
        }
    }
}

/// What the interface says about a step.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StepSummary {
    pub id: u64,
    pub kind: StepKind,
    pub items: u64,
    pub first_name: String,
    /// Some items were overwritten: undo cannot bring their contents back.
    pub partial: bool,
    pub at_ms: i64,
}

/// What undo and redo would do next.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct JournalSummary {
    pub undo: Option<StepSummary>,
    pub redo: Option<StepSummary>,
}

/// Which way a step is walked.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Direction {
    Undo,
    Redo,
}

/// The step the journal is told about: what was done, without an id yet.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StepRecord {
    pub kind: StepKind,
    pub items: u64,
    pub first_name: String,
    pub changes: Vec<Change>,
    pub truncated: bool,
}

impl StepRecord {
    /// A record for the items at `paths` acted on as `kind`.
    pub fn for_paths(kind: StepKind, paths: &[PathBuf], changes: Vec<Change>) -> StepRecord {
        StepRecord {
            kind,
            items: paths.len() as u64,
            first_name: paths.first().map(|p| display_name(p)).unwrap_or_default(),
            changes,
            truncated: false,
        }
    }
}

/// The last part of `path`, or all of it at a root.
pub fn display_name(path: &Path) -> String {
    path.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string_lossy().into_owned())
}

pub type JournalListener = Arc<dyn Fn(JournalSummary) + Send + Sync>;

#[derive(Default)]
struct Stacks {
    undo: VecDeque<Step>,
    redo: Vec<Step>,
    next_id: u64,
}

/// The undo and redo stacks, shared by every caller.
#[derive(Default)]
pub struct Journal {
    stacks: Mutex<Stacks>,
    listener: Mutex<Option<JournalListener>>,
}

impl Journal {
    /// Steps kept for undo; the oldest goes first.
    pub const CAPACITY: usize = 100;

    pub fn new() -> Journal {
        Journal::default()
    }

    /// Called with the new summary on every change; a later call replaces
    /// the listener.
    pub fn set_listener(&self, listener: JournalListener) {
        *self.listener.lock() = Some(listener);
    }

    pub fn summary(&self) -> JournalSummary {
        let stacks = self.stacks.lock();
        JournalSummary {
            undo: stacks.undo.back().map(Step::summary),
            redo: stacks.redo.last().map(Step::summary),
        }
    }

    /// Records a new step done by the user: it goes on the undo stack and
    /// the redo stack empties. A record without changes is dropped.
    /// Answers the step's id.
    pub fn record(&self, record: StepRecord) -> Option<u64> {
        if record.changes.is_empty() && !record.truncated {
            return None;
        }
        let id = {
            let mut stacks = self.stacks.lock();
            let step = stacks.make(record);
            let id = step.id;
            stacks.push_undo(step);
            stacks.redo.clear();
            id
        };
        self.notify();
        Some(id)
    }

    /// The step undo (or redo) would take next.
    pub fn peek(&self, direction: Direction) -> Option<Step> {
        let stacks = self.stacks.lock();
        match direction {
            Direction::Undo => stacks.undo.back().cloned(),
            Direction::Redo => stacks.redo.last().cloned(),
        }
    }

    /// Takes the step `id` off the top of its stack, to walk it; `None`
    /// when it is not on top any more.
    pub fn take(&self, direction: Direction, id: u64) -> Option<Step> {
        let step = {
            let mut stacks = self.stacks.lock();
            match direction {
                Direction::Undo if stacks.undo.back().is_some_and(|s| s.id == id) => stacks.undo.pop_back(),
                Direction::Redo if stacks.redo.last().is_some_and(|s| s.id == id) => stacks.redo.pop(),
                _ => None,
            }
        };
        if step.is_some() {
            self.notify();
        }
        step
    }

    /// Ends the walk of `step` in `direction`: what was `done` goes on the
    /// other stack, what was `left` back on its own, so the next undo (or
    /// redo) takes it up again.
    pub fn finish_walk(&self, direction: Direction, step: &Step, done: Vec<Change>, left: Vec<Change>) {
        {
            let mut stacks = self.stacks.lock();
            let template = |changes: Vec<Change>| StepRecord {
                kind: step.kind,
                items: step.items,
                first_name: step.first_name.clone(),
                changes,
                truncated: false,
            };
            if !left.is_empty() {
                let mut back = stacks.make(template(left));
                back.at_ms = step.at_ms;
                match direction {
                    Direction::Undo => stacks.push_undo(back),
                    Direction::Redo => stacks.redo.push(back),
                }
            }
            if !done.is_empty() {
                let inverse = stacks.make(template(done));
                match direction {
                    Direction::Undo => stacks.redo.push(inverse),
                    Direction::Redo => stacks.push_undo(inverse),
                }
            }
        }
        self.notify();
    }

    /// Drops the step `id` from the top of its stack (one that cannot be
    /// undone any more). Answers whether it was there.
    pub fn forget(&self, direction: Direction, id: u64) -> bool {
        self.take(direction, id).is_some()
    }

    /// Empties both stacks.
    pub fn clear(&self) {
        {
            let mut stacks = self.stacks.lock();
            stacks.undo.clear();
            stacks.redo.clear();
        }
        self.notify();
    }

    fn notify(&self) {
        let listener = self.listener.lock().clone();
        if let Some(listener) = listener {
            listener(self.summary());
        }
    }
}

impl Stacks {
    fn make(&mut self, record: StepRecord) -> Step {
        self.next_id += 1;
        Step {
            id: self.next_id,
            kind: record.kind,
            items: record.items,
            first_name: record.first_name,
            changes: record.changes,
            at_ms: now_ms(),
            truncated: record.truncated,
        }
    }

    fn push_undo(&mut self, step: Step) {
        self.undo.push_back(step);
        while self.undo.len() > Journal::CAPACITY {
            self.undo.pop_front();
        }
    }
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn created(path: &str) -> Change {
        Change::Created { path: PathBuf::from(path), fingerprint: None }
    }

    fn record(kind: StepKind, changes: Vec<Change>) -> StepRecord {
        StepRecord::for_paths(kind, &[PathBuf::from("/a/first.txt")], changes)
    }

    #[test]
    fn records_and_walks_both_ways() {
        let journal = Journal::new();
        assert_eq!(journal.summary(), JournalSummary::default());
        assert_eq!(journal.record(record(StepKind::Copy, vec![])), None);
        let id = journal.record(record(StepKind::Copy, vec![created("/b/first.txt")])).unwrap();
        let summary = journal.summary();
        assert_eq!(summary.undo.as_ref().unwrap().kind, StepKind::Copy);
        assert_eq!(summary.undo.as_ref().unwrap().first_name, "first.txt");
        assert!(summary.redo.is_none());

        let step = journal.take(Direction::Undo, id).unwrap();
        assert!(journal.take(Direction::Undo, id).is_none());
        journal.finish_walk(Direction::Undo, &step, vec![created("/inverse")], vec![]);
        let summary = journal.summary();
        assert!(summary.undo.is_none());
        let redo = summary.redo.unwrap();
        assert_eq!(redo.kind, StepKind::Copy);

        let step = journal.take(Direction::Redo, redo.id).unwrap();
        journal.finish_walk(Direction::Redo, &step, vec![created("/again")], vec![]);
        assert!(journal.summary().redo.is_none());
        assert!(journal.summary().undo.is_some());
    }

    #[test]
    fn a_new_step_empties_redo_and_the_stack_is_bounded() {
        let journal = Journal::new();
        let id = journal.record(record(StepKind::Move, vec![created("/x")])).unwrap();
        let step = journal.take(Direction::Undo, id).unwrap();
        journal.finish_walk(Direction::Undo, &step, vec![created("/y")], vec![]);
        assert!(journal.summary().redo.is_some());
        journal.record(record(StepKind::Rename, vec![created("/z")]));
        assert!(journal.summary().redo.is_none());

        for i in 0..(Journal::CAPACITY + 10) {
            journal.record(record(StepKind::CreateFile, vec![created(&format!("/f{i}"))]));
        }
        let mut walked = 0;
        while let Some(step) = journal.peek(Direction::Undo) {
            journal.take(Direction::Undo, step.id).unwrap();
            walked += 1;
        }
        assert_eq!(walked, Journal::CAPACITY);
    }

    #[test]
    fn what_was_left_stays_for_the_next_undo() {
        let journal = Journal::new();
        let id = journal.record(record(StepKind::Copy, vec![created("/1"), created("/2")])).unwrap();
        let step = journal.take(Direction::Undo, id).unwrap();
        journal.finish_walk(Direction::Undo, &step, vec![created("/undone")], vec![created("/1")]);
        let summary = journal.summary();
        let left = journal.peek(Direction::Undo).unwrap();
        assert_eq!(left.changes, vec![created("/1")]);
        assert_eq!(summary.undo.unwrap().kind, StepKind::Copy);
        assert_eq!(journal.peek(Direction::Redo).unwrap().changes, vec![created("/undone")]);
    }

    #[test]
    fn listener_hears_every_change_and_forget_drops() {
        let journal = Journal::new();
        let heard = Arc::new(Mutex::new(Vec::new()));
        let sink = heard.clone();
        journal.set_listener(Arc::new(move |s| sink.lock().push(s)));
        let id = journal.record(record(StepKind::Trash, vec![created("/t")])).unwrap();
        assert!(journal.forget(Direction::Undo, id));
        assert!(!journal.forget(Direction::Undo, id));
        let heard = heard.lock();
        assert!(heard.len() >= 2);
        assert!(heard.first().unwrap().undo.is_some());
        assert!(heard.last().unwrap().undo.is_none());
    }

    #[test]
    fn overwritten_marks_a_step_partial() {
        let journal = Journal::new();
        journal.record(record(
            StepKind::Copy,
            vec![created("/c"), Change::Overwritten { path: PathBuf::from("/o") }],
        ));
        assert!(journal.summary().undo.unwrap().partial);
    }
}
