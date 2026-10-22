//! Archives browsed as read-only folders: zip, tar, and gzipped tar.
//!
//! An [`ArchiveIndex`] reads the member list once; listing a folder inside
//! it filters that list, and reading a member goes back to the file.

use std::collections::BTreeMap;
use std::fs::{self, File};
use std::io::{self, BufReader, Read};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use ferryx_core::entry::{extension_of, Entry, EntryKind};
use serde::{Deserialize, Serialize};

use crate::error::{IoAt, VfsError, VfsErrorKind, VfsResult};
use crate::native::system_time_ms;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ArchiveFormat {
    Zip,
    Tar,
    TarGz,
}

/// The format a file's name says it is, or `None` for files that are not
/// archives Ferryx opens.
pub fn format_of(path: &Path) -> Option<ArchiveFormat> {
    let name = path.file_name()?.to_string_lossy().to_lowercase();
    if name.ends_with(".tar.gz") || name.ends_with(".tgz") {
        Some(ArchiveFormat::TarGz)
    } else if name.ends_with(".tar") {
        Some(ArchiveFormat::Tar)
    } else if name.ends_with(".zip")
        || name.ends_with(".jar")
        || name.ends_with(".ipa")
        || name.ends_with(".apk")
        || name.ends_with(".whl")
    {
        Some(ArchiveFormat::Zip)
    } else {
        None
    }
}

