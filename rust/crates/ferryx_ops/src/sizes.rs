//! Folder sizes, for the panel's size column: the logical size of the
//! files under a folder (what Finder shows), links not followed, a file
//! of several hard links counted once in each folder. A small pool of
//! threads reads the folders' trees (macOS a folder's entries in bulk);
//! each size is reported as soon as its tree is read, so the sizes come in
//! the order they end.

use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::thread;

use parking_lot::{Condvar, Mutex};

use crate::runner::OpContext;
use crate::types::*;

/// At most this many threads read folders: past it the disk, not the
/// threads, is what waits.
const MAX_WORKERS: usize = 8;

pub fn run(ctx: &OpContext, request: &OpRequest) -> Result<(), Abort> {
    ctx.set_totals(0, request.sources.len() as u64);
    walk(ctx, &request.sources, &|index, bytes| {
        let path = request.sources[index].clone();
        ctx.update(|p| {
            p.sizes.push(FolderSize { path, bytes });
            p.items_done += 1;
        });
    })
}

/// Bytes of every file under `dir`, links not followed.
pub fn folder_size(ctx: &OpContext, dir: &Path) -> Result<u64, Abort> {
    let total = AtomicU64::new(0);
    walk(ctx, &[dir.to_path_buf()], &|_, bytes| total.store(bytes, Ordering::Relaxed))?;
    Ok(total.into_inner())
}

/// Reads the trees of `roots` (a link as a root is followed, as the
/// folder it names); `done` hears each root's bytes once its tree is read.
fn walk(ctx: &OpContext, roots: &[PathBuf], done: &(dyn Fn(usize, u64) + Sync)) -> Result<(), Abort> {
    let walk = Walk {
        ctx,
        queue: Mutex::new(Queue { dirs: Vec::new(), busy: 0 }),
        changed: Condvar::new(),
        roots: roots.iter().map(|_| Root::default()).collect(),
        stopped: AtomicBool::new(false),
    };
    {
        let mut queue = walk.queue.lock();
        for (index, root) in roots.iter().enumerate() {
            match fs::metadata(root) {
                Ok(meta) if meta.is_dir() => {
                    walk.roots[index].open.store(1, Ordering::Relaxed);
                    queue.dirs.push((index, root.clone()));
                }
                Ok(meta) => done(index, if meta.is_file() { meta.len() } else { 0 }),
                Err(_) => done(index, 0),
            }
        }
    }
    let workers = thread::available_parallelism().map(|n| n.get()).unwrap_or(4).clamp(2, MAX_WORKERS);
    thread::scope(|scope| {
        let handles: Vec<_> = (0..workers).map(|_| scope.spawn(|| walk.work(done))).collect();
        let mut outcome = Ok(());
        for handle in handles {
            match handle.join() {
                Ok(result) => outcome = outcome.and(result),
                Err(panic) => std::panic::resume_unwind(panic),
            }
        }
        outcome
    })
}

struct Walk<'a> {
    ctx: &'a OpContext,
    queue: Mutex<Queue>,
    /// Folders queued, or the last one read.
    changed: Condvar,
    roots: Vec<Root>,
    stopped: AtomicBool,
}

/// The folders to read, by the index of their root, and how many are
/// being read.
struct Queue {
    dirs: Vec<(usize, PathBuf)>,
    busy: usize,
}

#[derive(Default)]
struct Root {
    bytes: AtomicU64,
    /// Its folders queued or being read: at 0 its tree is read.
    open: AtomicUsize,
    /// Its files of several links, by device and inode.
    #[cfg(unix)]
    linked: Mutex<std::collections::HashSet<(u64, u64)>>,
}

