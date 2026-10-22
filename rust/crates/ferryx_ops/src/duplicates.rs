//! Find Duplicates: files with the same contents under one or two folders.
//!
//! The walk notes every file's size; only sizes that occur more than once
//! go on. Hard links to one inode are one file (and overlapping folders
//! see a file once). The first 16 KB of each candidate are hashed and the
//! groups split by that; what still shares a size and a start is hashed
//! whole (BLAKE3). The candidates are settled a chunk at a time, the
//! largest files first, and each group is handed over as soon as it is
//! settled: the space most worth freeing shows up first, early.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

use crate::checksum::name_filter;
use crate::hashing::{self, Algorithm};

/// What the start hash reads of each file.
pub const PREFIX: u64 = 16 * 1024;

/// Candidates settled at a time (whole size groups, so a few more).
const CHUNK: usize = 2048;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DuplicatesRequest {
    pub roots: Vec<PathBuf>,
    /// Smaller files are left out; empty files always are.
    pub min_size: u64,
    /// A mask (`*.jpg;*.png`); empty for every name.
    pub name_mask: String,
    pub include_hidden: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Phase {
    /// Walking the folders.
    Scanning,
    /// Hashing the start of the files that share a size.
    Comparing,
    /// Hashing whole files that share a size and a start.
    Hashing,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DuplicatesProgress {
    pub phase: Option<Phase>,
    pub files_scanned: u64,
    /// Files that share their size with another.
    pub candidates: u64,
    /// Candidates compared so far (their start hashed).
    pub files_hashed: u64,
    /// Bytes read so far, starts and whole files.
    pub bytes_done: u64,
    pub current: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DuplicateFile {
    pub path: PathBuf,
    pub modified_ms: Option<i64>,
}

/// Files with the same contents.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DuplicateGroup {
    pub size: u64,
    pub files: Vec<DuplicateFile>,
}

impl DuplicateGroup {
    /// What removing all copies but one frees.
    pub fn wasted(&self) -> u64 {
        self.size * (self.files.len() as u64).saturating_sub(1)
    }
}

/// What a finished search saw.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DuplicatesStats {
    pub files_scanned: u64,
    pub groups: u64,
    pub wasted: u64,
}

/// A file found on the walk.
struct Found {
    path: PathBuf,
    size: u64,
    modified_ms: Option<i64>,
}

/// Runs the search; `on_group` gets each group as it is settled,
/// `on_progress` the counts about every `every`. Stops when `cancel` is
/// set. Answers what it saw, or why it could not start (a bad mask).
pub fn run(
    request: &DuplicatesRequest,
    cancel: &AtomicBool,
    every: Duration,
    on_group: &mut dyn FnMut(DuplicateGroup),
    on_progress: &mut dyn FnMut(&DuplicatesProgress),
) -> Result<DuplicatesStats, String> {
    let filter = name_filter(&request.name_mask)?;
    let mut progress = DuplicatesProgress { phase: Some(Phase::Scanning), ..Default::default() };
    let mut last = Instant::now();
    let mut report = |progress: &DuplicatesProgress, force: bool| {
        if force || last.elapsed() >= every {
            on_progress(progress);
            last = Instant::now();
        }
    };
    report(&progress, true);

    // ─── The walk: files by size, one per inode ───
    let mut by_size: HashMap<u64, Vec<Found>> = HashMap::new();
    let mut seen_inodes: HashSet<(u64, u64)> = HashSet::new();
    let mut seen_paths: HashSet<PathBuf> = HashSet::new();
    let min_size = request.min_size.max(1);
    for root in &request.roots {
        let include_hidden = request.include_hidden;
        let walker = WalkDir::new(root).follow_links(false).into_iter().filter_entry(move |e| {
            e.depth() == 0 || include_hidden || !e.file_name().to_string_lossy().starts_with('.')
        });
        for entry in walker {
            if cancel.load(Ordering::Relaxed) {
                return Ok(DuplicatesStats { files_scanned: progress.files_scanned, ..Default::default() });
            }
            let Ok(entry) = entry else { continue };
            if entry.file_type().is_dir() {
                progress.current = Some(entry.path().to_string_lossy().into_owned());
                report(&progress, false);
                continue;
            }
            if !entry.file_type().is_file() {
                continue;
            }
            progress.files_scanned += 1;
            if let Some(filter) = &filter {
                if !filter.matches(&entry.file_name().to_string_lossy()) {
                    continue;
                }
            }
            let Ok(meta) = entry.metadata() else { continue };
            if meta.len() < min_size {
                continue;
            }
            match inode(&meta) {
                Some(id) if !seen_inodes.insert(id) => continue,
                None if !seen_paths.insert(entry.path().to_path_buf()) => continue,
                _ => {}
            }
            by_size.entry(meta.len()).or_default().push(Found {
                path: entry.into_path(),
                size: meta.len(),
                modified_ms: meta.modified().ok().and_then(ferryx_vfs::native::system_time_ms),
            });
        }
    }
    drop(seen_inodes);
    drop(seen_paths);

    // ─── Candidates: sizes seen twice, the largest first ───
    let mut sizes: Vec<u64> = by_size.iter().filter(|(_, v)| v.len() > 1).map(|(s, _)| *s).collect();
    sizes.sort_unstable_by(|a, b| b.cmp(a));
    let candidates: Vec<Found> = sizes.iter().flat_map(|s| by_size.remove(s).unwrap_or_default()).collect();
    drop(by_size);
    progress.phase = Some(Phase::Comparing);
    progress.candidates = candidates.len() as u64;
    progress.current = None;
    report(&progress, true);

    let mut stats = DuplicatesStats { files_scanned: progress.files_scanned, ..Default::default() };
    let mut emit = |files: Vec<&Found>, stats: &mut DuplicatesStats| {
        let group = DuplicateGroup {
            size: files[0].size,
            files: files
                .into_iter()
                .map(|f| DuplicateFile { path: f.path.clone(), modified_ms: f.modified_ms })
                .collect(),
        };
        stats.groups += 1;
        stats.wasted += group.wasted();
        on_group(group);
    };
    let bytes_read = AtomicU64::new(0);

    // A chunk of whole size groups at a time, the largest files first: its
    // starts are hashed, what still looks alike is hashed whole, and its
    // groups are handed over before the next chunk begins. So the space
    // most worth freeing shows up first, early, on a big tree too.
    let mut start = 0;
    while start < candidates.len() {
        if cancel.load(Ordering::Relaxed) {
            return Ok(stats);
        }
        let mut end = (start + CHUNK).min(candidates.len());
        while end < candidates.len() && candidates[end].size == candidates[end - 1].size {
            end += 1;
        }
        let chunk = &candidates[start..end];
        start = end;

        progress.phase = Some(Phase::Comparing);
        let starts = hash_files(chunk, Some(PREFIX), cancel, &bytes_read, &mut progress, &mut report);
        if cancel.load(Ordering::Relaxed) {
            return Ok(stats);
        }
        // Small files are hashed whole already: they go out after the
        // chunk's bigger ones.
        let mut settled_small: Vec<Vec<&Found>> = Vec::new();
        let mut need_whole: Vec<Vec<&Found>> = Vec::new();
        for group in split(chunk, &starts) {
            if group[0].size <= PREFIX {
                settled_small.push(group);
            } else {
                need_whole.push(group);
            }
        }
        if need_whole.is_empty() {
            for group in settled_small {
                emit(group, &mut stats);
            }
            continue;
        }

        // Whole files, for what still looks alike; a group goes out as its
        // last file is hashed.
        progress.phase = Some(Phase::Hashing);
        let whole_jobs: Vec<&Found> = need_whole.iter().flatten().copied().collect();
        let mut group_of: Vec<usize> = Vec::with_capacity(whole_jobs.len());
        let mut remaining: Vec<usize> = Vec::with_capacity(need_whole.len());
        let mut offsets: Vec<usize> = Vec::with_capacity(need_whole.len());
        for (g, group) in need_whole.iter().enumerate() {
            offsets.push(group_of.len());
            group_of.extend(std::iter::repeat_n(g, group.len()));
            remaining.push(group.len());
        }
        let mut whole: Vec<Option<String>> = vec![None; whole_jobs.len()];
        hashing::parallel(
            &whole_jobs,
            hashing::workers(),
            cancel,
            |file, buffer| {
                hashing::hash_file(&file.path, Algorithm::Blake3, None, buffer, cancel, &mut |n| {
                    bytes_read.fetch_add(n, Ordering::Relaxed);
                })
                .ok()
            },
            |event| {
                progress.bytes_done = bytes_read.load(Ordering::Relaxed);
                let Some((index, hash)) = event else {
                    // A big file still shows its bytes while nothing finishes.
                    report(&progress, false);
                    return;
                };
                whole[index] = hash;
                progress.current = Some(whole_jobs[index].path.to_string_lossy().into_owned());
                report(&progress, false);
                let g = group_of[index];
                remaining[g] -= 1;
                if remaining[g] == 0 {
                    let members = &need_whole[g];
                    let hashes = &whole[offsets[g]..offsets[g] + members.len()];
                    for settled in split_refs(members, hashes) {
                        emit(settled, &mut stats);
                    }
                }
            },
        );
        if cancel.load(Ordering::Relaxed) {
            return Ok(stats);
        }
        for group in settled_small {
            emit(group, &mut stats);
        }
    }
    if cancel.load(Ordering::Relaxed) {
        return Ok(stats);
    }
    progress.current = None;
    progress.bytes_done = bytes_read.load(Ordering::Relaxed);
    report(&progress, true);
    Ok(stats)
}

/// The inode of a file, where the platform has one.
#[cfg(unix)]
fn inode(meta: &std::fs::Metadata) -> Option<(u64, u64)> {
    use std::os::unix::fs::MetadataExt;
    Some((meta.dev(), meta.ino()))
}

#[cfg(not(unix))]
fn inode(_meta: &std::fs::Metadata) -> Option<(u64, u64)> {
    None
}

/// Hashes `files` (their first `limit` bytes) on the workers; a file that
/// cannot be read has no hash and drops out. Each file counts as compared
/// once its start is; what is read adds to `bytes_done`.
fn hash_files(
    files: &[Found],
    limit: Option<u64>,
    cancel: &AtomicBool,
    bytes_done: &AtomicU64,
    progress: &mut DuplicatesProgress,
    report: &mut dyn FnMut(&DuplicatesProgress, bool),
) -> Vec<Option<String>> {
    let mut out = vec![None; files.len()];
    hashing::parallel(
        files,
        hashing::workers(),
        cancel,
        |file, buffer| {
            hashing::hash_file(&file.path, Algorithm::Blake3, limit, buffer, cancel, &mut |n| {
                bytes_done.fetch_add(n, Ordering::Relaxed);
            })
            .ok()
        },
        |event| {
            progress.bytes_done = bytes_done.load(Ordering::Relaxed);
            if let Some((index, hash)) = event {
                out[index] = hash;
                progress.files_hashed += 1;
                progress.current = Some(files[index].path.to_string_lossy().into_owned());
            }
            report(progress, false);
        },
    );
    out
}

/// `files` (in size groups, one after another) split by size and hash;
/// groups of two or more, in the files' order.
fn split<'a>(files: &'a [Found], hashes: &[Option<String>]) -> Vec<Vec<&'a Found>> {
    let refs: Vec<&Found> = files.iter().collect();
    split_refs(&refs, hashes)
}

