//! The member lists and the members' bytes of each format but ISO.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs::{self, File};
use std::io::{self, BufReader, Read, Seek, SeekFrom};
use std::path::Path;

use sevenz_rust2::{BlockDecoder, EncoderMethod, Password};
use unrar_rs::{HostOs, RarArchive, RarError};

use super::detect::read_up_to;
use super::{
    normalize, pump, single_member_name, ArchiveIndex, Backing, Compression, ExtractError, Listed, Member,
    MemberSink, SinkWriter,
};
use crate::error::{IoAt, VfsError, VfsErrorKind, VfsResult};
use crate::native::system_time_ms;

/// What an extraction reads: the index, the members picked (indices into
/// it, sorted), the password.
pub(crate) struct Job<'a> {
    pub index: &'a ArchiveIndex,
    pub picked: &'a [usize],
    pub password: Option<&'a str>,
}

impl Job<'_> {
    fn path(&self) -> &Path {
        &self.index.archive
    }

    fn member(&self, at: usize) -> &Member {
        &self.index.members[at]
    }
}

/// The stream `reader` unpacks to.
pub(crate) fn decoder<'a, R: Read + 'a>(
    reader: R,
    compression: Compression,
) -> io::Result<Box<dyn Read + 'a>> {
    Ok(match compression {
        Compression::None => Box::new(reader),
        Compression::Gzip => Box::new(flate2::read::MultiGzDecoder::new(reader)),
        Compression::Bzip2 => Box::new(bzip2::read::MultiBzDecoder::new(reader)),
        Compression::Xz => Box::new(lzma_rust2::XzReader::new(reader, true)),
        Compression::Zstd => Box::new(zstd::stream::read::Decoder::new(reader)?),
    })
}

/// A read failure inside the archive, at the archive's path.
fn read_error(archive: &Path, error: io::Error) -> VfsError {
    VfsError::io(&error, archive)
}

/// Reads a member through `body` and reports it to the sink: begun,
/// written, ended. Answers whether to go on.
fn deliver(
    sink: &mut dyn MemberSink,
    member: &Member,
    body: impl FnOnce(&mut dyn MemberSink) -> VfsResult<u64>,
) -> Result<(), ExtractError> {
    if !sink.begin(member)? {
        return Ok(());
    }
    let outcome = body(sink);
    sink.end(member, outcome)?;
    Ok(())
}

fn mode_or(mode: u32, is_dir: bool) -> u32 {
    if mode & 0o170000 != 0 {
        mode
    } else if is_dir {
        0o40000 | if mode & 0o777 != 0 { mode & 0o7777 } else { 0o755 }
    } else {
        0o100000 | if mode & 0o777 != 0 { mode & 0o7777 } else { 0o644 }
    }
}

// ─── Zip ───

pub(crate) fn zip_error(archive: &Path, error: zip::result::ZipError) -> VfsError {
    use zip::result::ZipError;
    match error {
        ZipError::Io(io) => VfsError::io(&io, archive),
        ZipError::FileNotFound => VfsError::new(VfsErrorKind::NotFound, Some(archive), "member not found"),
        ZipError::InvalidPassword => VfsError::wrong_password(archive),
        ZipError::UnsupportedArchive(what) if what == ZipError::PASSWORD_REQUIRED => {
            VfsError::password_required(archive)
        }
        ZipError::UnsupportedArchive(what) => VfsError::unsupported(what.to_string()),
        other => VfsError::new(VfsErrorKind::Io, Some(archive), other.to_string()),
    }
}

pub(crate) fn list_zip(archive: &Path) -> VfsResult<Listed> {
    let file = File::open(archive).at(archive)?;
    let mut zip = zip::ZipArchive::new(BufReader::new(file)).map_err(|e| zip_error(archive, e))?;
    let mut members = Vec::with_capacity(zip.len());
    for i in 0..zip.len() {
        let Ok(entry) = zip.by_index_raw(i) else { continue };
        let path = normalize(entry.name());
        if path.is_empty() {
            continue;
        }
        // Zip times are local time without a zone.
        let modified_ms = entry.last_modified().and_then(|dt| {
            use chrono::TimeZone;
            chrono::Local
                .with_ymd_and_hms(
                    dt.year() as i32,
                    dt.month() as u32,
                    dt.day() as u32,
                    dt.hour() as u32,
                    dt.minute() as u32,
                    dt.second() as u32,
                )
                .single()
                .map(|t| t.timestamp_millis())
        });
        let is_dir = entry.is_dir();
        members.push(Member {
            is_dir,
            is_symlink: entry.is_symlink(),
            size: entry.size(),
            modified_ms,
            mode: mode_or(entry.unix_mode().unwrap_or(0), is_dir),
            encrypted: entry.encrypted(),
            native: Some(i as u64),
            link: None,
            path,
        });
    }
    Ok(Listed::plain(members))
}

