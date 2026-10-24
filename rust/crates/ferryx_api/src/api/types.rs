//! Plain data that crosses the bridge. Enums carry no payloads, so Dart
//! sees them as enums; counts and times are `i64`, which Dart reads as
//! `int` on the desktops.

use std::path::{Path, PathBuf};

use ferryx_core::batch_rename as br;
use ferryx_core::collation::Collation;
use ferryx_core::entry::{Entry, EntryKind};
use ferryx_core::sorting::{SortField, SortOptions};
use ferryx_ops as ops;
use ferryx_vfs::{Location, VfsError, VfsErrorKind};
use flutter_rust_bridge::frb;

use crate::api::checksum::ChecksumUpdateView;
use crate::api::duplicates::DuplicatesUpdateView;
use crate::api::journal::JournalSummaryView;
use crate::api::network::NetworkEventView;
use crate::api::sync::CompareUpdateView;

// ─── Errors ───

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FerryxErrorKind {
    NotFound,
    PermissionDenied,
    AlreadyExists,
    NotADirectory,
    IsADirectory,
    NotEmpty,
    Unsupported,
    Cancelled,
    InvalidName,
    InvalidPattern,
    Io,
    /// An encrypted archive needs a password.
    PasswordRequired,
    /// The password given does not open the archive.
    WrongPassword,
    // ─── Network ───
    /// The server refused the login.
    AuthFailed,
    /// The server could not be reached.
    HostUnreachable,
    /// The server did not answer in time.
    TimedOut,
    /// The server's SSH key was not trusted.
    HostKeyUnknown,
    /// The server's SSH key is not the one on record: refused.
    HostKeyChanged,
    /// The connection dropped.
    ConnectionLost,
    /// No connection to the server is open.
    NotConnected,
    /// The server's certificate is not trusted.
    CertificateInvalid,
}

/// Every error the bridge raises; Dart sees it as an exception with a
/// typed kind and a message to show.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FerryxError {
    pub kind: FerryxErrorKind,
    pub message: String,
    pub path: Option<String>,
}

impl FerryxError {
    #[frb(ignore)]
    pub fn new(kind: FerryxErrorKind, message: impl Into<String>) -> FerryxError {
        FerryxError { kind, message: message.into(), path: None }
    }

    #[frb(ignore)]
    pub fn invalid_pattern(message: impl Into<String>) -> FerryxError {
        FerryxError::new(FerryxErrorKind::InvalidPattern, message)
    }
}

impl From<VfsError> for FerryxError {
    fn from(e: VfsError) -> Self {
        let kind = match e.kind {
            VfsErrorKind::NotFound => FerryxErrorKind::NotFound,
            VfsErrorKind::PermissionDenied => FerryxErrorKind::PermissionDenied,
            VfsErrorKind::AlreadyExists => FerryxErrorKind::AlreadyExists,
            VfsErrorKind::NotADirectory => FerryxErrorKind::NotADirectory,
            VfsErrorKind::IsADirectory => FerryxErrorKind::IsADirectory,
            VfsErrorKind::NotEmpty => FerryxErrorKind::NotEmpty,
            VfsErrorKind::Unsupported => FerryxErrorKind::Unsupported,
            VfsErrorKind::Cancelled => FerryxErrorKind::Cancelled,
            VfsErrorKind::InvalidName => FerryxErrorKind::InvalidName,
            VfsErrorKind::Io => FerryxErrorKind::Io,
            VfsErrorKind::PasswordRequired => FerryxErrorKind::PasswordRequired,
            VfsErrorKind::WrongPassword => FerryxErrorKind::WrongPassword,
            VfsErrorKind::AuthFailed => FerryxErrorKind::AuthFailed,
            VfsErrorKind::HostUnreachable => FerryxErrorKind::HostUnreachable,
            VfsErrorKind::TimedOut => FerryxErrorKind::TimedOut,
            VfsErrorKind::HostKeyUnknown => FerryxErrorKind::HostKeyUnknown,
            VfsErrorKind::HostKeyChanged => FerryxErrorKind::HostKeyChanged,
            VfsErrorKind::ConnectionLost => FerryxErrorKind::ConnectionLost,
            VfsErrorKind::NotConnected => FerryxErrorKind::NotConnected,
            VfsErrorKind::CertificateInvalid => FerryxErrorKind::CertificateInvalid,
        };
        FerryxError { kind, message: e.message, path: e.path }
    }
}

