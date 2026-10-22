//! Compare and synchronize folders.
//!
//! [`compare`] walks two folders side by side, a folder at a time, pairs
//! the names (exactly, else ignoring case when asked; Unicode forms are
//! one name either way), and reports a row per file: on one side only,
//! newer on one side, equal, or different. Rows come as they are found,
//! so a big tree shows up while it is walked and memory holds one folder
//! at a time. [`run_sync`] carries out the actions the user chose, as an
//! operation: copies both ways (attributes kept, copies verified when
//! asked), then deletions to the trash, each checked against what the
//! comparison saw. [`compare_pairs`] compares files byte for byte for the
//! panels' Compare Folders.

use std::collections::{BTreeSet, HashMap};
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use ferryx_core::collation::natural_cmp;
use ferryx_vfs::error::{VfsError, VfsErrorKind};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use unicode_normalization::UnicodeNormalization;

use crate::checksum::name_filter;
use crate::copy;
use crate::journal::Change;
use crate::runner::OpContext;
use crate::types::*;

/// What a comparison reads of each file.
const COMPARE_BUFFER: usize = 256 * 1024;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompareRequest {
    pub left: PathBuf,
    pub right: PathBuf,
    /// Into subfolders; else the top level only, where a folder on one
    /// side is a row of its own and folders on both are left alone.
    pub recursive: bool,
    /// Files of one size are compared byte for byte; equal contents are
    /// equal whatever their times.
    pub compare_content: bool,
    /// Times this close count as the same (FAT keeps two seconds).
    pub time_tolerance_ms: u64,
    /// Files whose names match (`*.jpg;*.png`); empty for all. Folders are
    /// always walked.
    pub name_mask: String,
    pub include_hidden: bool,
    /// Names that differ in case only are different names.
    pub case_sensitive: bool,
}

/// One side of a row, as the comparison saw it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SideInfo {
    pub size: u64,
    pub modified_ms: Option<i64>,
    pub is_dir: bool,
    pub is_symlink: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RowState {
    LeftOnly,
    RightOnly,
    LeftNewer,
    RightNewer,
    Equal,
    /// The same time, other sizes or contents: neither is newer.
    Different,
    /// A file on one side, a folder (or a link) on the other.
    Conflict,
}

/// One compared item.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompareRow {
    /// The item's path under the left folder, with `/`; for an item on
    /// the right only, where it would go there.
    pub left_rel: String,
    /// The same under the right folder (it differs when names matched
    /// ignoring case).
    pub right_rel: String,
    pub is_dir: bool,
    pub left: Option<SideInfo>,
    pub right: Option<SideInfo>,
    pub state: RowState,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompareProgress {
    pub folders: u64,
    pub files: u64,
    pub bytes_compared: u64,
    /// The folder being read, relative to the left one.
    pub current: Option<String>,
}

/// One item of a folder.
struct Item {
    name: String,
    side: SideInfo,
}

/// Walks both folders and reports every row; answers how many rows there
/// were, or why the walk could not start.
pub fn compare(
    request: &CompareRequest,
    cancel: &AtomicBool,
    every: Duration,
    on_row: &mut dyn FnMut(CompareRow),
    on_progress: &mut dyn FnMut(&CompareProgress),
    on_error: &mut dyn FnMut(String, String),
) -> Result<u64, String> {
    for root in [&request.left, &request.right] {
        if !root.is_dir() {
            return Err(format!("{} is not a folder", root.display()));
        }
    }
    let mut walk = TreeWalk {
        request,
        filter: name_filter(&request.name_mask)?,
        cancel,
        every,
        last: Instant::now(),
        progress: CompareProgress::default(),
        rows: 0,
        buffers: (vec![0u8; COMPARE_BUFFER], vec![0u8; COMPARE_BUFFER]),
        on_row,
        on_progress,
        on_error,
    };
    walk.folder(Some(request.left.as_path()), Some(request.right.as_path()), "", "");
    walk.progress.current = None;
    (walk.on_progress)(&walk.progress);
    Ok(walk.rows)
}

struct TreeWalk<'a> {
    request: &'a CompareRequest,
    filter: Option<ferryx_core::mask::NameFilter>,
    cancel: &'a AtomicBool,
    every: Duration,
    last: Instant,
    progress: CompareProgress,
    rows: u64,
    buffers: (Vec<u8>, Vec<u8>),
    on_row: &'a mut dyn FnMut(CompareRow),
    on_progress: &'a mut dyn FnMut(&CompareProgress),
    on_error: &'a mut dyn FnMut(String, String),
}

fn join_rel(parent: &str, name: &str) -> String {
    if parent.is_empty() {
        name.to_string()
    } else {
        format!("{parent}/{name}")
    }
}

