//! Permissions, flags, owners and times, read and written.

use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::error::{IoAt, VfsError, VfsResult};
use crate::native;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Attributes {
    /// Permission bits (the low 12 bits of the mode: rwx×3, setuid,
    /// setgid, sticky).
    pub permissions: u32,
    pub uid: u32,
    pub gid: u32,
    pub owner: String,
    pub group: String,
    /// BSD flags (macOS): `UF_NODUMP`, `UF_IMMUTABLE`, `UF_APPEND`,
    /// `UF_HIDDEN`, `SF_ARCHIVED`, `SF_IMMUTABLE`, `SF_APPEND`.
    pub flags: u32,
    pub modified_ms: Option<i64>,
    pub accessed_ms: Option<i64>,
    pub created_ms: Option<i64>,
    pub is_dir: bool,
}

/// What to change; `None` leaves the attribute as it is.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttributeChanges {
    /// Bits to set and bits to clear among the permissions, so a
    /// multi-selection can set some and leave others as each file has them.
    pub permissions_set: u32,
    pub permissions_clear: u32,
    pub uid: Option<u32>,
    pub gid: Option<u32>,
    pub flags_set: u32,
    pub flags_clear: u32,
    pub modified_ms: Option<i64>,
    pub accessed_ms: Option<i64>,
}

impl AttributeChanges {
    pub fn is_empty(&self) -> bool {
        self == &AttributeChanges::default()
    }
}

pub fn read(path: &Path) -> VfsResult<Attributes> {
    let entry = native::stat(path)?;
    Ok(Attributes {
        permissions: entry.mode & 0o7777,
        uid: entry.uid,
        gid: entry.gid,
        owner: entry.owner,
        group: entry.group,
        flags: entry.flags,
        modified_ms: entry.modified_ms,
        accessed_ms: entry.accessed_ms,
        created_ms: entry.created_ms,
        is_dir: entry.kind == ferryx_core::entry::EntryKind::Directory,
    })
}

/// Applies `changes` to `path`, and with `recursive` to everything inside
/// a folder. Errors are collected, not fatal: the first one is returned
/// after everything that could be done was.
pub fn apply(path: &Path, changes: &AttributeChanges, recursive: bool) -> VfsResult<()> {
    let mut first_error: Option<VfsError> = None;
    let mut visit = |p: &Path| {
        if let Err(e) = apply_one(p, changes) {
            first_error.get_or_insert(e);
        }
    };
    visit(path);
    if recursive
        && native::is_dir(path)
        && !fs::symlink_metadata(path).map(|m| m.file_type().is_symlink()).unwrap_or(false)
    {
        walk(path, &mut visit);
    }
    match first_error {
        Some(e) => Err(e),
        None => Ok(()),
    }
}

fn walk(dir: &Path, visit: &mut dyn FnMut(&Path)) {
    let Ok(read) = fs::read_dir(dir) else { return };
    for item in read.flatten() {
        let path = item.path();
        visit(&path);
        let is_real_dir = item.file_type().map(|t| t.is_dir()).unwrap_or(false);
        if is_real_dir {
            walk(&path, visit);
        }
    }
}

fn apply_one(path: &Path, changes: &AttributeChanges) -> VfsResult<()> {
    if changes.permissions_set != 0 || changes.permissions_clear != 0 {
        set_permissions(path, changes.permissions_set, changes.permissions_clear)?;
    }
    if changes.uid.is_some() || changes.gid.is_some() {
        chown(path, changes.uid, changes.gid)?;
    }
    if changes.flags_set != 0 || changes.flags_clear != 0 {
        set_flags(path, changes.flags_set, changes.flags_clear)?;
    }
    if changes.modified_ms.is_some() || changes.accessed_ms.is_some() {
        set_times(path, changes.modified_ms, changes.accessed_ms)?;
    }
    Ok(())
}

#[cfg(unix)]
fn set_permissions(path: &Path, set: u32, clear: u32) -> VfsResult<()> {
    use std::os::unix::fs::PermissionsExt;
    let meta = fs::symlink_metadata(path).at(path)?;
    if meta.file_type().is_symlink() {
        return Ok(());
    }
    let mode = (meta.permissions().mode() & 0o7777 & !clear) | set;
    fs::set_permissions(path, fs::Permissions::from_mode(mode)).at(path)
}

