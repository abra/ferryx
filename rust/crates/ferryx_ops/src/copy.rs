//! Copy, move and duplicate: everything that writes items of the disk into
//! a folder (`extract` writes an archive's).

use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use ferryx_vfs::error::{IoAt, VfsError, VfsErrorKind};
use ferryx_vfs::native;
use walkdir::WalkDir;

use crate::runner::{copy_name, free_name, OpContext};
use crate::types::*;

const BUFFER: usize = 1024 * 1024;

pub fn run(ctx: &OpContext, request: &OpRequest) -> Result<(), Abort> {
    match request.kind {
        OpKind::Duplicate => duplicate(ctx, request),
        OpKind::Move => copy_or_move(ctx, request, true),
        _ => copy_or_move(ctx, request, false),
    }
}

/// What one top-level source copies to.
struct Job {
    source: PathBuf,
    target: PathBuf,
}

fn copy_or_move(ctx: &OpContext, request: &OpRequest, moving: bool) -> Result<(), Abort> {
    let Some(dest_dir) = request.destination.as_deref() else {
        ctx.record_error(Path::new(""), "no destination".to_string());
        return Err(Abort::Stopped);
    };
    let mut jobs = Vec::new();
    for source in &request.sources {
        let name = match (&request.new_name, request.sources.len()) {
            (Some(new_name), 1) if !new_name.is_empty() => new_name.clone(),
            _ => file_name(source),
        };
        jobs.push(Job { source: source.clone(), target: dest_dir.join(name) });
    }
    // Copying a folder into itself would never end.
    for job in &jobs {
        if job.source.is_dir() && (job.target.starts_with(&job.source)) {
            ctx.record_error(&job.source, format!("cannot copy {} into itself", job.source.display()));
            return Err(Abort::Stopped);
        }
    }
    if let Err(e) = fs::create_dir_all(dest_dir) {
        ctx.record_error(dest_dir, VfsError::io(&e, dest_dir).message);
        return Err(Abort::Stopped);
    }
    scan(ctx, jobs.iter().map(|j| j.source.as_path()))?;
    let mut last_target = None;
    for job in &jobs {
        ctx.check()?;
        let done = if moving {
            move_item(ctx, &job.source, &job.target, &request.options)?
        } else {
            copy_item(ctx, &job.source, &job.target, &request.options)?
        };
        if done {
            last_target = Some(job.target.clone());
        }
    }
    if jobs.len() == 1 {
        ctx.update(|p| p.result_path = last_target);
    }
    Ok(())
}

fn duplicate(ctx: &OpContext, request: &OpRequest) -> Result<(), Abort> {
    scan(ctx, request.sources.iter().map(PathBuf::as_path))?;
    let mut last = None;
    for source in &request.sources {
        ctx.check()?;
        let Some(dir) = source.parent() else { continue };
        let target = copy_name(dir, &file_name(source));
        if copy_item(ctx, source, &target, &request.options)? {
            last = Some(target);
        }
    }
    ctx.update(|p| p.result_path = last);
    Ok(())
}

/// Counts bytes and items under the sources.
fn scan<'a>(ctx: &OpContext, sources: impl Iterator<Item = &'a Path>) -> Result<(), Abort> {
    let mut bytes = 0u64;
    let mut items = 0u64;
    for source in sources {
        ctx.check()?;
        for entry in WalkDir::new(source).follow_links(false).into_iter().filter_map(Result::ok) {
            items += 1;
            if entry.file_type().is_file() {
                bytes += entry.metadata().map(|m| m.len()).unwrap_or(0);
            }
        }
    }
    ctx.set_totals(bytes, items);
    Ok(())
}

fn file_name(path: &Path) -> String {
    path.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string_lossy().into_owned())
}