impl std::fmt::Display for FerryxError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for FerryxError {}

pub type ApiResult<T> = Result<T, FerryxError>;

// ─── Locations and entries ───

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LocationKind {
    Native,
    Archive,
    // ─── Network ───
    Remote,
}

/// Where a panel is: a folder on disk, a folder inside an archive
/// (`archive` the file, `path` the folder inside it, empty at its root),
/// or a folder on a server (`server` its key, `sftp://me@host:22`, and
/// `path` the folder there).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LocationView {
    pub kind: LocationKind,
    pub path: String,
    pub archive: Option<String>,
    pub server: Option<String>,
}

impl LocationView {
    #[frb(ignore)]
    pub fn native(path: &Path) -> LocationView {
        LocationView {
            kind: LocationKind::Native,
            path: path.to_string_lossy().into_owned(),
            archive: None,
            server: None,
        }
    }

    #[frb(ignore)]
    pub fn to_location(&self) -> Location {
        match self.kind {
            LocationKind::Native => Location::Native(PathBuf::from(&self.path)),
            LocationKind::Archive => Location::Archive {
                archive: PathBuf::from(self.archive.clone().unwrap_or_default()),
                inner: self.path.trim_matches('/').to_string(),
            },
            LocationKind::Remote => {
                let path = ferryx_vfs::remote::address::normalize(&self.path);
                Location::Remote {
                    server: self.server.clone().unwrap_or_default(),
                    path: if path.is_empty() { "/".to_string() } else { path },
                }
            }
        }
    }
}

