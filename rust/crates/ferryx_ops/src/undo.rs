//! Undo and redo: a journal step walked back, change by change, as an
//! operation with progress.
//!
//! Before a walk, [`check`] looks at every change: an item a step made
//! must still be there, the place an item goes back to must be free, a
//! trashed item must still be in the trash. A change that cannot be done
//! is reported by path and left out; the walk does the rest, last change
//! first, and records what it did (the step for the other direction) and
//! what it left (back on its own stack).

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use ferryx_vfs::error::VfsError;
use ferryx_vfs::trash::{self, TrashReceipt};
use serde::{Deserialize, Serialize};

use crate::copy;
use crate::journal::{Change, Direction, Fingerprint, Step};
use crate::runner::{Job, Journaling, OpContext, Runner};
use crate::types::*;

/// Why a change cannot be walked back as it was.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum IssueKind {
    /// The item the change left is gone (deleted, moved away).
    Missing,
    /// The place the item goes back to is taken.
    Occupied,
    /// The item changed since: it still goes, but the user should know.
    Changed,
    /// The step overwrote the item: its earlier contents are gone.
    Lost,
    /// The trashed item is no longer in the trash.
    NotInTrash,
    /// Putting items back from the trash is not possible on this desktop.
    Unsupported,
    /// The step changed more items than the journal keeps.
    Truncated,
}