/// Copies `source` to `target` (the item's own new path). Answers whether
/// anything was written.
fn copy_item(ctx: &OpContext, source: &Path, target: &Path, options: &OpOptions) -> Result<bool, Abort> {
    ctx.check()?;
    ctx.set_current(source);
    let meta = loop {
        match fs::symlink_metadata(source) {
            Ok(meta) => break meta,
            Err(e) => {
                if !ctx.ask_error(source, &VfsError::io(&e, source))? {
                    return Ok(false);
                }
            }
        }
    };
    let file_type = meta.file_type();
    if file_type.is_dir() {
        let target = match resolve_dir_conflict(ctx, source, target, options)? {
            Some(t) => t,
            None => return Ok(false),
        };
        if let Err(e) = fs::create_dir_all(&target) {
            let error = VfsError::io(&e, &target);
            if !ctx.ask_error(&target, &error)? {
                return Ok(false);
            }
        }
        let children = match fs::read_dir(source) {
            Ok(read) => read.filter_map(Result::ok).map(|e| e.path()).collect::<Vec<_>>(),
            Err(e) => {
                ctx.ask_error(source, &VfsError::io(&e, source))?;
                return Ok(false);
            }
        };
        for child in children {
            let child_target = target.join(file_name(&child));
            copy_item(ctx, &child, &child_target, options)?;
        }
        if options.preserve_attributes {
            preserve(source, &target, &meta);
        }
        ctx.item_done();
        return Ok(true);
    }
    let target = match resolve_conflict(
        ctx,
        target,
        Some(meta.len()),
        meta.modified().ok().and_then(native::system_time_ms),
        options,
    )? {
        Some(t) => t,
        None => {
            // Skipped: its bytes still count as handled.
            ctx.add_bytes(meta.len());
            return Ok(false);
        }
    };
    if file_type.is_symlink() {
        loop {
            match copy_symlink(source, &target) {
                Ok(()) => break,
                Err(e) => {
                    if !ctx.ask_error(source, &e)? {
                        return Ok(false);
                    }
                }
            }
        }
        ctx.item_done();
        return Ok(true);
    }
    loop {
        match copy_file(ctx, source, &target, options) {
            Ok(()) => break,
            Err(CopyFailure::Abort(abort)) => return Err(abort),
            Err(CopyFailure::Error(e)) => {
                let _ = fs::remove_file(&target);
                if !ctx.ask_error(source, &e)? {
                    return Ok(false);
                }
                ctx.update(|p| p.bytes_done = p.bytes_done.saturating_sub(0));
            }
        }
    }
    if options.preserve_attributes {
        preserve(source, &target, &meta);
    }
    ctx.item_done();
    Ok(true)
}

enum CopyFailure {
    Error(VfsError),
    Abort(Abort),
}

impl From<Abort> for CopyFailure {
    fn from(a: Abort) -> Self {
        CopyFailure::Abort(a)
    }
}

fn copy_file(ctx: &OpContext, source: &Path, target: &Path, options: &OpOptions) -> Result<(), CopyFailure> {
    let mut input = File::open(source).at(source).map_err(CopyFailure::Error)?;
    let mut output = File::create(target).at(target).map_err(CopyFailure::Error)?;
    let mut buffer = vec![0u8; BUFFER];
    loop {
        ctx.check()?;
        let read = match input.read(&mut buffer) {
            Ok(0) => break,
            Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(CopyFailure::Error(VfsError::io(&e, source))),
        };
        output.write_all(&buffer[..read]).at(target).map_err(CopyFailure::Error)?;
        ctx.add_bytes(read as u64);
    }
    output.flush().at(target).map_err(CopyFailure::Error)?;
    drop(output);
    if options.verify {
        verify(ctx, source, target)?;
    }
    Ok(())
}