/// Whether `path` is an archive a panel enters on Return.
pub fn is_archive(path: &Path) -> bool {
    format_of(path).is_some()
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Member {
    /// `/`-separated, no leading or trailing slash.
    pub path: String,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub size: u64,
    pub modified_ms: Option<i64>,
    pub mode: u32,
    pub encrypted: bool,
}

/// The member list of one archive.
#[derive(Clone, Debug)]
pub struct ArchiveIndex {
    pub archive: PathBuf,
    pub format: ArchiveFormat,
    /// Members by path, folders implied by member paths included.
    members: BTreeMap<String, Member>,
    /// The archive file's modification time when read: a changed file is
    /// read again.
    pub file_modified: Option<SystemTime>,
}

impl ArchiveIndex {
    pub fn open(archive: &Path) -> VfsResult<ArchiveIndex> {
        let format = format_of(archive).ok_or_else(|| {
            VfsError::new(
                VfsErrorKind::Unsupported,
                Some(archive),
                format!("{} is not an archive Ferryx opens", archive.display()),
            )
        })?;
        let file_modified = fs::metadata(archive).at(archive)?.modified().ok();
        let members = match format {
            ArchiveFormat::Zip => read_zip(archive)?,
            ArchiveFormat::Tar => read_tar(BufReader::new(File::open(archive).at(archive)?), archive)?,
            ArchiveFormat::TarGz => {
                let reader = flate2::read::GzDecoder::new(BufReader::new(File::open(archive).at(archive)?));
                read_tar(reader, archive)?
            }
        };
        let mut index =
            ArchiveIndex { archive: archive.to_path_buf(), format, members: BTreeMap::new(), file_modified };
        for member in members {
            index.add(member);
        }
        Ok(index)
    }

    /// Whether the archive file changed since the index was read.
    pub fn is_stale(&self) -> bool {
        let now = fs::metadata(&self.archive).ok().and_then(|m| m.modified().ok());
        now != self.file_modified
    }

    fn add(&mut self, member: Member) {
        // Folders the member path implies, as zips often leave them out.
        let mut at = 0;
        while let Some(slash) = member.path[at..].find('/') {
            let dir = &member.path[..at + slash];
            if !dir.is_empty() {
                self.members.entry(dir.to_string()).or_insert_with(|| Member {
                    path: dir.to_string(),
                    is_dir: true,
                    is_symlink: false,
                    size: 0,
                    modified_ms: None,
                    mode: 0o755,
                    encrypted: false,
                });
            }
            at += slash + 1;
        }
        match self.members.get_mut(&member.path) {
            Some(existing) if existing.is_dir && member.is_dir => {
                // An explicit folder entry replaces the implied one's times.
                if member.modified_ms.is_some() {
                    existing.modified_ms = member.modified_ms;
                    existing.mode = member.mode;
                }
            }
            _ => {
                self.members.insert(member.path.clone(), member);
            }
        }
    }

    pub fn member(&self, inner: &str) -> Option<&Member> {
        self.members.get(inner)
    }

    pub fn is_dir(&self, inner: &str) -> bool {
        inner.is_empty() || self.members.get(inner).map(|m| m.is_dir).unwrap_or(false)
    }

    /// The rows of the folder `inner` (empty for the root), with the `..`
    /// row when asked; entries' paths are member paths.
    pub fn list(&self, inner: &str, show_parent: bool, show_hidden: bool) -> VfsResult<Vec<Entry>> {
        if !self.is_dir(inner) {
            return Err(VfsError::new(
                VfsErrorKind::NotADirectory,
                None,
                format!("{inner} is not a folder in the archive"),
            ));
        }
        let mut out = Vec::new();
        if show_parent {
            let parent = match inner.rfind('/') {
                Some(at) => inner[..at].to_string(),
                None => String::new(),
            };
            out.push(Entry::parent(PathBuf::from(parent)));
        }
        let prefix = if inner.is_empty() { String::new() } else { format!("{inner}/") };
        for (path, member) in self.members.range(prefix.clone()..) {
            if !path.starts_with(&prefix) {
                break;
            }
            let rest = &path[prefix.len()..];
            if rest.is_empty() || rest.contains('/') {
                continue;
            }
            let hidden = rest.starts_with('.');
            if hidden && !show_hidden {
                continue;
            }
            out.push(entry_of(member, rest, hidden));
        }
        Ok(out)
    }

    /// Every file member under `inner` (or the member itself), for an
    /// extraction: `(member path, relative path)`.
    pub fn files_under(&self, inner: &str) -> Vec<(String, String)> {
        let base = match inner.rfind('/') {
            Some(at) => &inner[..at + 1],
            None => "",
        };
        let prefix = format!("{inner}/");
        self.members
            .iter()
            .filter(|(path, _)| path.as_str() == inner || path.starts_with(&prefix))
            .map(|(path, m)| (path.clone(), path[base.len()..].to_string(), m.is_dir))
            .filter(|(_, _, is_dir)| !is_dir)
            .map(|(p, r, _)| (p, r))
            .collect()
    }

    /// The whole member as bytes.
    pub fn read(&self, inner: &str) -> VfsResult<Vec<u8>> {
        let member = self.members.get(inner).ok_or_else(|| {
            VfsError::new(VfsErrorKind::NotFound, None, format!("{inner} is not in the archive"))
        })?;
        if member.is_dir {
            return Err(VfsError::new(VfsErrorKind::IsADirectory, None, format!("{inner} is a folder")));
        }
        if member.encrypted {
            return Err(VfsError::unsupported(format!("{inner} is encrypted")));
        }
        match self.format {
            ArchiveFormat::Zip => {
                let file = File::open(&self.archive).at(&self.archive)?;
                let mut zip = zip::ZipArchive::new(file).map_err(|e| zip_error(&self.archive, e))?;
                let mut entry = zip.by_name(inner).map_err(|e| zip_error(&self.archive, e))?;
                let mut out = Vec::with_capacity(entry.size() as usize);
                entry.read_to_end(&mut out).at(&self.archive)?;
                Ok(out)
            }
            ArchiveFormat::Tar => {
                self.read_tar_member(BufReader::new(File::open(&self.archive).at(&self.archive)?), inner)
            }
            ArchiveFormat::TarGz => {
                let reader = flate2::read::GzDecoder::new(BufReader::new(
                    File::open(&self.archive).at(&self.archive)?,
                ));
                self.read_tar_member(reader, inner)
            }
        }
    }

    /// Up to `len` bytes of the member from `offset` (the viewer reads
    /// archives this way; the whole member is decoded each time).
    pub fn read_range(&self, inner: &str, offset: u64, len: usize) -> VfsResult<Vec<u8>> {
        let all = self.read(inner)?;
        let start = (offset as usize).min(all.len());
        let end = (start + len).min(all.len());
        Ok(all[start..end].to_vec())
    }

    /// Extracts the member (a file, or a folder with everything in it) to
    /// `dest_dir`, under its own name; answers the path written.
    pub fn extract(&self, inner: &str, dest_dir: &Path) -> VfsResult<PathBuf> {
        let name = inner.rsplit('/').next().unwrap_or(inner);
        let target = dest_dir.join(name);
        if self.is_dir(inner) {
            fs::create_dir_all(&target).at(&target)?;
            for (member, relative) in self.files_under(inner) {
                let out = dest_dir.join(&relative);
                if let Some(parent) = out.parent() {
                    fs::create_dir_all(parent).at(parent)?;
                }
                fs::write(&out, self.read(&member)?).at(&out)?;
            }
        } else {
            fs::write(&target, self.read(inner)?).at(&target)?;
        }
        Ok(target)
    }

    fn read_tar_member<R: Read>(&self, reader: R, inner: &str) -> VfsResult<Vec<u8>> {
        let mut archive = tar::Archive::new(reader);
        for entry in archive.entries().at(&self.archive)? {
            let mut entry = entry.at(&self.archive)?;
            let path = entry.path().map(|p| normalize(&p.to_string_lossy())).unwrap_or_default();
            if path == inner {
                let mut out = Vec::with_capacity(entry.size() as usize);
                entry.read_to_end(&mut out).at(&self.archive)?;
                return Ok(out);
            }
        }
        Err(VfsError::new(VfsErrorKind::NotFound, None, format!("{inner} is not in the archive")))
    }
}

fn entry_of(member: &Member, name: &str, hidden: bool) -> Entry {
    Entry {
        name: name.to_string(),
        path: PathBuf::from(&member.path),
        kind: if member.is_dir {
            EntryKind::Directory
        } else if member.is_symlink {
            EntryKind::Symlink
        } else {
            EntryKind::File
        },
        is_dir: member.is_dir,
        is_parent: false,
        symlink_target: None,
        size: if member.is_dir { None } else { Some(member.size) },
        modified_ms: member.modified_ms,
        created_ms: None,
        accessed_ms: None,
        added_ms: None,
        mode: member.mode,
        uid: 0,
        gid: 0,
        owner: String::new(),
        group: String::new(),
        flags: 0,
        is_hidden: hidden,
        extension: extension_of(name).to_string(),
        tags: Vec::new(),
    }
}

/// A member path as the index keys it: forward slashes, no `./`, no
/// leading or trailing slash.
fn normalize(raw: &str) -> String {
    let mut s = raw.replace('\\', "/");
    while let Some(rest) = s.strip_prefix("./") {
        s = rest.to_string();
    }
    s.trim_matches('/').to_string()
}

fn zip_error(archive: &Path, error: zip::result::ZipError) -> VfsError {
    match error {
        zip::result::ZipError::Io(io) => VfsError::io(&io, archive),
        zip::result::ZipError::FileNotFound => {
            VfsError::new(VfsErrorKind::NotFound, Some(archive), "member not found")
        }
        zip::result::ZipError::UnsupportedArchive(what) => VfsError::unsupported(what.to_string()),
        other => VfsError::new(VfsErrorKind::Io, Some(archive), other.to_string()),
    }
}

fn read_zip(archive: &Path) -> VfsResult<Vec<Member>> {
    let file = File::open(archive).at(archive)?;
    let mut zip = zip::ZipArchive::new(file).map_err(|e| zip_error(archive, e))?;
    let mut members = Vec::with_capacity(zip.len());
    for i in 0..zip.len() {
        let entry = match zip.by_index_raw(i) {
            Ok(e) => e,
            Err(_) => continue,
        };
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
        let mode = entry.unix_mode().unwrap_or(if entry.is_dir() { 0o40755 } else { 0o100644 });
        members.push(Member {
            is_dir: entry.is_dir(),
            is_symlink: entry.is_symlink(),
            size: entry.size(),
            modified_ms,
            mode,
            encrypted: entry.encrypted(),
            path,
        });
    }
    Ok(members)
}

fn read_tar<R: Read>(reader: R, archive: &Path) -> VfsResult<Vec<Member>> {
    let mut tar = tar::Archive::new(reader);
    let mut members = Vec::new();
    for entry in tar.entries().at(archive)? {
        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };
        let path = entry.path().map(|p| normalize(&p.to_string_lossy())).unwrap_or_default();
        if path.is_empty() {
            continue;
        }
        let header = entry.header();
        let kind = header.entry_type();
        members.push(Member {
            path,
            is_dir: kind.is_dir(),
            is_symlink: kind.is_symlink(),
            size: entry.size(),
            modified_ms: header.mtime().ok().map(|s| s as i64 * 1000),
            mode: header.mode().unwrap_or(0o644),
            encrypted: false,
        });
    }
    Ok(members)
}

