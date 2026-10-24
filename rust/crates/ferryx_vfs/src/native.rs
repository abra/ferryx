//! The real file system: a folder's rows, one entry, a file's bytes.

use std::collections::HashMap;
use std::fs::{self, Metadata};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::LazyLock;
use std::time::SystemTime;

use ferryx_core::entry::{extension_of, Entry, EntryKind};
use parking_lot::Mutex;

use crate::error::{IoAt, VfsError, VfsErrorKind, VfsResult};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ListOptions {
    pub show_hidden: bool,
    /// The `..` row, leading to the parent, when there is one.
    pub show_parent: bool,
}

impl Default for ListOptions {
    fn default() -> Self {
        ListOptions { show_hidden: false, show_parent: true }
    }
}

/// The rows of the folder at `dir`, unsorted. Names the file system
/// cannot spell in Unicode are read lossily.
pub fn list_dir(dir: &Path, opts: &ListOptions) -> VfsResult<Vec<Entry>> {
    let read = fs::read_dir(dir).at(dir)?;
    let mut names = Names::default();
    let mut entries = Vec::new();
    if opts.show_parent {
        if let Some(parent) = dir.parent() {
            entries.push(Entry::parent(parent.to_path_buf()));
        }
    }
    for item in read {
        let item = match item {
            Ok(item) => item,
            Err(_) => continue,
        };
        let path = item.path();
        let name = item.file_name().to_string_lossy().into_owned();
        let meta = match fs::symlink_metadata(&path) {
            Ok(meta) => meta,
            Err(_) => continue,
        };
        let entry = build_entry(name, path, &meta, &mut names);
        if !opts.show_hidden && entry.is_hidden {
            continue;
        }
        entries.push(entry);
    }
    Ok(entries)
}

/// The owner and group names of single items ([`stat`]), looked up once
/// per id while the app runs; a listing keeps names of its own.
static NAMES: LazyLock<Mutex<Names>> = LazyLock::new(Mutex::default);

/// One entry, as a listing would show it.
pub fn stat(path: &Path) -> VfsResult<Entry> {
    let meta = fs::symlink_metadata(path).at(path)?;
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string_lossy().into_owned());
    let mut entry = build_entry(name, path.to_path_buf(), &meta, &mut NAMES.lock());
    // One item's tags cost nothing to read; a listing's come apart (see
    // `tags`).
    entry.tags = crate::tags::read(path);
    Ok(entry)
}

/// Whether `path` is a folder, following a symlink.
pub fn is_dir(path: &Path) -> bool {
    fs::metadata(path).map(|m| m.is_dir()).unwrap_or(false)
}

/// The entry of `path` from metadata already read (`symlink_metadata`),
/// as a listing would show it; for a walk that has the metadata in hand.
pub fn entry_from_metadata(name: String, path: PathBuf, meta: &Metadata, names: &mut Names) -> Entry {
    build_entry(name, path, meta, names)
}

fn build_entry(name: String, path: PathBuf, meta: &Metadata, names: &mut Names) -> Entry {
    let file_type = meta.file_type();
    let is_symlink = file_type.is_symlink();
    let (kind, is_dir, target) = if is_symlink {
        let target = fs::read_link(&path).ok().map(|t| t.to_string_lossy().into_owned());
        let points_to_dir = fs::metadata(&path).map(|m| m.is_dir()).unwrap_or(false);
        (EntryKind::Symlink, points_to_dir, target)
    } else if file_type.is_dir() {
        (EntryKind::Directory, true, None)
    } else if file_type.is_file() {
        (EntryKind::File, false, None)
    } else {
        (EntryKind::Other, false, None)
    };
    let flags = bsd_flags(meta);
    let is_hidden = name.starts_with('.') || flags & UF_HIDDEN != 0;
    let (uid, gid, mode) = ids(meta);
    Entry {
        extension: extension_of(&name).to_string(),
        name,
        kind,
        is_dir,
        is_parent: false,
        symlink_target: target,
        size: if kind == EntryKind::Directory { None } else { Some(meta.len()) },
        modified_ms: meta.modified().ok().and_then(system_time_ms),
        created_ms: meta.created().ok().and_then(system_time_ms),
        accessed_ms: meta.accessed().ok().and_then(system_time_ms),
        added_ms: added_time_ms(&path),
        mode,
        uid,
        gid,
        owner: names.owner(uid),
        group: names.group(gid),
        flags,
        is_hidden,
        tags: Vec::new(),
        path,
    }
}