impl TreeWalk<'_> {
    fn cancelled(&self) -> bool {
        self.cancel.load(Ordering::Relaxed)
    }

    fn report(&mut self, force: bool) {
        if force || self.last.elapsed() >= self.every {
            (self.on_progress)(&self.progress);
            self.last = Instant::now();
        }
    }

    fn emit(&mut self, row: CompareRow) {
        self.rows += 1;
        (self.on_row)(row);
    }

    fn read(&mut self, dir: &Path) -> Vec<Item> {
        let read = match fs::read_dir(dir) {
            Ok(read) => read,
            Err(e) => {
                (self.on_error)(dir.to_string_lossy().into_owned(), VfsError::io(&e, dir).message);
                return Vec::new();
            }
        };
        let mut items = Vec::new();
        for entry in read.filter_map(Result::ok) {
            let name = entry.file_name().to_string_lossy().into_owned();
            if !self.request.include_hidden && name.starts_with('.') {
                continue;
            }
            let Ok(meta) = entry.path().symlink_metadata() else { continue };
            let is_dir = meta.is_dir();
            if !is_dir {
                if let Some(filter) = &self.filter {
                    if !filter.matches(&name) {
                        continue;
                    }
                }
            }
            items.push(Item {
                name,
                side: SideInfo {
                    size: if is_dir { 0 } else { meta.len() },
                    modified_ms: meta.modified().ok().and_then(ferryx_vfs::native::system_time_ms),
                    is_dir,
                    is_symlink: meta.file_type().is_symlink(),
                },
            });
        }
        items
    }

    /// Compares the folder at `left_rel` / `right_rel`; either side may be
    /// missing. Answers how many rows it gave.
    fn folder(&mut self, left: Option<&Path>, right: Option<&Path>, left_rel: &str, right_rel: &str) -> u64 {
        if self.cancelled() {
            return 0;
        }
        self.progress.folders += 1;
        self.progress.current = Some(if left.is_some() { left_rel } else { right_rel }.to_string());
        self.report(false);
        let rows_before = self.rows;
        let left_items = left.map(|d| self.read(d)).unwrap_or_default();
        let right_items = right.map(|d| self.read(d)).unwrap_or_default();
        let pairs = pair(left_items, right_items, self.request.case_sensitive);
        let mut folders = Vec::new();
        for (l, r) in pairs {
            if self.cancelled() {
                return self.rows - rows_before;
            }
            let name_l = l.as_ref().or(r.as_ref()).map(|i| i.name.clone()).unwrap_or_default();
            let name_r = r.as_ref().or(l.as_ref()).map(|i| i.name.clone()).unwrap_or_default();
            let rel_l = join_rel(left_rel, &name_l);
            let rel_r = join_rel(right_rel, &name_r);
            let (ls, rs) = (l.as_ref().map(|i| i.side), r.as_ref().map(|i| i.side));
            let both_dirs = ls.is_some_and(|s| s.is_dir) && rs.is_some_and(|s| s.is_dir);
            let one_dir = (ls.is_some_and(|s| s.is_dir) && rs.is_none())
                || (rs.is_some_and(|s| s.is_dir) && ls.is_none());
            if both_dirs || (one_dir && self.request.recursive) {
                if self.request.recursive {
                    folders.push((
                        ls.is_some(),
                        rs.is_some(),
                        rel_l,
                        rel_r,
                        ls.or(rs).unwrap_or(SideInfo {
                            size: 0,
                            modified_ms: None,
                            is_dir: true,
                            is_symlink: false,
                        }),
                    ));
                }
                continue;
            }
            self.progress.files += 1;
            let state = match (ls, rs) {
                (Some(_), None) => RowState::LeftOnly,
                (None, Some(_)) => RowState::RightOnly,
                (Some(a), Some(b)) => self.decide(&rel_l, &rel_r, &a, &b),
                (None, None) => continue,
            };
            let is_dir = ls.or(rs).is_some_and(|s| s.is_dir);
            self.emit(CompareRow { left_rel: rel_l, right_rel: rel_r, is_dir, left: ls, right: rs, state });
            self.report(false);
        }
        for (on_left, on_right, rel_l, rel_r, side) in folders {
            if self.cancelled() {
                break;
            }
            let left_dir = on_left.then(|| self.request.left.join(&rel_l));
            let right_dir = on_right.then(|| self.request.right.join(&rel_r));
            let given = self.folder(left_dir.as_deref(), right_dir.as_deref(), &rel_l, &rel_r);
            // A folder on one side with nothing to show inside is a row of
            // its own, so it can be made or removed.
            if given == 0 && on_left != on_right && !self.cancelled() {
                let empty = left_dir
                    .as_deref()
                    .or(right_dir.as_deref())
                    .is_some_and(|d| fs::read_dir(d).map(|mut r| r.next().is_none()).unwrap_or(false));
                if empty {
                    self.emit(CompareRow {
                        left_rel: rel_l,
                        right_rel: rel_r,
                        is_dir: true,
                        left: on_left.then_some(side),
                        right: on_right.then_some(side),
                        state: if on_left { RowState::LeftOnly } else { RowState::RightOnly },
                    });
                }
            }
        }
        self.rows - rows_before
    }

    fn decide(&mut self, rel_l: &str, rel_r: &str, a: &SideInfo, b: &SideInfo) -> RowState {
        if a.is_dir != b.is_dir || a.is_symlink != b.is_symlink {
            return RowState::Conflict;
        }
        let tolerance = self.request.time_tolerance_ms as i64;
        let newer = match (a.modified_ms, b.modified_ms) {
            (Some(x), Some(y)) if (x - y).abs() > tolerance => Some(x > y),
            _ => None,
        };
        let by_time = |different: bool| match newer {
            Some(true) => RowState::LeftNewer,
            Some(false) => RowState::RightNewer,
            None if different => RowState::Different,
            None => RowState::Equal,
        };
        if self.request.compare_content && a.size == b.size {
            let left = self.request.left.join(rel_l);
            let right = self.request.right.join(rel_r);
            match self.same_contents(&left, &right, a.is_symlink) {
                Some(true) => RowState::Equal,
                Some(false) => match newer {
                    None => RowState::Different,
                    _ => by_time(true),
                },
                // Cancelled.
                None => by_time(false),
            }
        } else {
            by_time(a.size != b.size)
        }
    }

    /// Whether two files hold the same bytes (links: the same target);
    /// `None` when cancelled. A file that cannot be read differs.
    fn same_contents(&mut self, a: &Path, b: &Path, links: bool) -> Option<bool> {
        if links {
            return Some(fs::read_link(a).ok() == fs::read_link(b).ok());
        }
        let cancel = self.cancel;
        let (ba, bb) = (&mut self.buffers.0, &mut self.buffers.1);
        let mut counted = 0u64;
        let result = contents_equal(a, b, ba, bb, cancel, &mut |n| counted += n);
        self.progress.bytes_compared += counted;
        match result {
            Ok(equal) => equal,
            Err(e) => {
                (self.on_error)(e.path.clone().unwrap_or_default(), e.message);
                Some(false)
            }
        }
    }
}

