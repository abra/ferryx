//! Copy, move, delete and folder sizes where a server is on one side or
//! both: a folder on disk and a server, two servers, or one server with
//! itself. Every byte goes through a stream (a buffer of a few hundred
//! kilobytes, never a whole file), with the operation's progress, pause,
//! cancel and questions as on disk: a conflict asks (overwrite, older,
//! skip, keep both, merge folders) or follows the policy; an error asks to
//! try again (on a new connection when the old one dropped), skip or stop.
//!
//! On one server a move is a rename there, and WebDAV copies on the server
//! itself; across sides a move copies each file and then removes it, so a
//! file skipped stays where it was. Modification times go along where the
//! receiving side can set them (a folder on disk, SFTP, FTP with `MFMT`).
//! A link to a file is copied as the file; a link to a folder is not
//! followed (it is reported, never looped through).
//!
//! Nothing here goes on the undo journal: a server has no trash to bring
//! an item back from, and what is replaced there is gone.

use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use ferryx_core::entry::{split_name, Entry, EntryKind};
use ferryx_vfs::error::{IoAt, VfsError, VfsErrorKind, VfsResult};
use ferryx_vfs::remote::{self, RemoteRead, RemoteWrite, Server, Stop};

use crate::runner::OpContext;
use crate::types::*;

/// Bytes one read or write moves.
const BUFFER: usize = 256 * 1024;

/// Folders a walk goes into at most.
const MAX_DEPTH: usize = 128;

/// What an item is, as far as copying it goes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Meta {
    pub is_dir: bool,
    /// A symbolic link (`is_dir`: to a folder).
    pub is_link: bool,
    pub size: u64,
    pub modified_ms: Option<i64>,
}

impl Meta {
    fn of(entry: &Entry) -> Meta {
        let is_link = entry.kind == EntryKind::Symlink;
        Meta {
            is_dir: entry.is_dir,
            is_link,
            size: if entry.is_dir { 0 } else { entry.size.unwrap_or(0) },
            modified_ms: entry.modified_ms,
        }
    }
}

/// One side of a transfer: the disk, or a server.
#[derive(Clone)]
pub enum Side {
    Native,
    Remote(Arc<Server>),
}

impl Side {
    /// Whether `self` and `other` are one place (a move there is a
    /// rename).
    pub fn same_as(&self, other: &Side) -> bool {
        match (self, other) {
            (Side::Native, Side::Native) => true,
            (Side::Remote(a), Side::Remote(b)) => a.key() == b.key(),
            _ => false,
        }
    }

    /// `path` as the progress and the errors name it: a path on disk, or
    /// the server's key with the path (`sftp://me@host:22/srv/a`), so the
    /// interface tells one from the other.
    pub fn display(&self, path: &str) -> String {
        match self {
            Side::Native => path.to_string(),
            Side::Remote(server) => format!("{}{}", server.key(), path),
        }
    }

    pub fn join(&self, dir: &str, name: &str) -> String {
        match self {
            Side::Native => Path::new(dir).join(name).to_string_lossy().into_owned(),
            Side::Remote(_) => remote::address::join(dir, name),
        }
    }

