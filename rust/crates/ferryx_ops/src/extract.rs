//! Extract: members of an archive written out to a folder (F5 inside an
//! archive), or whole archives each into the destination or into a folder
//! named after it (Extract To). The members stream through
//! [`ArchiveIndex::extract_members`]: a tar is read once, a 7z block
//! decoded once, and no member is held in memory whole.

use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use ferryx_vfs::archive::{self, shared, ArchiveIndex, ExtractError, Member, MemberSink, Stop};
use ferryx_vfs::error::{VfsError, VfsErrorKind, VfsResult};

use crate::copy::{resolve_conflict, set_mode, set_times};
use crate::runner::OpContext;
use crate::types::*;

/// One archive's part of the operation: the members to write (empty for
/// the whole archive) and the folder their paths start from.
struct Job {
    archive: PathBuf,
    inners: Vec<String>,
    base: PathBuf,
}

pub fn run(ctx: &OpContext, request: &OpRequest) -> Result<(), Abort> {
    let Some(dest_dir) = request.destination.as_deref() else {
        ctx.record_error(Path::new(""), "no destination".to_string());
        return Err(Abort::Stopped);
    };
    let jobs: Vec<Job> = match &request.archive {
        Some(archive) => vec![Job {
            archive: archive.clone(),
            inners: request
                .sources
                .iter()
                .map(|s| s.to_string_lossy().replace('\\', "/").trim_matches('/').to_string())
                .collect(),
            base: dest_dir.to_path_buf(),
        }],
        None => request
            .sources
            .iter()
            .map(|archive| Job {
                archive: archive.clone(),
                inners: vec![String::new()],
                base: if request.options.into_folders {
                    dest_dir.join(archive::archive_stem(archive))
                } else {
                    dest_dir.to_path_buf()
                },
            })
            .collect(),
    };
    // Every index first, for the totals; an archive that will not open is
    // asked about and passed by.
    let mut ready: Vec<(Job, Opened)> = Vec::new();
    for job in jobs {
        ctx.check()?;
        ctx.set_current(&job.archive);
        if let Some(opened) = open(ctx, &job.archive, request.options.password.as_deref())? {
            ready.push((job, opened));
        }
    }
    let (mut bytes, mut files) = (0, 0);
    for (job, opened) in &ready {
        let (b, f) = opened.index.totals(&job.inners);
        bytes += b;
        files += f;
    }
    ctx.set_totals(bytes, files);
    let mut last = None;
    for (job, opened) in &ready {
        ctx.check()?;
        if extract_job(ctx, job, &opened.index, opened.password.as_deref(), &request.options)? {
            last = Some(match job.inners.as_slice() {
                [inner] if !inner.is_empty() => job.base.join(inner.rsplit('/').next().unwrap_or(inner)),
                _ => job.base.clone(),
            });
        }
    }
    if ready.len() == 1 {
        ctx.update(|p| p.result_path = last);
    }
    Ok(())
}

/// An archive ready to read: its index and the password it opens with.
struct Opened {
    index: Arc<ArchiveIndex>,
    password: Option<String>,
}

/// The archive's index and the password to read it with: the one given
/// (kept for the archive when it opens it), else one given before.
fn open(ctx: &OpContext, archive: &Path, given: Option<&str>) -> Result<Option<Opened>, Abort> {
    loop {
        let opened = match given {
            Some(password) => shared::set_password(archive, password).and_then(|_| shared::index(archive)),
            None => shared::index(archive),
        };
        match opened {
            Ok(index) => {
                let password = given.map(str::to_string).or_else(|| shared::password(archive));
                if index.encrypted && password.is_none() {
                    ctx.ask_skip(archive, &VfsError::password_required(archive))?;
                    return Ok(None);
                }
                return Ok(Some(Opened { index, password }));
            }
            Err(e) if matches!(e.kind, VfsErrorKind::PasswordRequired | VfsErrorKind::WrongPassword) => {
                ctx.ask_skip(archive, &e)?;
                return Ok(None);
            }
            Err(e) => {
                if !ctx.ask_error(archive, &e)? {
                    return Ok(None);
                }
            }
        }
    }
}

/// Writes one archive's members; answers whether it got to the end.
fn extract_job(
    ctx: &OpContext,
    job: &Job,
    index: &ArchiveIndex,
    password: Option<&str>,
    options: &OpOptions,
) -> Result<bool, Abort> {
    let mut targets = HashMap::new();
    for inner in &job.inners {
        for folder in index.folders_under(inner) {
            let path = job.base.join(&folder);
            if let Err(e) = fs::create_dir_all(&path) {
                ctx.ask_skip(&path, &VfsError::io(&e, &path))?;
            }
        }
        for (member, relative) in index.files_under(inner) {
            targets.insert(member, job.base.join(relative));
        }
    }
    if let Err(e) = fs::create_dir_all(&job.base) {
        ctx.ask_skip(&job.base, &VfsError::io(&e, &job.base))?;
        return Ok(false);
    }
    let wanted: Vec<String> = targets.keys().cloned().collect();
    let mut sink = OpSink { ctx, targets, options, open: None, abort: None, archive_failed: None };
    let outcome = index.extract_members(&wanted, password, &mut sink);
    if let Some(abort) = sink.abort {
        return Err(abort);
    }
    if let Some(e) = sink.archive_failed {
        ctx.ask_skip(&job.archive, &e)?;
        return Ok(false);
    }
    match outcome {
        Ok(()) => Ok(true),
        Err(ExtractError::Stopped) => Ok(false),
        Err(ExtractError::Failed(e)) => {
            ctx.ask_skip(&job.archive, &e)?;
            Ok(false)
        }
    }
}

