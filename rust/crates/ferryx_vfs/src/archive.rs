//! Archives browsed as read-only folders: zip (jar, apk…), tar alone or
//! compressed with gzip, bzip2, xz or zstd, 7z, rar, ISO 9660 images
//! (with Joliet or Rock Ridge names), and one file compressed with gzip,
//! bzip2, xz or zstd (an archive of one member, named without the
//! compression's extension).
//!
//! An [`ArchiveIndex`] reads the member list once — from the directory
//! where the format keeps one (zip, 7z, rar, iso), in one pass over the
//! stream where it has none (tar) — and keeps it sorted by path with each
//! folder's children, so a folder lists in the time its own rows take and
//! a subtree is one contiguous run. Members are read back streaming
//! ([`ArchiveIndex::extract_members`]): a tar stream in one pass whatever
//! the number of members, a 7z block decoded once for all it holds.
//!
//! [`shared`] keeps the indexes read lately and the passwords given, for
//! the whole process: a panel, the viewer and an extraction share one
//! index per archive, read again when the file changed.

mod detect;
mod formats;
mod iso;
pub mod shared;
mod view_cache;

use std::cell::RefCell;
use std::collections::{HashMap, VecDeque};
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock};
use std::time::SystemTime;

use ferryx_core::entry::{extension_of, split_name, Entry, EntryKind};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};

use crate::error::{IoAt, VfsError, VfsErrorKind, VfsResult};

pub use detect::detect;

/// How a stream is compressed.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Compression {
    None,
    Gzip,
    Bzip2,
    Xz,
    Zstd,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ArchiveFormat {
    Zip,
    /// A tar stream, compressed or not.
    Tar(Compression),
    SevenZip,
    Rar,
    Iso,
    /// One file compressed: an archive of one member.
    Single(Compression),
}

/// The format a file's name says it is, or `None` for files that are not
/// archives Ferryx opens. [`detect`] reads the file's first bytes too.
pub fn format_of(path: &Path) -> Option<ArchiveFormat> {
    use ArchiveFormat::*;
    use Compression as C;
    let name = path.file_name()?.to_string_lossy().to_lowercase();
    let ends = |suffixes: &[&str]| suffixes.iter().any(|s| name.ends_with(s));
    let format = if ends(&[".tar.gz", ".tgz", ".taz"]) {
        Tar(C::Gzip)
    } else if ends(&[".tar.bz2", ".tbz2", ".tbz", ".tb2"]) {
        Tar(C::Bzip2)
    } else if ends(&[".tar.xz", ".txz"]) {
        Tar(C::Xz)
    } else if ends(&[".tar.zst", ".tar.zstd", ".tzst"]) {
        Tar(C::Zstd)
    } else if ends(&[".tar"]) {
        Tar(C::None)
    } else if ends(&[".zip", ".jar", ".ipa", ".apk", ".whl"]) {
        Zip
    } else if ends(&[".7z"]) {
        SevenZip
    } else if ends(&[".rar"]) {
        Rar
    } else if ends(&[".iso"]) {
        Iso
    } else if ends(&[".gz"]) {
        Single(C::Gzip)
    } else if ends(&[".bz2"]) {
        Single(C::Bzip2)
    } else if ends(&[".xz"]) {
        Single(C::Xz)
    } else if ends(&[".zst", ".zstd"]) {
        Single(C::Zstd)
    } else {
        return None;
    };
    Some(format)
}