pub(crate) fn extract_zip(job: &Job, sink: &mut dyn MemberSink) -> Result<(), ExtractError> {
    let archive = job.path();
    let file = File::open(archive).at(archive)?;
    let mut zip = zip::ZipArchive::new(BufReader::new(file)).map_err(|e| zip_error(archive, e))?;
    // In the central directory's order, which is the data's: the reads go
    // forward through the file.
    let mut picked: Vec<(u64, usize)> =
        job.picked.iter().filter_map(|&at| job.member(at).native.map(|n| (n, at))).collect();
    picked.sort_unstable();
    for (native, at) in picked {
        let member = job.member(at);
        deliver(sink, member, |sink| {
            let entry = match (member.encrypted, job.password) {
                (true, None) => return Err(VfsError::password_required(archive)),
                (true, Some(password)) => zip.by_index_decrypt(native as usize, password.as_bytes()),
                (false, _) => zip.by_index(native as usize),
            };
            let mut entry = entry.map_err(|e| zip_error(archive, e))?;
            pump(&mut entry, &mut SinkWriter(sink)).map_err(|e| read_error(archive, e))
        })?;
    }
    Ok(())
}

// ─── Tar ───

pub(crate) fn list_tar(archive: &Path, compression: Compression) -> VfsResult<Listed> {
    let file = File::open(archive).at(archive)?;
    let members = if compression == Compression::None {
        // A plain tar seeks past each member's data.
        let mut tar = tar::Archive::new(BufReader::new(file));
        let entries = tar.entries_with_seek().at(archive)?;
        collect_tar(entries, archive)?
    } else {
        let reader = decoder(BufReader::new(file), compression).at(archive)?;
        let mut tar = tar::Archive::new(reader);
        let entries = tar.entries().at(archive)?;
        collect_tar(entries, archive)?
    };
    Ok(Listed::plain(members))
}

fn collect_tar<R: Read>(entries: tar::Entries<'_, R>, archive: &Path) -> VfsResult<Vec<Member>> {
    let mut members = Vec::new();
    for entry in entries {
        let entry = match entry {
            Ok(entry) => entry,
            // A broken stream keeps what was read before it, unless
            // nothing was: then it was no tar at all.
            Err(e) if members.is_empty() => return Err(read_error(archive, e)),
            Err(_) => break,
        };
        let kind = entry.header().entry_type();
        if !(kind.is_file()
            || kind.is_dir()
            || kind.is_symlink()
            || kind.is_hard_link()
            || kind.is_contiguous())
        {
            continue;
        }
        let path = entry.path().map(|p| normalize(&p.to_string_lossy())).unwrap_or_default();
        if path.is_empty() {
            continue;
        }
        let header = entry.header();
        let is_dir = kind.is_dir();
        members.push(Member {
            path,
            is_dir,
            is_symlink: kind.is_symlink(),
            size: if is_dir { 0 } else { entry.size() },
            modified_ms: header.mtime().ok().map(|s| s as i64 * 1000),
            mode: mode_or(header.mode().unwrap_or(0), is_dir),
            encrypted: false,
            native: None,
            link: if kind.is_symlink() {
                entry.link_name().ok().flatten().map(|l| l.to_string_lossy().into_owned())
            } else {
                None
            },
        });
    }
    Ok(members)
}

pub(crate) fn extract_tar(
    job: &Job,
    compression: Compression,
    sink: &mut dyn MemberSink,
) -> Result<(), ExtractError> {
    let archive = job.path();
    let file = File::open(archive).at(archive)?;
    if compression == Compression::None {
        // A plain tar seeks past the members not wanted.
        let mut tar = tar::Archive::new(BufReader::new(file));
        let entries = tar.entries_with_seek().map_err(|e| read_error(archive, e))?;
        return deliver_tar(job, entries, sink);
    }
    let reader = decoder(BufReader::new(file), compression).at(archive)?;
    let mut tar = tar::Archive::new(reader);
    let entries = tar.entries().map_err(|e| read_error(archive, e))?;
    deliver_tar(job, entries, sink)
}

