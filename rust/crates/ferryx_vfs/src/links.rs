//! Symbolic and hard links.

use std::fs;
use std::path::{Path, PathBuf};

use crate::error::{IoAt, VfsError, VfsErrorKind, VfsResult};

/// Makes a symbolic link at `link` pointing at `target`, written as given
/// (relative or absolute).
pub fn create_symlink(target: &Path, link: &Path) -> VfsResult<()> {
    if link.symlink_metadata().is_ok() {
        return Err(VfsError::new(
            VfsErrorKind::AlreadyExists,
            Some(link),
            format!("{} already exists", link.display()),
        ));
    }
    symlink(target, link).at(link)
}

#[cfg(unix)]
fn symlink(target: &Path, link: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(target, link)
}

#[cfg(windows)]
fn symlink(target: &Path, link: &Path) -> std::io::Result<()> {
    let resolved = if target.is_absolute() {
        target.to_path_buf()
    } else {
        link.parent().unwrap_or(Path::new(".")).join(target)
    };
    if resolved.is_dir() {
        std::os::windows::fs::symlink_dir(target, link)
    } else {
        std::os::windows::fs::symlink_file(target, link)
    }
}

/// Replaces the symbolic link at `link` with one pointing at `target`.
pub fn edit_symlink(link: &Path, target: &Path) -> VfsResult<()> {
    let meta = fs::symlink_metadata(link).at(link)?;
    if !meta.file_type().is_symlink() {
        return Err(VfsError::new(
            VfsErrorKind::Unsupported,
            Some(link),
            format!("{} is not a symbolic link", link.display()),
        ));
    }
    fs::remove_file(link).at(link)?;
    symlink(target, link).at(link)
}

pub fn read_symlink(link: &Path) -> VfsResult<PathBuf> {
    fs::read_link(link).at(link)
}

/// Makes a hard link at `link` to the file at `target`.
pub fn create_hardlink(target: &Path, link: &Path) -> VfsResult<()> {
    if link.symlink_metadata().is_ok() {
        return Err(VfsError::new(
            VfsErrorKind::AlreadyExists,
            Some(link),
            format!("{} already exists", link.display()),
        ));
    }
    fs::hard_link(target, link).at(link)
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    #[test]
    fn links_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("f");
        fs::write(&file, b"data").unwrap();
        let link = dir.path().join("l");
        create_symlink(Path::new("f"), &link).unwrap();
        assert_eq!(read_symlink(&link).unwrap(), PathBuf::from("f"));
        assert_eq!(create_symlink(Path::new("f"), &link).unwrap_err().kind, VfsErrorKind::AlreadyExists);
        fs::write(dir.path().join("g"), b"other").unwrap();
        edit_symlink(&link, Path::new("g")).unwrap();
        assert_eq!(fs::read(&link).unwrap(), b"other");
        assert!(edit_symlink(&file, Path::new("g")).is_err());
        let hard = dir.path().join("h");
        create_hardlink(&file, &hard).unwrap();
        assert_eq!(fs::read(&hard).unwrap(), b"data");
    }
}