/// Whether `path` is an archive a panel enters on Return. By the name
/// only: no I/O, so it is cheap enough to ask for any row.
pub fn is_archive(path: &Path) -> bool {
    format_of(path).is_some()
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Member {
    /// `/`-separated, no leading or trailing slash, no `.` or `..`.
    pub path: String,
    pub is_dir: bool,
    pub is_symlink: bool,
    /// Bytes when unpacked; 0 when the format does not say (a gzip of
    /// 4 GiB or more, a bzip2 stream).
    pub size: u64,
    pub modified_ms: Option<i64>,
    pub mode: u32,
    pub encrypted: bool,
    /// The member's number in the format's own list (zip, 7z and rar
    /// index; the extents' slot of an iso); `None` for folders the paths
    /// only imply.
    pub native: Option<u64>,
    /// Where a symbolic link points, when its header says (tar, rar);
    /// a zip or 7z link keeps it as its data.
    pub link: Option<String>,
}

impl Member {
    fn folder(path: String) -> Member {
        Member {
            path,
            is_dir: true,
            is_symlink: false,
            size: 0,
            modified_ms: None,
            mode: 0o40755,
            encrypted: false,
            native: None,
            link: None,
        }
    }

    /// The last component of the path.
    pub fn name(&self) -> &str {
        self.path.rsplit('/').next().unwrap_or(&self.path)
    }
}

/// What the members are read back with, besides the file itself.
pub(crate) enum Backing {
    Plain,
    /// The parsed 7z headers, so a member is found without reading them
    /// again (they may be encrypted).
    SevenZip(Box<sevenz_rust2::Archive>),
    /// The extents of each iso member, by [`Member::native`].
    Iso(Vec<Vec<(u64, u64)>>),
}

/// The member list of one archive.
pub struct ArchiveIndex {
    pub archive: PathBuf,
    pub format: ArchiveFormat,
    /// Every member, folders the paths imply included, sorted by path.
    members: Vec<Member>,
    /// The children of each member (folders only), as indices.
    children: Vec<Vec<u32>>,
    /// The members at the root.
    root: Vec<u32>,
    /// The archive file's modification time and length when read: a
    /// changed file is read again.
    pub file_modified: Option<SystemTime>,
    pub file_len: u64,
    /// Some member's data is encrypted.
    pub encrypted: bool,
    /// The member list itself is encrypted (7z `-mhe`, rar `-hp`): it was
    /// read with a password.
    pub headers_encrypted: bool,
    backing: Backing,
}

impl std::fmt::Debug for ArchiveIndex {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ArchiveIndex")
            .field("archive", &self.archive)
            .field("format", &self.format)
            .field("members", &self.members.len())
            .finish_non_exhaustive()
    }
}

/// Where an extraction's bytes go, member by member; see
/// [`ArchiveIndex::extract_members`].
pub trait MemberSink {
    /// Whether to read `member` (`false` passes it by); `Err(Stop)` ends
    /// the extraction.
    fn begin(&mut self, member: &Member) -> Result<bool, Stop>;

    /// The next bytes of the member begun. An error ends the member.
    fn write(&mut self, bytes: &[u8]) -> io::Result<()>;

    /// The member begun ended: `outcome` is its byte count, or why it
    /// could not be read or written.
    fn end(&mut self, member: &Member, outcome: VfsResult<u64>) -> Result<(), Stop>;
}

/// A sink as a writer, for the readers that push their bytes.
pub(crate) struct SinkWriter<'a>(pub &'a mut dyn MemberSink);

impl Write for SinkWriter<'_> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.0.write(buf)?;
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

/// A sink's request to stop an extraction.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Stop;

/// Why an extraction ended early.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ExtractError {
    /// The sink asked to stop.
    Stopped,
    /// The archive could not be read on (a broken stream, a wrong
    /// password for the member list).
    Failed(VfsError),
}

impl From<VfsError> for ExtractError {
    fn from(e: VfsError) -> Self {
        ExtractError::Failed(e)
    }
}

impl From<Stop> for ExtractError {
    fn from(_: Stop) -> Self {
        ExtractError::Stopped
    }
}

impl ArchiveIndex {
    /// Reads the member list of `archive`. An encrypted list answers a
    /// [`VfsErrorKind::PasswordRequired`] error: see [`Self::open_with`].
    pub fn open(archive: &Path) -> VfsResult<ArchiveIndex> {
        ArchiveIndex::open_with(archive, None)
    }