    fn name_of(&self, path: &str) -> String {
        match self {
            Side::Native => Path::new(path)
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| path.to_string()),
            Side::Remote(_) => remote::address::name(path).to_string(),
        }
    }

    fn can_set_modified(&self) -> bool {
        match self {
            Side::Native => true,
            Side::Remote(server) => server.fs().caps().set_modified,
        }
    }

    fn stat(&self, path: &str, stop: Stop) -> VfsResult<Option<Meta>> {
        match self {
            Side::Native => match fs::symlink_metadata(path) {
                Ok(meta) => Ok(Some(native_meta(Path::new(path), &meta))),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
                Err(e) => Err(VfsError::io(&e, Path::new(path))),
            },
            Side::Remote(server) => Ok(server.fs().stat(path, stop)?.as_ref().map(Meta::of)),
        }
    }

    fn list(&self, dir: &str, stop: Stop) -> VfsResult<Vec<(String, Meta)>> {
        match self {
            Side::Native => {
                let mut out = Vec::new();
                for item in fs::read_dir(dir).at(Path::new(dir))? {
                    let item = item.at(Path::new(dir))?;
                    let path = item.path();
                    let Ok(meta) = fs::symlink_metadata(&path) else { continue };
                    out.push((item.file_name().to_string_lossy().into_owned(), native_meta(&path, &meta)));
                }
                Ok(out)
            }
            Side::Remote(server) => {
                Ok(server.fs().list(dir, stop)?.iter().map(|e| (e.name.clone(), Meta::of(e))).collect())
            }
        }
    }

    fn open_read<'a>(&'a self, path: &str, stop: Stop) -> VfsResult<Box<dyn RemoteRead + 'a>> {
        match self {
            Side::Native => {
                Ok(Box::new(NativeRead(File::open(path).at(Path::new(path))?, PathBuf::from(path))))
            }
            Side::Remote(server) => server.fs().open_read(path, stop),
        }
    }

    fn create<'a>(&'a self, path: &str, size: u64, stop: Stop) -> VfsResult<Box<dyn RemoteWrite + 'a>> {
        match self {
            Side::Native => {
                Ok(Box::new(NativeWrite(File::create(path).at(Path::new(path))?, PathBuf::from(path))))
            }
            Side::Remote(server) => server.fs().create(path, Some(size), stop),
        }
    }

    fn mkdir(&self, path: &str, stop: Stop) -> VfsResult<()> {
        match self {
            Side::Native => fs::create_dir(path).at(Path::new(path)),
            Side::Remote(server) => server.fs().mkdir(path, stop),
        }
    }

    fn remove_file(&self, path: &str, stop: Stop) -> VfsResult<()> {
        match self {
            Side::Native => fs::remove_file(path).at(Path::new(path)),
            Side::Remote(server) => server.fs().remove_file(path, stop),
        }
    }

    fn remove_dir(&self, path: &str, stop: Stop) -> VfsResult<()> {
        match self {
            Side::Native => fs::remove_dir(path).at(Path::new(path)),
            Side::Remote(server) => server.fs().remove_dir(path, stop),
        }
    }

    fn rename(&self, from: &str, to: &str, stop: Stop) -> VfsResult<()> {
        match self {
            Side::Native => {
                if Path::new(to).symlink_metadata().is_ok() {
                    return Err(VfsError::new(
                        VfsErrorKind::AlreadyExists,
                        Some(Path::new(to)),
                        format!("{to} already exists"),
                    ));
                }
                fs::rename(from, to).at(Path::new(from))
            }
            Side::Remote(server) => server.fs().rename(from, to, stop),
        }
    }

    fn set_modified(&self, path: &str, modified_ms: i64, stop: Stop) -> VfsResult<()> {
        match self {
            Side::Native => {
                let time = filetime::FileTime::from_unix_time(
                    modified_ms.div_euclid(1000),
                    (modified_ms.rem_euclid(1000) * 1_000_000) as u32,
                );
                filetime::set_file_mtime(path, time).at(Path::new(path))
            }
            Side::Remote(server) => server.fs().set_modified(path, modified_ms, stop),
        }
    }

    /// A copy made on the server itself, when it can.
    fn server_copy(&self, from: &str, to: &str, stop: Stop) -> Option<VfsResult<()>> {
        match self {
            Side::Remote(server) if server.fs().caps().server_copy => Some(server.fs().copy(from, to, stop)),
            _ => None,
        }
    }

    fn recursive_delete(&self) -> bool {
        matches!(self, Side::Remote(server) if server.fs().caps().recursive_delete)
    }
}

fn native_meta(path: &Path, meta: &fs::Metadata) -> Meta {
    let is_link = meta.file_type().is_symlink();
    let target = if is_link { fs::metadata(path).ok() } else { None };
    let is_dir = if is_link { target.as_ref().is_some_and(fs::Metadata::is_dir) } else { meta.is_dir() };
    let size = if is_dir { 0 } else { target.as_ref().map(fs::Metadata::len).unwrap_or(meta.len()) };
    Meta {
        is_dir,
        is_link,
        size,
        modified_ms: target
            .as_ref()
            .unwrap_or(meta)
            .modified()
            .ok()
            .and_then(ferryx_vfs::native::system_time_ms),
    }
}

struct NativeRead(File, PathBuf);

impl RemoteRead for NativeRead {
    fn read(&mut self, buf: &mut [u8], _stop: Stop) -> VfsResult<usize> {
        loop {
            match self.0.read(buf) {
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                other => return other.at(&self.1),
            }
        }
    }
}

