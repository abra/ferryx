//! What can go wrong with a terminal session, typed for the interface.

/// The kind of a [`TermError`]; the interface words each one.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TermErrorKind {
    /// The shell does not exist, or the session is gone.
    NotFound,
    /// The shell is not executable.
    PermissionDenied,
    /// The system has no pseudo-terminals.
    Unsupported,
    /// The shell has exited; the session takes no more input.
    Closed,
    Io,
}

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
#[error("{message}")]
pub struct TermError {
    pub kind: TermErrorKind,
    pub message: String,
    /// The shell's path, when the error is about it.
    pub path: Option<String>,
}

impl TermError {
    pub fn new(kind: TermErrorKind, message: impl Into<String>) -> TermError {
        TermError { kind, message: message.into(), path: None }
    }

    pub fn with_path(mut self, path: impl Into<String>) -> TermError {
        self.path = Some(path.into());
        self
    }

    pub(crate) fn io(context: &str, error: impl std::fmt::Display) -> TermError {
        TermError::new(TermErrorKind::Io, format!("{context}: {error}"))
    }
}