    /// Reads the member list with `password` for an encrypted one.
    pub fn open_with(archive: &Path, password: Option<&str>) -> VfsResult<ArchiveIndex> {
        let format = detect(archive)?.ok_or_else(|| {
            VfsError::new(
                VfsErrorKind::Unsupported,
                Some(archive),
                format!("{} is not an archive Ferryx opens", archive.display()),
            )
        })?;
        let meta = fs::metadata(archive).at(archive)?;
        let listed = match format {
            ArchiveFormat::Zip => formats::list_zip(archive)?,
            ArchiveFormat::Tar(compression) => formats::list_tar(archive, compression)?,
            ArchiveFormat::SevenZip => formats::list_7z(archive, password)?,
            ArchiveFormat::Rar => formats::list_rar(archive, password)?,
            ArchiveFormat::Iso => iso::list(archive)?,
            ArchiveFormat::Single(compression) => formats::list_single(archive, compression)?,
        };
        let (members, children, root) = arrange(listed.members);
        Ok(ArchiveIndex {
            archive: archive.to_path_buf(),
            format,
            encrypted: members.iter().any(|m| m.encrypted),
            members,
            children,
            root,
            file_modified: meta.modified().ok(),
            file_len: meta.len(),
            headers_encrypted: listed.headers_encrypted,
            backing: listed.backing,
        })
    }

    /// Whether the archive file changed since the index was read.
    pub fn is_stale(&self) -> bool {
        match fs::metadata(&self.archive) {
            Ok(meta) => meta.modified().ok() != self.file_modified || meta.len() != self.file_len,
            Err(_) => true,
        }
    }

    /// The number of members, folders included.
    pub fn len(&self) -> usize {
        self.members.len()
    }

    pub fn is_empty(&self) -> bool {
        self.members.is_empty()
    }

    fn position(&self, inner: &str) -> Option<usize> {
        self.members.binary_search_by(|m| m.path.as_str().cmp(inner)).ok()
    }

    pub fn member(&self, inner: &str) -> Option<&Member> {
        self.position(inner).map(|i| &self.members[i])
    }

    pub fn is_dir(&self, inner: &str) -> bool {
        inner.is_empty() || self.member(inner).map(|m| m.is_dir).unwrap_or(false)
    }

    /// The members at the archive's root.
    pub fn top_level(&self) -> impl Iterator<Item = &Member> {
        self.root.iter().map(|&i| &self.members[i as usize])
    }

    fn children_of(&self, inner: &str) -> Option<&[u32]> {
        if inner.is_empty() {
            return Some(&self.root);
        }
        let at = self.position(inner)?;
        self.members[at].is_dir.then(|| self.children[at].as_slice())
    }

    /// The rows of the folder `inner` (empty for the root), with the `..`
    /// row when asked; entries' paths are member paths.
    pub fn list(&self, inner: &str, show_parent: bool, show_hidden: bool) -> VfsResult<Vec<Entry>> {
        let children = self.children_of(inner).ok_or_else(|| {
            VfsError::new(
                VfsErrorKind::NotADirectory,
                None,
                format!("{inner} is not a folder in the archive"),
            )
        })?;
        let mut out = Vec::with_capacity(children.len() + 1);
        if show_parent {
            let parent = match inner.rfind('/') {
                Some(at) => inner[..at].to_string(),
                None => String::new(),
            };
            out.push(Entry::parent(PathBuf::from(parent)));
        }
        for &child in children {
            let member = &self.members[child as usize];
            let name = member.name();
            let hidden = name.starts_with('.');
            if hidden && !show_hidden {
                continue;
            }
            out.push(entry_of(member, name, hidden));
        }
        Ok(out)
    }

    /// The members under the folder `inner`, its subfolders' too: the
    /// run of the sorted list that starts with `inner/`.
    fn subtree(&self, inner: &str) -> &[Member] {
        if inner.is_empty() {
            return &self.members;
        }
        let prefix = format!("{inner}/");
        let start = self.members.partition_point(|m| m.path.as_str() < prefix.as_str());
        let len = self.members[start..].partition_point(|m| m.path.starts_with(&prefix));
        &self.members[start..start + len]
    }