impl From<&Location> for LocationView {
    fn from(location: &Location) -> Self {
        match location {
            Location::Native(path) => LocationView::native(path),
            Location::Archive { archive, inner } => LocationView {
                kind: LocationKind::Archive,
                path: inner.clone(),
                archive: Some(archive.to_string_lossy().into_owned()),
                server: None,
            },
            Location::Remote { server, path } => LocationView {
                kind: LocationKind::Remote,
                path: path.clone(),
                archive: None,
                server: Some(server.clone()),
            },
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EntryKindView {
    File,
    Directory,
    Symlink,
    Other,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EntryView {
    pub name: String,
    /// The full path on disk, or the member's path inside its archive.
    pub path: String,
    pub kind: EntryKindView,
    pub is_dir: bool,
    pub is_parent: bool,
    pub symlink_target: Option<String>,
    pub size: Option<i64>,
    pub modified_ms: Option<i64>,
    pub created_ms: Option<i64>,
    pub accessed_ms: Option<i64>,
    pub added_ms: Option<i64>,
    pub mode: u32,
    pub uid: u32,
    pub gid: u32,
    pub owner: String,
    pub group: String,
    pub flags: u32,
    pub is_hidden: bool,
    pub extension: String,
    pub tags: Vec<crate::api::tags::TagView>,
}

impl From<&Entry> for EntryView {
    fn from(e: &Entry) -> Self {
        EntryView {
            name: e.name.clone(),
            path: e.path.to_string_lossy().into_owned(),
            kind: match e.kind {
                EntryKind::File => EntryKindView::File,
                EntryKind::Directory => EntryKindView::Directory,
                EntryKind::Symlink => EntryKindView::Symlink,
                EntryKind::Other => EntryKindView::Other,
            },
            is_dir: e.is_dir,
            is_parent: e.is_parent,
            symlink_target: e.symlink_target.clone(),
            size: e.size.map(|s| s as i64),
            modified_ms: e.modified_ms,
            created_ms: e.created_ms,
            accessed_ms: e.accessed_ms,
            added_ms: e.added_ms,
            mode: e.mode,
            uid: e.uid,
            gid: e.gid,
            owner: e.owner.clone(),
            group: e.group.clone(),
            flags: e.flags,
            is_hidden: e.is_hidden,
            extension: e.extension.clone(),
            tags: e.tags.iter().map(crate::api::tags::TagView::from).collect(),
        }
    }
}

// ─── Sorting and listings ───

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SortFieldView {
    Name,
    Extension,
    Size,
    Modified,
    Created,
    Added,
    Accessed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CollationView {
    Natural,
    CaseInsensitive,
    CaseSensitive,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SortOptionsView {
    pub field: SortFieldView,
    pub descending: bool,
    pub folders_first: bool,
    pub extensionless_folders: bool,
    pub collation: CollationView,
}

impl SortOptionsView {
    #[frb(ignore)]
    pub fn to_core(self) -> SortOptions {
        SortOptions {
            field: match self.field {
                SortFieldView::Name => SortField::Name,
                SortFieldView::Extension => SortField::Extension,
                SortFieldView::Size => SortField::Size,
                SortFieldView::Modified => SortField::Modified,
                SortFieldView::Created => SortField::Created,
                SortFieldView::Added => SortField::Added,
                SortFieldView::Accessed => SortField::Accessed,
            },
            descending: self.descending,
            folders_first: self.folders_first,
            extensionless_folders: self.extensionless_folders,
            collation: match self.collation {
                CollationView::Natural => Collation::Natural,
                CollationView::CaseInsensitive => Collation::CaseInsensitive,
                CollationView::CaseSensitive => Collation::CaseSensitive,
            },
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ListingOptionsView {
    pub show_hidden: bool,
    pub show_parent: bool,
    pub sort: SortOptionsView,
}

/// A panel's rows, sorted, with what the footer shows: all of them, or
/// an update of the rows the panel was sent as `base`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ListingView {
    pub location: LocationView,
    /// Every row; with `order`, only the rows the panel has not got.
    pub entries: Vec<EntryView>,
    /// For an update, each row in its place: `i >= 0` is row `i` of the
    /// rows numbered `base`, `-1 - i` is `entries[i]`.
    pub order: Option<Vec<i32>>,
    pub base: i64,
    /// The number of these rows: the `base` of the next update.
    pub version: i64,
    pub free_bytes: Option<i64>,
    pub total_bytes: Option<i64>,
    pub volume_name: Option<String>,
    /// Whether the folder is watched: an archive is not.
    pub watched: bool,
}

impl ListingView {
    /// The rows a panel holding `before` (the rows numbered `base`) has
    /// after this, as the interface applies it.
    #[flutter_rust_bridge::frb(ignore)]
    pub fn rows_after(&self, before: &[EntryView]) -> Vec<EntryView> {
        match &self.order {
            None => self.entries.clone(),
            Some(order) => order
                .iter()
                .map(|&i| {
                    if i >= 0 {
                        before[i as usize].clone()
                    } else {
                        self.entries[(-1 - i) as usize].clone()
                    }
                })
                .collect(),
        }
    }
}

// ─── Operations ───

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OpKindView {
    Copy,
    Move,
    Delete,
    Trash,
    Duplicate,
    Compress,
    Extract,
    CalcSizes,
    // ─── Operations stream ───
    Synchronize,
    CompareContents,
    Undo,
    Redo,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConflictPolicyView {
    Ask,
    Overwrite,
    OverwriteOlder,
    Skip,
    KeepBoth,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpRequestView {
    pub kind: OpKindView,
    pub sources: Vec<String>,
    pub archive: Option<String>,
    pub destination: Option<String>,
    pub new_name: Option<String>,
    pub conflicts: ConflictPolicyView,
    pub preserve_attributes: bool,
    pub verify: bool,
    pub password: Option<String>,
    /// Extract whole archives: each into a folder named after it.
    pub into_folders: bool,
}

impl OpRequestView {
    #[frb(ignore)]
    pub fn to_ops(&self) -> ops::OpRequest {
        ops::OpRequest {
            kind: match self.kind {
                OpKindView::Copy => ops::OpKind::Copy,
                OpKindView::Move => ops::OpKind::Move,
                OpKindView::Delete => ops::OpKind::Delete,
                OpKindView::Trash => ops::OpKind::Trash,
                OpKindView::Duplicate => ops::OpKind::Duplicate,
                OpKindView::Compress => ops::OpKind::Compress,
                OpKindView::Extract => ops::OpKind::Extract,
                OpKindView::CalcSizes => ops::OpKind::CalcSizes,
                OpKindView::Synchronize => ops::OpKind::Synchronize,
                OpKindView::CompareContents => ops::OpKind::CompareContents,
                OpKindView::Undo => ops::OpKind::Undo,
                OpKindView::Redo => ops::OpKind::Redo,
            },
            sources: self.sources.iter().map(PathBuf::from).collect(),
            archive: self.archive.as_ref().map(PathBuf::from),
            destination: self.destination.as_ref().map(PathBuf::from),
            new_name: self.new_name.clone(),
            options: ops::OpOptions {
                conflicts: match self.conflicts {
                    ConflictPolicyView::Ask => ops::ConflictPolicy::Ask,
                    ConflictPolicyView::Overwrite => ops::ConflictPolicy::Overwrite,
                    ConflictPolicyView::OverwriteOlder => ops::ConflictPolicy::OverwriteOlder,
                    ConflictPolicyView::Skip => ops::ConflictPolicy::Skip,
                    ConflictPolicyView::KeepBoth => ops::ConflictPolicy::KeepBoth,
                },
                preserve_attributes: self.preserve_attributes,
                verify: self.verify,
                password: self.password.clone(),
                into_folders: self.into_folders,
            },
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OpStateView {
    Scanning,
    Running,
    Paused,
    Waiting,
    Done,
    DoneWithErrors,
    Cancelled,
    Failed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum QuestionKindView {
    Conflict,
    Error,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AnswerView {
    Overwrite,
    OverwriteAll,
    OverwriteOlderAll,
    Skip,
    SkipAll,
    KeepBoth,
    KeepBothAll,
    Merge,
    MergeAll,
    Retry,
    Abort,
}

impl AnswerView {
    #[frb(ignore)]
    pub fn to_ops(self) -> ops::Answer {
        match self {
            AnswerView::Overwrite => ops::Answer::Overwrite,
            AnswerView::OverwriteAll => ops::Answer::OverwriteAll,
            AnswerView::OverwriteOlderAll => ops::Answer::OverwriteOlderAll,
            AnswerView::Skip => ops::Answer::Skip,
            AnswerView::SkipAll => ops::Answer::SkipAll,
            AnswerView::KeepBoth => ops::Answer::KeepBoth,
            AnswerView::KeepBothAll => ops::Answer::KeepBothAll,
            AnswerView::Merge => ops::Answer::Merge,
            AnswerView::MergeAll => ops::Answer::MergeAll,
            AnswerView::Retry => ops::Answer::Retry,
            AnswerView::Abort => ops::Answer::Abort,
        }
    }

    fn from_ops(answer: ops::Answer) -> AnswerView {
        match answer {
            ops::Answer::Overwrite => AnswerView::Overwrite,
            ops::Answer::OverwriteAll => AnswerView::OverwriteAll,
            ops::Answer::OverwriteOlderAll => AnswerView::OverwriteOlderAll,
            ops::Answer::Skip => AnswerView::Skip,
            ops::Answer::SkipAll => AnswerView::SkipAll,
            ops::Answer::KeepBoth => AnswerView::KeepBoth,
            ops::Answer::KeepBothAll => AnswerView::KeepBothAll,
            ops::Answer::Merge => AnswerView::Merge,
            ops::Answer::MergeAll => AnswerView::MergeAll,
            ops::Answer::Retry => AnswerView::Retry,
            ops::Answer::Abort => AnswerView::Abort,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConflictSideView {
    pub path: String,
    pub size: Option<i64>,
    pub modified_ms: Option<i64>,
    pub is_dir: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct QuestionView {
    pub id: i64,
    pub kind: QuestionKindView,
    pub message: String,
    pub source: Option<ConflictSideView>,
    pub existing: Option<ConflictSideView>,
    pub answers: Vec<AnswerView>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpErrorView {
    pub path: String,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FolderSizeView {
    pub path: String,
    pub bytes: i64,
}

/// What an operation reports. From `operation_progress` and
/// `list_operations` its lists are whole; in an `OperationProgress` event
/// they are the news since the operation's previous event, for the
/// receiver to add up.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProgressView {
    pub id: i64,
    pub kind: OpKindView,
    pub state: OpStateView,
    pub bytes_done: i64,
    pub bytes_total: i64,
    pub items_done: i64,
    pub items_total: i64,
    pub current: String,
    pub started_ms: i64,
    pub elapsed_ms: i64,
    pub bytes_per_second: i64,
    /// In an event: the errors since the previous one.
    pub errors: Vec<OpErrorView>,
    pub question: Option<QuestionView>,
    /// In an event: the folder sizes done since the previous one.
    pub sizes: Vec<FolderSizeView>,
    pub result_path: Option<String>,
    /// In an event: only in the operation's first and last (empty between).
    pub sources: Vec<String>,
    pub destination: Option<String>,
}

impl From<ops::Progress> for ProgressView {
    fn from(p: ops::Progress) -> Self {
        fn side(s: ops::ConflictSide) -> ConflictSideView {
            ConflictSideView {
                path: s.path,
                size: s.size.map(|v| v as i64),
                modified_ms: s.modified_ms,
                is_dir: s.is_dir,
            }
        }
        ProgressView {
            id: p.id as i64,
            kind: match p.kind {
                ops::OpKind::Copy => OpKindView::Copy,
                ops::OpKind::Move => OpKindView::Move,
                ops::OpKind::Delete => OpKindView::Delete,
                ops::OpKind::Trash => OpKindView::Trash,
                ops::OpKind::Duplicate => OpKindView::Duplicate,
                ops::OpKind::Compress => OpKindView::Compress,
                ops::OpKind::Extract => OpKindView::Extract,
                ops::OpKind::CalcSizes => OpKindView::CalcSizes,
                ops::OpKind::Synchronize => OpKindView::Synchronize,
                ops::OpKind::CompareContents => OpKindView::CompareContents,
                ops::OpKind::Undo => OpKindView::Undo,
                ops::OpKind::Redo => OpKindView::Redo,
            },
            state: match p.state {
                ops::OpState::Scanning => OpStateView::Scanning,
                ops::OpState::Running => OpStateView::Running,
                ops::OpState::Paused => OpStateView::Paused,
                ops::OpState::Waiting => OpStateView::Waiting,
                ops::OpState::Done => OpStateView::Done,
                ops::OpState::DoneWithErrors => OpStateView::DoneWithErrors,
                ops::OpState::Cancelled => OpStateView::Cancelled,
                ops::OpState::Failed => OpStateView::Failed,
            },
            bytes_done: p.bytes_done as i64,
            bytes_total: p.bytes_total as i64,
            items_done: p.items_done as i64,
            items_total: p.items_total as i64,
            current: p.current,
            started_ms: p.started_ms,
            elapsed_ms: p.elapsed_ms as i64,
            bytes_per_second: p.bytes_per_second as i64,
            errors: p.errors.into_iter().map(|e| OpErrorView { path: e.path, message: e.message }).collect(),
            question: p.question.map(|q| QuestionView {
                id: q.id as i64,
                kind: match q.kind {
                    ops::QuestionKind::Conflict => QuestionKindView::Conflict,
                    ops::QuestionKind::Error => QuestionKindView::Error,
                },
                message: q.message,
                source: q.source.map(side),
                existing: q.existing.map(side),
                answers: q.answers.into_iter().map(AnswerView::from_ops).collect(),
            }),
            sizes: p
                .sizes
                .into_iter()
                .map(|s| FolderSizeView {
                    path: s.path.to_string_lossy().into_owned(),
                    bytes: s.bytes as i64,
                })
                .collect(),
            result_path: p.result_path.map(|r| r.to_string_lossy().into_owned()),
            sources: p.sources.iter().map(|s| s.to_string_lossy().into_owned()).collect(),
            destination: p.destination.map(|d| d.to_string_lossy().into_owned()),
        }
    }
}

// ─── Find ───

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SizeOpView {
    Less,
    Equal,
    Greater,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FindRequestView {
    pub root: String,
    pub name: String,
    pub name_is_regex: bool,
    pub content_text: Option<String>,
    pub content_case_sensitive: bool,
    pub content_whole_phrase: bool,
    pub content_not_containing: bool,
    pub size_op: Option<SizeOpView>,
    pub size_bytes: i64,
    pub include_hidden: bool,
    pub include_folders: bool,
    /// Ask the Spotlight index first (macOS); the folders are walked when
    /// it cannot answer.
    pub use_spotlight: bool,
}

impl FindRequestView {
    #[frb(ignore)]
    pub fn to_ops(&self) -> ops::find::FindRequest {
        ops::find::FindRequest {
            root: PathBuf::from(&self.root),
            name: self.name.clone(),
            name_is_regex: self.name_is_regex,
            content: self.content_text.clone().filter(|t| !t.is_empty()).map(|text| {
                ops::find::ContentQuery {
                    text,
                    case_sensitive: self.content_case_sensitive,
                    whole_phrase: self.content_whole_phrase,
                    not_containing: self.content_not_containing,
                }
            }),
            size: self.size_op.map(|op| ops::find::SizeCondition {
                op: match op {
                    SizeOpView::Less => ops::find::SizeOp::Less,
                    SizeOpView::Equal => ops::find::SizeOp::Equal,
                    SizeOpView::Greater => ops::find::SizeOp::Greater,
                },
                bytes: self.size_bytes.max(0) as u64,
            }),
            include_hidden: self.include_hidden,
            include_folders: self.include_folders,
            max_depth: None,
            use_spotlight: self.use_spotlight,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FindHitView {
    pub path: String,
    pub is_dir: bool,
    pub size: i64,
    pub modified_ms: Option<i64>,
}

// ─── Batch rename ───

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RenameItemView {
    pub path: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CaseTransformView {
    Unchanged,
    Lower,
    Upper,
    Capitalize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NamePartView {
    Whole,
    Name,
    Extension,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RenameOptionsView {
    pub pattern: String,
    pub search: String,
    pub replace: String,
    pub search_regex: bool,
    pub search_case_sensitive: bool,
    pub search_once: bool,
    pub search_part: NamePartView,
    pub case: CaseTransformView,
    pub case_part: NamePartView,
    pub counter_start: i64,
    pub counter_step: i64,
    pub counter_width: i64,
}

fn part(p: NamePartView) -> br::NamePart {
    match p {
        NamePartView::Whole => br::NamePart::Whole,
        NamePartView::Name => br::NamePart::Name,
        NamePartView::Extension => br::NamePart::Extension,
    }
}

impl RenameOptionsView {
    #[frb(ignore)]
    pub fn to_core(&self) -> br::RenameOptions {
        br::RenameOptions {
            pattern: self.pattern.clone(),
            search: (!self.search.is_empty()).then(|| br::SearchReplace {
                search: self.search.clone(),
                replace: self.replace.clone(),
                regex: self.search_regex,
                case_sensitive: self.search_case_sensitive,
                once: self.search_once,
                part: part(self.search_part),
            }),
            case: match self.case {
                CaseTransformView::Unchanged => br::CaseTransform::Unchanged,
                CaseTransformView::Lower => br::CaseTransform::Lower,
                CaseTransformView::Upper => br::CaseTransform::Upper,
                CaseTransformView::Capitalize => br::CaseTransform::Capitalize,
            },
            case_part: part(self.case_part),
            counter: br::Counter {
                start: self.counter_start,
                step: self.counter_step,
                width: self.counter_width.max(1) as usize,
            },
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RenameProblemView {
    None,
    Empty,
    Invalid,
    Duplicate,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RenameOutcomeView {
    pub path: String,
    pub old_name: String,
    pub new_name: String,
    pub problem: RenameProblemView,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RenamePairView {
    pub path: String,
    pub new_name: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RenameFailureView {
    pub path: String,
    pub message: String,
}

// ─── Attributes ───

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AttributesView {
    pub path: String,
    pub permissions: u32,
    pub uid: u32,
    pub gid: u32,
    pub owner: String,
    pub group: String,
    pub flags: u32,
    /// Whether this file system keeps BSD flags (locked, hidden): the
    /// dialog shows them even when none is set.
    pub supports_flags: bool,
    pub modified_ms: Option<i64>,
    pub accessed_ms: Option<i64>,
    pub created_ms: Option<i64>,
    pub is_dir: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AttributeChangesView {
    pub permissions_set: u32,
    pub permissions_clear: u32,
    pub uid: Option<u32>,
    pub gid: Option<u32>,
    pub flags_set: u32,
    pub flags_clear: u32,
    pub modified_ms: Option<i64>,
    pub accessed_ms: Option<i64>,
}

// ─── System ───

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VolumeView {
    pub name: String,
    pub mount_point: String,
    pub total_bytes: i64,
    pub available_bytes: i64,
    pub file_system: String,
    pub removable: bool,
    pub is_root: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StandardFoldersView {
    pub home: String,
    pub desktop: String,
    pub documents: String,
    pub downloads: String,
    pub applications: String,
    pub utilities: String,
    pub library: String,
    pub root: String,
    pub temporary: String,
    pub user_name: String,
}

// ─── Events ───

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AppEventKind {
    /// The folder of the listing `listing_id` changed on disk.
    DirectoryChanged,
    /// An operation reported progress (`progress`).
    OperationProgress,
    /// A search found items (`hits`) or looked further (`find_current`).
    FindProgress,
    /// A search ended (`find_id`).
    FindDone,
    // ─── Operations stream ───
    /// What undo and redo would do changed (`journal`).
    JournalChanged,
    /// A folder comparison found rows or ended (`compare`).
    CompareProgress,
    /// A checksum task hashed files or ended (`checksum`).
    ChecksumProgress,
    /// A duplicate search settled groups or ended (`duplicates`).
    DuplicatesProgress,
    // ─── Network ───
    /// A server's connection came, dropped or closed (`network`).
    ConnectionChanged,
    /// A connection asks the user something (`network.question`).
    NetworkQuestion,
    /// A question no longer waits (`network.question_id`).
    NetworkQuestionWithdrawn,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AppEvent {
    pub kind: AppEventKind,
    pub listing_id: Option<String>,
    pub progress: Option<ProgressView>,
    pub find_id: Option<i64>,
    pub hits: Vec<FindHitView>,
    pub find_current: Option<String>,
    pub find_scanned: i64,
    pub find_error: Option<String>,
    // ─── Operations stream ───
    pub journal: Option<JournalSummaryView>,
    pub compare: Option<CompareUpdateView>,
    pub checksum: Option<ChecksumUpdateView>,
    pub duplicates: Option<DuplicatesUpdateView>,
    /// A search that asked Spotlight walked the folders instead: Spotlight
    /// could not answer.
    pub find_spotlight_failed: bool,
    // ─── Network ───
    pub network: Option<NetworkEventView>,
}

impl AppEvent {
    #[frb(ignore)]
    pub fn of(kind: AppEventKind, listing_id: Option<String>) -> AppEvent {
        AppEvent {
            kind,
            listing_id,
            progress: None,
            find_id: None,
            hits: Vec::new(),
            find_current: None,
            find_scanned: 0,
            find_error: None,
            journal: None,
            compare: None,
            checksum: None,
            duplicates: None,
            find_spotlight_failed: false,
            network: None,
        }
    }

    #[frb(ignore)]
    pub fn progress(progress: ProgressView) -> AppEvent {
        AppEvent { progress: Some(progress), ..AppEvent::of(AppEventKind::OperationProgress, None) }
    }
}