pub fn system_time_ms(time: SystemTime) -> Option<i64> {
    match time.duration_since(SystemTime::UNIX_EPOCH) {
        Ok(d) => i64::try_from(d.as_millis()).ok(),
        Err(e) => i64::try_from(e.duration().as_millis()).ok().map(|ms| -ms),
    }
}

/// `UF_HIDDEN` of the BSD file flags.
pub const UF_HIDDEN: u32 = 0x8000;

#[cfg(target_os = "macos")]
fn bsd_flags(meta: &Metadata) -> u32 {
    use std::os::macos::fs::MetadataExt;
    meta.st_flags()
}

#[cfg(not(target_os = "macos"))]
fn bsd_flags(_meta: &Metadata) -> u32 {
    0
}

#[cfg(unix)]
fn ids(meta: &Metadata) -> (u32, u32, u32) {
    use std::os::unix::fs::MetadataExt;
    (meta.uid(), meta.gid(), meta.mode())
}

#[cfg(not(unix))]
fn ids(meta: &Metadata) -> (u32, u32, u32) {
    let readonly = meta.permissions().readonly();
    let mode = if meta.is_dir() {
        0o40755
    } else if readonly {
        0o100444
    } else {
        0o100644
    };
    (0, 0, mode)
}

/// When the item was put into its folder: macOS keeps it
/// (`kMDItemDateAdded`, read with `getattrlist`).
#[cfg(target_os = "macos")]
pub fn added_time_ms(path: &Path) -> Option<i64> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;

    #[repr(C, packed)]
    struct Buffer {
        length: u32,
        added: libc::timespec,
    }

    let c_path = CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut list: libc::attrlist = unsafe { std::mem::zeroed() };
    list.bitmapcount = libc::ATTR_BIT_MAP_COUNT;
    list.commonattr = libc::ATTR_CMN_ADDEDTIME;
    let mut buffer: Buffer = unsafe { std::mem::zeroed() };
    let rc = unsafe {
        libc::getattrlist(
            c_path.as_ptr(),
            &mut list as *mut libc::attrlist as *mut libc::c_void,
            &mut buffer as *mut Buffer as *mut libc::c_void,
            std::mem::size_of::<Buffer>(),
            libc::FSOPT_NOFOLLOW,
        )
    };
    if rc != 0 || (buffer.length as usize) < std::mem::size_of::<Buffer>() {
        return None;
    }
    let added = buffer.added;
    let secs = added.tv_sec;
    let nanos = added.tv_nsec;
    if secs == 0 {
        return None;
    }
    Some(secs * 1000 + nanos / 1_000_000)
}

#[cfg(not(target_os = "macos"))]
pub fn added_time_ms(_path: &Path) -> Option<i64> {
    None
}

/// Owner and group names, looked up once per id for a listing.
#[derive(Default)]
pub struct Names {
    users: HashMap<u32, String>,
    groups: HashMap<u32, String>,
}

impl Names {
    pub fn owner(&mut self, uid: u32) -> String {
        self.users.entry(uid).or_insert_with(|| user_name(uid).unwrap_or_else(|| uid.to_string())).clone()
    }

    pub fn group(&mut self, gid: u32) -> String {
        self.groups.entry(gid).or_insert_with(|| group_name(gid).unwrap_or_else(|| gid.to_string())).clone()
    }
}