    /// Every file under the folder `inner` with its folder relative to
    /// `inner` (empty for its own files), for a flat view; members inside
    /// a hidden folder are hidden too.
    pub fn files_in_subtree(&self, inner: &str, show_hidden: bool) -> Vec<(Entry, String)> {
        self.files_in_subtree_until(inner, show_hidden, &|| false).collect()
    }

    /// The flat view's rows, made only as requested and stopped even
    /// while passing over folders or hidden members.
    pub fn files_in_subtree_until<'a>(
        &'a self,
        inner: &str,
        show_hidden: bool,
        stop: &'a dyn Fn() -> bool,
    ) -> impl Iterator<Item = (Entry, String)> + 'a {
        let skip = if inner.is_empty() { 0 } else { inner.len() + 1 };
        self.subtree(inner).iter().take_while(move |_| !stop()).filter_map(move |member| {
            if member.is_dir {
                return None;
            }
            let relative = &member.path[skip..];
            let hidden = relative.split('/').any(|c| c.starts_with('.'));
            if hidden && !show_hidden {
                return None;
            }
            let (folder, name) = match relative.rfind('/') {
                Some(at) => (&relative[..at], &relative[at + 1..]),
                None => ("", relative),
            };
            Some((entry_of(member, name, name.starts_with('.')), folder.to_string()))
        })
    }

    /// Every file member under `inner` (or the member itself), for an
    /// extraction: `(member path, path relative to inner's folder)`.
    pub fn files_under(&self, inner: &str) -> Vec<(String, String)> {
        let base = match inner.rfind('/') {
            Some(at) => at + 1,
            None => 0,
        };
        let own =
            self.member(inner).filter(|m| !m.is_dir).map(|m| (m.path.clone(), m.path[base..].to_string()));
        let under = self
            .subtree(inner)
            .iter()
            .filter(|m| !m.is_dir)
            .map(|m| (m.path.clone(), m.path[base..].to_string()));
        own.into_iter().chain(under).collect()
    }

    /// The folders under `inner` (and `inner` itself when it is one), with
    /// their paths relative to inner's folder: an extraction makes them
    /// all, the empty ones too.
    pub fn folders_under(&self, inner: &str) -> Vec<String> {
        let base = match inner.rfind('/') {
            Some(at) => at + 1,
            None => 0,
        };
        let own = (!inner.is_empty() && self.is_dir(inner)).then(|| inner[base..].to_string());
        let under = self.subtree(inner).iter().filter(|m| m.is_dir).map(|m| m.path[base..].to_string());
        own.into_iter().chain(under).collect()
    }

    /// The bytes and the number of files under each of `inners`.
    pub fn totals(&self, inners: &[String]) -> (u64, u64) {
        let mut bytes = 0;
        let mut files = 0;
        for inner in inners {
            for (member, _) in self.files_under(inner) {
                files += 1;
                bytes += self.member(&member).map(|m| m.size).unwrap_or(0);
            }
        }
        (bytes, files)
    }

    /// The smallest file member whose data is encrypted: the cheapest to
    /// try a password on.
    fn smallest_encrypted(&self) -> Option<&Member> {
        self.members.iter().filter(|m| m.encrypted && !m.is_dir).min_by_key(|m| m.size)
    }

    /// Whether `password` opens the archive: the member list when it is
    /// encrypted, else the smallest encrypted member's first bytes.
    pub fn check_password(&self, password: &str) -> VfsResult<()> {
        if self.headers_encrypted {
            return ArchiveIndex::open_with(&self.archive, Some(password)).map(|_| ());
        }
        let Some(member) = self.smallest_encrypted() else { return Ok(()) };
        const LIMIT: usize = 64 * 1024;
        let mut probe = Probe { left: LIMIT };
        // As much as the member has, up to the limit: a wrong key's garbage
        // may also read as a stream that ends early, with no error at all.
        let expected = usize::try_from(member.size).unwrap_or(usize::MAX).min(LIMIT);
        match self.read_member_to(&member.path, Some(password), &mut probe) {
            Ok(_) | Err(VfsError { kind: VfsErrorKind::Cancelled, .. }) if LIMIT - probe.left >= expected => {
                Ok(())
            }
            Ok(_) => Err(VfsError::wrong_password(&self.archive)),
            Err(e) if e.kind == VfsErrorKind::Cancelled => Ok(()),
            Err(e) if e.kind == VfsErrorKind::WrongPassword => Err(e),
            // Garbage out of a wrong key breaks the decoder or the check.
            Err(_) => Err(VfsError::wrong_password(&self.archive)),
        }
    }

    /// Streams the files among `wanted` (member paths) to `sink`, in the
    /// archive's own order: a tar stream is read once, a 7z block decoded
    /// once for all its members, a rar archive in member order, zip
    /// members and iso extents forward through the file.
    pub fn extract_members(
        &self,
        wanted: &[String],
        password: Option<&str>,
        sink: &mut dyn MemberSink,
    ) -> Result<(), ExtractError> {
        let mut picked: Vec<usize> =
            wanted.iter().filter_map(|p| self.position(p)).filter(|&i| !self.members[i].is_dir).collect();
        picked.sort_unstable();
        picked.dedup();
        if picked.is_empty() {
            return Ok(());
        }
        let job = formats::Job { index: self, picked: &picked, password };
        match self.format {
            ArchiveFormat::Zip => formats::extract_zip(&job, sink),
            ArchiveFormat::Tar(compression) => formats::extract_tar(&job, compression, sink),
            ArchiveFormat::SevenZip => formats::extract_7z(&job, sink),
            ArchiveFormat::Rar => formats::extract_rar(&job, sink),
            ArchiveFormat::Iso => iso::extract(&job, sink),
            ArchiveFormat::Single(compression) => formats::extract_single(&job, compression, sink),
        }
    }

    /// Writes the file member `inner` to `out`; answers its byte count.
    pub fn read_member_to(&self, inner: &str, password: Option<&str>, out: &mut dyn Write) -> VfsResult<u64> {
        let member = self.member(inner).ok_or_else(|| not_in_archive(inner))?;
        if member.is_dir {
            return Err(VfsError::new(VfsErrorKind::IsADirectory, None, format!("{inner} is a folder")));
        }
        let mut sink = WriterSink { out, outcome: None };
        let result = self.extract_members(&[inner.to_string()], password, &mut sink);
        match (sink.outcome.take(), result) {
            (Some(outcome), _) => outcome,
            (None, Err(ExtractError::Failed(e))) => Err(e),
            (None, _) => Err(not_in_archive(inner)),
        }
    }

    /// The whole member as bytes.
    pub fn read(&self, inner: &str) -> VfsResult<Vec<u8>> {
        self.read_with(inner, None)
    }

    pub fn read_with(&self, inner: &str, password: Option<&str>) -> VfsResult<Vec<u8>> {
        let mut out =
            Vec::with_capacity(self.member(inner).map(|m| m.size.min(1 << 24) as usize).unwrap_or(0));
        self.read_member_to(inner, password, &mut out)?;
        Ok(out)
    }

    /// Up to `len` bytes of the member from `offset`. A small member is
    /// decoded whole (and kept for the next window where that decodes what
    /// comes before it too); a large one is unpacked once to the temporary
    /// folder and read from there, so the viewer's windows do not decode
    /// it from the start each time.
    pub fn read_range(
        &self,
        inner: &str,
        offset: u64,
        len: usize,
        password: Option<&str>,
    ) -> VfsResult<Vec<u8>> {
        const DECODE_WHOLE: u64 = 4 * 1024 * 1024;
        let member = self.member(inner).ok_or_else(|| not_in_archive(inner))?;
        if member.size > DECODE_WHOLE || (member.size == 0 && !member.is_dir) {
            let unpacked = self.unpacked_copy(inner, password)?;
            return unpacked.read_range(offset, len);
        }
        let all = self.decoded(inner, password)?;
        let start = usize::try_from(offset).unwrap_or(usize::MAX).min(all.len());
        let end = start.saturating_add(len).min(all.len());
        Ok(all[start..end].to_vec())
    }

    /// A small member's bytes. Where reading one decodes everything before
    /// it (a compressed tar, a 7z or rar block, a compressed file), the
    /// last few are kept, keyed by the archive's version and the password.
    fn decoded(&self, inner: &str, password: Option<&str>) -> VfsResult<Arc<Vec<u8>>> {
        let streamed = match self.format {
            ArchiveFormat::Tar(compression) => compression != Compression::None,
            ArchiveFormat::SevenZip | ArchiveFormat::Rar | ArchiveFormat::Single(_) => true,
            ArchiveFormat::Zip | ArchiveFormat::Iso => false,
        };
        if !streamed {
            return self.read_with(inner, password).map(Arc::new);
        }
        let key = DecodedKey {
            archive: self.archive.clone(),
            modified: self.file_modified,
            len: self.file_len,
            inner: inner.to_string(),
            password: password.map(str::to_string),
        };
        if let Some((_, bytes)) = DECODED.lock().iter().find(|(k, _)| *k == key) {
            return Ok(bytes.clone());
        }
        let bytes = Arc::new(self.read_with(inner, password)?);
        let mut kept = DECODED.lock();
        kept.retain(|(k, _)| *k != key);
        kept.push_back((key, bytes.clone()));
        while kept.len() > DECODED_KEPT {
            kept.pop_front();
        }
        Ok(bytes)
    }

    /// The member's size: the index's, or the unpacked copy's when the
    /// format does not say.
    pub fn member_size(&self, inner: &str, password: Option<&str>) -> VfsResult<u64> {
        let member = self.member(inner).ok_or_else(|| not_in_archive(inner))?;
        if member.size > 0 || member.is_dir {
            return Ok(member.size);
        }
        let unpacked = self.unpacked_copy(inner, password)?;
        Ok(unpacked.bytes)
    }

    /// The member unpacked under the temporary folder, made once per
    /// version of the archive.
    fn unpacked_copy(&self, inner: &str, password: Option<&str>) -> VfsResult<Arc<view_cache::Unpacked>> {
        let key = DecodedKey {
            archive: self.archive.clone(),
            modified: self.file_modified,
            len: self.file_len,
            inner: inner.to_string(),
            password: password.map(str::to_string),
        };
        view_cache::unpacked(key, |file| self.read_member_to(inner, password, file))
    }

    /// Extracts the member (a file, or a folder with everything in it) to
    /// `dest_dir`, under its own name; answers the path written.
    pub fn extract(&self, inner: &str, dest_dir: &Path) -> VfsResult<PathBuf> {
        self.extract_with(inner, dest_dir, None)
    }

    pub fn extract_with(&self, inner: &str, dest_dir: &Path, password: Option<&str>) -> VfsResult<PathBuf> {
        let name = inner.rsplit('/').next().unwrap_or(inner);
        let target = dest_dir.join(name);
        if !self.is_dir(inner) {
            let mut file = io::BufWriter::new(File::create(&target).at(&target)?);
            self.read_member_to(inner, password, &mut file)?;
            file.flush().at(&target)?;
            return Ok(target);
        }
        fs::create_dir_all(&target).at(&target)?;
        for folder in self.folders_under(inner) {
            let path = dest_dir.join(folder);
            fs::create_dir_all(&path).at(&path)?;
        }
        let files = self.files_under(inner);
        let wanted: Vec<String> = files.iter().map(|(m, _)| m.clone()).collect();
        let targets: HashMap<String, PathBuf> =
            files.into_iter().map(|(m, relative)| (m, dest_dir.join(relative))).collect();
        let mut sink = FileSink { targets, open: None, failure: None };
        if let Err(ExtractError::Failed(e)) = self.extract_members(&wanted, password, &mut sink) {
            return Err(e);
        }
        match sink.failure {
            Some(e) => Err(e),
            None => Ok(target),
        }
    }
}

