//! A folder's whole subtree as one list of files, for a panel's flat view
//! (Total Commander's branch view): every file under the folder, each
//! with its folder relative to the one walked, handed over in batches as
//! the walk goes so the first rows show at once in a huge tree.
//!
//! Folders themselves are not rows (an empty folder shows nothing);
//! symbolic links to folders are rows and are not followed, so a link
//! cannot make the walk go round. Hidden items are left out unless asked
//! for, a hidden folder with everything in it.

use std::fs;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use ferryx_core::entry::Entry;
use walkdir::WalkDir;

use crate::error::{IoAt, VfsResult};
use crate::native::{self, Names};

/// How many files a flat list holds at most: past it the walk stops and
/// says so.
pub const CAP: usize = 200_000;

/// The first batch goes as soon as it has this many rows or this time
/// passed; later ones gather longer, so a long walk sends few batches.
const FIRST_BATCH_ROWS: usize = 200;
const FIRST_BATCH_AFTER: Duration = Duration::from_millis(30);
const BATCH_ROWS: usize = 5_000;
const BATCH_AFTER: Duration = Duration::from_millis(120);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FlatOptions {
    pub show_hidden: bool,
    /// The most files to list.
    pub cap: usize,
}

impl Default for FlatOptions {
    fn default() -> Self {
        FlatOptions { show_hidden: false, cap: CAP }
    }
}

/// How a walk ended.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FlatEnd {
    /// Every file was listed.
    Done,
    /// The cap was reached; the rest was not looked at.
    Capped,
    /// Stopped from outside.
    Cancelled,
}

/// A file of the list and its folder relative to the root (`/`-separated,
/// empty for the root's own files).
pub type FlatRow = (Entry, String);

/// Gathers rows and hands them on in batches, the first one early.
pub struct Batcher<'a> {
    pending: Vec<FlatRow>,
    sent: usize,
    last: Instant,
    on_batch: &'a mut dyn FnMut(Vec<FlatRow>),
}

impl<'a> Batcher<'a> {
    pub fn new(on_batch: &'a mut dyn FnMut(Vec<FlatRow>)) -> Batcher<'a> {
        Batcher { pending: Vec::new(), sent: 0, last: Instant::now(), on_batch }
    }

    pub fn push(&mut self, row: FlatRow) {
        self.pending.push(row);
        let (rows, after) =
            if self.sent == 0 { (FIRST_BATCH_ROWS, FIRST_BATCH_AFTER) } else { (BATCH_ROWS, BATCH_AFTER) };
        if self.pending.len() >= rows || self.last.elapsed() >= after {
            self.flush();
        }
    }

    pub fn flush(&mut self) {
        if self.pending.is_empty() {
            return;
        }
        self.sent += self.pending.len();
        self.last = Instant::now();
        (self.on_batch)(std::mem::take(&mut self.pending));
    }

    /// Rows handed on and waiting together.
    pub fn count(&self) -> usize {
        self.sent + self.pending.len()
    }
}

/// Walks the folder `root` on disk and hands its files to `on_batch`;
/// stops when `cancel` is set or [`FlatOptions::cap`] files were found.
/// A subfolder that cannot be read is passed by; a root that cannot be
/// read is the error.
pub fn walk(
    root: &Path,
    options: &FlatOptions,
    cancel: &AtomicBool,
    on_batch: &mut dyn FnMut(Vec<FlatRow>),
) -> VfsResult<FlatEnd> {
    // The root itself must read: its error is the walk's.
    fs::read_dir(root).at(root)?;
    let show_hidden = options.show_hidden;
    let mut names = Names::default();
    let mut batcher = Batcher::new(on_batch);
    let walker = WalkDir::new(root).follow_links(false).min_depth(1).into_iter().filter_entry(move |e| {
        // A hidden folder is left out with what it holds; files are
        // judged below with their flags.
        show_hidden || !e.file_type().is_dir() || !is_hidden_dir(e)
    });
    let mut end = FlatEnd::Done;
    for item in walker {
        if cancel.load(Ordering::Relaxed) {
            end = FlatEnd::Cancelled;
            break;
        }
        let Ok(item) = item else { continue };
        if item.file_type().is_dir() {
            continue;
        }
        let Ok(meta) = item.metadata() else { continue };
        let name = item.file_name().to_string_lossy().into_owned();
        let entry = native::entry_from_metadata(name, item.path().to_path_buf(), &meta, &mut names);
        if entry.is_hidden && !show_hidden {
            continue;
        }
        let folder = item
            .path()
            .parent()
            .and_then(|p| p.strip_prefix(root).ok())
            .map(|p| p.to_string_lossy().replace('\\', "/"))
            .unwrap_or_default();
        batcher.push((entry, folder));
        if batcher.count() >= options.cap {
            end = FlatEnd::Capped;
            break;
        }
    }
    batcher.flush();
    Ok(end)
}

/// A folder is hidden by its dot or, on macOS, its hidden flag.
fn is_hidden_dir(entry: &walkdir::DirEntry) -> bool {
    if entry.file_name().to_string_lossy().starts_with('.') {
        return true;
    }
    hidden_flag(entry)
}

#[cfg(target_os = "macos")]
fn hidden_flag(entry: &walkdir::DirEntry) -> bool {
    use std::os::macos::fs::MetadataExt;
    entry.metadata().map(|m| m.st_flags() & native::UF_HIDDEN != 0).unwrap_or(false)
}

#[cfg(not(target_os = "macos"))]
fn hidden_flag(_entry: &walkdir::DirEntry) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Instant;