#[cfg(unix)]
pub fn user_name(uid: u32) -> Option<String> {
    nix::unistd::User::from_uid(nix::unistd::Uid::from_raw(uid)).ok().flatten().map(|u| u.name)
}

#[cfg(unix)]
pub fn group_name(gid: u32) -> Option<String> {
    nix::unistd::Group::from_gid(nix::unistd::Gid::from_raw(gid)).ok().flatten().map(|g| g.name)
}

#[cfg(not(unix))]
pub fn user_name(_uid: u32) -> Option<String> {
    None
}

#[cfg(not(unix))]
pub fn group_name(_gid: u32) -> Option<String> {
    None
}

/// The user id to name, and the reverse, for the attributes dialog.
#[cfg(unix)]
pub fn user_id(name: &str) -> Option<u32> {
    nix::unistd::User::from_name(name).ok().flatten().map(|u| u.uid.as_raw())
}

#[cfg(unix)]
pub fn group_id(name: &str) -> Option<u32> {
    nix::unistd::Group::from_name(name).ok().flatten().map(|g| g.gid.as_raw())
}

#[cfg(not(unix))]
pub fn user_id(_name: &str) -> Option<u32> {
    None
}

#[cfg(not(unix))]
pub fn group_id(_name: &str) -> Option<u32> {
    None
}

/// Up to `len` bytes of the file from `offset`; fewer at the end.
pub fn read_range(path: &Path, offset: u64, len: usize) -> VfsResult<Vec<u8>> {
    let mut file = fs::File::open(path).at(path)?;
    file.seek(SeekFrom::Start(offset)).at(path)?;
    let mut buffer = vec![0u8; len];
    let mut read = 0;
    while read < len {
        match file.read(&mut buffer[read..]) {
            Ok(0) => break,
            Ok(n) => read += n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(VfsError::io(&e, path)),
        }
    }
    buffer.truncate(read);
    Ok(buffer)
}

pub fn file_size(path: &Path) -> VfsResult<u64> {
    Ok(fs::metadata(path).at(path)?.len())
}

/// Makes the folder and every missing one above it; `New 1/New 2` from a
/// panel makes two.
pub fn create_dir_all(path: &Path) -> VfsResult<()> {
    if path.exists() {
        return Err(VfsError::new(
            VfsErrorKind::AlreadyExists,
            Some(path),
            format!("{} already exists", path.display()),
        ));
    }
    fs::create_dir_all(path).at(path)
}

/// Makes an empty file; fails when something is there already.
pub fn create_file(path: &Path) -> VfsResult<()> {
    fs::OpenOptions::new().write(true).create_new(true).open(path).at(path).map(|_| ())
}

/// Renames `path` to `new_name` in the same folder. A name with a
/// separator or empty is refused; renaming onto an existing item fails.
pub fn rename(path: &Path, new_name: &str) -> VfsResult<PathBuf> {
    if new_name.is_empty() || new_name.contains('/') || new_name == "." || new_name == ".." {
        return Err(VfsError::invalid_name(new_name));
    }
    let target = path.with_file_name(new_name);
    if target != path && target.exists() && !same_file_case_change(path, &target) {
        return Err(VfsError::new(
            VfsErrorKind::AlreadyExists,
            Some(&target),
            format!("{} already exists", target.display()),
        ));
    }
    fs::rename(path, &target).at(path)?;
    Ok(target)
}

/// `Readme` → `README` on a case-insensitive file system: the target
/// "exists" because it is the source.
fn same_file_case_change(a: &Path, b: &Path) -> bool {
    let (Some(na), Some(nb)) = (a.file_name(), b.file_name()) else { return false };
    a.parent() == b.parent()
        && na != nb
        && na.to_string_lossy().to_lowercase() == nb.to_string_lossy().to_lowercase()
}

/// Free bytes on the volume holding `path`.
#[cfg(unix)]
pub fn free_space(path: &Path) -> Option<u64> {
    let stat = nix::sys::statvfs::statvfs(path).ok()?;
    Some(stat.blocks_available() as u64 * stat.fragment_size() as u64)
}