/// Which small member, decoded, [`ArchiveIndex::decoded`] keeps.
#[derive(Clone, PartialEq, Eq, Hash)]
struct DecodedKey {
    archive: PathBuf,
    modified: Option<SystemTime>,
    len: u64,
    inner: String,
    password: Option<String>,
}

/// How many decoded members stay in memory (4 MiB each at most).
const DECODED_KEPT: usize = 2;

/// The small members decoded lately, the most recent last.
type DecodedMembers = VecDeque<(DecodedKey, Arc<Vec<u8>>)>;

static DECODED: LazyLock<Mutex<DecodedMembers>> = LazyLock::new(|| Mutex::new(VecDeque::new()));

fn not_in_archive(inner: &str) -> VfsError {
    VfsError::new(VfsErrorKind::NotFound, None, format!("{inner} is not in the archive"))
}

/// Writes members to files at the paths given; the first failure stops.
struct FileSink {
    targets: HashMap<String, PathBuf>,
    open: Option<io::BufWriter<File>>,
    failure: Option<VfsError>,
}

impl MemberSink for FileSink {
    fn begin(&mut self, member: &Member) -> Result<bool, Stop> {
        let Some(target) = self.targets.get(&member.path) else { return Ok(false) };
        if let Some(parent) = target.parent() {
            if let Err(e) = fs::create_dir_all(parent) {
                self.failure = Some(VfsError::io(&e, parent));
                return Err(Stop);
            }
        }
        match File::create(target) {
            Ok(file) => {
                self.open = Some(io::BufWriter::new(file));
                Ok(true)
            }
            Err(e) => {
                self.failure = Some(VfsError::io(&e, target));
                Err(Stop)
            }
        }
    }

    fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
        match self.open.as_mut() {
            Some(file) => file.write_all(bytes),
            None => Ok(()),
        }
    }

    fn end(&mut self, _: &Member, outcome: VfsResult<u64>) -> Result<(), Stop> {
        let flushed = self.open.take().map(|mut f| f.flush()).unwrap_or(Ok(()));
        match (outcome, flushed) {
            (Err(e), _) => {
                self.failure = Some(e);
                Err(Stop)
            }
            (Ok(_), Err(e)) => {
                self.failure = Some(VfsError::new(VfsErrorKind::Io, None, e.to_string()));
                Err(Stop)
            }
            (Ok(_), Ok(())) => Ok(()),
        }
    }
}

/// One member into a writer, for [`ArchiveIndex::read_member_to`].
struct WriterSink<'a> {
    out: &'a mut dyn Write,
    outcome: Option<VfsResult<u64>>,
}

impl MemberSink for WriterSink<'_> {
    fn begin(&mut self, _: &Member) -> Result<bool, Stop> {
        Ok(true)
    }

    fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
        self.out.write_all(bytes)
    }

    fn end(&mut self, _: &Member, outcome: VfsResult<u64>) -> Result<(), Stop> {
        self.outcome = Some(match outcome {
            Err(e) if e.message.contains(PROBE_FULL) => {
                Err(VfsError::new(VfsErrorKind::Cancelled, None, PROBE_FULL))
            }
            other => other,
        });
        Err(Stop)
    }
}