/// The two sides' items paired by name: exactly first, then (unless
/// `case_sensitive`) ignoring case; Unicode composed and decomposed forms
/// are one name. In natural name order.
fn pair(left: Vec<Item>, right: Vec<Item>, case_sensitive: bool) -> Vec<(Option<Item>, Option<Item>)> {
    let key = |name: &str| name.nfc().collect::<String>();
    let mut right_slots: Vec<Option<Item>> = right.into_iter().map(Some).collect();
    let mut exact: HashMap<String, usize> = HashMap::new();
    for (i, item) in right_slots.iter().enumerate() {
        if let Some(item) = item {
            exact.insert(key(&item.name), i);
        }
    }
    let mut out: Vec<(Option<Item>, Option<Item>)> = Vec::new();
    let mut unmatched: Vec<Item> = Vec::new();
    for item in left {
        match exact.get(&key(&item.name)).copied() {
            Some(i) if right_slots[i].is_some() => out.push((Some(item), right_slots[i].take())),
            _ => unmatched.push(item),
        }
    }
    if !case_sensitive && !unmatched.is_empty() {
        let mut folded: HashMap<String, Vec<usize>> = HashMap::new();
        for (i, item) in right_slots.iter().enumerate() {
            if let Some(item) = item {
                folded.entry(key(&item.name).to_lowercase()).or_default().push(i);
            }
        }
        for item in std::mem::take(&mut unmatched) {
            let slot = folded.get_mut(&key(&item.name).to_lowercase()).and_then(|slots| {
                slots.iter().position(|&i| right_slots[i].is_some()).map(|p| slots.remove(p))
            });
            match slot {
                Some(i) => out.push((Some(item), right_slots[i].take())),
                None => unmatched.push(item),
            }
        }
    }
    out.extend(unmatched.into_iter().map(|item| (Some(item), None)));
    out.extend(right_slots.into_iter().flatten().map(|item| (None, Some(item))));
    out.sort_by(|a, b| {
        let name = |p: &(Option<Item>, Option<Item>)| p.0.as_ref().or(p.1.as_ref()).map(|i| i.name.clone());
        natural_cmp(&name(a).unwrap_or_default(), &name(b).unwrap_or_default())
    });
    out
}