impl IssueKind {
    /// Whether the change is left out (else it is a warning).
    pub fn blocks(self) -> bool {
        !matches!(self, IssueKind::Changed | IssueKind::Lost)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Issue {
    pub kind: IssueKind,
    pub path: PathBuf,
}

/// What walking a step would do.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Check {
    pub issues: Vec<Issue>,
    /// Changes that can be walked back.
    pub doable: u64,
    /// Changes that do something when walked back (an overwrite does
    /// nothing).
    pub total: u64,
}

/// Paths the walk empties (where an item leaves) and fills (where an item
/// comes back).
fn vacated(step: &Step) -> HashSet<&Path> {
    step.changes
        .iter()
        .filter_map(|c| match c {
            Change::Moved { to, .. } => Some(to.as_path()),
            Change::Created { path, .. } => Some(path.as_path()),
            _ => None,
        })
        .collect()
}

/// Looks at every change of `step` against the disk.
pub fn check(step: &Step) -> Check {
    let mut issues = Vec::new();
    let mut doable = 0u64;
    let mut total = 0u64;
    if step.truncated {
        return Check {
            issues: vec![Issue { kind: IssueKind::Truncated, path: PathBuf::from(&step.first_name) }],
            doable: 0,
            total: step.items,
        };
    }
    let vacated = vacated(step);
    let taken = |path: &Path| path.symlink_metadata().is_ok() && !vacated.contains(path);
    let receipts: Vec<&TrashReceipt> = step
        .changes
        .iter()
        .filter_map(|c| match c {
            Change::Trashed { receipt } => Some(receipt),
            _ => None,
        })
        .collect();
    let mut in_trash = trash::are_in_trash(&receipts).into_iter();
    for change in &step.changes {
        let issue = match change {
            Change::Created { path, fingerprint } => {
                total += 1;
                if path.symlink_metadata().is_err() {
                    Some(Issue { kind: IssueKind::Missing, path: path.clone() })
                } else if fingerprint.is_some() && Fingerprint::of(path) != *fingerprint {
                    issues.push(Issue { kind: IssueKind::Changed, path: path.clone() });
                    None
                } else {
                    None
                }
            }
            Change::Moved { from, to } => {
                total += 1;
                if to.symlink_metadata().is_err() {
                    Some(Issue { kind: IssueKind::Missing, path: to.clone() })
                } else if taken(from) {
                    Some(Issue { kind: IssueKind::Occupied, path: from.clone() })
                } else {
                    None
                }
            }
            Change::Trashed { receipt } => {
                total += 1;
                let present = in_trash.next().unwrap_or(false);
                if !trash::put_back_supported() || receipt.token.is_none() {
                    Some(Issue { kind: IssueKind::Unsupported, path: receipt.original.clone() })
                } else if !present {
                    Some(Issue { kind: IssueKind::NotInTrash, path: receipt.original.clone() })
                } else if taken(&receipt.original) {
                    Some(Issue { kind: IssueKind::Occupied, path: receipt.original.clone() })
                } else {
                    None
                }
            }
            Change::FolderRemoved { path } => {
                total += 1;
                match path.symlink_metadata() {
                    Ok(meta) if !meta.is_dir() && !vacated.contains(path.as_path()) => {
                        Some(Issue { kind: IssueKind::Occupied, path: path.clone() })
                    }
                    _ => None,
                }
            }
            Change::Overwritten { path } => {
                issues.push(Issue { kind: IssueKind::Lost, path: path.clone() });
                None
            }
        };
        match issue {
            Some(issue) => issues.push(issue),
            None if !matches!(change, Change::Overwritten { .. }) => doable += 1,
            None => {}
        }
    }
    Check { issues, doable, total }
}

/// Starts the walk of the step `id` on top of `direction`'s stack as an
/// operation; answers its id, or `None` when that step is not on top.
pub fn start(runner: &Runner, direction: Direction, id: u64) -> Option<u64> {
    let step = runner.journal().take(direction, id)?;
    let kind = match direction {
        Direction::Undo => OpKind::Undo,
        Direction::Redo => OpKind::Redo,
    };
    let request = OpRequest {
        kind,
        sources: affected(&step),
        archive: None,
        destination: None,
        new_name: None,
        options: OpOptions::default(),
    };
    let walked = step.clone();
    let job: Job = Box::new(move |ctx: &OpContext| run(ctx, &walked));
    Some(runner.start_job(request, Journaling::Walk { direction, step: Box::new(step) }, job))
}

/// The items a walk of `step` touches, as the operation's sources (a few
/// are enough for the card).
fn affected(step: &Step) -> Vec<PathBuf> {
    step.changes
        .iter()
        .filter_map(|c| match c {
            Change::Created { path, .. } | Change::FolderRemoved { path } => Some(path.clone()),
            Change::Moved { to, .. } => Some(to.clone()),
            Change::Trashed { receipt } => Some(receipt.original.clone()),
            Change::Overwritten { .. } => None,
        })
        .take(1000)
        .collect()
}

/// An item moved aside under a temporary name, because its place back was
/// still taken by another item of the step (names that swapped).
struct Staged {
    temp: PathBuf,
    from: PathBuf,
    to: PathBuf,
}

/// Walks `step` back: the inverse of each change, last first. What is done
/// goes on record (the step for the other direction); a change that
/// cannot be done is reported and recorded as left.
pub fn run(ctx: &OpContext, step: &Step) -> Result<(), Abort> {
    if step.truncated {
        ctx.record_error(Path::new(&step.first_name), "too many items changed to undo".to_string());
        return Err(Abort::Stopped);
    }
    let changes: Vec<&Change> = step.changes.iter().rev().collect();
    ctx.set_totals(0, changes.len() as u64);
    let vacated: HashSet<PathBuf> = vacated(step).into_iter().map(Path::to_path_buf).collect();
    let mut walk = Walk { ctx, vacated, staged: Vec::new(), left: Vec::new(), next_temp: 0 };
    let outcome = walk.all(&changes);
    // Whatever stands aside goes to its place now, even on a stop.
    walk.land_staged();
    // The changes not done, in their own order, for the next walk.
    for change in walk.left.into_iter().rev() {
        ctx.record_left(change);
    }
    outcome
}

struct Walk<'a> {
    ctx: &'a OpContext,
    vacated: HashSet<PathBuf>,
    staged: Vec<Staged>,
    /// Not done, in walk order.
    left: Vec<Change>,
    next_temp: usize,
}

