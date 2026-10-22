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
    /// An encrypted archive needs a password to be listed or read.
    PasswordRequired,
    /// The password given does not open the archive.
    WrongPassword,
    // ─── Network ───
    /// The server refused the user's credentials.
    AuthFailed,
    /// The server could not be reached: no such host, refused, no route.
    HostUnreachable,
    /// The server did not answer in time.
    TimedOut,
    /// The server's SSH key is not known yet and the user did not accept
    /// it.
    HostKeyUnknown,
    /// The server's SSH key is not the one on record: refused.
    HostKeyChanged,
    /// The connection to the server dropped.
    ConnectionLost,
    /// No connection to the server is open: connect first.
    NotConnected,
    /// The server's TLS certificate could not be verified.
    CertificateInvalid,
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

    /// An error of `kind` about a path on a server (`path` as the server
    /// spells it, `/`-separated).
    pub fn remote(kind: VfsErrorKind, path: Option<&str>, message: impl Into<String>) -> VfsError {
        VfsError { kind, path: path.map(str::to_string), message: message.into() }
    }

    /// Whether the error says the connection is gone (so a fresh one may
    /// do what this one could not).
    pub fn is_connection_error(&self) -> bool {
        matches!(
            self.kind,
            VfsErrorKind::ConnectionLost
                | VfsErrorKind::TimedOut
                | VfsErrorKind::HostUnreachable
                | VfsErrorKind::NotConnected
        )
    }

    pub fn password_required(archive: &Path) -> VfsError {
        VfsError::new(
            VfsErrorKind::PasswordRequired,
            Some(archive),
            format!("{} is encrypted", archive.display()),
        )
    }

    pub fn wrong_password(archive: &Path) -> VfsError {
        VfsError::new(
            VfsErrorKind::WrongPassword,
            Some(archive),
            format!("the password does not open {}", archive.display()),
        )
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