    fn tree() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        fs::create_dir_all(root.join("a/b")).unwrap();
        fs::create_dir_all(root.join("empty")).unwrap();
        fs::create_dir_all(root.join(".hidden")).unwrap();
        fs::write(root.join("top.txt"), b"t").unwrap();
        fs::write(root.join("a/one.txt"), b"1").unwrap();
        fs::write(root.join("a/b/two.txt"), b"22").unwrap();
        fs::write(root.join("a/.dot"), b"").unwrap();
        fs::write(root.join(".hidden/secret"), b"").unwrap();
        dir
    }

    fn rows(root: &Path, options: &FlatOptions) -> (Vec<(String, String)>, FlatEnd) {
        let mut all = Vec::new();
        let end = walk(root, options, &AtomicBool::new(false), &mut |batch| {
            all.extend(batch.into_iter().map(|(e, folder)| (folder, e.name)));
        })
        .unwrap();
        all.sort();
        (all, end)
    }

    #[test]
    fn lists_every_file_with_its_folder() {
        let dir = tree();
        let (all, end) = rows(dir.path(), &FlatOptions::default());
        assert_eq!(end, FlatEnd::Done);
        let expected: Vec<(String, String)> = [("", "top.txt"), ("a", "one.txt"), ("a/b", "two.txt")]
            .iter()
            .map(|(f, n)| (f.to_string(), n.to_string()))
            .collect();
        assert_eq!(all, expected);
        let (hidden, _) = rows(dir.path(), &FlatOptions { show_hidden: true, ..Default::default() });
        assert!(hidden.contains(&(".hidden".to_string(), "secret".to_string())));
        assert!(hidden.contains(&("a".to_string(), ".dot".to_string())));
    }

    #[test]
    fn stops_at_the_cap_and_on_cancel() {
        let dir = tree();
        let (all, end) = rows(dir.path(), &FlatOptions { show_hidden: false, cap: 2 });
        assert_eq!(all.len(), 2);
        assert_eq!(end, FlatEnd::Capped);
        let cancel = AtomicBool::new(true);
        let end = walk(dir.path(), &FlatOptions::default(), &cancel, &mut |_| {}).unwrap();
        assert_eq!(end, FlatEnd::Cancelled);
        assert!(walk(&dir.path().join("missing"), &FlatOptions::default(), &cancel, &mut |_| {}).is_err());
    }

    #[cfg(unix)]
    #[test]
    fn links_to_folders_are_rows_not_walked() {
        let dir = tree();
        std::os::unix::fs::symlink(dir.path(), dir.path().join("a/loop")).unwrap();
        let (all, end) = rows(dir.path(), &FlatOptions::default());
        assert_eq!(end, FlatEnd::Done);
        assert!(all.contains(&("a".to_string(), "loop".to_string())));
        assert_eq!(all.len(), 4);
    }

    #[test]
    fn the_first_batch_comes_early() {
        let dir = tempfile::tempdir().unwrap();
        for i in 0..1_000 {
            fs::write(dir.path().join(format!("f{i}")), b"").unwrap();
        }
        let mut batches = Vec::new();
        walk(dir.path(), &FlatOptions::default(), &AtomicBool::new(false), &mut |batch| {
            batches.push(batch.len())
        })
        .unwrap();
        assert!(batches[0] <= FIRST_BATCH_ROWS);
        assert_eq!(batches.iter().sum::<usize>(), 1_000);
    }

    /// Times a walk of a large folder: `FERRYX_FLAT_BENCH=~/Library cargo
    /// test --release -p ferryx_vfs flat_bench -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn flat_bench() {
        let root = std::env::var("FERRYX_FLAT_BENCH").unwrap_or_else(|_| "/usr".to_string());
        let start = Instant::now();
        let mut first = None;
        let mut total = 0;
        let end = walk(
            Path::new(&root),
            &FlatOptions { show_hidden: true, cap: CAP },
            &AtomicBool::new(false),
            &mut |batch| {
                first.get_or_insert(start.elapsed());
                total += batch.len();
            },
        )
        .unwrap();
        println!(
            "{root}: {total} files ({end:?}), first rows after {first:?}, all after {:?}",
            start.elapsed()
        );
    }
}