fn deliver_tar<R: Read>(
    job: &Job,
    entries: tar::Entries<'_, R>,
    sink: &mut dyn MemberSink,
) -> Result<(), ExtractError> {
    let archive = job.path();
    let mut wanted = vec![false; job.index.members.len()];
    for &at in job.picked {
        wanted[at] = true;
    }
    let mut remaining = job.picked.len();
    for entry in entries {
        let mut entry = entry.map_err(|e| read_error(archive, e))?;
        let path = entry.path().map(|p| normalize(&p.to_string_lossy())).unwrap_or_default();
        let Some(at) = job.index.position(&path) else { continue };
        if !wanted[at] {
            continue;
        }
        wanted[at] = false;
        let member = job.member(at);
        deliver(sink, member, |sink| {
            pump(&mut entry, &mut SinkWriter(sink)).map_err(|e| read_error(archive, e))
        })?;
        remaining -= 1;
        if remaining == 0 {
            break;
        }
    }
    Ok(())
}

// ─── 7z ───

/// Threads for a block's LZMA2 when `needed` bytes of it are to be
/// decoded: a stream 7-Zip wrote on several threads starts afresh every
/// four dictionaries, and those parts decode at once. A part comes out
/// only when decoded whole, so a read of less than one (a password tried,
/// a small member near the start) streams on one thread; else a few, as
/// each holds its part unpacked (128 MiB at most).
fn sevenz_threads(needed: u64) -> u32 {
    const WORTH_IT: u64 = 128 * 1024 * 1024;
    if needed < WORTH_IT {
        return 1;
    }
    std::thread::available_parallelism().map_or(1, |n| n.get()).clamp(1, 4) as u32
}

fn sevenz_error(archive: &Path, error: sevenz_rust2::Error, encrypted: bool) -> VfsError {
    use sevenz_rust2::Error;
    match error {
        Error::PasswordRequired => VfsError::password_required(archive),
        Error::MaybeBadPassword(_) => VfsError::wrong_password(archive),
        Error::ChecksumVerificationFailed if encrypted => VfsError::wrong_password(archive),
        Error::Io(e, _) | Error::FileOpen(e, _) => VfsError::io(&e, archive),
        Error::Unsupported(what) => VfsError::unsupported(what.to_string()),
        Error::UnsupportedCompressionMethod(what) => VfsError::unsupported(what),
        other => VfsError::new(VfsErrorKind::Io, Some(archive), other.to_string()),
    }
}

fn read_7z_headers(
    archive: &Path,
    password: &Password,
) -> Result<sevenz_rust2::Archive, sevenz_rust2::Error> {
    let file =
        File::open(archive).map_err(|e| sevenz_rust2::Error::FileOpen(e, archive.display().to_string()))?;
    sevenz_rust2::Archive::read(&mut BufReader::new(file), password)
}

pub(crate) fn list_7z(archive: &Path, password: Option<&str>) -> VfsResult<Listed> {
    let (headers, headers_encrypted) = match read_7z_headers(archive, &Password::empty()) {
        Ok(headers) => (headers, false),
        Err(sevenz_rust2::Error::PasswordRequired) => {
            let Some(password) = password else { return Err(VfsError::password_required(archive)) };
            match read_7z_headers(archive, &Password::new(password)) {
                Ok(headers) => (headers, true),
                Err(sevenz_rust2::Error::FileOpen(e, _)) => return Err(VfsError::io(&e, archive)),
                // Headers that do not decode with the key: the key is wrong.
                Err(_) => return Err(VfsError::wrong_password(archive)),
            }
        }
        Err(e) => return Err(sevenz_error(archive, e, false)),
    };
    let encrypted_blocks: Vec<bool> = headers
        .blocks
        .iter()
        .map(|b| b.coders.iter().any(|c| c.encoder_method_id() == EncoderMethod::ID_AES256_SHA256))
        .collect();
    let mut members = Vec::with_capacity(headers.files.len());
    for (i, file) in headers.files.iter().enumerate() {
        // An anti-item deletes a file in an update; the folders some
        // writers flag so are folders still.
        if file.is_anti_item && !file.is_directory {
            continue;
        }
        let path = normalize(&file.name);
        if path.is_empty() {
            continue;
        }
        let block = headers.stream_map.file_block_index.get(i).copied().flatten();
        // p7zip keeps the Unix mode in the high half of the attributes.
        let unix = if file.has_windows_attributes && file.windows_attributes & 0x8000 != 0 {
            file.windows_attributes >> 16
        } else {
            0
        };
        let is_dir = file.is_directory;
        members.push(Member {
            path,
            is_dir,
            is_symlink: unix & 0o170000 == 0o120000,
            size: file.size,
            modified_ms: file
                .has_last_modified_date
                .then(|| system_time_ms(std::time::SystemTime::from(file.last_modified_date)))
                .flatten(),
            mode: mode_or(unix, is_dir),
            encrypted: block.map(|b| encrypted_blocks[b]).unwrap_or(false),
            native: Some(i as u64),
            link: None,
        });
    }
    Ok(Listed { members, headers_encrypted, backing: Backing::SevenZip(Box::new(headers)) })
}

