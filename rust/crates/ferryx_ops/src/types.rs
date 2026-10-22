//! What an operation is asked to do and what it reports.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum OpKind {
    Copy,
    Move,
    Delete,
    Trash,
    Duplicate,
    Compress,
    /// Members of an archive copied out to a folder.
    Extract,
    /// The sizes of folders, for the panel.
    CalcSizes,
}

/// What to do when the destination already has the item.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum ConflictPolicy {
    #[default]
    Ask,
    Overwrite,
    OverwriteOlder,
    Skip,
    /// Keep the existing item and write the new one under a free name.
    KeepBoth,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpOptions {
    pub conflicts: ConflictPolicy,
    /// Permissions and times copied with the data.
    pub preserve_attributes: bool,
    /// Read the copy back and compare it.
    pub verify: bool,
    /// Compress: AES-256 password. Extract: the archives' password.
    pub password: Option<String>,
    /// Extract whole archives: each into a folder named after it.
    pub into_folders: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpRequest {
    pub kind: OpKind,
    /// Paths on disk; for [`OpKind::Extract`], member paths inside
    /// [`OpRequest::archive`], or archives on disk to extract whole when
    /// there is none.
    pub sources: Vec<PathBuf>,
    pub archive: Option<PathBuf>,
    /// The folder written into (copy, move, extract, compress). Delete,
    /// trash, duplicate and sizes work in place.
    pub destination: Option<PathBuf>,
    /// Copy As / Move As with one source, or the archive's file name for
    /// Compress: the name the result takes in the destination.
    pub new_name: Option<String>,
    pub options: OpOptions,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum OpState {
    /// Counting what there is to do.
    Scanning,
    Running,
    Paused,
    /// Waiting for an answer to [`Progress::question`].
    Waiting,
    Done,
    /// Done, with errors skipped on the way.
    DoneWithErrors,
    Cancelled,
    Failed,
}

impl OpState {
    pub fn is_finished(self) -> bool {
        matches!(self, OpState::Done | OpState::DoneWithErrors | OpState::Cancelled | OpState::Failed)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpError {
    pub path: String,
    pub message: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum QuestionKind {
    /// The destination has the item already.
    Conflict,
    /// Something failed; retry, skip or stop.
    Error,
}

/// A size and time of one side of a conflict, for the dialog.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConflictSide {
    pub path: String,
    pub size: Option<u64>,
    pub modified_ms: Option<i64>,
    pub is_dir: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Answer {
    Overwrite,
    OverwriteAll,
    OverwriteOlderAll,
    Skip,
    SkipAll,
    KeepBoth,
    KeepBothAll,
    /// Open the folder and copy into it (a folder onto a folder).
    Merge,
    MergeAll,
    Retry,
    Abort,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Question {
    pub id: u64,
    pub kind: QuestionKind,
    pub message: String,
    pub source: Option<ConflictSide>,
    pub existing: Option<ConflictSide>,
    pub answers: Vec<Answer>,
}

/// A folder whose size was calculated.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FolderSize {
    pub path: PathBuf,
    pub bytes: u64,
}

/// What an operation reports; every change comes through the listener.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Progress {
    pub id: u64,
    pub kind: OpKind,
    pub state: OpState,
    pub bytes_done: u64,
    pub bytes_total: u64,
    pub items_done: u64,
    pub items_total: u64,
    /// The item being worked on.
    pub current: String,
    pub started_ms: i64,
    pub elapsed_ms: u64,
    pub bytes_per_second: u64,
    pub errors: Vec<OpError>,
    pub question: Option<Question>,
    /// [`OpKind::CalcSizes`]: the folders done so far.
    pub sizes: Vec<FolderSize>,
    /// What the operation made: the archive, the duplicate, the copy with
    /// its new name.
    pub result_path: Option<PathBuf>,
    /// The source folders, so a panel knows to refresh.
    pub sources: Vec<PathBuf>,
    pub destination: Option<PathBuf>,
}

/// Raised inside an operation to stop it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Abort {
    Cancelled,
    /// The user chose Abort on an error.
    Stopped,
}