impl Walk<'_> {
    fn work(&self, done: &(dyn Fn(usize, u64) + Sync)) -> Result<(), Abort> {
        let mut buffer = Vec::new();
        loop {
            let (root, dir) = {
                let mut queue = self.queue.lock();
                loop {
                    if self.stopped.load(Ordering::Relaxed) {
                        return Ok(());
                    }
                    if let Some(next) = queue.dirs.pop() {
                        queue.busy += 1;
                        break next;
                    }
                    if queue.busy == 0 {
                        return Ok(());
                    }
                    self.changed.wait(&mut queue);
                }
            };
            if let Err(abort) = self.ctx.check() {
                self.stopped.store(true, Ordering::Relaxed);
                self.changed.notify_all();
                return Err(abort);
            }
            let subdirs = self.read(root, &dir, &mut buffer);
            self.roots[root].open.fetch_add(subdirs.len(), Ordering::AcqRel);
            {
                let mut queue = self.queue.lock();
                queue.busy -= 1;
                queue.dirs.extend(subdirs.into_iter().map(|d| (root, d)));
            }
            self.changed.notify_all();
            if self.roots[root].open.fetch_sub(1, Ordering::AcqRel) == 1 {
                done(root, self.roots[root].bytes.load(Ordering::Acquire));
            }
        }
    }

    /// Adds the files of `dir` to its root's bytes; answers its folders.
    fn read(&self, root: usize, dir: &Path, buffer: &mut Vec<u8>) -> Vec<PathBuf> {
        let mut subdirs = Vec::new();
        let mut bytes = 0u64;
        let mut found = |item: Found| match item {
            Found::Folder(name) => subdirs.push(dir.join(name)),
            Found::File { len, links, id } => {
                if links <= 1 || self.first_link(root, id) {
                    bytes += len;
                }
            }
        };
        #[cfg(target_os = "macos")]
        let listed = bulk::read(dir, buffer, &mut found);
        #[cfg(not(target_os = "macos"))]
        let listed = {
            let _ = buffer;
            false
        };
        if !listed {
            read_entries(dir, &mut found);
        }
        self.roots[root].bytes.fetch_add(bytes, Ordering::AcqRel);
        subdirs
    }

    /// Whether a file of several links is met first in its root.
    #[cfg(unix)]
    fn first_link(&self, root: usize, id: (u64, u64)) -> bool {
        self.roots[root].linked.lock().insert(id)
    }

    #[cfg(not(unix))]
    fn first_link(&self, _root: usize, _id: (u64, u64)) -> bool {
        true
    }
}

/// An entry of a folder that counts.
enum Found<'a> {
    Folder(&'a OsStr),
    /// `id`: its device and inode.
    File {
        len: u64,
        links: u64,
        id: (u64, u64),
    },
}

/// Hands the entries of `dir` to `found` one by one: a `lstat` per file.
fn read_entries(dir: &Path, found: &mut dyn FnMut(Found)) {
    let Ok(entries) = fs::read_dir(dir) else { return };
    for entry in entries.filter_map(Result::ok) {
        let Ok(kind) = entry.file_type() else { continue };
        if kind.is_dir() {
            found(Found::Folder(&entry.file_name()));
        } else if kind.is_file() {
            if let Ok(meta) = entry.metadata() {
                let (links, id) = links_of(&meta);
                found(Found::File { len: meta.len(), links, id });
            }
        }
    }
}

#[cfg(unix)]
fn links_of(meta: &fs::Metadata) -> (u64, (u64, u64)) {
    use std::os::unix::fs::MetadataExt;
    (meta.nlink(), (meta.dev(), meta.ino()))
}

#[cfg(not(unix))]
fn links_of(_meta: &fs::Metadata) -> (u64, (u64, u64)) {
    (1, (0, 0))
}

/// macOS hands over a folder's entries with their attributes in bulk
/// (`getattrlistbulk`): a call per hundreds of entries, not a `lstat` each.
#[cfg(target_os = "macos")]
mod bulk {
    use std::ffi::{CString, OsStr};
    use std::os::raw::c_void;
    use std::os::unix::ffi::OsStrExt;
    use std::path::Path;

    use super::Found;