/// Whether the files at `a` and `b` hold the same bytes, read side by
/// side until they differ; `Ok(None)` when cancelled.
pub fn contents_equal(
    a: &Path,
    b: &Path,
    ba: &mut [u8],
    bb: &mut [u8],
    cancel: &AtomicBool,
    on_bytes: &mut dyn FnMut(u64),
) -> Result<Option<bool>, VfsError> {
    let mut fa = File::open(a).map_err(|e| VfsError::io(&e, a))?;
    let mut fb = File::open(b).map_err(|e| VfsError::io(&e, b))?;
    if fa.metadata().map(|m| m.len()).ok() != fb.metadata().map(|m| m.len()).ok() {
        return Ok(Some(false));
    }
    loop {
        if cancel.load(Ordering::Relaxed) {
            return Ok(None);
        }
        let na = read_full(&mut fa, ba).map_err(|e| VfsError::io(&e, a))?;
        let nb = read_full(&mut fb, bb).map_err(|e| VfsError::io(&e, b))?;
        on_bytes(na as u64);
        if na != nb || ba[..na] != bb[..nb] {
            return Ok(Some(false));
        }
        if na == 0 {
            return Ok(Some(true));
        }
    }
}

fn read_full(file: &mut File, buffer: &mut [u8]) -> std::io::Result<usize> {
    let mut total = 0;
    while total < buffer.len() {
        match file.read(&mut buffer[total..]) {
            Ok(0) => break,
            Ok(n) => total += n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        }
    }
    Ok(total)
}

// ─── Synchronizing ───

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SyncAction {
    CopyToRight,
    CopyToLeft,
    DeleteLeft,
    DeleteRight,
}

/// One item to synchronize, with both sides as the comparison saw them:
/// what changed since is asked about, not overwritten.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyncItem {
    pub left_rel: String,
    pub right_rel: String,
    pub is_dir: bool,
    pub action: SyncAction,
    pub left: Option<SideInfo>,
    pub right: Option<SideInfo>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyncPlan {
    pub left: PathBuf,
    pub right: PathBuf,
    /// The comparison went into subfolders: a folder row stands for the
    /// folder alone, not its contents.
    pub recursive: bool,
    pub items: Vec<SyncItem>,
    pub preserve_attributes: bool,
    pub verify: bool,
}

/// The paths of an item: (source, target, what the source was, what the
/// target was).
fn ends(plan: &SyncPlan, item: &SyncItem) -> (PathBuf, PathBuf, Option<SideInfo>, Option<SideInfo>) {
    let left = plan.left.join(&item.left_rel);
    let right = plan.right.join(&item.right_rel);
    match item.action {
        SyncAction::CopyToRight | SyncAction::DeleteLeft => (left, right, item.left, item.right),
        SyncAction::CopyToLeft | SyncAction::DeleteRight => (right, left, item.right, item.left),
    }
}

/// What is at `path` now, as a [`SideInfo`].
fn side_now(path: &Path) -> Option<SideInfo> {
    let meta = fs::symlink_metadata(path).ok()?;
    Some(SideInfo {
        size: if meta.is_dir() { 0 } else { meta.len() },
        modified_ms: meta.modified().ok().and_then(ferryx_vfs::native::system_time_ms),
        is_dir: meta.is_dir(),
        is_symlink: meta.file_type().is_symlink(),
    })
}

/// Whether `now` is still what the comparison saw (a folder's time and
/// size do not count).
fn unchanged(seen: Option<SideInfo>, now: Option<SideInfo>) -> bool {
    match (seen, now) {
        (None, None) => true,
        (Some(a), Some(b)) if a.is_dir && b.is_dir => true,
        (Some(a), Some(b)) => a.size == b.size && a.modified_ms == b.modified_ms && a.is_dir == b.is_dir,
        _ => false,
    }
}

fn changed_error(path: &Path) -> VfsError {
    VfsError::new(VfsErrorKind::Io, Some(path), format!("{} changed after the comparison", path.display()))
}

fn conflict_side(path: &Path, side: Option<SideInfo>) -> ConflictSide {
    ConflictSide {
        path: path.to_string_lossy().into_owned(),
        size: side.filter(|s| !s.is_dir).map(|s| s.size),
        modified_ms: side.and_then(|s| s.modified_ms),
        is_dir: side.is_some_and(|s| s.is_dir),
    }
}

/// Carries out `plan`: the copies (either way), then the deletions, which
/// go to the trash.
pub fn run_sync(ctx: &OpContext, plan: &SyncPlan) -> Result<(), Abort> {
    let copies: Vec<&SyncItem> = plan
        .items
        .iter()
        .filter(|i| matches!(i.action, SyncAction::CopyToRight | SyncAction::CopyToLeft))
        .collect();
    let deletions: Vec<&SyncItem> = plan
        .items
        .iter()
        .filter(|i| matches!(i.action, SyncAction::DeleteLeft | SyncAction::DeleteRight))
        .collect();
    let bytes: u64 =
        copies.iter().map(|i| ends(plan, i).2.filter(|s| !s.is_dir).map(|s| s.size).unwrap_or(0)).sum();
    ctx.set_totals(bytes, plan.items.len() as u64);
    let options = OpOptions {
        conflicts: ConflictPolicy::Ask,
        preserve_attributes: plan.preserve_attributes,
        verify: plan.verify,
        password: None,
        into_folders: false,
    };
    for item in copies {
        ctx.check()?;
        copy_one(ctx, plan, item, &options)?;
    }
    delete_all(ctx, plan, &deletions)
}