impl Walk<'_> {
    fn all(&mut self, changes: &[&Change]) -> Result<(), Abort> {
        let mut i = 0;
        while i < changes.len() {
            if let Err(abort) = self.ctx.check() {
                self.left.extend(changes[i..].iter().map(|c| (*c).clone()));
                return Err(abort);
            }
            // Runs of items to trash or to put back go together: the
            // freedesktop trash is listed once per run.
            let run_end = |pred: fn(&Change) -> bool| {
                let mut end = i;
                while end < changes.len() && end - i < 64 && pred(changes[end]) {
                    end += 1;
                }
                end
            };
            let outcome = match changes[i] {
                Change::Created { .. } => {
                    let end = run_end(|c| matches!(c, Change::Created { .. }));
                    let outcome = self.trash(&changes[i..end]);
                    i = end;
                    outcome
                }
                Change::Trashed { .. } => {
                    let end = run_end(|c| matches!(c, Change::Trashed { .. }));
                    let outcome = self.put_back(&changes[i..end]);
                    i = end;
                    outcome
                }
                change => {
                    i += 1;
                    self.one(change)
                }
            };
            if let Err(abort) = outcome {
                self.left.extend(changes[i..].iter().map(|c| (*c).clone()));
                return Err(abort);
            }
        }
        Ok(())
    }

    /// Asks about `error` at `path`: `Ok(true)` to try again.
    fn ask(&self, path: &Path, error: &VfsError) -> Result<bool, Abort> {
        self.ctx.ask_error(path, error)
    }

    /// Created items go to the trash.
    fn trash(&mut self, changes: &[&Change]) -> Result<(), Abort> {
        let mut paths = Vec::new();
        let mut kept = Vec::new();
        for change in changes {
            let Change::Created { path, .. } = change else { continue };
            self.ctx.set_current(path);
            if path.symlink_metadata().is_err() {
                // Gone already: nothing to undo, nothing to redo.
                self.ctx.record_error(path, format!("{} no longer exists", path.display()));
                self.ctx.item_done();
                continue;
            }
            paths.push(path.clone());
            kept.push((*change).clone());
        }
        let results = trash::trash_items(&paths);
        for ((path, change), result) in paths.iter().zip(kept).zip(results) {
            let mut result = result;
            loop {
                match result {
                    Ok(receipt) => {
                        self.ctx.record(Change::Trashed { receipt });
                        break;
                    }
                    Err(error) => {
                        if !self.ask(path, &error)? {
                            self.left.push(change);
                            break;
                        }
                        result = trash::trash_items(std::slice::from_ref(path))
                            .into_iter()
                            .next()
                            .unwrap_or(Err(error));
                    }
                }
            }
            self.ctx.item_done();
        }
        Ok(())
    }

    /// Trashed items come back from the trash.
    fn put_back(&mut self, changes: &[&Change]) -> Result<(), Abort> {
        let receipts: Vec<&TrashReceipt> = changes
            .iter()
            .filter_map(|c| match c {
                Change::Trashed { receipt } => Some(receipt),
                _ => None,
            })
            .collect();
        let outcomes = trash::put_back_all(&receipts);
        for (receipt, outcome) in receipts.into_iter().zip(outcomes) {
            self.ctx.set_current(&receipt.original);
            let mut outcome = outcome;
            loop {
                match outcome {
                    Ok(()) => {
                        self.ctx.record(Change::Created {
                            path: receipt.original.clone(),
                            fingerprint: Fingerprint::of(&receipt.original),
                        });
                        break;
                    }
                    Err(error) => {
                        if !self.ask(&receipt.original, &error)? {
                            self.left.push(Change::Trashed { receipt: receipt.clone() });
                            break;
                        }
                        outcome = trash::put_back(receipt);
                    }
                }
            }
            self.ctx.item_done();
        }
        Ok(())
    }

    fn one(&mut self, change: &Change) -> Result<(), Abort> {
        match change {
            Change::Moved { from, to } => self.move_back(from, to, change)?,
            Change::FolderRemoved { path } => {
                self.ctx.set_current(path);
                match path.symlink_metadata() {
                    Ok(meta) if meta.is_dir() => {}
                    Ok(_) => {
                        let error = VfsError::new(
                            ferryx_vfs::VfsErrorKind::AlreadyExists,
                            Some(path),
                            format!("{} already exists", path.display()),
                        );
                        self.ctx.ask_error(path, &error)?;
                        self.left.push(change.clone());
                    }
                    Err(_) => match fs::create_dir_all(path) {
                        Ok(()) => self.ctx.record_created(path),
                        Err(e) => {
                            self.ctx.ask_error(path, &VfsError::io(&e, path))?;
                            self.left.push(change.clone());
                        }
                    },
                }
            }
            // Nothing brings back what was overwritten.
            Change::Overwritten { .. } | Change::Created { .. } | Change::Trashed { .. } => {}
        }
        self.ctx.item_done();
        Ok(())
    }

    /// The item at `to` goes back to `from`.
    fn move_back(&mut self, from: &Path, to: &Path, change: &Change) -> Result<(), Abort> {
        self.ctx.set_current(to);
        if to.symlink_metadata().is_err() {
            self.ctx.record_error(to, format!("{} no longer exists", to.display()));
            return Ok(());
        }
        if from.symlink_metadata().is_ok() {
            if self.vacated.contains(from) {
                // Another item of the step still stands there and leaves
                // later: wait aside under a temporary name.
                let temp =
                    to.with_file_name(format!(".ferryx-undo-{}-{}", std::process::id(), self.next_temp));
                self.next_temp += 1;
                match fs::rename(to, &temp) {
                    Ok(()) => {
                        self.vacated.remove(to);
                        self.staged.push(Staged { temp, from: from.to_path_buf(), to: to.to_path_buf() });
                    }
                    Err(e) => {
                        self.ctx.ask_error(to, &VfsError::io(&e, to))?;
                        self.left.push(change.clone());
                    }
                }
                return Ok(());
            }
            let error = VfsError::new(
                ferryx_vfs::VfsErrorKind::AlreadyExists,
                Some(from),
                format!("{} already exists", from.display()),
            );
            self.ctx.ask_error(from, &error)?;
            self.left.push(change.clone());
            return Ok(());
        }
        self.make_parents(from);
        let same_device = ferryx_vfs::native::device_of(to).is_some()
            && ferryx_vfs::native::device_of(to)
                == ferryx_vfs::native::device_of(from.parent().unwrap_or(from));
        if same_device {
            loop {
                match fs::rename(to, from) {
                    Ok(()) => {
                        self.vacated.remove(to);
                        self.ctx.record(Change::Moved { from: to.to_path_buf(), to: from.to_path_buf() });
                        return Ok(());
                    }
                    Err(e) => {
                        if !self.ctx.ask_error(to, &VfsError::io(&e, to))? {
                            self.left.push(change.clone());
                            return Ok(());
                        }
                    }
                }
            }
        }
        // Across volumes: the operations' own move (a copy, then a delete),
        // which records itself.
        let options =
            OpOptions { conflicts: ConflictPolicy::Skip, preserve_attributes: true, ..Default::default() };
        if copy::move_item(self.ctx, to, from, &options)? {
            self.vacated.remove(to);
        } else {
            self.left.push(change.clone());
        }
        Ok(())
    }

    /// Makes the missing folders above `path`, on record so that the walk
    /// back removes them again.
    fn make_parents(&self, path: &Path) {
        let Some(parent) = path.parent() else { return };
        if parent.exists() {
            return;
        }
        let top = parent.ancestors().take_while(|a| !a.exists()).last().map(Path::to_path_buf);
        if fs::create_dir_all(parent).is_ok() {
            if let Some(top) = top {
                self.ctx.record_created(&top);
            }
        }
    }

    /// The items set aside go to their places.
    fn land_staged(&mut self) {
        for staged in std::mem::take(&mut self.staged) {
            let landed =
                staged.from.symlink_metadata().is_err() && fs::rename(&staged.temp, &staged.from).is_ok();
            if landed {
                self.ctx.record(Change::Moved { from: staged.to, to: staged.from });
            } else {
                // Back where it stood, and on record as not done.
                let _ = fs::rename(&staged.temp, &staged.to);
                self.ctx.record_error(&staged.from, format!("{} already exists", staged.from.display()));
                self.left.push(Change::Moved { from: staged.from, to: staged.to });
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::journal::{Journal, StepKind};

    fn step(changes: Vec<Change>) -> Step {
        Step {
            id: 1,
            kind: StepKind::Rename,
            items: changes.len() as u64,
            first_name: "x".to_string(),
            changes,
            at_ms: 0,
            truncated: false,
        }
    }

    fn walk(step: &Step) -> (OpContext, Result<(), Abort>) {
        let request = OpRequest {
            kind: OpKind::Undo,
            sources: Vec::new(),
            archive: None,
            destination: None,
            new_name: None,
            options: OpOptions::default(),
        };
        let ctx = OpContext::detached(&request);
        let outcome = run(&ctx, step);
        (ctx, outcome)
    }

    fn moved(from: &Path, to: &Path) -> Change {
        Change::Moved { from: from.to_path_buf(), to: to.to_path_buf() }
    }

    #[test]
    fn a_move_goes_back_and_the_inverse_goes_forward() {
        let dir = tempfile::tempdir().unwrap();
        let a = dir.path().join("a.txt");
        let b = dir.path().join("sub/b.txt");
        fs::create_dir_all(b.parent().unwrap()).unwrap();
        fs::write(&b, b"x").unwrap();
        let s = step(vec![moved(&a, &b)]);
        let checked = check(&s);
        assert_eq!((checked.doable, checked.total), (1, 1));
        assert!(checked.issues.is_empty());
        let (ctx, outcome) = walk(&s);
        outcome.unwrap();
        assert!(a.exists() && !b.exists());
        let inverse = step(ctx.recorded());
        assert_eq!(inverse.changes, vec![moved(&b, &a)]);
        // Redo walks the inverse.
        let (_, outcome) = walk(&inverse);
        outcome.unwrap();
        assert!(!a.exists() && b.exists());
    }

    #[test]
    fn swapped_names_go_back_through_a_temporary_name() {
        let dir = tempfile::tempdir().unwrap();
        let a = dir.path().join("a");
        let b = dir.path().join("b");
        let c = dir.path().join("c");
        // Renamed a → b, b → c (a shift), and c → a.
        fs::write(&a, b"was c").unwrap();
        fs::write(&b, b"was a").unwrap();
        fs::write(&c, b"was b").unwrap();
        let s = step(vec![moved(&a, &b), moved(&b, &c), moved(&c, &a)]);
        assert!(check(&s).issues.is_empty());
        let (ctx, outcome) = walk(&s);
        outcome.unwrap();
        assert_eq!(fs::read(&a).unwrap(), b"was a");
        assert_eq!(fs::read(&b).unwrap(), b"was b");
        assert_eq!(fs::read(&c).unwrap(), b"was c");
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 3);
        assert!(ctx.recorded_left().is_empty());
        assert_eq!(ctx.recorded().len(), 3);
    }

    #[test]
    fn a_taken_place_is_reported_and_left() {
        let dir = tempfile::tempdir().unwrap();
        let a = dir.path().join("a");
        let b = dir.path().join("b");
        fs::write(&a, b"someone else").unwrap();
        fs::write(&b, b"moved").unwrap();
        let s = step(vec![moved(&a, &b)]);
        let checked = check(&s);
        assert_eq!(checked.doable, 0);
        assert_eq!(checked.issues, vec![Issue { kind: IssueKind::Occupied, path: a.clone() }]);
        let (ctx, outcome) = walk(&s);
        outcome.unwrap();
        assert_eq!(fs::read(&a).unwrap(), b"someone else");
        assert!(b.exists());
        assert_eq!(ctx.recorded_left(), vec![moved(&a, &b)]);
        assert!(!ctx.snapshot().errors.is_empty());
    }

    #[test]
    fn a_missing_item_is_reported_and_dropped() {
        let dir = tempfile::tempdir().unwrap();
        let s = step(vec![moved(&dir.path().join("a"), &dir.path().join("gone"))]);
        assert_eq!(check(&s).issues[0].kind, IssueKind::Missing);
        let (ctx, outcome) = walk(&s);
        outcome.unwrap();
        assert!(ctx.recorded().is_empty());
        assert!(ctx.recorded_left().is_empty());
    }

    #[test]
    fn a_moved_item_goes_back_into_a_folder_made_again() {
        let dir = tempfile::tempdir().unwrap();
        let from = dir.path().join("gone/deeper/a");
        let to = dir.path().join("a");
        fs::write(&to, b"a").unwrap();
        let s = step(vec![moved(&from, &to)]);
        let (ctx, outcome) = walk(&s);
        outcome.unwrap();
        assert!(from.exists());
        // The folders made on the way are on record before the move, so a
        // redo moves the item out first and then trashes the empty folders.
        let recorded = ctx.recorded();
        assert!(matches!(&recorded[0], Change::Created { path, .. } if path == &dir.path().join("gone")));
        assert_eq!(recorded[1], moved(&to, &from));
    }

    #[test]
    fn overwritten_and_changed_items_are_warnings() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("f");
        fs::write(&file, b"1").unwrap();
        let fingerprint = Fingerprint { size: 99, modified_ms: None };
        let s = step(vec![
            Change::Overwritten { path: dir.path().join("o") },
            Change::Created { path: file.clone(), fingerprint: Some(fingerprint) },
        ]);
        let checked = check(&s);
        assert_eq!((checked.doable, checked.total), (1, 1));
        let kinds: Vec<IssueKind> = checked.issues.iter().map(|i| i.kind).collect();
        assert_eq!(kinds, vec![IssueKind::Lost, IssueKind::Changed]);
        assert!(kinds.iter().all(|k| !k.blocks()));
    }

    #[test]
    fn a_removed_folder_is_made_again() {
        let dir = tempfile::tempdir().unwrap();
        let folder = dir.path().join("emptied");
        let s = step(vec![Change::FolderRemoved { path: folder.clone() }]);
        let (ctx, outcome) = walk(&s);
        outcome.unwrap();
        assert!(folder.is_dir());
        assert!(matches!(&ctx.recorded()[0], Change::Created { path, .. } if path == &folder));
    }

    #[test]
    fn a_truncated_step_cannot_be_walked() {
        let mut s = step(vec![]);
        s.truncated = true;
        assert_eq!(check(&s).issues[0].kind, IssueKind::Truncated);
        let (_, outcome) = walk(&s);
        assert_eq!(outcome, Err(Abort::Stopped));
    }

    #[test]
    fn start_takes_the_step_off_its_stack() {
        let runner = Runner::new();
        let journal: &Journal = runner.journal();
        let dir = tempfile::tempdir().unwrap();
        let a = dir.path().join("a");
        let b = dir.path().join("b");
        fs::write(&b, b"b").unwrap();
        let id = journal
            .record(crate::journal::StepRecord::for_paths(
                StepKind::Rename,
                std::slice::from_ref(&a),
                vec![moved(&a, &b)],
            ))
            .unwrap();
        assert!(start(&runner, Direction::Undo, id + 1).is_none());
        let op = start(&runner, Direction::Undo, id).unwrap();
        let started = std::time::Instant::now();
        while !runner.progress(op).unwrap().state.is_finished() {
            assert!(started.elapsed().as_secs() < 10);
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert!(a.exists());
        let summary = journal.summary();
        assert!(summary.undo.is_none());
        assert_eq!(summary.redo.unwrap().kind, StepKind::Rename);
    }
}