pub(crate) fn extract_7z(job: &Job, sink: &mut dyn MemberSink) -> Result<(), ExtractError> {
    let archive = job.path();
    let Backing::SevenZip(headers) = &job.index.backing else {
        return Err(ExtractError::Failed(VfsError::unsupported("not a 7z archive")));
    };
    let password = job.password.map(Password::new).unwrap_or_else(Password::empty);
    let mut by_block: BTreeMap<usize, HashMap<usize, usize>> = BTreeMap::new();
    let mut empty = Vec::new();
    for &at in job.picked {
        let member = job.member(at);
        let Some(native) = member.native.map(|n| n as usize) else { continue };
        match headers.stream_map.file_block_index.get(native).copied().flatten() {
            Some(block) => {
                by_block.entry(block).or_default().insert(native, at);
            }
            None => empty.push(at),
        }
    }
    let mut file = BufReader::new(File::open(archive).at(archive)?);
    for (block, wanted) in by_block {
        let encrypted = wanted.values().any(|&at| job.member(at).encrypted);
        if encrypted && job.password.is_none() {
            for &at in wanted.values() {
                deliver(sink, job.member(at), |_| Err(VfsError::password_required(archive)))?;
            }
            continue;
        }
        let mut remaining = wanted.len();
        let mut native = headers.stream_map.block_first_file_index[block];
        let last = wanted.keys().max().copied().unwrap_or(native);
        let needed: u64 =
            headers.files.get(native..=last).map_or(0, |files| files.iter().map(|f| f.size).sum());
        let mut done: HashSet<usize> = HashSet::new();
        let mut stopped = false;
        let decoded = BlockDecoder::new(sevenz_threads(needed), block, headers, &password, &mut file)
            .for_each_entries(&mut |_, reader| {
                let this = native;
                native += 1;
                let Some(&at) = wanted.get(&this) else {
                    io::copy(reader, &mut io::sink())?;
                    return Ok(true);
                };
                let member = job.member(at);
                done.insert(at);
                match sink.begin(member) {
                    Err(_) => {
                        stopped = true;
                        return Ok(false);
                    }
                    Ok(false) => {
                        io::copy(reader, &mut io::sink())?;
                    }
                    Ok(true) => {
                        let outcome = pump(reader, &mut SinkWriter(sink));
                        // What the sink did not take is passed by, so the next
                        // member starts where it should.
                        let drained = io::copy(reader, &mut io::sink());
                        let outcome = outcome.map_err(|e| read_error(archive, e));
                        if sink.end(member, outcome).is_err() {
                            stopped = true;
                            return Ok(false);
                        }
                        drained?;
                    }
                }
                remaining -= 1;
                Ok(remaining > 0)
            });
        if stopped {
            return Err(ExtractError::Stopped);
        }
        if let Err(e) = decoded {
            let error = sevenz_error(archive, e, encrypted);
            // The block broke: its members not yet delivered fail with it.
            for &at in wanted.values() {
                if !done.contains(&at) {
                    let e = error.clone();
                    deliver(sink, job.member(at), move |_| Err(e))?;
                }
            }
        }
    }
    for at in empty {
        deliver(sink, job.member(at), |_| Ok(0))?;
    }
    Ok(())
}

// ─── Rar ───

fn rar_error(archive: &Path, error: RarError) -> VfsError {
    match error {
        RarError::Io(e) => VfsError::io(&e, archive),
        RarError::EncryptedArchive | RarError::EncryptedMember { .. } => VfsError::password_required(archive),
        RarError::InvalidPassword | RarError::WrongPassword { .. } => VfsError::wrong_password(archive),
        RarError::MemberNotFound { name } => {
            VfsError::new(VfsErrorKind::NotFound, Some(archive), format!("{name} is not in the archive"))
        }
        other => VfsError::new(VfsErrorKind::Io, Some(archive), other.to_string()),
    }
}

fn open_rar(archive: &Path, password: Option<&str>) -> Result<RarArchive, RarError> {
    let file = BufReader::new(File::open(archive).map_err(RarError::Io)?);
    match password {
        Some(password) => RarArchive::open_with_password(file, password),
        None => RarArchive::open(file),
    }
}