    /// Not in `libc`: the entry's error, packed right after the returned
    /// attributes; the kinds of `ATTR_CMN_OBJTYPE` (`vtype`).
    const ATTR_CMN_ERROR: u32 = 0x2000_0000;
    const VREG: u32 = 1;
    const VDIR: u32 = 2;

    /// Room for a few hundred entries a call.
    pub const BUFFER: usize = 128 * 1024;

    /// Hands every entry of `dir` to `found`; answers `false` when the
    /// volume cannot list it so (the caller reads it entry by entry).
    pub fn read(dir: &Path, buffer: &mut Vec<u8>, found: &mut dyn FnMut(Found)) -> bool {
        let Ok(path) = CString::new(dir.as_os_str().as_bytes()) else { return false };
        let fd = unsafe { libc::open(path.as_ptr(), libc::O_RDONLY | libc::O_DIRECTORY | libc::O_CLOEXEC) };
        if fd < 0 {
            // Unreadable: nothing in it counts, as a walk would skip it.
            return true;
        }
        buffer.resize(BUFFER, 0);
        let mut list: libc::attrlist = unsafe { std::mem::zeroed() };
        list.bitmapcount = libc::ATTR_BIT_MAP_COUNT;
        list.commonattr = libc::ATTR_CMN_RETURNED_ATTRS
            | ATTR_CMN_ERROR
            | libc::ATTR_CMN_NAME
            | libc::ATTR_CMN_DEVID
            | libc::ATTR_CMN_OBJTYPE
            | libc::ATTR_CMN_FILEID;
        list.fileattr = libc::ATTR_FILE_LINKCOUNT | libc::ATTR_FILE_DATALENGTH;
        let mut first = true;
        let listed = loop {
            let count = unsafe {
                libc::getattrlistbulk(
                    fd,
                    &mut list as *mut libc::attrlist as *mut c_void,
                    buffer.as_mut_ptr() as *mut c_void,
                    buffer.len(),
                    0,
                )
            };
            if count <= 0 {
                // Failing at once: the volume does not do it. Later: what
                // was listed stands.
                break !(count < 0 && first);
            }
            first = false;
            let mut at = 0;
            for _ in 0..count {
                let Some(length) = u32_at(buffer, at).map(|n| n as usize) else { break };
                if length == 0 {
                    break;
                }
                if let Some(entry) = buffer.get(at..at + length) {
                    entry_of(entry, found);
                }
                at += length;
            }
        };
        unsafe { libc::close(fd) };
        listed
    }

    /// One entry: its length, the attributes returned, then those asked
    /// for in their order (common, then file).
    fn entry_of(entry: &[u8], found: &mut dyn FnMut(Found)) -> Option<()> {
        let common = u32_at(entry, 4)?;
        let file = u32_at(entry, 16)?;
        let mut at = 4 + std::mem::size_of::<libc::attribute_set_t>();
        if common & ATTR_CMN_ERROR != 0 {
            if u32_at(entry, at)? != 0 {
                return None;
            }
            at += 4;
        }
        if common & libc::ATTR_CMN_NAME == 0 || common & libc::ATTR_CMN_OBJTYPE == 0 {
            return None;
        }
        // An `attrreference_t`: where the name is from it, and its length
        // with the closing NUL.
        let start = at.checked_add_signed(i32_at(entry, at)? as isize)?;
        let len = (u32_at(entry, at + 4)? as usize).saturating_sub(1);
        let name = entry.get(start..start + len)?;
        at += 8;
        let mut device = 0;
        if common & libc::ATTR_CMN_DEVID != 0 {
            // As `MetadataExt::dev` widens it.
            device = i32_at(entry, at)? as u64;
            at += 4;
        }
        let kind = u32_at(entry, at)?;
        at += 4;
        let mut inode = 0;
        if common & libc::ATTR_CMN_FILEID != 0 {
            inode = u64_at(entry, at)?;
            at += 8;
        }
        match kind {
            VDIR => found(Found::Folder(OsStr::from_bytes(name))),
            VREG => {
                let mut links = 1;
                if file & libc::ATTR_FILE_LINKCOUNT != 0 {
                    links = u32_at(entry, at)? as u64;
                    at += 4;
                }
                let len = if file & libc::ATTR_FILE_DATALENGTH != 0 { u64_at(entry, at)? } else { 0 };
                found(Found::File { len, links, id: (device, inode) });
            }
            _ => {}
        }
        Some(())
    }

