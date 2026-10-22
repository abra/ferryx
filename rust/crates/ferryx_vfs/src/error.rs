use std::io;
use std::path::Path;

use serde::{Deserialize, Serialize};

/// Why a file system call failed, by kind, so the interface can word it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum VfsErrorKind {
    NotFound,
    PermissionDenied,
    AlreadyExists,
    NotADirectory,
    IsADirectory,
    NotEmpty,
    /// What was asked cannot be done here: writing into an archive, a
    /// flag the file system has not.
    Unsupported,
    Cancelled,
    InvalidName,
    Io,
}

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error, Serialize, Deserialize)]
#[error("{message}")]
pub struct VfsError {
    pub kind: VfsErrorKind,
    pub path: Option<String>,
    pub message: String,
}

impl VfsError {
    pub fn new(kind: VfsErrorKind, path: Option<&Path>, message: impl Into<String>) -> VfsError {
        VfsError { kind, path: path.map(|p| p.to_string_lossy().into_owned()), message: message.into() }
    }

    pub fn unsupported(message: impl Into<String>) -> VfsError {
        VfsError::new(VfsErrorKind::Unsupported, None, message)
    }

    pub fn invalid_name(name: &str) -> VfsError {
        VfsError::new(VfsErrorKind::InvalidName, None, format!("“{name}” is not a valid name"))
    }

    pub fn cancelled() -> VfsError {
        VfsError::new(VfsErrorKind::Cancelled, None, "cancelled")
    }

    /// An I/O error at `path`, classified by its kind.
    pub fn io(error: &io::Error, path: &Path) -> VfsError {
        let kind = match error.kind() {
            io::ErrorKind::NotFound => VfsErrorKind::NotFound,
            io::ErrorKind::PermissionDenied => VfsErrorKind::PermissionDenied,
            io::ErrorKind::AlreadyExists => VfsErrorKind::AlreadyExists,
            io::ErrorKind::NotADirectory => VfsErrorKind::NotADirectory,
            io::ErrorKind::IsADirectory => VfsErrorKind::IsADirectory,
            io::ErrorKind::DirectoryNotEmpty => VfsErrorKind::NotEmpty,
            io::ErrorKind::InvalidInput | io::ErrorKind::InvalidFilename => VfsErrorKind::InvalidName,
            _ => match error.raw_os_error() {
                Some(libc::ENOTEMPTY) => VfsErrorKind::NotEmpty,
                Some(libc::ENOTDIR) => VfsErrorKind::NotADirectory,
                Some(libc::EISDIR) => VfsErrorKind::IsADirectory,
                Some(libc::EEXIST) => VfsErrorKind::AlreadyExists,
                Some(libc::EACCES) | Some(libc::EPERM) => VfsErrorKind::PermissionDenied,
                _ => VfsErrorKind::Io,
            },
        };
        let message = match error.raw_os_error() {
            Some(code) => format!("{}: {} (os error {code})", path.display(), os_message(error)),
            None => format!("{}: {}", path.display(), error),
        };
        VfsError::new(kind, Some(path), message)
    }
}

fn os_message(error: &io::Error) -> String {
    let text = error.to_string();
    match text.find(" (os error") {
        Some(at) => text[..at].to_string(),
        None => text,
    }
}

/// `Result` of every call in this crate.
pub type VfsResult<T> = Result<T, VfsError>;

/// Attaches `path` to an I/O result.
pub trait IoAt<T> {
    fn at(self, path: &Path) -> VfsResult<T>;
}

impl<T> IoAt<T> for io::Result<T> {
    fn at(self, path: &Path) -> VfsResult<T> {
        self.map_err(|e| VfsError::io(&e, path))
    }
}