fn copy_one(ctx: &OpContext, plan: &SyncPlan, item: &SyncItem, options: &OpOptions) -> Result<(), Abort> {
    let (source, target, seen_source, seen_target) = ends(plan, item);
    ctx.set_current(&source);
    if !unchanged(seen_source, side_now(&source)) {
        ctx.ask_error(&source, &changed_error(&source))?;
        ctx.item_done();
        return Ok(());
    }
    let now_target = side_now(&target);
    if now_target.is_some() {
        let planned = seen_target.is_some() && unchanged(seen_target, now_target);
        let overwrite = if planned {
            // The user saw it and chose to replace it.
            true
        } else {
            let answer = ctx.ask_conflict(
                conflict_side(&source, seen_source),
                conflict_side(&target, now_target),
                vec![Answer::Overwrite, Answer::OverwriteAll, Answer::Skip, Answer::SkipAll, Answer::Abort],
            )?;
            match answer {
                Answer::Overwrite | Answer::OverwriteAll => true,
                Answer::Abort => return Err(Abort::Stopped),
                _ => false,
            }
        };
        if !overwrite {
            ctx.add_bytes(seen_source.map(|s| s.size).unwrap_or(0));
            ctx.item_done();
            return Ok(());
        }
        if !(item.is_dir && plan.recursive && now_target.is_some_and(|s| s.is_dir)) {
            match remove(&target) {
                Ok(()) => ctx.record_overwritten(&target),
                Err(e) => {
                    ctx.ask_error(&target, &e)?;
                    ctx.item_done();
                    return Ok(());
                }
            }
        }
    }
    make_parents(ctx, &target);
    if item.is_dir && plan.recursive {
        // The folder alone: its contents are rows of their own.
        if target.symlink_metadata().is_err() {
            match fs::create_dir(&target) {
                Ok(()) => ctx.record_created(&target),
                Err(e) => {
                    ctx.ask_error(&target, &VfsError::io(&e, &target))?;
                }
            }
        }
        ctx.item_done();
        return Ok(());
    }
    copy::copy_item_to(ctx, &source, &target, options)?;
    Ok(())
}

/// Makes the missing folders above `path`, the topmost on record.
fn make_parents(ctx: &OpContext, path: &Path) {
    let Some(parent) = path.parent() else { return };
    if parent.exists() {
        return;
    }
    let top = parent.ancestors().take_while(|a| !a.exists()).last().map(Path::to_path_buf);
    if fs::create_dir_all(parent).is_ok() {
        if let Some(top) = top {
            ctx.record_created(&top);
        }
    }
}

fn remove(path: &Path) -> Result<(), VfsError> {
    let meta = fs::symlink_metadata(path).map_err(|e| VfsError::io(&e, path))?;
    if meta.is_dir() {
        fs::remove_dir_all(path).map_err(|e| VfsError::io(&e, path))
    } else {
        fs::remove_file(path).map_err(|e| VfsError::io(&e, path))
    }
}

/// Trashes the items to delete (each still as the comparison saw it),
/// then the folders that emptied and are not on the other side.
fn delete_all(ctx: &OpContext, plan: &SyncPlan, items: &[&SyncItem]) -> Result<(), Abort> {
    let mut doomed: Vec<PathBuf> = Vec::new();
    // Folders that may have emptied: (this side's folder, the other side's).
    let mut parents: BTreeSet<(PathBuf, PathBuf)> = BTreeSet::new();
    for item in items {
        ctx.check()?;
        let (path, other, seen, _) = ends(plan, item);
        if !unchanged(seen, side_now(&path)) {
            ctx.ask_error(&path, &changed_error(&path))?;
            ctx.item_done();
            continue;
        }
        let (mut here, mut there) = (path.parent(), other.parent());
        let root = if path.starts_with(&plan.left) { &plan.left } else { &plan.right };
        while let (Some(h), Some(t)) = (here, there) {
            if h == root.as_path() || !h.starts_with(root) {
                break;
            }
            parents.insert((h.to_path_buf(), t.to_path_buf()));
            here = h.parent();
            there = t.parent();
        }
        doomed.push(path);
    }
    trash_paths(ctx, &doomed)?;
    // Deepest first, so a folder whose only content was an emptied folder
    // goes too.
    let mut emptied: Vec<(PathBuf, PathBuf)> = parents.into_iter().collect();
    emptied.sort_by_key(|(h, _)| std::cmp::Reverse(h.components().count()));
    for (here, there) in emptied {
        let empty = fs::read_dir(&here).map(|mut r| r.next().is_none()).unwrap_or(false);
        if empty && there.symlink_metadata().is_err() {
            if let Some(Ok(receipt)) =
                ferryx_vfs::trash::trash_items(std::slice::from_ref(&here)).into_iter().next()
            {
                ctx.record(Change::Trashed { receipt });
            }
        }
    }
    Ok(())
}