/// Where extracted members go for viewing and opening: a folder per
/// archive under the system's temporary folder.
pub fn temp_dir_for(archive: &Path) -> PathBuf {
    let stem = archive
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "archive".to_string());
    let hash = archive
        .to_string_lossy()
        .bytes()
        .fold(0u64, |h, b| h.wrapping_mul(1099511628211).wrapping_add(b as u64));
    std::env::temp_dir().join("Ferryx").join(format!("{stem}-{hash:x}"))
}

/// Unused helper kept for symmetry with the native layer.
pub fn modified_ms_of(meta: &fs::Metadata) -> Option<i64> {
    meta.modified().ok().and_then(system_time_ms)
}

#[allow(dead_code)]
fn _io_marker(_: io::Error) {}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn make_zip(dir: &Path) -> PathBuf {
        let path = dir.join("a.zip");
        let file = File::create(&path).unwrap();
        let mut zip = zip::ZipWriter::new(file);
        let opts = zip::write::SimpleFileOptions::default();
        zip.start_file("top.txt", opts).unwrap();
        zip.write_all(b"top").unwrap();
        zip.start_file("dir/inner.txt", opts).unwrap();
        zip.write_all(b"inner text").unwrap();
        zip.start_file("dir/.secret", opts).unwrap();
        zip.write_all(b"s").unwrap();
        zip.finish().unwrap();
        path
    }

    #[test]
    fn zip_lists_and_reads() {
        let dir = tempfile::tempdir().unwrap();
        let path = make_zip(dir.path());
        let index = ArchiveIndex::open(&path).unwrap();
        let root = index.list("", true, false).unwrap();
        let names: Vec<&str> = root.iter().map(|e| e.name.as_str()).collect();
        assert_eq!(names, ["..", "dir", "top.txt"]);
        assert!(root[1].is_dir);
        let inside = index.list("dir", true, false).unwrap();
        assert_eq!(inside.iter().map(|e| e.name.as_str()).collect::<Vec<_>>(), ["..", "inner.txt"]);
        assert_eq!(inside[0].path, PathBuf::from(""));
        let all = index.list("dir", false, true).unwrap();
        assert_eq!(all.len(), 2);
        assert_eq!(index.read("dir/inner.txt").unwrap(), b"inner text");
        assert_eq!(index.read_range("dir/inner.txt", 6, 100).unwrap(), b"text");
        assert!(index.read("dir").is_err());
        assert!(index.list("top.txt", true, false).is_err());
        let out = tempfile::tempdir().unwrap();
        let extracted = index.extract("dir", out.path()).unwrap();
        assert!(extracted.join("inner.txt").exists());
        assert!(extracted.join(".secret").exists());
        let one = index.extract("top.txt", out.path()).unwrap();
        assert_eq!(fs::read(one).unwrap(), b"top");
        assert!(!index.is_stale());
    }

    #[test]
    fn tar_gz_lists() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.join_tgz();
        let index = ArchiveIndex::open(&path).unwrap();
        let root = index.list("", false, false).unwrap();
        assert_eq!(root.iter().map(|e| e.name.as_str()).collect::<Vec<_>>(), ["d", "x.txt"]);
        assert_eq!(index.read("d/y.txt").unwrap(), b"yy");
        assert_eq!(format_of(Path::new("a.TGZ")), Some(ArchiveFormat::TarGz));
        assert_eq!(format_of(Path::new("a.txt")), None);
    }

    trait Tgz {
        fn join_tgz(&self) -> PathBuf;
    }

    impl Tgz for tempfile::TempDir {
        fn join_tgz(&self) -> PathBuf {
            let path = self.path().join("t.tar.gz");
            let file = File::create(&path).unwrap();
            let gz = flate2::write::GzEncoder::new(file, flate2::Compression::fast());
            let mut tar = tar::Builder::new(gz);
            let mut header = tar::Header::new_gnu();
            header.set_size(2);
            header.set_mode(0o644);
            header.set_cksum();
            tar.append_data(&mut header, "./x.txt", &b"xx"[..]).unwrap();
            let mut header = tar::Header::new_gnu();
            header.set_size(2);
            header.set_mode(0o644);
            header.set_cksum();
            tar.append_data(&mut header, "d/y.txt", &b"yy"[..]).unwrap();
            tar.into_inner().unwrap().finish().unwrap();
            path
        }
    }
}