#[cfg(not(unix))]
pub fn free_space(_path: &Path) -> Option<u64> {
    None
}

/// The device a path is on, to tell a rename from a copy across volumes.
#[cfg(unix)]
pub fn device_of(path: &Path) -> Option<u64> {
    use std::os::unix::fs::MetadataExt;
    fs::metadata(path).ok().map(|m| m.dev())
}

#[cfg(not(unix))]
pub fn device_of(path: &Path) -> Option<u64> {
    path.components().next().map(|c| {
        let s = c.as_os_str().to_string_lossy();
        s.bytes().fold(0u64, |h, b| h.wrapping_mul(31).wrapping_add(b as u64))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_a_folder_with_metadata() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("a.txt"), b"hello").unwrap();
        fs::create_dir(dir.path().join("sub")).unwrap();
        fs::write(dir.path().join(".hidden"), b"").unwrap();

        let shown = list_dir(dir.path(), &ListOptions::default()).unwrap();
        let names: Vec<&str> = shown.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&".."));
        assert!(names.contains(&"a.txt"));
        assert!(names.contains(&"sub"));
        assert!(!names.contains(&".hidden"));
        let a = shown.iter().find(|e| e.name == "a.txt").unwrap();
        assert_eq!(a.size, Some(5));
        assert_eq!(a.extension, "txt");
        assert!(a.modified_ms.is_some());
        assert!(!a.is_dir);
        let sub = shown.iter().find(|e| e.name == "sub").unwrap();
        assert!(sub.is_dir);
        assert_eq!(sub.size, None);

        let all = list_dir(dir.path(), &ListOptions { show_hidden: true, show_parent: false }).unwrap();
        assert!(all.iter().any(|e| e.name == ".hidden" && e.is_hidden));
        assert!(!all.iter().any(|e| e.is_parent));
    }

    #[test]
    fn reads_ranges_and_renames() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("f.bin");
        fs::write(&file, b"0123456789").unwrap();
        assert_eq!(read_range(&file, 3, 4).unwrap(), b"3456");
        assert_eq!(read_range(&file, 8, 10).unwrap(), b"89");
        let renamed = rename(&file, "g.bin").unwrap();
        assert!(renamed.exists());
        assert!(rename(&renamed, "x/y").is_err());
        fs::write(dir.path().join("h.bin"), b"").unwrap();
        assert_eq!(rename(&renamed, "h.bin").unwrap_err().kind, VfsErrorKind::AlreadyExists);
        assert!(create_dir_all(&dir.path().join("n1/n2")).is_ok());
        assert_eq!(create_dir_all(&dir.path().join("n1")).unwrap_err().kind, VfsErrorKind::AlreadyExists);
        assert!(create_file(&dir.path().join("new")).is_ok());
        assert_eq!(create_file(&dir.path().join("new")).unwrap_err().kind, VfsErrorKind::AlreadyExists);
    }

    #[cfg(unix)]
    #[test]
    fn symlinks_say_where_they_point() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir(dir.path().join("target")).unwrap();
        std::os::unix::fs::symlink("target", dir.path().join("link")).unwrap();
        let link = stat(&dir.path().join("link")).unwrap();
        assert_eq!(link.kind, EntryKind::Symlink);
        assert!(link.is_dir);
        assert_eq!(link.symlink_target.as_deref(), Some("target"));
    }

    /// Times single-item stats: `cargo test --release -p ferryx_vfs
    /// stat_bench -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn stat_bench() {
        let dir = tempfile::tempdir().unwrap();
        let paths: Vec<PathBuf> = (0..10_000)
            .map(|i| {
                let path = dir.path().join(format!("f{i}"));
                fs::write(&path, b"x").unwrap();
                path
            })
            .collect();
        let start = std::time::Instant::now();
        for path in &paths {
            stat(path).unwrap();
        }
        println!("10 000 stats: {:?}", start.elapsed());
    }
}