fn trash_paths(ctx: &OpContext, paths: &[PathBuf]) -> Result<(), Abort> {
    for batch in paths.chunks(64) {
        ctx.check()?;
        let results = ferryx_vfs::trash::trash_items(batch);
        for (path, result) in batch.iter().zip(results) {
            ctx.set_current(path);
            match result {
                Ok(receipt) => ctx.record(Change::Trashed { receipt }),
                Err(e) => {
                    ctx.ask_error(path, &e)?;
                }
            }
            ctx.item_done();
        }
    }
    Ok(())
}

// ─── Compare Folders: contents ───

/// Two files to compare byte for byte.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContentPair {
    pub left: PathBuf,
    pub right: PathBuf,
}

/// Compares each pair as an operation (bytes as progress); the indexes of
/// the pairs that differ (or could not be read) go to `differing`.
pub fn compare_pairs(
    ctx: &OpContext,
    pairs: &[ContentPair],
    differing: &Mutex<Vec<usize>>,
) -> Result<(), Abort> {
    let sizes: Vec<u64> = pairs.iter().map(|p| fs::metadata(&p.left).map(|m| m.len()).unwrap_or(0)).collect();
    ctx.set_totals(sizes.iter().sum(), pairs.len() as u64);
    let mut ba = vec![0u8; COMPARE_BUFFER];
    let mut bb = vec![0u8; COMPARE_BUFFER];
    let stop = AtomicBool::new(false);
    for (index, pair) in pairs.iter().enumerate() {
        ctx.check()?;
        ctx.set_current(&pair.left);
        let mut read = 0u64;
        let mut failure: Option<Abort> = None;
        // A pause waits between reads; a stop ends the file under way.
        let result = contents_equal(&pair.left, &pair.right, &mut ba, &mut bb, &stop, &mut |n| {
            read += n;
            ctx.add_bytes(n);
            if let Err(abort) = ctx.check() {
                failure = Some(abort);
                stop.store(true, Ordering::Relaxed);
            }
        });
        if let Some(abort) = failure {
            return Err(abort);
        }
        let same = match result {
            Ok(Some(same)) => same,
            Ok(None) => return Err(Abort::Cancelled),
            Err(e) => {
                ctx.record_error(&pair.left, e.message);
                false
            }
        };
        // What was not read of a file that differed early still counts.
        ctx.add_bytes(sizes[index].saturating_sub(read));
        if !same {
            differing.lock().push(index);
        }
        ctx.item_done();
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(left: &Path, right: &Path) -> CompareRequest {
        CompareRequest {
            left: left.to_path_buf(),
            right: right.to_path_buf(),
            recursive: true,
            compare_content: false,
            time_tolerance_ms: 1000,
            name_mask: String::new(),
            include_hidden: false,
            case_sensitive: false,
        }
    }

    fn rows(request: &CompareRequest) -> Vec<CompareRow> {
        let mut out = Vec::new();
        compare(
            request,
            &AtomicBool::new(false),
            Duration::ZERO,
            &mut |r| out.push(r),
            &mut |_| {},
            &mut |_, _| {},
        )
        .unwrap();
        out
    }

    fn set_time(path: &Path, seconds: i64) {
        let time = filetime::FileTime::from_unix_time(seconds, 0);
        filetime::set_file_mtime(path, time).unwrap();
    }

    fn states(rows: &[CompareRow]) -> Vec<(String, RowState)> {
        rows.iter().map(|r| (r.left_rel.clone(), r.state)).collect()
    }

    struct Trees {
        _dir: tempfile::TempDir,
        left: PathBuf,
        right: PathBuf,
    }

    fn trees() -> Trees {
        let dir = tempfile::tempdir().unwrap();
        let left = dir.path().join("L");
        let right = dir.path().join("R");
        fs::create_dir_all(left.join("sub")).unwrap();
        fs::create_dir_all(right.join("sub")).unwrap();
        fs::create_dir_all(left.join("only/deep")).unwrap();
        fs::create_dir_all(right.join("emptyright")).unwrap();
        for (path, body, time) in [
            (left.join("same.txt"), "same", 1000),
            (right.join("same.txt"), "same", 1000),
            (left.join("newer.txt"), "new", 2000),
            (right.join("newer.txt"), "old", 1000),
            (left.join("older.txt"), "a", 1000),
            (right.join("older.txt"), "b", 3000),
            (left.join("sub/diff.txt"), "abc", 1000),
            (right.join("sub/diff.txt"), "abcd", 1000),
            (left.join("only/deep/x.txt"), "x", 1000),
            (right.join("right.txt"), "r", 1000),
            (left.join("Case.txt"), "c", 1000),
            (right.join("case.TXT"), "c", 1000),
        ] {
            fs::write(&path, body).unwrap();
            set_time(&path, time);
        }
        fs::create_dir_all(left.join("kind")).unwrap();
        fs::write(right.join("kind"), "file").unwrap();
        Trees { _dir: dir, left, right }
    }

    #[test]
    fn compares_two_trees() {
        let t = trees();
        let found = rows(&request(&t.left, &t.right));
        assert_eq!(
            states(&found),
            vec![
                ("Case.txt".to_string(), RowState::Equal),
                ("kind".to_string(), RowState::Conflict),
                ("newer.txt".to_string(), RowState::LeftNewer),
                ("older.txt".to_string(), RowState::RightNewer),
                ("right.txt".to_string(), RowState::RightOnly),
                ("same.txt".to_string(), RowState::Equal),
                ("emptyright".to_string(), RowState::RightOnly),
                ("only/deep/x.txt".to_string(), RowState::LeftOnly),
                ("sub/diff.txt".to_string(), RowState::Different),
            ]
        );
        // Matched ignoring case: each side keeps its own name.
        assert_eq!(found[0].right_rel, "case.TXT");
        assert!(found[6].is_dir);
    }

    #[test]
    fn case_sensitive_names_stay_apart_and_masks_filter() {
        let t = trees();
        let mut req = request(&t.left, &t.right);
        req.case_sensitive = true;
        req.name_mask = "*.txt".to_string();
        let found = states(&rows(&req));
        assert!(found.contains(&("Case.txt".to_string(), RowState::LeftOnly)));
        // The file `kind` on the right is masked out; the empty folder of
        // that name on the left stays, as a folder on one side.
        assert!(found.contains(&("kind".to_string(), RowState::LeftOnly)));
        // case.TXT matches `*.txt` (masks ignore case), and is right only.
        assert!(found.iter().any(|(rel, state)| rel == "case.TXT" && *state == RowState::RightOnly));
    }

    #[test]
    fn top_level_only_and_contents() {
        let t = trees();
        let mut req = request(&t.left, &t.right);
        req.recursive = false;
        let found = states(&rows(&req));
        assert!(found.contains(&("only".to_string(), RowState::LeftOnly)));
        assert!(!found.iter().any(|(rel, _)| rel.contains('/')));
        assert!(!found.iter().any(|(rel, _)| rel == "sub"));

        // Same size, other bytes, other times: contents decide.
        fs::write(t.left.join("newer.txt"), "same").unwrap();
        fs::write(t.right.join("newer.txt"), "same").unwrap();
        set_time(&t.left.join("newer.txt"), 5000);
        let mut req = request(&t.left, &t.right);
        req.compare_content = true;
        let found = states(&rows(&req));
        assert!(found.contains(&("newer.txt".to_string(), RowState::Equal)));
        assert!(found.contains(&("older.txt".to_string(), RowState::RightNewer)));
    }

    #[test]
    fn a_missing_root_is_an_error() {
        let dir = tempfile::tempdir().unwrap();
        let result = compare(
            &request(&dir.path().join("nope"), dir.path()),
            &AtomicBool::new(false),
            Duration::ZERO,
            &mut |_| {},
            &mut |_| {},
            &mut |_, _| {},
        );
        assert!(result.is_err());
    }

    fn plan_of(t: &Trees, rows: &[CompareRow], pick: impl Fn(&CompareRow) -> Option<SyncAction>) -> SyncPlan {
        SyncPlan {
            left: t.left.clone(),
            right: t.right.clone(),
            recursive: true,
            items: rows
                .iter()
                .filter_map(|r| {
                    pick(r).map(|action| SyncItem {
                        left_rel: r.left_rel.clone(),
                        right_rel: r.right_rel.clone(),
                        is_dir: r.is_dir,
                        action,
                        left: r.left,
                        right: r.right,
                    })
                })
                .collect(),
            preserve_attributes: true,
            verify: true,
        }
    }

    fn detached() -> OpContext {
        OpContext::detached(&OpRequest {
            kind: OpKind::Synchronize,
            sources: Vec::new(),
            archive: None,
            destination: None,
            new_name: None,
            options: OpOptions::default(),
        })
    }

    #[test]
    fn synchronizes_both_ways_and_records() {
        let t = trees();
        let found = rows(&request(&t.left, &t.right));
        let plan = plan_of(&t, &found, |r| match r.state {
            RowState::LeftOnly | RowState::LeftNewer => Some(SyncAction::CopyToRight),
            RowState::RightOnly | RowState::RightNewer => Some(SyncAction::CopyToLeft),
            _ => None,
        });
        let ctx = detached();
        run_sync(&ctx, &plan).unwrap();
        assert_eq!(fs::read_to_string(t.right.join("newer.txt")).unwrap(), "new");
        assert_eq!(fs::read_to_string(t.left.join("older.txt")).unwrap(), "b");
        assert_eq!(fs::read_to_string(t.right.join("only/deep/x.txt")).unwrap(), "x");
        assert_eq!(fs::read_to_string(t.left.join("right.txt")).unwrap(), "r");
        assert!(t.left.join("emptyright").is_dir());
        assert!(ctx.snapshot().errors.is_empty());
        let recorded = ctx.recorded();
        assert!(recorded.contains(&Change::Overwritten { path: t.right.join("newer.txt") }));
        // The new folder on the right is one record with its contents.
        assert!(recorded
            .iter()
            .any(|c| matches!(c, Change::Created { path, .. } if path == &t.right.join("only"))));
        // A second comparison finds them alike.
        let again = rows(&request(&t.left, &t.right));
        assert!(again
            .iter()
            .all(|r| matches!(r.state, RowState::Equal | RowState::Different | RowState::Conflict)));
    }

    #[test]
    fn what_changed_after_the_comparison_is_asked_about() {
        let t = trees();
        let found = rows(&request(&t.left, &t.right));
        // A source changed since: an error, and the copy is skipped.
        let plan = plan_of(&t, &found, |r| (r.left_rel == "older.txt").then_some(SyncAction::CopyToLeft));
        fs::write(t.right.join("older.txt"), "changed source").unwrap();
        let ctx = detached();
        run_sync(&ctx, &plan).unwrap();
        assert_eq!(fs::read_to_string(t.left.join("older.txt")).unwrap(), "a");
        assert_eq!(ctx.snapshot().errors.len(), 1);
        // A target that appeared since is a conflict question; nobody is
        // here to answer, so its first answer (Overwrite) stands, and the
        // replaced item is on record as lost.
        let plan =
            plan_of(&t, &found, |r| (r.left_rel == "only/deep/x.txt").then_some(SyncAction::CopyToRight));
        fs::create_dir_all(t.right.join("only/deep")).unwrap();
        fs::write(t.right.join("only/deep/x.txt"), "appeared").unwrap();
        let ctx = detached();
        run_sync(&ctx, &plan).unwrap();
        assert_eq!(fs::read_to_string(t.right.join("only/deep/x.txt")).unwrap(), "x");
        assert!(ctx.recorded().contains(&Change::Overwritten { path: t.right.join("only/deep/x.txt") }));
    }

    #[test]
    fn deletions_go_to_the_trash_with_emptied_folders() {
        let home = ferryx_vfs::system::home_dir();
        let Ok(dir) = tempfile::Builder::new().prefix(".ferryx-sync-test").tempdir_in(&home) else { return };
        let left = dir.path().join("L");
        let right = dir.path().join("R");
        fs::create_dir_all(left.join("gone/inner")).unwrap();
        fs::create_dir_all(&right).unwrap();
        fs::write(left.join("gone/inner/a.txt"), "a").unwrap();
        let t = Trees { _dir: dir, left, right };
        let found = rows(&request(&t.left, &t.right));
        let plan = plan_of(&t, &found, |_| Some(SyncAction::DeleteLeft));
        let ctx = detached();
        run_sync(&ctx, &plan).unwrap();
        if !ferryx_vfs::trash::put_back_supported() {
            return;
        }
        assert!(!t.left.join("gone").exists());
        let trashed = ctx.recorded().iter().filter(|c| matches!(c, Change::Trashed { .. })).count();
        assert_eq!(trashed, 3);
        // Leave the user's trash as it was: the folders first.
        for change in ctx.recorded().into_iter().rev() {
            if let Change::Trashed { receipt } = change {
                let _ = ferryx_vfs::trash::put_back(&receipt);
            }
        }
    }

    #[test]
    fn compares_pairs_of_files() {
        let dir = tempfile::tempdir().unwrap();
        let p = |n: &str, body: &str| {
            let path = dir.path().join(n);
            fs::write(&path, body).unwrap();
            path
        };
        let pairs = vec![
            ContentPair { left: p("a1", "same"), right: p("a2", "same") },
            ContentPair { left: p("b1", "left"), right: p("b2", "rite") },
            ContentPair { left: p("c1", "x"), right: dir.path().join("missing") },
        ];
        let ctx = detached();
        let differing = Mutex::new(Vec::new());
        compare_pairs(&ctx, &pairs, &differing).unwrap();
        assert_eq!(*differing.lock(), vec![1, 2]);
        assert_eq!(ctx.snapshot().errors.len(), 1);
        assert_eq!(ctx.snapshot().bytes_done, ctx.snapshot().bytes_total);
    }
}