/// The file being written: its writer, where it goes, and a symbolic
/// link's target gathered from its data.
enum Open {
    File { writer: BufWriter<File>, path: PathBuf },
    Link { target: Vec<u8>, path: PathBuf },
}

/// Writes members to their targets with the operation's conflict policy,
/// progress, pause and cancellation.
struct OpSink<'a> {
    ctx: &'a OpContext,
    targets: HashMap<String, PathBuf>,
    options: &'a OpOptions,
    open: Option<Open>,
    /// Why the whole operation stops (cancelled, or the user stopped it).
    abort: Option<Abort>,
    /// A failure that ends this archive (a missing or wrong password).
    archive_failed: Option<VfsError>,
}

impl OpSink<'_> {
    fn stop(&mut self, abort: Abort) -> Stop {
        self.abort = Some(abort);
        Stop
    }
}

impl MemberSink for OpSink<'_> {
    fn begin(&mut self, member: &Member) -> Result<bool, Stop> {
        if let Err(abort) = self.ctx.check() {
            return Err(self.stop(abort));
        }
        let Some(target) = self.targets.get(&member.path).cloned() else { return Ok(false) };
        self.ctx.set_current(&target);
        if let Some(parent) = target.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let resolved =
            match resolve_conflict(self.ctx, &target, Some(member.size), member.modified_ms, self.options) {
                Ok(resolved) => resolved,
                Err(abort) => return Err(self.stop(abort)),
            };
        let Some(path) = resolved else {
            // Skipped: its bytes count as handled.
            self.ctx.add_bytes(member.size);
            self.ctx.item_done();
            return Ok(false);
        };
        if member.is_symlink {
            if let Some(link) = &member.link {
                if let Err(e) = ferryx_vfs::links::create_symlink(Path::new(link), &path) {
                    self.ctx.record_error(&path, e.message);
                }
                self.ctx.item_done();
                return Ok(false);
            }
            self.open = Some(Open::Link { target: Vec::new(), path });
            return Ok(true);
        }
        match File::create(&path) {
            Ok(file) => {
                self.open = Some(Open::File { writer: BufWriter::with_capacity(1 << 20, file), path });
                Ok(true)
            }
            Err(e) => {
                let error = VfsError::io(&e, &path);
                match self.ctx.ask_skip(&path, &error) {
                    Ok(()) => Ok(false),
                    Err(abort) => Err(self.stop(abort)),
                }
            }
        }
    }

    fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
        if self.ctx.check().is_err() {
            return Err(io::Error::other("cancelled"));
        }
        match self.open.as_mut() {
            Some(Open::File { writer, .. }) => writer.write_all(bytes)?,
            Some(Open::Link { target, .. }) => target.extend_from_slice(bytes),
            None => {}
        }
        self.ctx.add_bytes(bytes.len() as u64);
        Ok(())
    }

    fn end(&mut self, member: &Member, outcome: VfsResult<u64>) -> Result<(), Stop> {
        let (path, finished) = match self.open.take() {
            Some(Open::File { mut writer, path }) => {
                let flushed = writer.flush().map_err(|e| VfsError::io(&e, &path));
                (Some(path), outcome.and_then(|n| flushed.map(|_| n)))
            }
            Some(Open::Link { target, path }) => {
                let made = outcome.and_then(|n| {
                    let target = String::from_utf8_lossy(&target).into_owned();
                    ferryx_vfs::links::create_symlink(Path::new(&target), &path).map(|_| n)
                });
                (Some(path), made)
            }
            None => (None, outcome),
        };
        let path = path.unwrap_or_default();
        match finished {
            Ok(_) => {
                if !member.is_symlink {
                    set_mode(&path, member.mode);
                    if let Some(ms) = member.modified_ms {
                        set_times(&path, Some(ms), None);
                    }
                }
                self.ctx.item_done();
                Ok(())
            }
            Err(e) => {
                let _ = fs::remove_file(&path);
                if let Err(abort) = self.ctx.check() {
                    return Err(self.stop(abort));
                }
                if matches!(e.kind, VfsErrorKind::PasswordRequired | VfsErrorKind::WrongPassword) {
                    self.archive_failed = Some(e);
                    return Err(Stop);
                }
                match self.ctx.ask_skip(&path, &e) {
                    Ok(()) => Ok(()),
                    Err(abort) => Err(self.stop(abort)),
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn zip_at(path: &Path, files: &[(&str, &[u8])], password: Option<&str>) {
        let mut zip = zip::ZipWriter::new(File::create(path).unwrap());
        for (name, data) in files {
            let mut opts = zip::write::SimpleFileOptions::default();
            if let Some(password) = password {
                opts = opts.with_aes_encryption(zip::AesMode::Aes256, password);
            }
            zip.start_file(*name, opts).unwrap();
            zip.write_all(data).unwrap();
        }
        zip.finish().unwrap();
    }

    fn request(sources: Vec<PathBuf>, archive: Option<PathBuf>, dest: &Path) -> OpRequest {
        OpRequest {
            kind: OpKind::Extract,
            sources,
            archive,
            destination: Some(dest.to_path_buf()),
            new_name: None,
            options: OpOptions::default(),
        }
    }

    #[test]
    fn extracts_members_out_of_an_archive() {
        let dir = tempfile::tempdir().unwrap();
        let archive = dir.path().join("a.zip");
        zip_at(&archive, &[("top.txt", b"top"), ("d/x.txt", b"xx"), ("d/e/y.txt", b"yyy")], None);
        let dest = dir.path().join("out");
        let req = request(vec![PathBuf::from("d")], Some(archive.clone()), &dest);
        let ctx = OpContext::detached(&req);
        run(&ctx, &req).unwrap();
        let p = ctx.snapshot();
        assert_eq!((p.bytes_total, p.items_total), (5, 2));
        assert_eq!(p.items_done, 2);
        assert_eq!(fs::read(dest.join("d/e/y.txt")).unwrap(), b"yyy");
        assert!(!dest.join("top.txt").exists());
        assert_eq!(p.result_path, Some(dest.join("d")));
    }

    #[test]
    fn extracts_whole_archives_into_folders_of_their_own() {
        let dir = tempfile::tempdir().unwrap();
        let one = dir.path().join("one.zip");
        let two = dir.path().join("two.tar.gz");
        zip_at(&one, &[("a.txt", b"a"), ("b.txt", b"b")], None);
        {
            let gz = flate2::write::GzEncoder::new(File::create(&two).unwrap(), flate2::Compression::fast());
            let mut tar = tar::Builder::new(gz);
            let mut header = tar::Header::new_gnu();
            header.set_size(1);
            header.set_mode(0o644);
            header.set_cksum();
            tar.append_data(&mut header, "c.txt", &b"c"[..]).unwrap();
            tar.into_inner().unwrap().finish().unwrap();
        }
        let dest = dir.path().join("out");
        let mut req = request(vec![one.clone(), two.clone()], None, &dest);
        req.options.into_folders = true;
        run(&OpContext::detached(&req), &req).unwrap();
        assert_eq!(fs::read(dest.join("one/a.txt")).unwrap(), b"a");
        assert_eq!(fs::read(dest.join("two/c.txt")).unwrap(), b"c");

        // Without folders, into the destination; a conflict follows the policy.
        let flat = dir.path().join("flat");
        let mut req = request(vec![one.clone()], None, &flat);
        run(&OpContext::detached(&req), &req).unwrap();
        fs::write(flat.join("a.txt"), b"mine").unwrap();
        req.options.conflicts = ConflictPolicy::Skip;
        run(&OpContext::detached(&req), &req).unwrap();
        assert_eq!(fs::read(flat.join("a.txt")).unwrap(), b"mine");
        req.options.conflicts = ConflictPolicy::KeepBoth;
        run(&OpContext::detached(&req), &req).unwrap();
        assert_eq!(fs::read(flat.join("a 2.txt")).unwrap(), b"a");
    }

    #[test]
    fn passwords_open_encrypted_members() {
        let dir = tempfile::tempdir().unwrap();
        let archive = dir.path().join("locked.zip");
        zip_at(&archive, &[("s.txt", b"secret")], Some("pw"));
        let dest = dir.path().join("out");
        // No password: the archive is passed by with an error.
        let req = request(vec![archive.clone()], None, &dest);
        let ctx = OpContext::detached(&req);
        run(&ctx, &req).unwrap();
        assert!(!ctx.snapshot().errors.is_empty());
        assert!(!dest.join("s.txt").exists());
        // A wrong one, the same.
        let mut wrong = request(vec![archive.clone()], None, &dest);
        wrong.options.password = Some("nope".into());
        let ctx = OpContext::detached(&wrong);
        run(&ctx, &wrong).unwrap();
        assert!(!ctx.snapshot().errors.is_empty());
        // The right one writes it.
        let mut right = request(vec![archive.clone()], None, &dest);
        right.options.password = Some("pw".into());
        let ctx = OpContext::detached(&right);
        run(&ctx, &right).unwrap();
        assert!(ctx.snapshot().errors.is_empty());
        assert_eq!(fs::read(dest.join("s.txt")).unwrap(), b"secret");
    }
}