fn split_refs<'a>(files: &[&'a Found], hashes: &[Option<String>]) -> Vec<Vec<&'a Found>> {
    let mut groups: Vec<Vec<&Found>> = Vec::new();
    let mut index: HashMap<(u64, &str), usize> = HashMap::new();
    for (file, hash) in files.iter().zip(hashes) {
        let Some(hash) = hash else { continue };
        match index.get(&(file.size, hash.as_str())) {
            Some(&g) => groups[g].push(file),
            None => {
                index.insert((file.size, hash.as_str()), groups.len());
                groups.push(vec![file]);
            }
        }
    }
    groups.retain(|g| g.len() > 1);
    groups
}

/// The path shortest to read, for "keep the shortest path".
pub fn path_depth(path: &Path) -> usize {
    path.components().count()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn search(request: &DuplicatesRequest) -> (Vec<DuplicateGroup>, DuplicatesStats) {
        let mut groups = Vec::new();
        let stats =
            run(request, &AtomicBool::new(false), Duration::ZERO, &mut |g| groups.push(g), &mut |_| {})
                .unwrap();
        for group in &mut groups {
            group.files.sort_by(|a, b| a.path.cmp(&b.path));
        }
        (groups, stats)
    }

    fn request(roots: Vec<PathBuf>) -> DuplicatesRequest {
        DuplicatesRequest { roots, min_size: 1, name_mask: String::new(), include_hidden: false }
    }

    #[test]
    fn finds_groups_by_contents_not_names() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        fs::create_dir_all(root.join("x/y")).unwrap();
        fs::write(root.join("a.txt"), b"same").unwrap();
        fs::write(root.join("x/b.bin"), b"same").unwrap();
        fs::write(root.join("x/y/c"), b"same").unwrap();
        fs::write(root.join("other"), b"diff").unwrap();
        fs::write(root.join("empty1"), b"").unwrap();
        fs::write(root.join("empty2"), b"").unwrap();
        // Same size and start, different end: big files hashed whole.
        let mut big = vec![7u8; (PREFIX as usize) * 2];
        fs::write(root.join("big1"), &big).unwrap();
        fs::write(root.join("big2"), &big).unwrap();
        big[PREFIX as usize + 10] = 8;
        fs::write(root.join("big3"), &big).unwrap();

        let (groups, stats) = search(&request(vec![root.to_path_buf()]));
        assert_eq!(groups.len(), 2);
        // The largest first.
        assert_eq!(groups[0].size, PREFIX * 2);
        let big_names: Vec<String> = groups[0]
            .files
            .iter()
            .map(|f| f.path.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        assert_eq!(big_names, ["big1", "big2"]);
        assert_eq!(groups[1].files.len(), 3);
        assert_eq!(stats.groups, 2);
        assert_eq!(stats.wasted, PREFIX * 2 + 4 * 2);
        assert!(stats.files_scanned >= 9);
    }

    #[test]
    fn masks_sizes_hidden_and_overlapping_roots() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        fs::create_dir_all(root.join(".hid")).unwrap();
        fs::create_dir_all(root.join("sub")).unwrap();
        fs::write(root.join("a.jpg"), b"pixels").unwrap();
        fs::write(root.join("sub/b.jpg"), b"pixels").unwrap();
        fs::write(root.join(".hid/c.jpg"), b"pixels").unwrap();
        fs::write(root.join("a.txt"), b"pixels").unwrap();

        let mut req = request(vec![root.to_path_buf(), root.join("sub")]);
        req.name_mask = "*.jpg".to_string();
        let (groups, _) = search(&req);
        assert_eq!(groups.len(), 1);
        // `sub` is walked twice but its file counts once.
        assert_eq!(groups[0].files.len(), 2);

        req.include_hidden = true;
        assert_eq!(search(&req).0[0].files.len(), 3);

        req.min_size = 7;
        assert!(search(&req).0.is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn hard_links_are_one_file() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("a"), b"linked").unwrap();
        fs::hard_link(dir.path().join("a"), dir.path().join("b")).unwrap();
        let (groups, _) = search(&request(vec![dir.path().to_path_buf()]));
        assert!(groups.is_empty());
        fs::write(dir.path().join("c"), b"linked").unwrap();
        let (groups, _) = search(&request(vec![dir.path().to_path_buf()]));
        assert_eq!(groups[0].files.len(), 2);
    }

    #[test]
    fn cancel_stops_it() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("a"), b"x").unwrap();
        fs::write(dir.path().join("b"), b"x").unwrap();
        let mut groups = 0;
        let stats = run(
            &request(vec![dir.path().to_path_buf()]),
            &AtomicBool::new(true),
            Duration::ZERO,
            &mut |_| groups += 1,
            &mut |_| {},
        )
        .unwrap();
        assert_eq!(groups, 0);
        assert_eq!(stats.groups, 0);
    }
}