    fn u32_at(bytes: &[u8], at: usize) -> Option<u32> {
        Some(u32::from_ne_bytes(bytes.get(at..at + 4)?.try_into().ok()?))
    }

    fn i32_at(bytes: &[u8], at: usize) -> Option<i32> {
        Some(i32::from_ne_bytes(bytes.get(at..at + 4)?.try_into().ok()?))
    }

    fn u64_at(bytes: &[u8], at: usize) -> Option<u64> {
        Some(u64::from_ne_bytes(bytes.get(at..at + 8)?.try_into().ok()?))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn sums_files_under_folders() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("a/b")).unwrap();
        fs::write(dir.path().join("a/x"), b"123").unwrap();
        fs::write(dir.path().join("a/b/y"), b"4567").unwrap();
        let req = OpRequest {
            kind: OpKind::CalcSizes,
            sources: vec![dir.path().join("a")],
            archive: None,
            destination: None,
            new_name: None,
            options: OpOptions::default(),
        };
        let ctx = OpContext::detached(&req);
        run(&ctx, &req).unwrap();
        let p = ctx.snapshot();
        assert_eq!(p.sizes, vec![FolderSize { path: dir.path().join("a"), bytes: 7 }]);
    }

    fn sizes_request(sources: Vec<std::path::PathBuf>) -> OpRequest {
        OpRequest {
            kind: OpKind::CalcSizes,
            sources,
            archive: None,
            destination: None,
            new_name: None,
            options: OpOptions::default(),
        }
    }

    #[cfg(unix)]
    #[test]
    fn a_hard_linked_file_counts_once_in_a_folder() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("a/b")).unwrap();
        fs::create_dir_all(dir.path().join("c")).unwrap();
        fs::write(dir.path().join("a/f"), b"12345").unwrap();
        fs::hard_link(dir.path().join("a/f"), dir.path().join("a/b/g")).unwrap();
        fs::hard_link(dir.path().join("a/f"), dir.path().join("c/h")).unwrap();
        std::os::unix::fs::symlink("f", dir.path().join("a/link")).unwrap();
        let req = sizes_request(vec![dir.path().join("a"), dir.path().join("c")]);
        let ctx = OpContext::detached(&req);
        run(&ctx, &req).unwrap();
        let mut sizes = ctx.snapshot().sizes;
        sizes.sort_by(|x, y| x.path.cmp(&y.path));
        assert_eq!(
            sizes,
            vec![
                FolderSize { path: dir.path().join("a"), bytes: 5 },
                FolderSize { path: dir.path().join("c"), bytes: 5 },
            ]
        );
    }

    #[test]
    fn many_folders_add_up_as_one_walk_would() {
        let dir = tempfile::tempdir().unwrap();
        let mut sources = Vec::new();
        let mut expected = Vec::new();
        for f in 0..12 {
            let folder = dir.path().join(format!("folder {f}"));
            let mut bytes = 0;
            for d in 0..f {
                let deep = folder.join(format!("d{d}/e{d}"));
                fs::create_dir_all(&deep).unwrap();
                for i in 0..d * 3 {
                    let data = vec![b'x'; i * 7 + d];
                    fs::write(deep.join(format!("{i}")), &data).unwrap();
                    bytes += data.len() as u64;
                }
            }
            fs::create_dir_all(&folder).unwrap();
            sources.push(folder.clone());
            expected.push(FolderSize { path: folder, bytes });
        }
        // A file and a missing item as sources: their own size, nothing.
        fs::write(dir.path().join("file"), b"abc").unwrap();
        sources.push(dir.path().join("file"));
        expected.push(FolderSize { path: dir.path().join("file"), bytes: 3 });
        sources.push(dir.path().join("gone"));
        expected.push(FolderSize { path: dir.path().join("gone"), bytes: 0 });

        let req = sizes_request(sources.clone());
        let ctx = OpContext::detached(&req);
        run(&ctx, &req).unwrap();
        let p = ctx.snapshot();
        let mut sizes = p.sizes;
        sizes.sort_by(|x, y| x.path.cmp(&y.path));
        expected.sort_by(|x, y| x.path.cmp(&y.path));
        assert_eq!(sizes, expected);
        assert_eq!((p.items_done, p.items_total), (sources.len() as u64, sources.len() as u64));
        let five = expected.iter().find(|s| s.path.ends_with("folder 5")).unwrap();
        assert_eq!(folder_size(&ctx, &five.path).unwrap(), five.bytes);
    }

    /// What a reader found in `dir`: folders, and files with their size,
    /// links and inode, sorted.
    #[cfg(target_os = "macos")]
    fn found_by(dir: &Path, read: impl FnOnce(&Path, &mut dyn FnMut(Found))) -> Vec<String> {
        let mut found = Vec::new();
        read(dir, &mut |item| {
            found.push(match item {
                Found::Folder(name) => format!("folder {}", name.to_string_lossy()),
                Found::File { len, links, id } => format!("file {len} {links} {id:?}"),
            })
        });
        found.sort();
        found
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn the_bulk_listing_finds_what_lstat_finds() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir(dir.path().join("sub")).unwrap();
        for i in 0..700 {
            fs::write(dir.path().join(format!("file with a long name {i}")), vec![b'x'; i]).unwrap();
        }
        fs::hard_link(dir.path().join("file with a long name 5"), dir.path().join("linked")).unwrap();
        std::os::unix::fs::symlink("sub", dir.path().join("link")).unwrap();
        for folder in [dir.path(), Path::new("/usr/bin"), Path::new("/System/Library/CoreServices")] {
            let bulk = found_by(folder, |dir, found| assert!(bulk::read(dir, &mut Vec::new(), found)));
            let one_by_one = found_by(folder, |dir, found| read_entries(dir, found));
            assert_eq!(bulk, one_by_one, "{}", folder.display());
        }
    }

    #[test]
    fn a_cancelled_walk_stops() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("a/b")).unwrap();
        let req = sizes_request(vec![dir.path().join("a")]);
        let ctx = OpContext::detached(&req);
        ctx.cancel();
        assert_eq!(run(&ctx, &req), Err(Abort::Cancelled));
        assert!(ctx.snapshot().sizes.is_empty());
    }

    /// Times the sizes of every folder in a folder, as the panel asks for
    /// them: `FERRYX_SIZES_BENCH=/usr cargo test --release -p ferryx_ops
    /// sizes_bench -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn sizes_bench() {
        let root = std::env::var("FERRYX_SIZES_BENCH").unwrap_or_else(|_| "/usr".to_string());
        let sources: Vec<_> = fs::read_dir(&root)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
            .map(|e| e.path())
            .collect();
        let req = OpRequest {
            kind: OpKind::CalcSizes,
            sources,
            archive: None,
            destination: None,
            new_name: None,
            options: OpOptions::default(),
        };
        for round in ["first", "second"] {
            let ctx = OpContext::detached(&req);
            let start = std::time::Instant::now();
            run(&ctx, &req).unwrap();
            let p = ctx.snapshot();
            let bytes: u64 = p.sizes.iter().map(|s| s.bytes).sum();
            println!("{root}, {round} run: {} folders, {bytes} bytes, {:?}", p.sizes.len(), start.elapsed());
        }
    }
}
