//! Find Duplicates: files with the same contents under one or two folders.
//!
//! The walk notes every file's size; only sizes that occur more than once
//! go on. Hard links to one inode are one file (and overlapping folders
//! see a file once). The first 16 KB of each candidate are hashed and the
//! groups split by that, then the last 16 KB of files over 32 KB (a log
//! appended to, a video tagged again differ there). What still looks
//! alike is read past its start: two files compared byte for byte, up to
//! the first difference; more hashed (BLAKE3). The candidates are settled
//! a chunk at a time, the largest files first, and each group is handed
//! over as soon as it is settled: the space most worth freeing shows up
//! first, early.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

use crate::checksum::name_filter;
use crate::hashing::{self, Algorithm};
use crate::sync;

/// What the start hash reads of each file.
pub const PREFIX: u64 = 16 * 1024;

/// What the end hash reads of each file over `PREFIX + TAIL`.
const TAIL: u64 = 16 * 1024;

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
    /// Hashing the start (and end) of the files that share a size.
    Comparing,
    /// Reading on through the files that share a size, a start and an end.
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
    // starts and ends are hashed, what still looks alike is read on, and
    // its groups are handed over before the next chunk begins. So the
    // space most worth freeing shows up first, early, on a big tree too.
    let mut start = 0;
    while start < candidates.len() {
        if cancel.load(Ordering::Relaxed) {
            return Ok(stats);
        }
        let mut end = (start + CHUNK).min(candidates.len());
        while end < candidates.len() && candidates[end].size == candidates[end - 1].size {
            end += 1;
        }
        let chunk: Vec<&Found> = candidates[start..end].iter().collect();
        start = end;

        progress.phase = Some(Phase::Comparing);
        let starts = hash_files(&chunk, Part::Start, cancel, &bytes_read, &mut progress, &mut report);
        if cancel.load(Ordering::Relaxed) {
            return Ok(stats);
        }
        // Small files are hashed whole already: they go out after the
        // chunk's bigger ones.
        let (settled_small, look_alike): (Vec<_>, Vec<_>) =
            split(&chunk, &starts).into_iter().partition(|group| group[0].size <= PREFIX);
        let (need_ends, mut alike): (Vec<_>, Vec<_>) =
            look_alike.into_iter().partition(|group| group[0].size > PREFIX + TAIL);
        let end_jobs: Vec<&Found> = need_ends.iter().flatten().copied().collect();
        let ends = hash_files(&end_jobs, Part::End, cancel, &bytes_read, &mut progress, &mut report);
        if cancel.load(Ordering::Relaxed) {
            return Ok(stats);
        }
        let mut at = 0;
        for group in &need_ends {
            alike.extend(split(group, &ends[at..at + group.len()]));
            at += group.len();
        }
        if alike.is_empty() {
            for group in settled_small {
                emit(group, &mut stats);
            }
            continue;
        }

        // The rest of what still looks alike: a pair compared byte for
        // byte, more hashed; a group goes out as its last job ends.
        progress.phase = Some(Phase::Hashing);
        let mut jobs: Vec<Rest> = Vec::new();
        let mut remaining: Vec<usize> = Vec::with_capacity(alike.len());
        let mut offsets: Vec<usize> = Vec::with_capacity(alike.len());
        for (g, group) in alike.iter().enumerate() {
            offsets.push(jobs.len());
            if let [a, b] = group.as_slice() {
                jobs.push(Rest::Pair(g, a, b));
                remaining.push(1);
            } else {
                jobs.extend(group.iter().map(|&file| Rest::Hash(g, file)));
                remaining.push(group.len());
            }
        }
        let mut hashes: Vec<Option<String>> = vec![None; jobs.len()];
        hashing::parallel(
            &jobs,
            hashing::workers(),
            cancel,
            |job, buffer| {
                let mut count = |n| {
                    bytes_read.fetch_add(n, Ordering::Relaxed);
                };
                match job {
                    Rest::Pair(_, a, b) => {
                        let (ba, bb) = buffer.split_at_mut(buffer.len() / 2);
                        let same =
                            sync::contents_equal_from(&a.path, &b.path, PREFIX, ba, bb, cancel, &mut |n| {
                                count(2 * n)
                            });
                        Done::Same(matches!(same, Ok(Some(true))))
                    }
                    Rest::Hash(_, file) => Done::Hash(
                        hashing::hash_range(
                            &file.path,
                            Algorithm::Blake3,
                            PREFIX,
                            None,
                            buffer,
                            cancel,
                            &mut count,
                        )
                        .ok(),
                    ),
                }
            },
            |event| {
                progress.bytes_done = bytes_read.load(Ordering::Relaxed);
                let Some((index, done)) = event else {
                    // A big file still shows its bytes while nothing finishes.
                    report(&progress, false);
                    return;
                };
                let (g, file) = match jobs[index] {
                    Rest::Pair(g, a, _) => (g, a),
                    Rest::Hash(g, file) => (g, file),
                };
                progress.current = Some(file.path.to_string_lossy().into_owned());
                report(&progress, false);
                remaining[g] -= 1;
                match done {
                    Done::Same(true) => emit(alike[g].clone(), &mut stats),
                    Done::Same(false) => {}
                    Done::Hash(hash) => {
                        hashes[index] = hash;
                        if remaining[g] == 0 {
                            let members = &alike[g];
                            for settled in split(members, &hashes[offsets[g]..offsets[g] + members.len()]) {
                                emit(settled, &mut stats);
                            }
                        }
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

/// What of a file a quick hash reads.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Part {
    /// The first `PREFIX` bytes.
    Start,
    /// The last `TAIL`.
    End,
}

/// What is left to do for a group that still looks alike past its start
/// and end: two files compared, or each file of more hashed.
enum Rest<'a> {
    Pair(usize, &'a Found, &'a Found),
    Hash(usize, &'a Found),
}

enum Done {
    Same(bool),
    Hash(Option<String>),
}

/// Hashes a part of each of `files` on the workers; a file that cannot be
/// read has no hash and drops out. Each file counts as compared once its
/// start is; what is read adds to `bytes_done`.
fn hash_files(
    files: &[&Found],
    part: Part,
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
            let (start, limit) = match part {
                Part::Start => (0, PREFIX),
                Part::End => (file.size.saturating_sub(TAIL), TAIL),
            };
            hashing::hash_range(&file.path, Algorithm::Blake3, start, Some(limit), buffer, cancel, &mut |n| {
                bytes_done.fetch_add(n, Ordering::Relaxed);
            })
            .ok()
        },
        |event| {
            progress.bytes_done = bytes_done.load(Ordering::Relaxed);
            if let Some((index, hash)) = event {
                out[index] = hash;
                if part == Part::Start {
                    progress.files_hashed += 1;
                }
                progress.current = Some(files[index].path.to_string_lossy().into_owned());
            }
            report(progress, false);
        },
    );
    out
}

/// `files` (in size groups, one after another) split by size and hash;
/// groups of two or more, in the files' order.
fn split<'a>(files: &[&'a Found], hashes: &[Option<String>]) -> Vec<Vec<&'a Found>> {
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

    /// Files over 32 KB that share a start: ends that differ part them
    /// before anything else is read; a pair is compared byte for byte,
    /// more are hashed, whatever the size of the rest.
    #[test]
    fn look_alikes_part_at_the_end_or_in_the_middle() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        let size = (PREFIX + TAIL) as usize + 5_000;
        let base: Vec<u8> = (0..size).map(|i| (i % 251) as u8).collect();
        let with = |at: usize| {
            let mut data = base.clone();
            data[at] ^= 0xff;
            data
        };
        // A pair, equal; a pair that differs in the middle.
        fs::write(root.join("pair-a"), &base).unwrap();
        fs::write(root.join("pair-b"), &base).unwrap();
        let other: Vec<u8> = base.iter().map(|b| b.wrapping_add(1)).collect();
        fs::write(root.join("mid-a"), &other).unwrap();
        let mut changed = other.clone();
        changed[PREFIX as usize + 100] ^= 0xff;
        fs::write(root.join("mid-b"), &changed).unwrap();
        // One size, one start: two copies, one with another end, one
        // changed in the middle, one at the very last byte.
        let third: Vec<u8> = base.iter().map(|b| b.wrapping_mul(3)).chain([0u8; 7]).collect();
        let tweak = |at: usize| {
            let mut data = third.clone();
            data[at] ^= 0xff;
            data
        };
        fs::write(root.join("many-1"), &third).unwrap();
        fs::write(root.join("many-2"), &third).unwrap();
        fs::write(root.join("many-3"), tweak(third.len() - 1)).unwrap();
        fs::write(root.join("many-4"), tweak(PREFIX as usize + 1)).unwrap();
        fs::write(root.join("many-5"), tweak(third.len() - TAIL as usize - 1)).unwrap();
        // Two files whose ends differ only.
        fs::write(root.join("end-a"), with(size - 1)).unwrap();
        fs::write(root.join("end-b"), with(size - 2)).unwrap();

        let (groups, stats) = search(&request(vec![root.to_path_buf()]));
        let mut names: Vec<Vec<String>> = groups
            .iter()
            .map(|g| {
                g.files.iter().map(|f| f.path.file_name().unwrap().to_string_lossy().into_owned()).collect()
            })
            .collect();
        // Settled at once, the two may come in either order.
        names.sort();
        assert_eq!(names, [vec!["many-1", "many-2"], vec!["pair-a", "pair-b"]]);
        assert_eq!(stats.wasted, third.len() as u64 + size as u64);
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

    /// Times a search over generated files that share sizes (pairs and
    /// triples of copies, look-alikes that differ at the end or in the
    /// middle), warm in the cache: `cargo test --release -p ferryx_ops
    /// duplicates_bench -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn duplicates_bench() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        let mut seed = 0x9e37_79b9_7f4a_7c15u64;
        let mut fill = |len: usize| {
            let mut out = vec![0u8; len];
            for chunk in out.chunks_mut(8) {
                seed ^= seed << 13;
                seed ^= seed >> 7;
                seed ^= seed << 17;
                chunk.copy_from_slice(&seed.to_le_bytes()[..chunk.len()]);
            }
            out
        };
        // 40 pairs of 16 MB copies, 10 triples of 8 MB.
        for i in 0..40 {
            let data = fill((16 << 20) + i);
            fs::write(root.join(format!("pair{i}-a")), &data).unwrap();
            fs::write(root.join(format!("pair{i}-b")), &data).unwrap();
        }
        for i in 0..10 {
            let data = fill((8 << 20) + 100 + i);
            for c in 0..3 {
                fs::write(root.join(format!("triple{i}-{c}")), &data).unwrap();
            }
        }
        // 200 files of one size and one start that differ in their last
        // bytes (a log rotated, a video re-tagged), 100 in the middle.
        let shared = fill(4 << 20);
        for i in 0..200u32 {
            let mut data = shared.clone();
            let at = data.len() - 4;
            data[at..].copy_from_slice(&i.to_le_bytes());
            fs::write(root.join(format!("tail{i}")), &data).unwrap();
        }
        let shared = fill((4 << 20) + 1);
        for i in 0..100u32 {
            let mut data = shared.clone();
            let at = data.len() / 2;
            data[at..at + 4].copy_from_slice(&i.to_le_bytes());
            fs::write(root.join(format!("middle{i}")), &data).unwrap();
        }
        let req = request(vec![root.to_path_buf()]);
        let mut best = Duration::MAX;
        let mut summary = None;
        for _ in 0..3 {
            let start = Instant::now();
            let mut bytes = 0;
            let (groups, stats) = {
                let mut groups = Vec::new();
                let stats =
                    run(&req, &AtomicBool::new(false), Duration::ZERO, &mut |g| groups.push(g), &mut |p| {
                        bytes = p.bytes_done
                    })
                    .unwrap();
                (groups, stats)
            };
            best = best.min(start.elapsed());
            summary = Some((groups.len(), stats.wasted, bytes));
        }
        let (groups, wasted, bytes) = summary.unwrap();
        println!("{groups} groups, {wasted} bytes to free, {bytes} bytes read, in {best:?}");
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