#[cfg(not(unix))]
fn set_permissions(path: &Path, set: u32, clear: u32) -> VfsResult<()> {
    let mut perms = fs::metadata(path).at(path)?.permissions();
    if clear & 0o200 != 0 {
        perms.set_readonly(true);
    }
    if set & 0o200 != 0 {
        perms.set_readonly(false);
    }
    fs::set_permissions(path, perms).at(path)
}

#[cfg(unix)]
fn chown(path: &Path, uid: Option<u32>, gid: Option<u32>) -> VfsResult<()> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let c_path = CString::new(path.as_os_str().as_bytes())
        .map_err(|_| VfsError::invalid_name(&path.to_string_lossy()))?;
    // -1 leaves an id as it is.
    let rc = unsafe { libc::lchown(c_path.as_ptr(), uid.unwrap_or(u32::MAX), gid.unwrap_or(u32::MAX)) };
    if rc != 0 {
        return Err(VfsError::io(&std::io::Error::last_os_error(), path));
    }
    Ok(())
}

#[cfg(not(unix))]
fn chown(_path: &Path, _uid: Option<u32>, _gid: Option<u32>) -> VfsResult<()> {
    Err(VfsError::unsupported("owners cannot be changed here"))
}

#[cfg(target_os = "macos")]
fn set_flags(path: &Path, set: u32, clear: u32) -> VfsResult<()> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let current = native::stat(path)?.flags;
    let flags = (current & !clear) | set;
    let c_path = CString::new(path.as_os_str().as_bytes())
        .map_err(|_| VfsError::invalid_name(&path.to_string_lossy()))?;
    let rc = unsafe { libc::lchflags(c_path.as_ptr(), flags) };
    if rc != 0 {
        let error = std::io::Error::last_os_error();
        return Err(VfsError::io(&error, path));
    }
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn set_flags(_path: &Path, _set: u32, _clear: u32) -> VfsResult<()> {
    Err(VfsError::unsupported("file flags are a macOS feature"))
}

fn set_times(path: &Path, modified_ms: Option<i64>, accessed_ms: Option<i64>) -> VfsResult<()> {
    use filetime::FileTime;
    let meta = fs::symlink_metadata(path).at(path)?;
    let to_time =
        |ms: i64| FileTime::from_unix_time(ms.div_euclid(1000), (ms.rem_euclid(1000) * 1_000_000) as u32);
    let atime = accessed_ms.map(to_time).unwrap_or_else(|| FileTime::from_last_access_time(&meta));
    let mtime = modified_ms.map(to_time).unwrap_or_else(|| FileTime::from_last_modification_time(&meta));
    filetime::set_symlink_file_times(path, atime, mtime).at(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn permissions_and_times_change() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("f");
        fs::write(&file, b"x").unwrap();
        let before = read(&file).unwrap();
        assert!(!before.is_dir);
        apply(
            &file,
            &AttributeChanges {
                permissions_set: 0o111,
                permissions_clear: 0o022,
                modified_ms: Some(1_000_000_000_000),
                ..Default::default()
            },
            false,
        )
        .unwrap();
        let after = read(&file).unwrap();
        assert_eq!(after.permissions & 0o111, 0o111);
        assert_eq!(after.permissions & 0o022, 0);
        assert_eq!(after.modified_ms, Some(1_000_000_000_000));
        assert_eq!(after.owner, before.owner);
    }

    #[cfg(unix)]
    #[test]
    fn recursion_reaches_inside() {
        let dir = tempfile::tempdir().unwrap();
        let sub = dir.path().join("sub");
        fs::create_dir(&sub).unwrap();
        let inner = sub.join("f");
        fs::write(&inner, b"x").unwrap();
        apply(
            &sub,
            &AttributeChanges { permissions_clear: 0o022, permissions_set: 0o100, ..Default::default() },
            true,
        )
        .unwrap();
        assert_eq!(read(&inner).unwrap().permissions & 0o100, 0o100);
    }
}