pub(crate) fn list_rar(archive: &Path, password: Option<&str>) -> VfsResult<Listed> {
    let (rar, headers_encrypted) = match open_rar(archive, None) {
        Ok(rar) => (rar, false),
        Err(RarError::EncryptedArchive) => {
            let Some(password) = password else { return Err(VfsError::password_required(archive)) };
            match open_rar(archive, Some(password)) {
                Ok(rar) => (rar, true),
                Err(RarError::Io(e)) => return Err(VfsError::io(&e, archive)),
                Err(_) => return Err(VfsError::wrong_password(archive)),
            }
        }
        Err(e) => return Err(rar_error(archive, e)),
    };
    let mut members = Vec::with_capacity(rar.len());
    for (i, info) in rar.entries().enumerate() {
        let path = normalize(&info.name);
        if path.is_empty() {
            continue;
        }
        let unix = match info.host_os {
            HostOs::Unix | HostOs::Darwin => info.attributes.unix_mode(),
            _ => 0,
        };
        members.push(Member {
            path,
            is_dir: info.is_directory,
            is_symlink: info.is_symlink,
            size: info.unpacked_size.unwrap_or(0),
            modified_ms: info.mtime.and_then(system_time_ms),
            mode: mode_or(unix, info.is_directory),
            encrypted: info.is_encrypted,
            native: Some(i as u64),
            link: info.link_target.clone(),
        });
    }
    Ok(Listed { members, headers_encrypted, backing: Backing::Plain })
}

pub(crate) fn extract_rar(job: &Job, sink: &mut dyn MemberSink) -> Result<(), ExtractError> {
    let archive = job.path();
    let header_password = if job.index.headers_encrypted { job.password } else { None };
    let mut rar = open_rar(archive, header_password).map_err(|e| rar_error(archive, e))?;
    if let Some(password) = job.password {
        rar.set_password(password);
    }
    // A solid archive is read in member order.
    let mut picked: Vec<(u64, usize)> =
        job.picked.iter().filter_map(|&at| job.member(at).native.map(|n| (n, at))).collect();
    picked.sort_unstable();
    for (native, at) in picked {
        let member = job.member(at);
        deliver(sink, member, |sink| {
            if member.encrypted && job.password.is_none() {
                return Err(VfsError::password_required(archive));
            }
            let entry = rar.by_index(native as usize).map_err(|e| rar_error(archive, e))?;
            entry.copy_to(&mut SinkWriter(sink)).map_err(|e| rar_error(archive, e))
        })?;
    }
    Ok(())
}

// ─── One compressed file ───

pub(crate) fn list_single(archive: &Path, compression: Compression) -> VfsResult<Listed> {
    let meta = fs::metadata(archive).at(archive)?;
    let size = match compression {
        Compression::Gzip => gzip_size(archive, meta.len()),
        Compression::Zstd => zstd_size(archive),
        _ => None,
    };
    Ok(Listed::plain(vec![Member {
        path: single_member_name(archive),
        is_dir: false,
        is_symlink: false,
        size: size.unwrap_or(0),
        modified_ms: meta.modified().ok().and_then(system_time_ms),
        mode: 0o100644,
        encrypted: false,
        native: Some(0),
        link: None,
    }]))
}

/// A gzip stream's size as its trailer keeps it (modulo 4 GiB).
fn gzip_size(archive: &Path, len: u64) -> Option<u64> {
    if len < 18 {
        return None;
    }
    let mut file = File::open(archive).ok()?;
    file.seek(SeekFrom::End(-4)).ok()?;
    let mut tail = [0u8; 4];
    file.read_exact(&mut tail).ok()?;
    Some(u32::from_le_bytes(tail) as u64)
}

/// A zstd frame's size when its header gives it.
fn zstd_size(archive: &Path) -> Option<u64> {
    let mut file = File::open(archive).ok()?;
    let mut head = [0u8; 18];
    let n = read_up_to(&mut file, &mut head).ok()?;
    zstd::zstd_safe::get_frame_content_size(&head[..n]).ok().flatten()
}

pub(crate) fn extract_single(
    job: &Job,
    compression: Compression,
    sink: &mut dyn MemberSink,
) -> Result<(), ExtractError> {
    let archive = job.path();
    let Some(&at) = job.picked.first() else { return Ok(()) };
    let file = File::open(archive).at(archive)?;
    let mut reader = decoder(BufReader::new(file), compression).at(archive)?;
    deliver(sink, job.member(at), |sink| {
        pump(&mut reader, &mut SinkWriter(sink)).map_err(|e| read_error(archive, e))
    })
}
