//! Extract: members of an archive written out to a folder (F5 inside an
//! archive), or whole archives each into the destination or into a folder
//! named after it (Extract To). The members stream through
//! [`ArchiveIndex::extract_members`]: a tar is read once, a 7z block
//! decoded once, and no member is held in memory whole.

use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use ferryx_vfs::archive::{self, shared, ArchiveIndex, ExtractError, Member, MemberSink, Stop};
use ferryx_vfs::error::{VfsError, VfsErrorKind, VfsResult};

use crate::runner::OpContext;
use crate::types::*;

mod destination;
use destination::{Destination, Target};

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
            base: PathBuf::new(),
        }],
        None => request
            .sources
            .iter()
            .map(|archive| Job {
                archive: archive.clone(),
                inners: vec![String::new()],
                base: if request.options.into_folders {
                    PathBuf::from(archive::archive_stem(archive))
                } else {
                    PathBuf::new()
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
    if ready.is_empty() {
        return Ok(());
    }
    let destination = match Destination::open(ctx, dest_dir) {
        Ok(destination) => destination,
        Err(e) => {
            ctx.ask_skip(dest_dir, &VfsError::io(&e, dest_dir))?;
            return Ok(());
        }
    };
    let mut last = None;
    for (job, opened) in &ready {
        ctx.check()?;
        if extract_job(ctx, job, &destination, &opened.index, opened.password.as_deref(), &request.options)? {
            last = Some(destination.path(&match job.inners.as_slice() {
                [inner] if !inner.is_empty() => job.base.join(inner.rsplit('/').next().unwrap_or(inner)),
                _ => job.base.clone(),
            }));
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
    destination: &Destination,
    index: &ArchiveIndex,
    password: Option<&str>,
    options: &OpOptions,
) -> Result<bool, Abort> {
    let mut folders = Folders { destination, known: HashSet::new() };
    if let Err(e) = folders.make(ctx, &job.base) {
        let path = destination.path(&job.base);
        ctx.ask_skip(&path, &VfsError::io(&e, &path))?;
        return Ok(false);
    }
    let mut targets = HashMap::new();
    for inner in &job.inners {
        for folder in index.folders_under(inner) {
            let path = job.base.join(&folder);
            if let Err(e) = folders.make(ctx, &path) {
                let path = destination.path(&path);
                ctx.ask_skip(&path, &VfsError::io(&e, &path))?;
            }
        }
        for (member, relative) in index.files_under(inner) {
            targets.insert(member, job.base.join(relative));
        }
    }
    let wanted: Vec<String> = targets.keys().cloned().collect();
    let mut sink = OpSink { ctx, targets, folders, options, open: None, abort: None, archive_failed: None };
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

/// The folders one archive's extraction made or found, so each is made
/// once rather than for every file in it.
struct Folders<'a> {
    destination: &'a Destination,
    known: HashSet<PathBuf>,
}

impl Folders<'_> {
    fn make(&mut self, ctx: &OpContext, folder: &Path) -> io::Result<()> {
        if !self.known.contains(folder) {
            self.destination.make_folders(ctx, folder)?;
            self.known.insert(folder.to_path_buf());
        }
        Ok(())
    }
}

/// The file being written: its writer, where it goes, and a symbolic
/// link's target gathered from its data.
enum Open {
    File { writer: BufWriter<File>, target: Target },
    Link { contents: Vec<u8>, target: Target },
}

/// Writes members to their targets with the operation's conflict policy,
/// progress, pause and cancellation.
struct OpSink<'a> {
    ctx: &'a OpContext,
    targets: HashMap<String, PathBuf>,
    folders: Folders<'a>,
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
        let Some(relative) = self.targets.get(&member.path).cloned() else { return Ok(false) };
        let path = self.folders.destination.path(&relative);
        self.ctx.set_current(&path);
        let prepared = (|| {
            if let Some(parent) = relative.parent() {
                self.folders.make(self.ctx, parent)?;
            }
            self.folders.destination.target(&relative)
        })();
        let target = match prepared {
            Ok(target) => target,
            Err(e) => {
                return match self.ctx.ask_skip(&path, &VfsError::io(&e, &path)) {
                    Ok(()) => Ok(false),
                    Err(abort) => Err(self.stop(abort)),
                }
            }
        };
        let resolved = match target.resolve(self.ctx, member.size, member.modified_ms, self.options.conflicts)
        {
            Ok(resolved) => resolved,
            Err(abort) => return Err(self.stop(abort)),
        };
        let Some(target) = resolved else {
            // Skipped: its bytes count as handled.
            self.ctx.add_bytes(member.size);
            self.ctx.item_done();
            return Ok(false);
        };
        if member.is_symlink {
            if let Some(link) = &member.link {
                match target.symlink(Path::new(link)) {
                    Ok(()) => self.ctx.record_created(&target.path),
                    Err(e) => self.ctx.record_error(&target.path, VfsError::io(&e, &target.path).message),
                }
                self.ctx.item_done();
                return Ok(false);
            }
            self.open = Some(Open::Link { contents: Vec::new(), target });
            return Ok(true);
        }
        match target.create() {
            Ok(file) => {
                self.open = Some(Open::File { writer: BufWriter::with_capacity(1 << 20, file), target });
                Ok(true)
            }
            Err(e) => {
                let error = VfsError::io(&e, &target.path);
                match self.ctx.ask_skip(&target.path, &error) {
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
            Some(Open::Link { contents, .. }) => {
                if contents.len().saturating_add(bytes.len()) > 64 * 1024 {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "symbolic link target is too long",
                    ));
                }
                contents.extend_from_slice(bytes);
            }
            None => {}
        }
        self.ctx.add_bytes(bytes.len() as u64);
        Ok(())
    }

    fn end(&mut self, member: &Member, outcome: VfsResult<u64>) -> Result<(), Stop> {
        let (target, finished, cleanup) = match self.open.take() {
            Some(Open::File { mut writer, target }) => {
                let flushed = writer.flush().map_err(|e| VfsError::io(&e, &target.path));
                let finished = outcome.and_then(|n| flushed.map(|_| n));
                if finished.is_ok() {
                    preserve(writer.get_ref(), member);
                }
                (target, finished, true)
            }
            Some(Open::Link { contents, target }) => {
                let made = outcome.and_then(|n| {
                    let link = String::from_utf8_lossy(&contents);
                    target
                        .symlink(Path::new(link.as_ref()))
                        .map(|_| n)
                        .map_err(|e| VfsError::io(&e, &target.path))
                });
                (target, made, false)
            }
            None => return Ok(()),
        };
        let path = &target.path;
        match finished {
            Ok(_) => {
                // Complete, so its fingerprint is the one an undo checks.
                self.ctx.record_created(path);
                self.ctx.item_done();
                Ok(())
            }
            Err(e) => {
                if cleanup {
                    let _ = target.remove_file();
                }
                if let Err(abort) = self.ctx.check() {
                    return Err(self.stop(abort));
                }
                if matches!(e.kind, VfsErrorKind::PasswordRequired | VfsErrorKind::WrongPassword) {
                    self.archive_failed = Some(e);
                    return Err(Stop);
                }
                match self.ctx.ask_skip(path, &e) {
                    Ok(()) => Ok(()),
                    Err(abort) => Err(self.stop(abort)),
                }
            }
        }
    }
}

/// Apply metadata through the open file, so a renamed parent or replaced
/// name cannot redirect chmod or the timestamp update to another file.
fn preserve(file: &File, member: &Member) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = file.set_permissions(std::fs::Permissions::from_mode(member.mode & 0o7777));
    }
    #[cfg(not(unix))]
    if let Ok(meta) = file.metadata() {
        let mut permissions = meta.permissions();
        permissions.set_readonly(member.mode & 0o200 == 0);
        let _ = file.set_permissions(permissions);
    }
    if let Some(ms) = member.modified_ms {
        let modified =
            filetime::FileTime::from_unix_time(ms.div_euclid(1000), (ms.rem_euclid(1000) * 1_000_000) as u32);
        let _ = filetime::set_file_handle_times(file, Some(filetime::FileTime::now()), Some(modified));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

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

    /// Times extracting a zip of 20 000 small files in 400 folders:
    /// `cargo test --release -p ferryx_ops extract_bench -- --ignored
    /// --nocapture`.
    #[test]
    #[ignore]
    fn extract_bench() {
        let dir = tempfile::tempdir().unwrap();
        let archive = dir.path().join("many.zip");
        {
            let mut zip = zip::ZipWriter::new(io::BufWriter::new(File::create(&archive).unwrap()));
            let opts = zip::write::SimpleFileOptions::default();
            for i in 0..20_000 {
                zip.start_file(format!("top/d{}/e{}/f{i}.txt", i % 20, i % 400), opts).unwrap();
                zip.write_all(b"a small file").unwrap();
            }
            zip.finish().unwrap();
        }
        let mut best = std::time::Duration::MAX;
        for round in 0..3 {
            let dest = dir.path().join(format!("out{round}"));
            let req = request(vec![archive.clone()], None, &dest);
            let start = std::time::Instant::now();
            run(&OpContext::detached(&req), &req).unwrap();
            best = best.min(start.elapsed());
        }
        println!("20 000 files in 400 folders: {best:?}");
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