struct NativeWrite(File, PathBuf);

impl RemoteWrite for NativeWrite {
    fn write_all(&mut self, data: &[u8], _stop: Stop) -> VfsResult<()> {
        self.0.write_all(data).at(&self.1)
    }

    fn finish(mut self: Box<Self>, _stop: Stop) -> VfsResult<()> {
        self.0.flush().at(&self.1)
    }
}

/// What to do: [`OpKind::Copy`], [`OpKind::Move`], [`OpKind::Delete`] or
/// [`OpKind::CalcSizes`] of `sources` on `from`, into the folder `to`.
#[derive(Clone)]
pub struct Transfer {
    pub kind: OpKind,
    pub from: Side,
    pub sources: Vec<String>,
    pub to: Option<(Side, String)>,
    /// Copy As / Move As with one source: the name it takes.
    pub new_name: Option<String>,
    pub options: OpOptions,
}

impl Transfer {
    /// The request the operation's card shows: the kind, the sources and
    /// the destination as [`Side::display`] names them.
    pub fn shown_as(&self) -> OpRequest {
        OpRequest {
            kind: self.kind,
            sources: self.sources.iter().map(|s| PathBuf::from(self.from.display(s))).collect(),
            archive: None,
            destination: self.to.as_ref().map(|(side, dir)| PathBuf::from(side.display(dir))),
            new_name: self.new_name.clone(),
            options: self.options.clone(),
        }
    }
}

/// Runs `transfer` as the operation `ctx`.
pub fn run(ctx: &OpContext, transfer: &Transfer) -> Result<(), Abort> {
    let mut work = Work { ctx, transfer, tree: HashMap::new(), there: HashMap::new() };
    match transfer.kind {
        OpKind::Delete => work.delete(),
        OpKind::CalcSizes => work.sizes(),
        OpKind::Move | OpKind::Copy => work.copy_or_move(transfer.kind == OpKind::Move),
        other => {
            ctx.record_error(Path::new(""), format!("{other:?} does not reach a server"));
            Err(Abort::Stopped)
        }
    }
}

struct Work<'a> {
    ctx: &'a OpContext,
    transfer: &'a Transfer,
    /// The source side's folders as the scan read them.
    tree: HashMap<String, Vec<(String, Meta)>>,
    /// The destination's folders as seen (and changed) so far, by name.
    there: HashMap<String, HashMap<String, Meta>>,
}

/// How one item went.
struct Outcome {
    /// Where it went (another name when both are kept), if anywhere.
    written: Option<String>,
    /// Everything in it went: a move may take it from its side.
    complete: bool,
}

impl Outcome {
    fn skipped() -> Outcome {
        Outcome { written: None, complete: false }
    }
}