/// A writer that takes a limited number of bytes and then fails: enough
/// to try a password on.
struct Probe {
    left: usize,
}

impl Write for Probe {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        if self.left == 0 {
            return Err(io::Error::other(PROBE_FULL));
        }
        let n = buf.len().min(self.left);
        self.left -= n;
        Ok(n)
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

const PROBE_FULL: &str = "enough read";

/// What a format's listing gives.
pub(crate) struct Listed {
    pub members: Vec<Member>,
    pub headers_encrypted: bool,
    pub backing: Backing,
}

impl Listed {
    pub fn plain(members: Vec<Member>) -> Listed {
        Listed { members, headers_encrypted: false, backing: Backing::Plain }
    }
}

/// Sorts the members by path, adds the folders their paths imply, and
/// finds each folder's children. A path met twice keeps the last member
/// (a tar appended to); an explicit folder keeps its own time and mode.
fn arrange(listed: Vec<Member>) -> (Vec<Member>, Vec<Vec<u32>>, Vec<u32>) {
    let mut by_path: HashMap<String, usize> = HashMap::with_capacity(listed.len());
    let mut members: Vec<Member> = Vec::with_capacity(listed.len());
    for member in listed {
        if member.path.is_empty() {
            continue;
        }
        let mut at = 0;
        while let Some(slash) = member.path[at..].find('/') {
            let dir = &member.path[..at + slash];
            if !by_path.contains_key(dir) {
                by_path.insert(dir.to_string(), members.len());
                members.push(Member::folder(dir.to_string()));
            }
            at += slash + 1;
        }
        match by_path.get(&member.path) {
            Some(&existing) if members[existing].is_dir && member.is_dir => {
                if member.modified_ms.is_some() {
                    members[existing].modified_ms = member.modified_ms;
                    members[existing].mode = member.mode;
                }
            }
            Some(&existing) => members[existing] = member,
            None => {
                by_path.insert(member.path.clone(), members.len());
                members.push(member);
            }
        }
    }
    drop(by_path);
    members.sort_unstable_by(|a, b| a.path.cmp(&b.path));
    let mut children = vec![Vec::new(); members.len()];
    let mut root = Vec::new();
    for (i, member) in members.iter().enumerate() {
        match member.path.rfind('/') {
            None => root.push(i as u32),
            Some(at) => {
                let parent = &member.path[..at];
                if let Ok(p) = members.binary_search_by(|m| m.path.as_str().cmp(parent)) {
                    children[p].push(i as u32);
                }
            }
        }
    }
    (members, children, root)
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

/// A member path as the index keys it: forward slashes, no `.` or `..`
/// components (an archive cannot write outside the folder it is
/// extracted to), no leading or trailing slash.
pub(crate) fn normalize(raw: &str) -> String {
    let unified = raw.replace('\\', "/");
    let parts: Vec<&str> =
        unified.split('/').filter(|part| !part.is_empty() && *part != "." && *part != "..").collect();
    parts.join("/")
}

/// The name of the one member of a compressed file: the file's name
/// without the compression's extension.
pub(crate) fn single_member_name(archive: &Path) -> String {
    let name = archive.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let (stem, _) = split_name(&name);
    if stem.is_empty() || stem == name {
        format!("{name}.out")
    } else {
        stem.to_string()
    }
}

/// The archive's name without its archive extensions (`site.tar.gz` →
/// `site`): the folder an extraction into a folder of its own makes.
pub fn archive_stem(archive: &Path) -> String {
    let name = archive.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let lower = name.to_lowercase();
    for suffix in [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.zstd"] {
        if lower.ends_with(suffix) && lower.len() > suffix.len() {
            return name[..name.len() - suffix.len()].to_string();
        }
    }
    let (stem, _) = split_name(&name);
    if stem.is_empty() {
        name
    } else {
        stem.to_string()
    }
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

/// Copies `reader` into `writer` in large steps; answers the bytes. The
/// buffer is the thread's own, kept: an archive of many small members
/// would otherwise take a fresh one from the system for each.
pub(crate) fn pump(reader: &mut dyn Read, writer: &mut dyn Write) -> io::Result<u64> {
    thread_local! {
        static BUFFER: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
    }
    BUFFER.with(|cell| {
        // A writer that pumps again in turn gets a buffer of its own.
        let mut owned = Vec::new();
        let mut borrowed = cell.try_borrow_mut();
        let buffer = match borrowed.as_deref_mut() {
            Ok(buffer) => buffer,
            Err(_) => &mut owned,
        };
        buffer.resize(256 * 1024, 0);
        let mut total = 0u64;
        loop {
            let n = match reader.read(buffer) {
                Ok(0) => return Ok(total),
                Ok(n) => n,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(e),
            };
            writer.write_all(&buffer[..n])?;
            total += n as u64;
        }
    })
}

#[cfg(test)]
mod tests;
