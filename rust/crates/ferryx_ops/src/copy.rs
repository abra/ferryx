//! Copy, move and duplicate: everything that writes items of the disk into
//! a folder (`extract` writes an archive's).
//!
//! A file whose attributes are kept is cloned where the volume can (APFS:
//! at once, its blocks shared, every attribute with it). Otherwise it goes
//! through one buffer per operation, or on macOS, when bigger than that,
//! through `copyfile(3)` (holes kept); macOS then gives it the extended
//! attributes, ACL, flags and dates too. A copy to verify goes through
//! the buffer: its source is hashed on the way and the copy read back
//! past the page cache.

use std::cell::RefCell;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

use ferryx_vfs::error::{IoAt, VfsError, VfsErrorKind};
use ferryx_vfs::native;
use walkdir::WalkDir;

use crate::journal::Change;
use crate::runner::{copy_name, free_name, OpContext};
use crate::types::*;

const BUFFER: usize = 1024 * 1024;

thread_local! {
    /// The copy buffer of the operation on this thread: made at its first
    /// use, then reused for every file the operation copies.
    static COPY_BUFFER: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

fn with_buffer<R>(f: impl FnOnce(&mut [u8]) -> R) -> R {
    COPY_BUFFER.with_borrow_mut(|buffer| {
        if buffer.is_empty() {
            buffer.resize(BUFFER, 0);
        }
        f(buffer)
    })
}

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
    // A move on one volume renames each item whole: nothing under it is
    // counted, the item is one.
    let dest_device = if moving { native::device_of(dest_dir) } else { None };
    let renamed: Vec<bool> = jobs
        .iter()
        .map(|job| dest_device.is_some() && native::device_of(&job.source) == dest_device)
        .collect();
    let copied = jobs.iter().zip(&renamed).filter(|(_, r)| !**r).map(|(job, _)| job.source.as_path());
    scan(ctx, copied, renamed.iter().filter(|r| **r).count() as u64)?;
    let mut last_target = None;
    for (job, rename) in jobs.iter().zip(renamed) {
        ctx.check()?;
        let done = if moving {
            move_job(ctx, &job.source, &job.target, &request.options, rename)?
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
    scan(ctx, request.sources.iter().map(PathBuf::as_path), 0)?;
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

/// Counts bytes and items under the sources, plus `renames` items moved
/// whole by a rename each.
fn scan<'a>(ctx: &OpContext, sources: impl Iterator<Item = &'a Path>, renames: u64) -> Result<(), Abort> {
    let mut bytes = 0u64;
    let mut items = renames;
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
    copy_item_to(ctx, source, target, options).map(|written| written.is_some())
}

/// Copies `source` to `target` as [`copy_item`] does, answering where it
/// went (another name when both are kept), or `None` when nothing was
/// written. What it makes goes on the operation's record.
pub(crate) fn copy_item_to(
    ctx: &OpContext,
    source: &Path,
    target: &Path,
    options: &OpOptions,
) -> Result<Option<PathBuf>, Abort> {
    copy_entry(ctx, source, target, options, false)
}

/// [`copy_item_to`]; `fresh` when `target`'s folder was made by this copy,
/// so its name needs no look for a conflict first (one found all the
/// same, say of two names the volume folds together, is asked about).
fn copy_entry(
    ctx: &OpContext,
    source: &Path,
    target: &Path,
    options: &OpOptions,
    fresh: bool,
) -> Result<Option<PathBuf>, Abort> {
    ctx.check()?;
    ctx.set_current(source);
    let meta = loop {
        match fs::symlink_metadata(source) {
            Ok(meta) => break meta,
            Err(e) => {
                if !ctx.ask_error(source, &VfsError::io(&e, source))? {
                    return Ok(None);
                }
            }
        }
    };
    let file_type = meta.file_type();
    if file_type.is_dir() {
        return copy_dir(ctx, source, target, &meta, options, fresh);
    }
    if file_type.is_symlink() {
        let Some(target) = resolve_file_conflict(ctx, target, &meta, options)? else { return Ok(None) };
        loop {
            match copy_symlink(source, &target) {
                Ok(()) => break,
                Err(e) => {
                    if !ctx.ask_error(source, &e)? {
                        return Ok(None);
                    }
                }
            }
        }
        ctx.record_created(&target);
        ctx.item_done();
        return Ok(Some(target));
    }
    copy_regular(ctx, source, target, &meta, options, fresh)
}

fn copy_dir(
    ctx: &OpContext,
    source: &Path,
    target: &Path,
    meta: &fs::Metadata,
    options: &OpOptions,
    fresh: bool,
) -> Result<Option<PathBuf>, Abort> {
    let (target, made) = if fresh && fs::create_dir(target).is_ok() {
        (target.to_path_buf(), true)
    } else {
        let Some(target) = resolve_dir_conflict(ctx, source, target, options)? else { return Ok(None) };
        let made = target.symlink_metadata().is_err();
        loop {
            match fs::create_dir_all(&target) {
                Ok(()) => break,
                Err(e) => {
                    if !ctx.ask_error(&target, &VfsError::io(&e, &target))? {
                        return Ok(None);
                    }
                }
            }
        }
        (target, made)
    };
    if made {
        // Before its contents, which then need no record of their own.
        ctx.record_created(&target);
    }
    let children = match fs::read_dir(source) {
        Ok(read) => read.filter_map(Result::ok).map(|e| e.path()).collect::<Vec<_>>(),
        Err(e) => {
            ctx.ask_error(source, &VfsError::io(&e, source))?;
            return Ok(None);
        }
    };
    for child in children {
        let child_target = target.join(file_name(&child));
        copy_entry(ctx, &child, &child_target, options, made)?;
    }
    if options.preserve_attributes {
        preserve_dir(source, &target, meta);
    }
    ctx.item_done();
    Ok(Some(target))
}

fn copy_regular(
    ctx: &OpContext,
    source: &Path,
    target: &Path,
    meta: &fs::Metadata,
    options: &OpOptions,
    fresh: bool,
) -> Result<Option<PathBuf>, Abort> {
    // In a folder this copy made the name is free: it is made exclusively
    // instead of looked at first.
    let mut checked = !fresh;
    let mut target = target.to_path_buf();
    if checked {
        match resolve_file_conflict(ctx, &target, meta, options)? {
            Some(t) => target = t,
            None => return Ok(None),
        }
    }
    loop {
        let mut attempt = Attempt::default();
        let failure = match copy_file(ctx, source, &target, meta, options, !checked, &mut attempt) {
            Ok(()) => break,
            Err(CopyFailure::Taken) => {
                checked = true;
                match resolve_file_conflict(ctx, &target, meta, options)? {
                    Some(t) => target = t,
                    None => return Ok(None),
                }
                continue;
            }
            Err(failure) => failure,
        };
        // What the attempt made and counted goes again.
        ctx.take_back_bytes(attempt.bytes);
        if attempt.made {
            let _ = fs::remove_file(&target);
        }
        match failure {
            CopyFailure::Error(e) => {
                if !ctx.ask_error(source, &e)? {
                    return Ok(None);
                }
            }
            CopyFailure::Abort(abort) => return Err(abort),
            CopyFailure::Taken => unreachable!(),
        }
    }
    ctx.record_created(&target);
    ctx.item_done();
    Ok(Some(target))
}

/// [`resolve_conflict`] for a file or a link at `target`; a skipped one's
/// bytes still count as handled.
fn resolve_file_conflict(
    ctx: &OpContext,
    target: &Path,
    meta: &fs::Metadata,
    options: &OpOptions,
) -> Result<Option<PathBuf>, Abort> {
    let resolved = resolve_conflict(
        ctx,
        target,
        Some(meta.len()),
        meta.modified().ok().and_then(native::system_time_ms),
        options,
    )?;
    if resolved.is_none() {
        ctx.add_bytes(meta.len());
    }
    Ok(resolved)
}

enum CopyFailure {
    Error(VfsError),
    Abort(Abort),
    /// The target, made exclusively, was there.
    Taken,
}

impl From<Abort> for CopyFailure {
    fn from(a: Abort) -> Self {
        CopyFailure::Abort(a)
    }
}

/// What one attempt at a file did, undone when it fails.
#[derive(Default)]
struct Attempt {
    /// Bytes it counted in the progress.
    bytes: u64,
    /// It made the target.
    made: bool,
}

impl Attempt {
    fn add(&mut self, ctx: &OpContext, bytes: u64) {
        self.bytes += bytes;
        ctx.add_bytes(bytes);
    }
}

/// Copies the file `source` to `target`, with its attributes when they
/// are kept; `exclusive` fails with [`CopyFailure::Taken`] when `target`
/// is there (else it is replaced).
fn copy_file(
    ctx: &OpContext,
    source: &Path,
    target: &Path,
    meta: &fs::Metadata,
    options: &OpOptions,
    exclusive: bool,
    attempt: &mut Attempt,
) -> Result<(), CopyFailure> {
    // A clone has nothing of its own to verify: its blocks are the source's.
    #[cfg(target_os = "macos")]
    if options.preserve_attributes && clones() {
        match sys::clone(source, target) {
            Ok(()) => {
                attempt.made = true;
                // It keeps every attribute but setuid and setgid.
                if mode_of(meta) & 0o6000 != 0 {
                    set_mode(target, mode_of(meta));
                }
                attempt.add(ctx, meta.len());
                return Ok(());
            }
            Err(e) if exclusive && e.kind() == io::ErrorKind::AlreadyExists => {
                return Err(CopyFailure::Taken)
            }
            // Another volume, or one that cannot clone: copied below.
            Err(_) => {}
        }
    }
    let mut input = File::open(source).at(source).map_err(CopyFailure::Error)?;
    let mut output = create(target, exclusive)?;
    attempt.made = true;
    if options.verify {
        sys::bypass_cache(&output);
        let hash = copy_data(ctx, &mut input, &mut output, source, target, meta, true, attempt)?;
        sys::written(&output);
        if let Some(hash) = hash {
            verify(ctx, target, hash)?;
        }
    } else {
        // A file of one buffer or less costs less in one read and one write
        // than in `copyfile`'s own setup (about 120 and 160 µs on APFS).
        #[cfg(target_os = "macos")]
        if meta.len() > BUFFER as u64 {
            if sys::copy(ctx, &input, &output, options.preserve_attributes, attempt)? {
                // Holes and compressed sources report less than their size.
                if attempt.bytes < meta.len() {
                    attempt.add(ctx, meta.len() - attempt.bytes);
                }
                if options.preserve_attributes {
                    sys::set_times(&output, meta);
                }
                return Ok(());
            }
            // Copied here instead, from the start: the loop names an error.
            ctx.take_back_bytes(std::mem::take(&mut attempt.bytes));
            input.rewind().at(source).map_err(CopyFailure::Error)?;
            output.set_len(0).and_then(|()| output.rewind()).at(target).map_err(CopyFailure::Error)?;
        }
        copy_data(ctx, &mut input, &mut output, source, target, meta, false, attempt)?;
    }
    if options.preserve_attributes {
        #[cfg(target_os = "macos")]
        if sys::copy_metadata(&input, &output) {
            sys::set_times(&output, meta);
            return Ok(());
        }
        drop(output);
        preserve(target, meta);
    }
    Ok(())
}

/// Whether files are cloned where the volume can; a test turns it off on
/// its thread to reach the copies.
#[cfg(target_os = "macos")]
fn clones() -> bool {
    #[cfg(test)]
    return tests::CLONES.get();
    #[cfg(not(test))]
    true
}

fn create(target: &Path, exclusive: bool) -> Result<File, CopyFailure> {
    let mut options = OpenOptions::new();
    options.write(true);
    if exclusive {
        options.create_new(true);
    } else {
        options.create(true).truncate(true);
    }
    options.open(target).map_err(|e| {
        if exclusive && e.kind() == io::ErrorKind::AlreadyExists {
            CopyFailure::Taken
        } else {
            CopyFailure::Error(VfsError::io(&e, target))
        }
    })
}

/// Copies the rest of `input` into `output` through the operation's
/// buffer, answering the hash of what it read when `hash`. Runs of zeros
/// of a sparse source become holes again.
#[allow(clippy::too_many_arguments)]
fn copy_data(
    ctx: &OpContext,
    input: &mut File,
    output: &mut File,
    source: &Path,
    target: &Path,
    meta: &fs::Metadata,
    hash: bool,
    attempt: &mut Attempt,
) -> Result<Option<blake3::Hash>, CopyFailure> {
    let sparse = is_sparse(meta);
    let mut hasher = hash.then(blake3::Hasher::new);
    let mut ends_in_hole = false;
    with_buffer(|buffer| -> Result<(), CopyFailure> {
        loop {
            ctx.check()?;
            let read = match input.read(buffer) {
                Ok(0) => break,
                Ok(n) => n,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(CopyFailure::Error(VfsError::io(&e, source))),
            };
            let chunk = &buffer[..read];
            if let Some(hasher) = hasher.as_mut() {
                hash_part(hasher, chunk);
            }
            ends_in_hole = sparse && chunk.iter().all(|b| *b == 0);
            if ends_in_hole {
                output.seek(SeekFrom::Current(read as i64)).at(target).map_err(CopyFailure::Error)?;
            } else {
                output.write_all(chunk).at(target).map_err(CopyFailure::Error)?;
            }
            attempt.add(ctx, read as u64);
        }
        Ok(())
    })?;
    if ends_in_hole {
        let end = output.stream_position().at(target).map_err(CopyFailure::Error)?;
        output.set_len(end).at(target).map_err(CopyFailure::Error)?;
    }
    output.flush().at(target).map_err(CopyFailure::Error)?;
    Ok(hasher.map(|h| h.finalize()))
}

/// Hashes `bytes` on every core when there are enough of them: a buffer's
/// worth takes a third of the time it takes on one.
fn hash_part(hasher: &mut blake3::Hasher, bytes: &[u8]) {
    if bytes.len() >= 128 * 1024 {
        hasher.update_rayon(bytes);
    } else {
        hasher.update(bytes);
    }
}

/// Fewer blocks than bytes: holes (or compression), so zeros may be holes.
#[cfg(unix)]
fn is_sparse(meta: &fs::Metadata) -> bool {
    use std::os::unix::fs::MetadataExt;
    meta.blocks().saturating_mul(512) < meta.len()
}

#[cfg(not(unix))]
fn is_sparse(_meta: &fs::Metadata) -> bool {
    false
}

/// Reads the copy back past the page cache and compares it with what was
/// read from its source (`expected`).
fn verify(ctx: &OpContext, target: &Path, expected: blake3::Hash) -> Result<(), CopyFailure> {
    let mut file = File::open(target).at(target).map_err(CopyFailure::Error)?;
    sys::bypass_cache(&file);
    let mut hasher = blake3::Hasher::new();
    with_buffer(|buffer| -> Result<(), CopyFailure> {
        loop {
            ctx.check()?;
            match file.read(buffer) {
                Ok(0) => return Ok(()),
                Ok(n) => {
                    hash_part(&mut hasher, &buffer[..n]);
                }
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(CopyFailure::Error(VfsError::io(&e, target))),
            }
        }
    })?;
    // A test makes verifications fail on purpose.
    #[cfg(test)]
    let expected = if tests::FAULTS.replace(tests::FAULTS.get().saturating_sub(1)) > 0 {
        blake3::hash(b"a copy gone wrong")
    } else {
        expected
    };
    if hasher.finalize() != expected {
        return Err(CopyFailure::Error(VfsError::new(
            VfsErrorKind::Io,
            Some(target),
            format!("{} differs from its source after copying", target.display()),
        )));
    }
    Ok(())
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
            ctx.record_overwritten(target);
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
                ctx.record_overwritten(target);
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

/// The attributes of the folder `source` given to its copy, once its
/// items are in (they change its times).
fn preserve_dir(source: &Path, target: &Path, meta: &fs::Metadata) {
    #[cfg(target_os = "macos")]
    if let (Ok(input), Ok(output)) = (File::open(source), File::open(target)) {
        if sys::copy_metadata(&input, &output) {
            sys::set_times(&output, meta);
            return;
        }
    }
    let _ = source;
    preserve(target, meta);
}

/// Permissions and times of `meta` given to `target`: what every desktop
/// keeps.
fn preserve(target: &Path, meta: &fs::Metadata) {
    if meta.file_type().is_symlink() {
        return;
    }
    set_mode(target, mode_of(meta));
    let modified = meta.modified().ok().and_then(native::system_time_ms);
    let accessed = meta.accessed().ok().and_then(native::system_time_ms);
    set_times(target, modified, accessed);
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

/// Whether `source` renames to `target`: both on one volume.
fn same_volume(source: &Path, target: &Path) -> bool {
    let device = native::device_of(source);
    device.is_some() && device == native::device_of(target.parent().unwrap_or(target))
}

/// Moves `source` to `target`: a rename on the same volume, else a copy
/// and a delete. Answers whether the item moved.
pub(crate) fn move_item(
    ctx: &OpContext,
    source: &Path,
    target: &Path,
    options: &OpOptions,
) -> Result<bool, Abort> {
    move_job(ctx, source, target, options, same_volume(source, target))
}

/// [`move_item`], knowing whether `source` renames (`rename`): such an
/// item counts as one, whatever is in it.
fn move_job(
    ctx: &OpContext,
    source: &Path,
    target: &Path,
    options: &OpOptions,
    rename: bool,
) -> Result<bool, Abort> {
    ctx.check()?;
    ctx.set_current(source);
    if rename {
        let moved = source != target && rename_item(ctx, source, target, options)?;
        ctx.item_done();
        return Ok(moved);
    }
    if source == target {
        return Ok(false);
    }
    // Across volumes: copy, then remove what was copied.
    let mark = ctx.record_mark();
    let merging = source.is_dir() && target.is_dir();
    let Some(written) = copy_item_to(ctx, source, target, options)? else { return Ok(false) };
    match remove_any(source) {
        Ok(()) if merging && written == target => ctx.record_merged(mark, source, &written),
        Ok(()) => ctx.record_moved_by_copy(mark, source, &written),
        // Left in place: on record it is a copy.
        Err(e) => ctx.record_error(source, e.message),
    }
    Ok(true)
}

/// Renames `source` to `target` on its volume; a folder onto a folder
/// merges item by item. Counts nothing: the item is counted whole.
fn rename_item(ctx: &OpContext, source: &Path, target: &Path, options: &OpOptions) -> Result<bool, Abort> {
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
                    let child_target = target.join(file_name(&child));
                    if same_volume(&child, &child_target) {
                        ctx.check()?;
                        ctx.set_current(&child);
                        rename_item(ctx, &child, &child_target, options)?;
                    } else {
                        // A volume mounted inside: its items are copied.
                        move_job(ctx, &child, &child_target, options, false)?;
                    }
                }
                if fs::remove_dir(source).is_ok() {
                    ctx.record(Change::FolderRemoved { path: source.to_path_buf() });
                }
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
    let Some(target) = resolved else { return Ok(false) };
    loop {
        match fs::rename(source, &target) {
            Ok(()) => {
                ctx.record_moved(source, &target);
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

/// What the desktop does for a copy beyond reading and writing.
#[cfg(target_os = "macos")]
mod sys {
    use std::ffi::CString;
    use std::fs::{File, Metadata};
    use std::io;
    use std::os::macos::fs::MetadataExt;
    use std::os::raw::{c_char, c_int, c_void};
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::io::AsRawFd;
    use std::panic::{self, AssertUnwindSafe};
    use std::path::Path;

    use super::Attempt;
    use crate::runner::OpContext;
    use crate::types::Abort;

    /// `clonefile(2)`'s flag: a link is cloned as a link.
    const CLONE_NOFOLLOW: u32 = 0x0001;

    fn c_path(path: &Path) -> io::Result<CString> {
        CString::new(path.as_os_str().as_bytes()).map_err(|_| io::Error::from(io::ErrorKind::InvalidInput))
    }

    /// Makes `target` a clone of `source`: its blocks shared until either
    /// changes, every attribute kept. Fails where `target` is, across
    /// volumes and on a volume that cannot clone.
    pub fn clone(source: &Path, target: &Path) -> io::Result<()> {
        let (source, target) = (c_path(source)?, c_path(target)?);
        if unsafe { libc::clonefile(source.as_ptr(), target.as_ptr(), CLONE_NOFOLLOW) } == 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }

    struct Status<'a> {
        ctx: &'a OpContext,
        attempt: &'a mut Attempt,
        panic: Option<Box<dyn std::any::Any + Send>>,
    }

    /// `copyfile`'s progress callback: counts the bytes, stops it when the
    /// operation is cancelled (and waits while it is paused).
    extern "C" fn status(
        what: c_int,
        stage: c_int,
        state: libc::copyfile_state_t,
        _source: *const c_char,
        _target: *const c_char,
        context: *mut c_void,
    ) -> c_int {
        // SAFETY: `context` is the `Status` that `copy` handed over, alive
        // for the whole call.
        let status = unsafe { &mut *(context as *mut Status) };
        let answer = panic::catch_unwind(AssertUnwindSafe(|| {
            if what == libc::COPYFILE_COPY_DATA && stage == libc::COPYFILE_ERR {
                // Copied again by the loop, which names the error.
                return libc::COPYFILE_QUIT;
            }
            if what == libc::COPYFILE_COPY_DATA && stage == libc::COPYFILE_PROGRESS {
                let mut copied: libc::off_t = 0;
                let read = unsafe {
                    libc::copyfile_state_get(
                        state,
                        libc::COPYFILE_STATE_COPIED as u32,
                        &mut copied as *mut libc::off_t as *mut c_void,
                    )
                };
                let copied = copied.max(0) as u64;
                if read == 0 && copied > status.attempt.bytes {
                    status.attempt.add(status.ctx, copied - status.attempt.bytes);
                }
            }
            if status.ctx.check().is_err() {
                libc::COPYFILE_QUIT
            } else {
                libc::COPYFILE_CONTINUE
            }
        }));
        answer.unwrap_or_else(|panic| {
            status.panic = Some(panic);
            libc::COPYFILE_QUIT
        })
    }

    /// Copies `input` into `output` with `fcopyfile`: the data with its
    /// holes, and with `metadata` the extended attributes, ACL, flags,
    /// permissions and times ([`set_times`] then puts the times right).
    /// Answers `false` when it failed (the caller copies another way).
    pub fn copy(
        ctx: &OpContext,
        input: &File,
        output: &File,
        metadata: bool,
        attempt: &mut Attempt,
    ) -> Result<bool, Abort> {
        let mut flags = libc::COPYFILE_DATA | libc::COPYFILE_DATA_SPARSE;
        if metadata {
            flags |= libc::COPYFILE_METADATA;
        }
        let state = unsafe { libc::copyfile_state_alloc() };
        if state.is_null() {
            return Ok(false);
        }
        let mut status = Status { ctx, attempt, panic: None };
        let copied = unsafe {
            libc::copyfile_state_set(state, libc::COPYFILE_STATE_STATUS_CB as u32, status_callback());
            libc::copyfile_state_set(
                state,
                libc::COPYFILE_STATE_STATUS_CTX as u32,
                &mut status as *mut Status as *const c_void,
            );
            let rc = libc::fcopyfile(input.as_raw_fd(), output.as_raw_fd(), state, flags);
            libc::copyfile_state_free(state);
            rc == 0
        };
        if let Some(panic) = status.panic.take() {
            panic::resume_unwind(panic);
        }
        if !copied {
            ctx.check()?;
        }
        Ok(copied)
    }

    fn status_callback() -> *const c_void {
        let callback: extern "C" fn(
            c_int,
            c_int,
            libc::copyfile_state_t,
            *const c_char,
            *const c_char,
            *mut c_void,
        ) -> c_int = status;
        callback as *const c_void
    }

    /// Gives `output` the extended attributes, ACL, flags, permissions and
    /// times of `input` (files or folders); answers whether it went.
    pub fn copy_metadata(input: &File, output: &File) -> bool {
        unsafe {
            libc::fcopyfile(
                input.as_raw_fd(),
                output.as_raw_fd(),
                std::ptr::null_mut(),
                libc::COPYFILE_METADATA,
            ) == 0
        }
    }

    /// Gives `output` the times of `meta`, read before the source was:
    /// `copyfile` takes the access time that reading left and not the
    /// creation date (APFS pulls it back to the modification time). A
    /// locked item is unlocked for it a moment.
    pub fn set_times(output: &File, meta: &Metadata) {
        let fd = output.as_raw_fd();
        let modified = libc::timespec { tv_sec: meta.st_mtime(), tv_nsec: meta.st_mtime_nsec() };
        let accessed = libc::timespec { tv_sec: meta.st_atime(), tv_nsec: meta.st_atime_nsec() };
        let created = libc::timespec { tv_sec: meta.st_birthtime(), tv_nsec: meta.st_birthtime_nsec() };
        // The creation date after the modification time, which would pull
        // it back.
        let set = || {
            set_attributes(fd, libc::ATTR_CMN_MODTIME | libc::ATTR_CMN_ACCTIME, &[modified, accessed])
                && set_attributes(fd, libc::ATTR_CMN_CRTIME, &[created])
        };
        if set() {
            return;
        }
        let Ok(now) = output.metadata() else { return };
        let locks = libc::UF_IMMUTABLE | libc::UF_APPEND;
        let flags = now.st_flags();
        if flags & locks != 0 && unsafe { libc::fchflags(fd, flags & !locks) } == 0 {
            set();
            unsafe { libc::fchflags(fd, flags) };
        }
    }

    /// `fsetattrlist` of common attributes, `values` in their order.
    fn set_attributes(fd: c_int, attributes: libc::attrgroup_t, values: &[libc::timespec]) -> bool {
        let mut list: libc::attrlist = unsafe { std::mem::zeroed() };
        list.bitmapcount = libc::ATTR_BIT_MAP_COUNT;
        list.commonattr = attributes;
        unsafe {
            libc::fsetattrlist(
                fd,
                &mut list as *mut libc::attrlist as *mut c_void,
                values.as_ptr() as *mut c_void,
                std::mem::size_of_val(values),
                0,
            ) == 0
        }
    }

    /// Reads of `file` that go past the page cache, and writes that do not
    /// stay in it.
    pub fn bypass_cache(file: &File) {
        unsafe { libc::fcntl(file.as_raw_fd(), libc::F_NOCACHE, 1) };
    }

    /// Nothing to drop: writes made past the cache did not stay in it.
    pub fn written(_file: &File) {}
}

#[cfg(target_os = "linux")]
mod sys {
    use std::fs::File;
    use std::os::unix::io::AsRawFd;

    /// Reads go to the disk once [`written`] dropped the copy's pages.
    pub fn bypass_cache(_file: &File) {}

    /// The copy written out and dropped from the page cache, so reading it
    /// back reads the disk.
    pub fn written(file: &File) {
        let _ = file.sync_data();
        unsafe { libc::posix_fadvise(file.as_raw_fd(), 0, 0, libc::POSIX_FADV_DONTNEED) };
    }
}

#[cfg(not(any(target_os = "macos", target_os = "linux")))]
mod sys {
    use std::fs::File;

    /// Not on this desktop: the copy is read back as the cache has it.
    pub fn bypass_cache(_file: &File) {}

    pub fn written(_file: &File) {}
}

#[cfg(test)]
mod tests {
    use std::cell::Cell;
    use std::sync::Arc;
    use std::time::{Duration, Instant};

    use super::*;
    use crate::runner::{Journaling, Runner};

    thread_local! {
        /// Whether this test's copies may be clones (see `clones`).
        #[cfg(target_os = "macos")]
        pub(super) static CLONES: Cell<bool> = const { Cell::new(true) };
        /// How many verifications on this thread are still to fail.
        pub(super) static FAULTS: Cell<u32> = const { Cell::new(0) };
    }

    fn set_clones(on: bool) {
        #[cfg(target_os = "macos")]
        CLONES.set(on);
        let _ = on;
    }

    /// The ways a file is copied, as (name, clones allowed, verify): a
    /// clone (macOS), the desktop's copy, the buffer of a verified copy.
    fn ways() -> Vec<(&'static str, bool, bool)> {
        let mut ways = vec![("copied", false, false), ("verified", false, true)];
        if cfg!(target_os = "macos") {
            ways.push(("cloned", true, false));
        }
        ways
    }

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

    const OLD_ACCESS: i64 = 1_000_000_000;
    const OLD_CHANGE: i64 = 1_100_000_000;

    fn make_old(path: &Path) {
        filetime::set_file_times(
            path,
            filetime::FileTime::from_unix_time(OLD_ACCESS, 0),
            filetime::FileTime::from_unix_time(OLD_CHANGE, 0),
        )
        .unwrap();
    }

    fn modified_secs(path: &Path) -> i64 {
        filetime::FileTime::from_last_modification_time(&fs::symlink_metadata(path).unwrap()).unix_seconds()
    }

    #[cfg(target_os = "macos")]
    mod xattr {
        use std::ffi::CString;
        use std::os::unix::ffi::OsStrExt;
        use std::path::Path;

        fn c(path: &Path) -> CString {
            CString::new(path.as_os_str().as_bytes()).unwrap()
        }

        pub fn set(path: &Path, name: &str, value: &[u8]) {
            let name = CString::new(name).unwrap();
            let rc = unsafe {
                libc::setxattr(c(path).as_ptr(), name.as_ptr(), value.as_ptr().cast(), value.len(), 0, 0)
            };
            assert_eq!(rc, 0);
        }

        pub fn get(path: &Path, name: &str) -> Option<Vec<u8>> {
            let name = CString::new(name).unwrap();
            let mut buffer = vec![0u8; 1024];
            let n = unsafe {
                libc::getxattr(
                    c(path).as_ptr(),
                    name.as_ptr(),
                    buffer.as_mut_ptr().cast(),
                    buffer.len(),
                    0,
                    0,
                )
            };
            (n >= 0).then(|| buffer[..n as usize].to_vec())
        }

        pub fn hide(path: &Path) {
            assert_eq!(unsafe { libc::chflags(c(path).as_ptr(), libc::UF_HIDDEN) }, 0);
        }

        pub fn set_created(path: &Path, secs: i64) {
            let mut list: libc::attrlist = unsafe { std::mem::zeroed() };
            list.bitmapcount = libc::ATTR_BIT_MAP_COUNT;
            list.commonattr = libc::ATTR_CMN_CRTIME;
            let time = libc::timespec { tv_sec: secs, tv_nsec: 0 };
            let rc = unsafe {
                libc::setattrlist(
                    c(path).as_ptr(),
                    (&mut list as *mut libc::attrlist).cast(),
                    (&time as *const libc::timespec as *mut libc::timespec).cast(),
                    std::mem::size_of::<libc::timespec>(),
                    0,
                )
            };
            assert_eq!(rc, 0);
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn a_copy_keeps_extended_attributes_tags_flags_and_dates() {
        use std::os::macos::fs::MetadataExt;
        let tag = ferryx_core::entry::Tag { name: "Blue".to_string(), color: 4 };
        // A small file goes through the buffer, a big one through `copyfile`.
        let files = [("f.txt", b"data".to_vec()), ("big.bin", vec![9u8; BUFFER + 1])];
        for (way, clones, verify) in ways() {
            set_clones(clones);
            let dir = tempfile::tempdir().unwrap();
            let src = dir.path().join("src");
            fs::create_dir(&src).unwrap();
            for (name, data) in &files {
                let file = src.join(name);
                fs::write(&file, data).unwrap();
                xattr::set(&file, "user.ferryx", b"kept");
                ferryx_vfs::tags::apply(&file, std::slice::from_ref(&tag), &[]).unwrap();
                xattr::hide(&file);
                make_old(&file);
                // Made after it was last changed (an item unpacked from an
                // archive), which APFS would pull back to that change.
                xattr::set_created(&file, OLD_CHANGE + 100);
            }
            ferryx_vfs::tags::apply(&src, std::slice::from_ref(&tag), &[]).unwrap();
            make_old(&src);
            xattr::set_created(&src, OLD_ACCESS);

            let dest = dir.path().join("dest");
            let mut req = request(OpKind::Copy, vec![src.clone()], &dest);
            req.options.verify = verify;
            run(&OpContext::detached(&req), &req).unwrap();

            for (name, data) in &files {
                // The times first: reading the copy touches its access time.
                let (file, copy) = (src.join(name), dest.join("src").join(name));
                let (a, b) = (fs::symlink_metadata(&file).unwrap(), fs::symlink_metadata(&copy).unwrap());
                assert_eq!((b.st_mtime(), b.st_atime()), (OLD_CHANGE, OLD_ACCESS), "{way} {name}");
                assert_eq!(b.st_birthtime(), OLD_CHANGE + 100, "{way} {name}");
                assert_ne!(b.st_flags() & libc::UF_HIDDEN, 0, "{way} {name}");
                assert_eq!(b.st_mode(), a.st_mode(), "{way} {name}");
                assert_eq!(xattr::get(&copy, "user.ferryx").as_deref(), Some(&b"kept"[..]), "{way} {name}");
                assert_eq!(ferryx_vfs::tags::read(&copy), vec![tag.clone()], "{way} {name}");
                assert_eq!(&fs::read(&copy).unwrap(), data, "{way} {name}");
            }
            let folder = fs::symlink_metadata(dest.join("src")).unwrap();
            assert_eq!((folder.st_mtime(), folder.st_birthtime()), (OLD_CHANGE, OLD_ACCESS), "{way}");
            assert_eq!(ferryx_vfs::tags::read(&dest.join("src")), vec![tag.clone()], "{way}");
        }
    }

    #[test]
    fn without_attributes_a_copy_is_data_only() {
        let files = [("f.txt", b"data".to_vec()), ("big.bin", vec![9u8; BUFFER + 1])];
        for (way, clones, verify) in ways() {
            set_clones(clones);
            let dir = tempfile::tempdir().unwrap();
            let mut sources = Vec::new();
            for (name, data) in &files {
                let file = dir.path().join(name);
                fs::write(&file, data).unwrap();
                #[cfg(target_os = "macos")]
                xattr::set(&file, "user.ferryx", b"dropped");
                make_old(&file);
                sources.push(file);
            }
            let dest = dir.path().join("dest");
            let mut req = request(OpKind::Copy, sources, &dest);
            req.options = OpOptions { preserve_attributes: false, verify, ..Default::default() };
            run(&OpContext::detached(&req), &req).unwrap();
            for (name, data) in &files {
                let copy = dest.join(name);
                assert!(modified_secs(&copy) > OLD_CHANGE, "{way} {name}");
                #[cfg(target_os = "macos")]
                assert_eq!(xattr::get(&copy, "user.ferryx"), None, "{way} {name}");
                assert_eq!(&fs::read(&copy).unwrap(), data, "{way} {name}");
            }
        }
    }

    #[cfg(unix)]
    #[test]
    fn a_sparse_file_stays_sparse() {
        use std::os::unix::fs::{FileExt, MetadataExt};
        const LEN: u64 = 64 << 20;
        for (way, clones, verify) in ways() {
            set_clones(clones);
            let dir = tempfile::tempdir().unwrap();
            let file = dir.path().join("sparse");
            let f = File::create(&file).unwrap();
            f.set_len(LEN).unwrap();
            f.write_at(b"middle", LEN / 2).unwrap();
            drop(f);
            if fs::metadata(&file).unwrap().blocks() * 512 >= LEN {
                return; // This volume keeps no holes.
            }
            let dest = dir.path().join("dest");
            let mut req = request(OpKind::Copy, vec![file.clone()], &dest);
            req.options.verify = verify;
            let ctx = OpContext::detached(&req);
            run(&ctx, &req).unwrap();
            let copy = dest.join("sparse");
            let meta = fs::metadata(&copy).unwrap();
            assert_eq!(meta.len(), LEN, "{way}");
            assert!(meta.blocks() * 512 < LEN / 4, "{way}: {} blocks", meta.blocks());
            assert_eq!(fs::read(&copy).unwrap(), fs::read(&file).unwrap(), "{way}");
            assert_eq!(ctx.snapshot().bytes_done, LEN, "{way}");
        }
    }

    #[test]
    fn bytes_add_up_to_the_size() {
        for (way, clones, verify) in ways() {
            set_clones(clones);
            let dir = tempfile::tempdir().unwrap();
            let file = dir.path().join("f.bin");
            let data: Vec<u8> = (0..(5 << 20) + 123).map(|i| (i % 251) as u8).collect();
            fs::write(&file, &data).unwrap();
            let req = request(OpKind::Copy, vec![file.clone()], &dir.path().join("dest"));
            let mut req = req;
            req.options.verify = verify;
            let ctx = OpContext::detached(&req);
            run(&ctx, &req).unwrap();
            let p = ctx.snapshot();
            assert_eq!((p.bytes_done, p.bytes_total), (data.len() as u64, data.len() as u64), "{way}");
            assert_eq!((p.items_done, p.items_total), (1, 1), "{way}");
            assert_eq!(fs::read(dir.path().join("dest/f.bin")).unwrap(), data, "{way}");
        }
    }

    #[test]
    fn a_cancel_mid_copy_takes_the_part_away() {
        for (way, _, verify) in ways().into_iter().filter(|(_, clones, _)| !clones) {
            let dir = tempfile::tempdir().unwrap();
            let big = dir.path().join("big.bin");
            big_file(&big, 128);
            let dest = dir.path().join("dest");
            let mut req = request(OpKind::Copy, vec![big.clone()], &dest);
            req.options.verify = verify;
            let ctx = Arc::new(OpContext::detached(&req));
            let worker = {
                let (ctx, req) = (ctx.clone(), req.clone());
                std::thread::spawn(move || {
                    set_clones(false);
                    run(&ctx, &req)
                })
            };
            let start = Instant::now();
            while ctx.snapshot().bytes_done == 0 {
                assert!(start.elapsed() < Duration::from_secs(10), "{way}: no bytes");
                std::thread::yield_now();
            }
            ctx.cancel();
            assert_eq!(worker.join().unwrap(), Err(Abort::Cancelled), "{way}");
            assert!(dest.join("big.bin").symlink_metadata().is_err(), "{way}: the part stayed");
            assert_eq!(ctx.snapshot().bytes_done, 0, "{way}");
            assert!(ctx.recorded().is_empty(), "{way}");
        }
    }

    #[test]
    fn a_retried_copy_counts_its_bytes_once() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("f.bin");
        fs::write(&file, vec![7u8; 3 << 20]).unwrap();
        let req = request(OpKind::Copy, vec![file.clone()], &dir.path().join("dest"));
        let runner = Arc::new(Runner::new());
        let asked = Arc::new(std::sync::atomic::AtomicU32::new(0));
        {
            let (weak, asked) = (Arc::downgrade(&runner), asked.clone());
            runner.set_listener(Arc::new(move |p: Progress| {
                if let (OpState::Waiting, Some(question)) = (p.state, p.question) {
                    asked.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                    let weak = weak.clone();
                    std::thread::spawn(move || {
                        if let Some(runner) = weak.upgrade() {
                            runner.answer(p.id, question.id, Answer::Retry);
                        }
                    });
                }
            }));
        }
        let job_request = req.clone();
        let id = runner.start_job(
            req,
            Journaling::Off,
            Box::new(move |ctx| {
                // Verified through the buffer, the first verification fails.
                set_clones(false);
                FAULTS.set(1);
                run(ctx, &job_request)
            }),
        );
        let start = Instant::now();
        let p = loop {
            let p = runner.progress(id).unwrap();
            if p.state.is_finished() {
                break p;
            }
            assert!(start.elapsed() < Duration::from_secs(10), "did not end");
            std::thread::sleep(Duration::from_millis(5));
        };
        assert_eq!(p.state, OpState::Done, "{:?}", p.errors);
        assert_eq!(asked.load(std::sync::atomic::Ordering::SeqCst), 1);
        assert_eq!((p.bytes_done, p.bytes_total), (3 << 20, 3 << 20));
        assert_eq!(fs::read(dir.path().join("dest/f.bin")).unwrap(), vec![7u8; 3 << 20]);
    }

    #[test]
    fn a_name_taken_in_a_new_folder_is_still_asked_about() {
        // Two names one volume folds together meet in a folder the copy
        // made: the second is made exclusively, finds the first and goes
        // through the conflict as ever.
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("a");
        fs::write(&file, b"new").unwrap();
        let dest = dir.path().join("dest");
        fs::create_dir(&dest).unwrap();
        fs::write(dest.join("a"), b"old").unwrap();
        for (policy, kept, written) in [
            (ConflictPolicy::Skip, b"old", None),
            (ConflictPolicy::KeepBoth, b"old", Some(dest.join("a 2"))),
            (ConflictPolicy::Overwrite, b"new", Some(dest.join("a"))),
        ] {
            let mut req = request(OpKind::Copy, vec![file.clone()], &dest);
            req.options.conflicts = policy;
            let ctx = OpContext::detached(&req);
            let got = copy_entry(&ctx, &file, &dest.join("a"), &req.options, true).unwrap();
            assert_eq!(got, written, "{policy:?}");
            assert_eq!(fs::read(dest.join("a")).unwrap(), kept, "{policy:?}");
        }
        assert_eq!(fs::read(dest.join("a 2")).unwrap(), b"new");
    }

    #[test]
    fn a_move_on_one_volume_counts_each_item_once() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("src");
        fs::create_dir_all(src.join("sub")).unwrap();
        fs::write(src.join("sub/a"), b"a").unwrap();
        fs::write(src.join("b"), b"bb").unwrap();
        fs::write(dir.path().join("f"), b"fff").unwrap();
        let dest = dir.path().join("dest");
        let req = request(OpKind::Move, vec![src.clone(), dir.path().join("f")], &dest);
        let ctx = OpContext::detached(&req);
        run(&ctx, &req).unwrap();
        let p = ctx.snapshot();
        assert_eq!((p.items_done, p.items_total), (2, 2));
        assert_eq!((p.bytes_done, p.bytes_total), (0, 0));
        assert_eq!(fs::read(dest.join("src/sub/a")).unwrap(), b"a");
        assert_eq!(fs::read(dest.join("f")).unwrap(), b"fff");
        assert!(!src.exists());
        assert_eq!(
            ctx.recorded(),
            vec![
                Change::Moved { from: src.clone(), to: dest.join("src") },
                Change::Moved { from: dir.path().join("f"), to: dest.join("f") },
            ]
        );
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

    /// A file of `mb` MiB of varied bytes.
    fn big_file(path: &Path, mb: usize) {
        let mut file = File::create(path).unwrap();
        let mut chunk: Vec<u8> = (0..BUFFER).map(|i| (i * 31 % 251) as u8).collect();
        for i in 0..mb {
            chunk[0] = i as u8;
            file.write_all(&chunk).unwrap();
        }
    }

    /// Times copies on this volume: `cargo test --release -p ferryx_ops
    /// copy_bench -- --ignored --nocapture` (`FERRYX_COPY_BENCH_MB` sizes
    /// the big file, 1024 by default).
    #[test]
    #[ignore]
    fn copy_bench() {
        let mb = std::env::var("FERRYX_COPY_BENCH_MB").ok().and_then(|v| v.parse().ok()).unwrap_or(1024);
        let dir = tempfile::tempdir().unwrap();
        let big = dir.path().join("big.bin");
        big_file(&big, mb);
        let time = |label: &str, req: OpRequest| {
            let ctx = OpContext::detached(&req);
            let start = std::time::Instant::now();
            run(&ctx, &req).unwrap();
            println!("{label}: {:?}", start.elapsed());
            assert!(ctx.snapshot().errors.is_empty());
        };
        let options =
            |preserve_attributes, verify| OpOptions { preserve_attributes, verify, ..Default::default() };
        let mut req = request(OpKind::Copy, vec![big.clone()], &dir.path().join("a"));
        req.options = options(true, false);
        time(&format!("{mb} MiB file"), req.clone());
        req.destination = Some(dir.path().join("b"));
        req.options = options(true, true);
        time(&format!("{mb} MiB file, verified"), req.clone());
        req.destination = Some(dir.path().join("c"));
        req.options = options(false, false);
        time(&format!("{mb} MiB file, data only"), req.clone());
        req.destination = Some(dir.path().join("v"));
        req.options = options(false, true);
        time(&format!("{mb} MiB file, data only, verified"), req);

        let tree = dir.path().join("tree");
        for d in 0..100 {
            fs::create_dir_all(tree.join(format!("d{d}"))).unwrap();
            for f in 0..100 {
                fs::write(tree.join(format!("d{d}/f{f}.txt")), [b'x'; 4096]).unwrap();
            }
        }
        let mut req = request(OpKind::Copy, vec![tree.clone()], &dir.path().join("d"));
        req.options = options(true, false);
        time("10 000 files of 4 KiB", req.clone());
        req.destination = Some(dir.path().join("e"));
        req.options = options(false, false);
        time("10 000 files of 4 KiB, data only", req);
    }

    /// Runs `req` through a runner whose listener counts the reports and
    /// the list items they carry; answers the time to the last report.
    fn through_runner(req: OpRequest) -> (std::time::Duration, u64, u64) {
        use std::sync::atomic::{AtomicU64, Ordering};
        use std::sync::Arc;
        let runner = crate::Runner::new();
        let reports = Arc::new(AtomicU64::new(0));
        let listed = Arc::new(AtomicU64::new(0));
        let (tx, rx) = std::sync::mpsc::channel();
        {
            let (reports, listed) = (reports.clone(), listed.clone());
            runner.set_listener(Arc::new(move |p: Progress| {
                reports.fetch_add(1, Ordering::Relaxed);
                listed
                    .fetch_add((p.sources.len() + p.errors.len() + p.sizes.len()) as u64, Ordering::Relaxed);
                if p.state.is_finished() {
                    let _ = tx.send(p.state);
                }
            }));
        }
        let start = std::time::Instant::now();
        runner.start(req);
        let state = rx.recv_timeout(std::time::Duration::from_secs(600)).unwrap();
        let elapsed = start.elapsed();
        assert_eq!(state, OpState::Done);
        (elapsed, reports.load(Ordering::Relaxed), listed.load(Ordering::Relaxed))
    }

    /// Times moves on this volume through a runner, with what its listener
    /// is sent: `cargo test --release -p ferryx_ops move_bench -- --ignored
    /// --nocapture`.
    #[test]
    #[ignore]
    fn move_bench() {
        let dir = tempfile::tempdir().unwrap();
        let flat = dir.path().join("flat");
        fs::create_dir(&flat).unwrap();
        let sources: Vec<PathBuf> = (0..10_000).map(|i| flat.join(format!("f{i}"))).collect();
        for source in &sources {
            fs::write(source, b"x").unwrap();
        }
        let (took, reports, listed) =
            through_runner(request(OpKind::Move, sources, &dir.path().join("flat moved")));
        println!("10 000 files as 10 000 sources: {took:?}, {reports} reports carrying {listed} list items");

        let tree = dir.path().join("tree");
        for d in 0..100 {
            fs::create_dir_all(tree.join(format!("d{d}"))).unwrap();
            for f in 0..500 {
                fs::write(tree.join(format!("d{d}/f{f}")), b"x").unwrap();
            }
        }
        let (took, reports, listed) =
            through_runner(request(OpKind::Move, vec![tree], &dir.path().join("tree moved")));
        println!("a folder of 50 000 files: {took:?}, {reports} reports carrying {listed} list items");
    }
}