impl<'a> Work<'a> {
    fn stop(&self) -> impl Fn() -> bool + Sync + 'a {
        let ctx: &'a OpContext = self.ctx;
        move || ctx.is_cancelled()
    }

    fn report_path(&self, side: &Side, path: &str) -> PathBuf {
        PathBuf::from(side.display(path))
    }

    /// Asks about `error` at `path` on `side`: `Ok(true)` to try again.
    fn ask(&self, side: &Side, path: &str, error: &VfsError) -> Result<bool, Abort> {
        if error.kind == VfsErrorKind::Cancelled && self.ctx.is_cancelled() {
            return Err(Abort::Cancelled);
        }
        self.ctx.ask_error(&self.report_path(side, path), error)
    }

    // ─── Scanning ───

    /// Counts what is under the sources (reading each folder once: the
    /// copy uses what the scan read); answers each source's kind, `None`
    /// for one gone.
    fn scan(&mut self) -> Result<Vec<Option<Meta>>, Abort> {
        let from = &self.transfer.from;
        let mut bytes = 0u64;
        let mut items = 0u64;
        let mut kinds = Vec::new();
        for source in &self.transfer.sources {
            self.ctx.check()?;
            let meta = loop {
                let stop = self.stop();
                match from.stat(source, &stop) {
                    Ok(meta) => break meta,
                    Err(e) => {
                        if !self.ask(from, source, &e)? {
                            break None;
                        }
                    }
                }
            };
            if let Some(meta) = &meta {
                items += 1;
                bytes += meta.size;
                if meta.is_dir && !meta.is_link {
                    let (b, i) = self.walk(source, 0)?;
                    bytes += b;
                    items += i;
                }
            } else {
                self.ctx.record_error(
                    &self.report_path(from, source),
                    format!("{} is not there", from.display(source)),
                );
            }
            kinds.push(meta);
        }
        self.ctx.set_totals(bytes, items);
        Ok(kinds)
    }

    fn walk(&mut self, dir: &str, depth: usize) -> Result<(u64, u64), Abort> {
        self.ctx.check()?;
        let from = self.transfer.from.clone();
        self.ctx.set_current(&self.report_path(&from, dir));
        if depth > MAX_DEPTH {
            return Ok((0, 0));
        }
        let rows = loop {
            let stop = self.stop();
            match from.list(dir, &stop) {
                Ok(rows) => break rows,
                Err(e) => {
                    if !self.ask(&from, dir, &e)? {
                        break Vec::new();
                    }
                }
            }
        };
        let (mut bytes, mut items) = (0u64, 0u64);
        for (name, meta) in &rows {
            items += 1;
            bytes += meta.size;
            if meta.is_dir && !meta.is_link {
                let (b, i) = self.walk(&from.join(dir, name), depth + 1)?;
                bytes += b;
                items += i;
            }
        }
        self.tree.insert(dir.to_string(), rows);
        Ok((bytes, items))
    }

    fn children(&self, dir: &str) -> Vec<(String, Meta)> {
        self.tree.get(dir).cloned().unwrap_or_default()
    }

    // ─── The destination ───

    /// What is in `dir` on the destination, read once.
    fn there(&mut self, to: &Side, dir: &str) -> Result<&mut HashMap<String, Meta>, Abort> {
        if !self.there.contains_key(dir) {
            let rows = loop {
                let stop = self.stop();
                match to.list(dir, &stop) {
                    Ok(rows) => break rows,
                    Err(e) if e.kind == VfsErrorKind::NotFound => break Vec::new(),
                    Err(e) => {
                        if !self.ask(to, dir, &e)? {
                            break Vec::new();
                        }
                    }
                }
            };
            self.there.insert(dir.to_string(), rows.into_iter().collect());
        }
        Ok(self.there.get_mut(dir).expect("just put there"))
    }

    /// `name 2.ext`, `name 3.ext`… the first free in `dir`.
    fn free_name(&mut self, to: &Side, dir: &str, name: &str) -> Result<String, Abort> {
        let taken = self.there(to, dir)?;
        let (stem, ext) = split_name(name);
        for n in 2.. {
            let candidate = if ext.is_empty() { format!("{stem} {n}") } else { format!("{stem} {n}.{ext}") };
            if !taken.contains_key(&candidate) {
                return Ok(candidate);
            }
        }
        unreachable!()
    }

    // ─── Copy and move ───

    fn copy_or_move(&mut self, moving: bool) -> Result<(), Abort> {
        let Some((to, dest)) = self.transfer.to.clone() else {
            self.ctx.record_error(Path::new(""), "no destination".to_string());
            return Err(Abort::Stopped);
        };
        let from = self.transfer.from.clone();
        // A folder into itself would never end.
        if from.same_as(&to) {
            for source in &self.transfer.sources {
                let inside =
                    dest == *source || dest.starts_with(&format!("{}/", source.trim_end_matches('/')));
                if inside {
                    let shown = from.display(source);
                    self.ctx.record_error(
                        &self.report_path(&from, source),
                        format!("cannot copy {shown} into itself"),
                    );
                    return Err(Abort::Stopped);
                }
            }
        }
        let kinds = self.scan()?;
        let single = self.transfer.sources.len() == 1;
        let mut last = None;
        for (source, meta) in self.transfer.sources.clone().iter().zip(kinds) {
            self.ctx.check()?;
            let Some(meta) = meta else { continue };
            let name = match (&self.transfer.new_name, single) {
                (Some(name), true) if !name.is_empty() => name.clone(),
                _ => from.name_of(source),
            };
            let outcome = if moving && from.same_as(&to) {
                self.rename_item(&from, source, &meta, &dest, &name)?
            } else {
                self.copy_item(&from, source, &meta, &to, &dest, &name, moving, 0)?
            };
            if outcome.written.is_some() {
                last = outcome.written.map(|w| to.display(&w));
            }
        }
        if single {
            self.ctx.update(|p| p.result_path = last.map(PathBuf::from));
        }
        Ok(())
    }

    /// Copies (or, `moving`, moves) the item at `source` on `from` into
    /// the folder `dir` on `to` as `name`.
    #[allow(clippy::too_many_arguments)]
    fn copy_item(
        &mut self,
        from: &Side,
        source: &str,
        meta: &Meta,
        to: &Side,
        dir: &str,
        name: &str,
        moving: bool,
        depth: usize,
    ) -> Result<Outcome, Abort> {
        if moving && from.same_as(to) {
            return self.rename_item(from, source, meta, dir, name);
        }
        self.ctx.check()?;
        self.ctx.set_current(&self.report_path(from, source));
        if meta.is_dir && meta.is_link {
            // Followed, a link to a folder could lead round for ever.
            self.ctx.record_error(
                &self.report_path(from, source),
                format!("{} is a link to a folder: not copied", from.display(source)),
            );
            self.ctx.item_done();
            return Ok(Outcome::skipped());
        }
        let existing = self.there(to, dir)?.get(name).cloned();
        if meta.is_dir {
            return self.copy_dir(from, source, meta, to, dir, name, existing, moving, depth);
        }
        let Some(name) = self.resolve_file_conflict(from, source, meta, to, dir, name, existing)? else {
            self.ctx.add_bytes(meta.size);
            self.ctx.item_done();
            return Ok(Outcome::skipped());
        };
        let target = to.join(dir, &name);
        // On one server, a copy made there.
        if !moving && from.same_as(to) {
            let stop = self.stop();
            if let Some(result) = from.server_copy(source, &target, &stop) {
                match result {
                    Ok(()) => {
                        self.ctx.add_bytes(meta.size);
                        self.landed(dir, &name, meta);
                        self.ctx.item_done();
                        return Ok(Outcome { written: Some(target), complete: true });
                    }
                    Err(e) if e.kind == VfsErrorKind::Unsupported => {}
                    Err(e) => {
                        self.ctx.record_error(&self.report_path(from, source), e.message);
                        self.ctx.item_done();
                        return Ok(Outcome::skipped());
                    }
                }
            }
        }
        loop {
            match self.stream(from, source, meta, to, &target) {
                Ok(()) => break,
                Err(Failure::Abort(abort)) => return Err(abort),
                Err(Failure::Error(e, side, at)) => {
                    let side = if side { to } else { from };
                    if !self.ask(side, &at, &e)? {
                        // Skipped: its bytes still count as handled.
                        self.ctx.add_bytes(meta.size);
                        self.ctx.item_done();
                        return Ok(Outcome::skipped());
                    }
                }
            }
        }
        if self.transfer.options.preserve_attributes && to.can_set_modified() {
            if let Some(ms) = meta.modified_ms {
                let stop = self.stop();
                // A time not kept is no reason to stop.
                let _ = to.set_modified(&target, ms, &stop);
            }
        }
        self.landed(dir, &name, meta);
        if moving {
            loop {
                let stop = self.stop();
                match from.remove_file(source, &stop) {
                    Ok(()) => break,
                    Err(e) => {
                        if !self.ask(from, source, &e)? {
                            self.ctx.item_done();
                            return Ok(Outcome { written: Some(target), complete: false });
                        }
                    }
                }
            }
        }
        self.ctx.item_done();
        Ok(Outcome { written: Some(target), complete: true })
    }

    /// A folder: made (or merged into one there), then its items.
    #[allow(clippy::too_many_arguments)]
    fn copy_dir(
        &mut self,
        from: &Side,
        source: &str,
        meta: &Meta,
        to: &Side,
        dir: &str,
        name: &str,
        existing: Option<Meta>,
        moving: bool,
        depth: usize,
    ) -> Result<Outcome, Abort> {
        let name = match existing {
            None => name.to_string(),
            Some(there) if there.is_dir => {
                match self.dir_decision(from, source, meta, to, dir, name, &there)? {
                    Answer::Skip | Answer::SkipAll => {
                        self.ctx.item_done();
                        return Ok(Outcome::skipped());
                    }
                    Answer::KeepBoth | Answer::KeepBothAll => self.free_name(to, dir, name)?,
                    Answer::Abort => return Err(Abort::Stopped),
                    _ => name.to_string(),
                }
            }
            Some(_) => {
                self.ctx.record_error(
                    &self.report_path(to, &to.join(dir, name)),
                    format!(
                        "{} is a file: the folder is not copied over it",
                        to.display(&to.join(dir, name))
                    ),
                );
                self.ctx.item_done();
                return Ok(Outcome::skipped());
            }
        };
        let merging = self.there(to, dir)?.get(&name).is_some_and(|m| m.is_dir);
        self.fill_dir(from, source, meta, to, dir, &name, merging, moving, depth)
    }

    /// What to do with a folder whose name is taken by a folder there:
    /// merge (the policy's default), keep both, skip.
    #[allow(clippy::too_many_arguments)]
    fn dir_decision(
        &mut self,
        from: &Side,
        source: &str,
        meta: &Meta,
        to: &Side,
        dir: &str,
        name: &str,
        there: &Meta,
    ) -> Result<Answer, Abort> {
        Ok(match self.transfer.options.conflicts {
            ConflictPolicy::Skip => Answer::Skip,
            ConflictPolicy::KeepBoth => Answer::KeepBoth,
            ConflictPolicy::Ask => self.ctx.ask_conflict(
                ConflictSide {
                    path: from.display(source),
                    size: None,
                    modified_ms: meta.modified_ms,
                    is_dir: true,
                },
                ConflictSide {
                    path: to.display(&to.join(dir, name)),
                    size: None,
                    modified_ms: there.modified_ms,
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
        })
    }

    /// Makes the folder `name` in `dir` (unless `merging` into the one
    /// there), puts the source's items in it, and for a move takes the
    /// source away once all of it went.
    #[allow(clippy::too_many_arguments)]
    fn fill_dir(
        &mut self,
        from: &Side,
        source: &str,
        meta: &Meta,
        to: &Side,
        dir: &str,
        name: &str,
        merging: bool,
        moving: bool,
        depth: usize,
    ) -> Result<Outcome, Abort> {
        let name = name.to_string();
        let target = to.join(dir, &name);
        if !merging {
            loop {
                let stop = self.stop();
                match to.mkdir(&target, &stop) {
                    Ok(()) => break,
                    Err(e) if e.kind == VfsErrorKind::AlreadyExists => break,
                    Err(e) => {
                        if !self.ask(to, &target, &e)? {
                            self.ctx.item_done();
                            return Ok(Outcome::skipped());
                        }
                    }
                }
            }
            self.landed(dir, &name, meta);
            // A folder just made holds nothing: no need to read it.
            self.there.insert(target.clone(), HashMap::new());
        }
        let mut complete = true;
        if depth < MAX_DEPTH {
            for (child, child_meta) in self.children(source) {
                let child_path = from.join(source, &child);
                let outcome =
                    self.copy_item(from, &child_path, &child_meta, to, &target, &child, moving, depth + 1)?;
                complete &= outcome.complete;
            }
        }
        if moving && complete {
            let stop = self.stop();
            if let Err(e) = from.remove_dir(source, &stop) {
                self.ctx.record_error(&self.report_path(from, source), e.message);
                complete = false;
            }
        }
        self.ctx.item_done();
        Ok(Outcome { written: Some(target), complete })
    }

    /// Where a file goes when its name is taken there: the same name
    /// (replaced), a free one (both kept), or none (skipped).
    #[allow(clippy::too_many_arguments)]
    fn resolve_file_conflict(
        &mut self,
        from: &Side,
        source: &str,
        meta: &Meta,
        to: &Side,
        dir: &str,
        name: &str,
        existing: Option<Meta>,
    ) -> Result<Option<String>, Abort> {
        let Some(there) = existing else { return Ok(Some(name.to_string())) };
        let target = to.join(dir, name);
        if there.is_dir {
            self.ctx.record_error(
                &self.report_path(to, &target),
                format!("{} is a folder: the file is not copied over it", to.display(&target)),
            );
            return Ok(None);
        }
        let decision = match self.transfer.options.conflicts {
            ConflictPolicy::Overwrite => Answer::Overwrite,
            ConflictPolicy::OverwriteOlder => Answer::OverwriteOlderAll,
            ConflictPolicy::Skip => Answer::Skip,
            ConflictPolicy::KeepBoth => Answer::KeepBoth,
            ConflictPolicy::Ask => self.ctx.ask_conflict(
                ConflictSide {
                    path: from.display(source),
                    size: Some(meta.size),
                    modified_ms: meta.modified_ms,
                    is_dir: false,
                },
                ConflictSide {
                    path: to.display(&target),
                    size: Some(there.size),
                    modified_ms: there.modified_ms,
                    is_dir: false,
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
        Ok(match decision {
            Answer::Overwrite | Answer::OverwriteAll => Some(name.to_string()),
            Answer::OverwriteOlderAll => match (meta.modified_ms, there.modified_ms) {
                (Some(new), Some(old)) if new > old => Some(name.to_string()),
                _ => None,
            },
            Answer::KeepBoth | Answer::KeepBothAll => Some(self.free_name(to, dir, name)?),
            Answer::Abort => return Err(Abort::Stopped),
            _ => None,
        })
    }

    /// The item `name` is in `dir` on `to` now.
    fn landed(&mut self, dir: &str, name: &str, meta: &Meta) {
        if let Some(names) = self.there.get_mut(dir) {
            names.insert(name.to_string(), meta.clone());
        }
    }

    /// The file's bytes from `source` to `target`; what a failed attempt
    /// counted is taken back, and what it left behind removed.
    fn stream(&self, from: &Side, source: &str, meta: &Meta, to: &Side, target: &str) -> Result<(), Failure> {
        let stop = self.stop();
        let mut moved = 0u64;
        let result = (|| -> Result<(), Failure> {
            let mut reader =
                from.open_read(source, &stop).map_err(|e| Failure::Error(e, false, source.to_string()))?;
            let mut writer = to
                .create(target, meta.size, &stop)
                .map_err(|e| Failure::Error(e, true, target.to_string()))?;
            let mut buffer = vec![0u8; BUFFER];
            loop {
                self.ctx.check().map_err(Failure::Abort)?;
                let n = reader
                    .read(&mut buffer, &stop)
                    .map_err(|e| Failure::Error(e, false, source.to_string()))?;
                if n == 0 {
                    break;
                }
                writer
                    .write_all(&buffer[..n], &stop)
                    .map_err(|e| Failure::Error(e, true, target.to_string()))?;
                moved += n as u64;
                self.ctx.add_bytes(n as u64);
            }
            drop(reader);
            writer.finish(&stop).map_err(|e| Failure::Error(e, true, target.to_string()))
        })();
        if let Err(failure) = &result {
            self.ctx.update(|p| p.bytes_done = p.bytes_done.saturating_sub(moved));
            let cancelled = matches!(failure, Failure::Abort(_))
                || matches!(failure, Failure::Error(e, _, _) if e.kind == VfsErrorKind::Cancelled);
            // What a broken transfer left there is no copy of anything.
            let _ = to.remove_file(target, &remote::never);
            if cancelled && self.ctx.is_cancelled() {
                return Err(Failure::Abort(Abort::Cancelled));
            }
        }
        result
    }

    /// A move on one side: a rename, a folder merged into one there item
    /// by item.
    fn rename_item(
        &mut self,
        side: &Side,
        source: &str,
        meta: &Meta,
        dir: &str,
        name: &str,
    ) -> Result<Outcome, Abort> {
        self.ctx.check()?;
        self.ctx.set_current(&self.report_path(side, source));
        let target = side.join(dir, name);
        if target == source {
            return Ok(Outcome::skipped());
        }
        let existing = self.there(side, dir)?.get(name).cloned();
        let name = match existing {
            None => name.to_string(),
            Some(there) if there.is_dir && meta.is_dir && !meta.is_link => {
                match self.dir_decision(side, source, meta, side, dir, name, &there)? {
                    // Onto a folder: merged, the folder's items renamed in.
                    Answer::Merge | Answer::MergeAll => {
                        return self.fill_dir(side, source, meta, side, dir, name, true, true, 0);
                    }
                    Answer::KeepBoth | Answer::KeepBothAll => self.free_name(side, dir, name)?,
                    Answer::Abort => return Err(Abort::Stopped),
                    _ => {
                        let (bytes, items) = self.counted(source, meta);
                        self.ctx.add_bytes(bytes);
                        self.ctx.update(|p| p.items_done += items);
                        return Ok(Outcome::skipped());
                    }
                }
            }
            Some(there) => {
                let resolved =
                    self.resolve_file_conflict(side, source, meta, side, dir, name, Some(there.clone()))?;
                let Some(resolved) = resolved else {
                    self.ctx.item_done();
                    return Ok(Outcome::skipped());
                };
                if resolved == name {
                    // Replacing it: the old one goes first.
                    let stop = self.stop();
                    let gone = if there.is_dir {
                        side.remove_dir(&target, &stop)
                    } else {
                        side.remove_file(&target, &stop)
                    };
                    if let Err(e) = gone {
                        self.ctx.record_error(&self.report_path(side, &target), e.message);
                        self.ctx.item_done();
                        return Ok(Outcome::skipped());
                    }
                }
                resolved
            }
        };
        let target = side.join(dir, &name);
        loop {
            let stop = self.stop();
            match side.rename(source, &target, &stop) {
                Ok(()) => break,
                Err(e) => {
                    if !self.ask(side, source, &e)? {
                        self.ctx.item_done();
                        return Ok(Outcome::skipped());
                    }
                }
            }
        }
        self.landed(dir, &name, meta);
        // The whole tree moved at once.
        let (bytes, items) = self.counted(source, meta);
        self.ctx.add_bytes(bytes);
        self.ctx.update(|p| p.items_done += items);
        Ok(Outcome { written: Some(target), complete: true })
    }

    /// Bytes and items the scan counted at and under `path`.
    fn counted(&self, path: &str, meta: &Meta) -> (u64, u64) {
        let mut bytes = meta.size;
        let mut items = 1;
        if meta.is_dir {
            for (name, child) in self.tree.get(path).into_iter().flatten() {
                let (b, i) = self.counted(&self.transfer.from.join(path, name), child);
                bytes += b;
                items += i;
            }
        }
        (bytes, items)
    }

    // ─── Delete ───

    fn delete(&mut self) -> Result<(), Abort> {
        let from = self.transfer.from.clone();
        let whole = from.recursive_delete();
        let kinds = if whole {
            // The server removes a folder with what it holds: no walk.
            let kinds: Vec<Option<Meta>> = self
                .transfer
                .sources
                .iter()
                .map(|s| {
                    let stop = self.stop();
                    from.stat(s, &stop).ok().flatten()
                })
                .collect();
            self.ctx.set_totals(0, kinds.len() as u64);
            kinds
        } else {
            self.scan()?
        };
        for (source, meta) in self.transfer.sources.clone().iter().zip(kinds) {
            self.ctx.check()?;
            let Some(meta) = meta else { continue };
            self.delete_item(&from, source, &meta, whole, 0)?;
        }
        Ok(())
    }

    fn delete_item(
        &mut self,
        side: &Side,
        path: &str,
        meta: &Meta,
        whole: bool,
        depth: usize,
    ) -> Result<(), Abort> {
        self.ctx.check()?;
        self.ctx.set_current(&self.report_path(side, path));
        if meta.is_dir && !meta.is_link && !whole && depth < MAX_DEPTH {
            for (child, child_meta) in self.children(path) {
                self.delete_item(side, &side.join(path, &child), &child_meta, whole, depth + 1)?;
            }
        }
        loop {
            let stop = self.stop();
            let result = if meta.is_dir && !meta.is_link {
                side.remove_dir(path, &stop)
            } else {
                side.remove_file(path, &stop)
            };
            match result {
                Ok(()) => break,
                Err(e) => {
                    if !self.ask(side, path, &e)? {
                        break;
                    }
                }
            }
        }
        self.ctx.item_done();
        Ok(())
    }

    // ─── Sizes ───

    fn sizes(&mut self) -> Result<(), Abort> {
        self.ctx.set_totals(0, self.transfer.sources.len() as u64);
        for source in self.transfer.sources.clone() {
            self.ctx.check()?;
            let (bytes, _) = self.walk(&source, 0)?;
            let shown = PathBuf::from(&source);
            self.ctx.update(|p| {
                p.sizes.push(FolderSize { path: shown, bytes });
                p.items_done += 1;
            });
        }
        Ok(())
    }
}

enum Failure {
    /// An error, on the destination side (`true`) or the source's, at the
    /// path given.
    Error(VfsError, bool, String),
    Abort(Abort),
}