fn verify(ctx: &OpContext, source: &Path, target: &Path) -> Result<(), CopyFailure> {
    let mut a = File::open(source).at(source).map_err(CopyFailure::Error)?;
    let mut b = File::open(target).at(target).map_err(CopyFailure::Error)?;
    let mut ba = vec![0u8; BUFFER];
    let mut bb = vec![0u8; BUFFER];
    loop {
        ctx.check()?;
        let na = read_full(&mut a, &mut ba).at(source).map_err(CopyFailure::Error)?;
        let nb = read_full(&mut b, &mut bb).at(target).map_err(CopyFailure::Error)?;
        if na != nb || ba[..na] != bb[..nb] {
            return Err(CopyFailure::Error(VfsError::new(
                VfsErrorKind::Io,
                Some(target),
                format!("{} differs from its source after copying", target.display()),
            )));
        }
        if na == 0 {
            return Ok(());
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

fn copy_symlink(source: &Path, target: &Path) -> Result<(), VfsError> {
    let link_target = fs::read_link(source).at(source)?;
    if target.symlink_metadata().is_ok() {
        remove_any(target)?;
    }
    ferryx_vfs::links::create_symlink(&link_target, target)
}

fn remove_any(path: &Path) -> Result<(), VfsError> {
    let meta = fs::symlink_metadata(path).at(path)?;
    if meta.is_dir() {
        fs::remove_dir_all(path).at(path)
    } else {
        fs::remove_file(path).at(path)
    }
}

/// Where a file goes when `target` is taken: the same path (overwrite),
/// a free name (keep both), or nothing (skip).
pub(crate) fn resolve_conflict(
    ctx: &OpContext,
    target: &Path,
    source_size: Option<u64>,
    source_modified: Option<i64>,
    options: &OpOptions,
) -> Result<Option<PathBuf>, Abort> {
    let Ok(existing) = fs::symlink_metadata(target) else { return Ok(Some(target.to_path_buf())) };
    let existing_modified = existing.modified().ok().and_then(native::system_time_ms);
    let decision = match options.conflicts {
        ConflictPolicy::Overwrite => Answer::Overwrite,
        ConflictPolicy::OverwriteOlder => Answer::OverwriteOlderAll,
        ConflictPolicy::Skip => Answer::Skip,
        ConflictPolicy::KeepBoth => Answer::KeepBoth,
        ConflictPolicy::Ask => ctx.ask_conflict(
            ConflictSide {
                path: String::new(),
                size: source_size,
                modified_ms: source_modified,
                is_dir: false,
            },
            ConflictSide {
                path: target.to_string_lossy().into_owned(),
                size: Some(existing.len()),
                modified_ms: existing_modified,
                is_dir: existing.is_dir(),
            },
            vec![
                Answer::Overwrite,
                Answer::OverwriteAll,
                Answer::OverwriteOlderAll,
                Answer::Skip,
                Answer::SkipAll,
                Answer::KeepBoth,
                Answer::KeepBothAll,
                Answer::Abort,
            ],
        )?,
    };
    match decision {
        Answer::Overwrite | Answer::OverwriteAll | Answer::Merge | Answer::MergeAll => {
            if let Err(e) = remove_any(target) {
                if !ctx.ask_error(target, &e)? {
                    return Ok(None);
                }
            }
            Ok(Some(target.to_path_buf()))
        }
        Answer::OverwriteOlderAll => {
            let newer = match (source_modified, existing_modified) {
                (Some(s), Some(e)) => s > e,
                _ => false,
            };
            if newer {
                if let Err(e) = remove_any(target) {
                    if !ctx.ask_error(target, &e)? {
                        return Ok(None);
                    }
                }
                Ok(Some(target.to_path_buf()))
            } else {
                Ok(None)
            }
        }
        Answer::KeepBoth | Answer::KeepBothAll => {
            let dir = target.parent().unwrap_or(Path::new("."));
            Ok(Some(free_name(dir, &file_name(target))))
        }
        Answer::Abort => Err(Abort::Stopped),
        _ => Ok(None),
    }
}

/// A folder onto an existing folder merges by default; onto a file it asks
/// as a file would.
fn resolve_dir_conflict(
    ctx: &OpContext,
    source: &Path,
    target: &Path,
    options: &OpOptions,
) -> Result<Option<PathBuf>, Abort> {
    let Ok(existing) = fs::symlink_metadata(target) else { return Ok(Some(target.to_path_buf())) };
    if existing.is_dir() {
        let decision = match options.conflicts {
            ConflictPolicy::Skip => Answer::Skip,
            ConflictPolicy::KeepBoth => Answer::KeepBoth,
            ConflictPolicy::Ask => ctx.ask_conflict(
                ConflictSide {
                    path: source.to_string_lossy().into_owned(),
                    size: None,
                    modified_ms: None,
                    is_dir: true,
                },
                ConflictSide {
                    path: target.to_string_lossy().into_owned(),
                    size: None,
                    modified_ms: existing.modified().ok().and_then(native::system_time_ms),
                    is_dir: true,
                },
                vec![
                    Answer::Merge,
                    Answer::MergeAll,
                    Answer::Skip,
                    Answer::SkipAll,
                    Answer::KeepBoth,
                    Answer::KeepBothAll,
                    Answer::Abort,
                ],
            )?,
            _ => Answer::Merge,
        };
        return match decision {
            Answer::Skip | Answer::SkipAll => Ok(None),
            Answer::KeepBoth | Answer::KeepBothAll => {
                Ok(Some(free_name(target.parent().unwrap_or(Path::new(".")), &file_name(target))))
            }
            Answer::Abort => Err(Abort::Stopped),
            _ => Ok(Some(target.to_path_buf())),
        };
    }
    resolve_conflict(ctx, target, None, None, options)
}

fn preserve(source: &Path, target: &Path, meta: &fs::Metadata) {
    if meta.file_type().is_symlink() {
        return;
    }
    set_mode(target, mode_of(meta));
    let modified = meta.modified().ok().and_then(native::system_time_ms);
    let accessed = meta.accessed().ok().and_then(native::system_time_ms);
    set_times(target, modified, accessed);
    let _ = source;
}

#[cfg(unix)]
fn mode_of(meta: &fs::Metadata) -> u32 {
    use std::os::unix::fs::MetadataExt;
    meta.mode() & 0o7777
}

#[cfg(not(unix))]
fn mode_of(meta: &fs::Metadata) -> u32 {
    if meta.permissions().readonly() {
        0o444
    } else {
        0o644
    }
}

#[cfg(unix)]
pub(crate) fn set_mode(path: &Path, mode: u32) {
    use std::os::unix::fs::PermissionsExt;
    let _ = fs::set_permissions(path, fs::Permissions::from_mode(mode & 0o7777));
}

#[cfg(not(unix))]
pub(crate) fn set_mode(path: &Path, mode: u32) {
    if let Ok(meta) = fs::metadata(path) {
        let mut perms = meta.permissions();
        perms.set_readonly(mode & 0o200 == 0);
        let _ = fs::set_permissions(path, perms);
    }
}

pub(crate) fn set_times(path: &Path, modified_ms: Option<i64>, accessed_ms: Option<i64>) {
    use filetime::FileTime;
    let to_time =
        |ms: i64| FileTime::from_unix_time(ms.div_euclid(1000), (ms.rem_euclid(1000) * 1_000_000) as u32);
    let now = FileTime::now();
    let atime = accessed_ms.map(to_time).unwrap_or(now);
    let mtime = modified_ms.map(to_time).unwrap_or(now);
    let _ = filetime::set_file_times(path, atime, mtime);
}

/// Moves `source` to `target`: a rename on the same volume, else a copy
/// and a delete. Answers whether the item moved.
fn move_item(ctx: &OpContext, source: &Path, target: &Path, options: &OpOptions) -> Result<bool, Abort> {
    ctx.check()?;
    ctx.set_current(source);
    if source == target {
        return Ok(false);
    }
    let same_device = native::device_of(source).is_some()
        && native::device_of(source) == native::device_of(target.parent().unwrap_or(target));
    if same_device {
        let meta = match fs::symlink_metadata(source) {
            Ok(m) => m,
            Err(e) => {
                ctx.ask_error(source, &VfsError::io(&e, source))?;
                return Ok(false);
            }
        };
        let resolved = if meta.is_dir() && target.is_dir() {
            // Moving a folder onto a folder: merge item by item.
            match resolve_dir_conflict(ctx, source, target, options)? {
                Some(t) if t == target => {
                    let children: Vec<PathBuf> = fs::read_dir(source)
                        .map(|r| r.filter_map(Result::ok).map(|e| e.path()).collect())
                        .unwrap_or_default();
                    for child in children {
                        move_item(ctx, &child, &target.join(file_name(&child)), options)?;
                    }
                    let _ = fs::remove_dir(source);
                    ctx.item_done();
                    return Ok(true);
                }
                other => other,
            }
        } else if meta.is_dir() {
            resolve_dir_conflict(ctx, source, target, options)?
        } else {
            resolve_conflict(
                ctx,
                target,
                Some(meta.len()),
                meta.modified().ok().and_then(native::system_time_ms),
                options,
            )?
        };
        let Some(target) = resolved else {
            ctx.add_bytes(if meta.is_file() { meta.len() } else { 0 });
            return Ok(false);
        };
        loop {
            match fs::rename(source, &target) {
                Ok(()) => {
                    ctx.add_bytes(if meta.is_file() { meta.len() } else { 0 });
                    count_items(ctx, &target);
                    return Ok(true);
                }
                Err(e) => {
                    let error = VfsError::io(&e, source);
                    if !ctx.ask_error(source, &error)? {
                        return Ok(false);
                    }
                }
            }
        }
    }
    // Across volumes: copy, then remove what was copied.
    let copied = copy_item(ctx, source, target, options)?;
    if copied {
        if let Err(e) = remove_any(source) {
            ctx.record_error(source, e.message);
        }
    }
    Ok(copied)
}

/// A rename moves a whole tree at once: count its items as done.
fn count_items(ctx: &OpContext, path: &Path) {
    let n = WalkDir::new(path).follow_links(false).into_iter().filter_map(Result::ok).count() as u64;
    ctx.update(|p| p.items_done += n.max(1));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(kind: OpKind, sources: Vec<PathBuf>, dest: &Path) -> OpRequest {
        OpRequest {
            kind,
            sources,
            archive: None,
            destination: Some(dest.to_path_buf()),
            new_name: None,
            options: OpOptions { preserve_attributes: true, verify: true, ..Default::default() },
        }
    }

    #[test]
    fn copies_a_tree_and_counts() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("src");
        fs::create_dir_all(src.join("sub")).unwrap();
        fs::write(src.join("a.txt"), b"hello").unwrap();
        fs::write(src.join("sub/b.txt"), b"world!").unwrap();
        let dest = dir.path().join("dest");
        let req = request(OpKind::Copy, vec![src.clone()], &dest);
        let ctx = OpContext::detached(&req);
        run(&ctx, &req).unwrap();
        let p = ctx.snapshot();
        assert_eq!(p.bytes_total, 11);
        assert_eq!(p.bytes_done, 11);
        assert_eq!(p.items_total, 4);
        assert_eq!(p.items_done, 4);
        assert!(p.errors.is_empty());
        assert_eq!(fs::read(dest.join("src/sub/b.txt")).unwrap(), b"world!");
        assert_eq!(p.result_path, Some(dest.join("src")));
    }

    #[test]
    fn copy_as_renames_and_keep_both_finds_a_free_name() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("f.txt");
        fs::write(&file, b"1").unwrap();
        let dest = dir.path().join("d");
        let mut req = request(OpKind::Copy, vec![file.clone()], &dest);
        req.new_name = Some("g.txt".to_string());
        run(&OpContext::detached(&req), &req).unwrap();
        assert!(dest.join("g.txt").exists());
        let mut again = request(OpKind::Copy, vec![file.clone()], &dest);
        again.new_name = Some("g.txt".to_string());
        again.options.conflicts = ConflictPolicy::KeepBoth;
        run(&OpContext::detached(&again), &again).unwrap();
        assert!(dest.join("g 2.txt").exists());
        let mut skip = request(OpKind::Copy, vec![file.clone()], &dest);
        skip.new_name = Some("g.txt".to_string());
        skip.options.conflicts = ConflictPolicy::Skip;
        fs::write(dest.join("g.txt"), b"kept").unwrap();
        run(&OpContext::detached(&skip), &skip).unwrap();
        assert_eq!(fs::read(dest.join("g.txt")).unwrap(), b"kept");
        let mut over = skip.clone();
        over.options.conflicts = ConflictPolicy::Overwrite;
        run(&OpContext::detached(&over), &over).unwrap();
        assert_eq!(fs::read(dest.join("g.txt")).unwrap(), b"1");
    }

    #[test]
    fn moves_by_rename_and_merges_folders() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("src");
        fs::create_dir_all(src.join("sub")).unwrap();
        fs::write(src.join("sub/a"), b"a").unwrap();
        let dest = dir.path().join("dest");
        fs::create_dir_all(dest.join("src/sub")).unwrap();
        fs::write(dest.join("src/sub/b"), b"b").unwrap();
        let req = request(OpKind::Move, vec![src.clone()], &dest);
        run(&OpContext::detached(&req), &req).unwrap();
        assert!(!src.exists());
        assert!(dest.join("src/sub/a").exists());
        assert!(dest.join("src/sub/b").exists());
    }

    #[test]
    fn duplicates_like_finder() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("note.md");
        fs::write(&file, b"n").unwrap();
        let req = OpRequest {
            kind: OpKind::Duplicate,
            sources: vec![file.clone()],
            archive: None,
            destination: None,
            new_name: None,
            options: OpOptions::default(),
        };
        run(&OpContext::detached(&req), &req).unwrap();
        assert!(dir.path().join("note copy.md").exists());
        run(&OpContext::detached(&req), &req).unwrap();
        assert!(dir.path().join("note copy 2.md").exists());
    }

    #[test]
    fn refuses_a_folder_into_itself() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("src");
        fs::create_dir_all(&src).unwrap();
        let req = request(OpKind::Copy, vec![src.clone()], &src.join("inner"));
        let ctx = OpContext::detached(&req);
        assert_eq!(run(&ctx, &req), Err(Abort::Stopped));
        assert!(!ctx.snapshot().errors.is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn symlinks_are_copied_as_links() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("t"), b"t").unwrap();
        std::os::unix::fs::symlink("t", dir.path().join("l")).unwrap();
        let dest = dir.path().join("d");
        let req = request(OpKind::Copy, vec![dir.path().join("l")], &dest);
        run(&OpContext::detached(&req), &req).unwrap();
        assert_eq!(fs::read_link(dest.join("l")).unwrap(), PathBuf::from("t"));
    }
}
