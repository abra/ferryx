//! Checksums: the hashes of files on a thread (`ChecksumProgress`
//! events), the check of a checksum file, and saving one.

use std::cell::RefCell;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use ferryx_ops::checksum::{self, ChecksumFile, ChecksumOutcome, ChecksumRequest, ChecksumStatus};
use ferryx_ops::hashing::Algorithm;
use ferryx_ops::journal::{Change, StepKind};
use flutter_rust_bridge::frb;

use crate::api::types::{ApiResult, AppEvent, AppEventKind, FerryxError, FerryxErrorKind};
use crate::app;
use crate::tasks::{self, Pacer};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChecksumAlgorithmView {
    Sha256,
    Sha1,
    Md5,
    Blake3,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChecksumRequestView {
    /// Files, and folders whose files are hashed.
    pub paths: Vec<String>,
    /// The folder names are shown relative to.
    pub base: String,
    pub algorithm: ChecksumAlgorithmView,
    pub recursive: bool,
    pub include_hidden: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChecksumStatusView {
    Ok,
    Mismatch,
    Missing,
    Error,
}

/// One file of the table, before its hash.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChecksumFileView {
    pub index: i64,
    /// Relative to the base (or to the checksum file's folder), with `/`.
    pub name: String,
    pub path: String,
    pub size: i64,
    /// Checking a checksum file: the hash it lists.
    pub expected: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChecksumOutcomeView {
    pub index: i64,
    pub status: ChecksumStatusView,
    pub hash: Option<String>,
    pub error: Option<FerryxError>,
}

/// What a running checksum task says. The first events bring the files;
/// later ones their outcomes, by index.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChecksumUpdateView {
    pub task_id: i64,
    /// The algorithm a checksum file uses (checking one).
    pub algorithm: Option<ChecksumAlgorithmView>,
    pub files: Vec<ChecksumFileView>,
    pub outcomes: Vec<ChecksumOutcomeView>,
    pub files_done: i64,
    pub files_total: i64,
    pub bytes_done: i64,
    pub bytes_total: i64,
    pub current: Option<String>,
    /// Checking a checksum file: lines that list nothing readable.
    pub bad_lines: i64,
    pub done: bool,
    pub error: Option<String>,
}

/// One line of a checksum file to save.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChecksumLineView {
    pub hash: String,
    pub name: String,
}

impl ChecksumAlgorithmView {
    #[frb(ignore)]
    pub fn to_ops(self) -> Algorithm {
        match self {
            ChecksumAlgorithmView::Sha256 => Algorithm::Sha256,
            ChecksumAlgorithmView::Sha1 => Algorithm::Sha1,
            ChecksumAlgorithmView::Md5 => Algorithm::Md5,
            ChecksumAlgorithmView::Blake3 => Algorithm::Blake3,
        }
    }

    #[frb(ignore)]
    pub fn from_ops(algorithm: Algorithm) -> ChecksumAlgorithmView {
        match algorithm {
            Algorithm::Sha256 => ChecksumAlgorithmView::Sha256,
            Algorithm::Sha1 => ChecksumAlgorithmView::Sha1,
            Algorithm::Md5 => ChecksumAlgorithmView::Md5,
            Algorithm::Blake3 => ChecksumAlgorithmView::Blake3,
        }
    }
}

impl ChecksumUpdateView {
    fn empty(task_id: i64) -> ChecksumUpdateView {
        ChecksumUpdateView {
            task_id,
            algorithm: None,
            files: Vec::new(),
            outcomes: Vec::new(),
            files_done: 0,
            files_total: 0,
            bytes_done: 0,
            bytes_total: 0,
            current: None,
            bad_lines: 0,
            done: false,
            error: None,
        }
    }
}

fn emit(update: ChecksumUpdateView) {
    app::emit(AppEvent { checksum: Some(update), ..AppEvent::of(AppEventKind::ChecksumProgress, None) });
}

fn file_view(index: usize, file: &ChecksumFile) -> ChecksumFileView {
    ChecksumFileView {
        index: index as i64,
        name: file.name.clone(),
        path: file.path.to_string_lossy().into_owned(),
        size: file.size as i64,
        expected: file.expected.clone(),
    }
}

fn outcome_view(outcome: ChecksumOutcome) -> ChecksumOutcomeView {
    ChecksumOutcomeView {
        index: outcome.index as i64,
        status: match outcome.status {
            ChecksumStatus::Ok => ChecksumStatusView::Ok,
            ChecksumStatus::Mismatch => ChecksumStatusView::Mismatch,
            ChecksumStatus::Missing => ChecksumStatusView::Missing,
            ChecksumStatus::Error => ChecksumStatusView::Error,
        },
        hash: outcome.hash,
        error: outcome.error.map(FerryxError::from),
    }
}

/// The files go out in batches, then the hashes as they come.
fn hash_and_report(
    id: i64,
    cancel: &AtomicBool,
    files: Vec<ChecksumFile>,
    algorithm: Algorithm,
    from_sums: Option<usize>,
) {
    let mut first = ChecksumUpdateView::empty(id);
    first.files_total = files.len() as i64;
    first.bytes_total = files.iter().map(|f| f.size as i64).sum();
    if let Some(bad_lines) = from_sums {
        first.algorithm = Some(ChecksumAlgorithmView::from_ops(algorithm));
        first.bad_lines = bad_lines as i64;
    }
    for (chunk_index, chunk) in files.chunks(tasks::BATCH_ROWS * 4).enumerate() {
        let base = chunk_index * tasks::BATCH_ROWS * 4;
        emit(ChecksumUpdateView {
            files: chunk.iter().enumerate().map(|(i, f)| file_view(base + i, f)).collect(),
            ..first.clone()
        });
    }
    let pending = RefCell::new(first);
    let pacer = RefCell::new(Pacer::new());
    let flush = |force: bool| {
        let mut update = pending.borrow_mut();
        let mut pacer = pacer.borrow_mut();
        if force || pacer.due(update.outcomes.len()) {
            let outcomes = std::mem::take(&mut update.outcomes);
            emit(ChecksumUpdateView { outcomes, ..update.clone() });
            pacer.sent();
        }
    };
    checksum::hash_all(
        &files,
        algorithm,
        cancel,
        tasks::BATCH,
        &mut |outcome| {
            pending.borrow_mut().outcomes.push(outcome_view(outcome));
            flush(false);
        },
        &mut |progress| {
            {
                let mut update = pending.borrow_mut();
                update.files_done = progress.files_done as i64;
                update.bytes_done = progress.bytes_done as i64;
                update.current = progress.current.clone();
            }
            flush(false);
        },
    );
    pending.borrow_mut().done = true;
    pending.borrow_mut().current = None;
    flush(true);
}

/// Starts hashing the files under `request.paths` and answers the task's
/// id; `ChecksumProgress` events bring the files, then their hashes.
pub fn start_checksums(request: ChecksumRequestView) -> i64 {
    let (id, cancel) = tasks::begin();
    let ops_request = ChecksumRequest {
        paths: request.paths.iter().map(PathBuf::from).collect(),
        base: PathBuf::from(&request.base),
        algorithm: request.algorithm.to_ops(),
        recursive: request.recursive,
        include_hidden: request.include_hidden,
    };
    let spawned = std::thread::Builder::new().name(format!("checksums {id}")).spawn(move || {
        let files = checksum::expand(&ops_request, &cancel);
        hash_and_report(id, &cancel, files, ops_request.algorithm, None);
        tasks::end(id);
    });
    if spawned.is_err() {
        emit(ChecksumUpdateView {
            done: true,
            error: Some("could not start".to_string()),
            ..ChecksumUpdateView::empty(id)
        });
    }
    id
}

/// Starts checking the files a checksum file lists and answers the task's
/// id; the first event names the algorithm, the outcomes say OK, mismatch
/// or missing.
pub fn start_checksum_verify(sums_path: String) -> i64 {
    let (id, cancel) = tasks::begin();
    let spawned = std::thread::Builder::new().name(format!("verify {id}")).spawn(move || {
        match checksum::read_sums(Path::new(&sums_path)) {
            Ok(sums) => hash_and_report(id, &cancel, sums.files, sums.algorithm, Some(sums.bad_lines)),
            Err(message) => {
                emit(ChecksumUpdateView { done: true, error: Some(message), ..ChecksumUpdateView::empty(id) })
            }
        }
        tasks::end(id);
    });
    if spawned.is_err() {
        emit(ChecksumUpdateView {
            done: true,
            error: Some("could not start".to_string()),
            ..ChecksumUpdateView::empty(id)
        });
    }
    id
}

pub fn cancel_checksums(task_id: i64) {
    tasks::cancel(task_id);
}

/// Writes `lines` as a checksum file at `path` (GNU form); an existing file
/// is replaced only with `overwrite`. On the journal: undo removes a new
/// file.
pub fn save_checksum_file(path: String, lines: Vec<ChecksumLineView>, overwrite: bool) -> ApiResult<()> {
    let path = PathBuf::from(path);
    let existed = path.symlink_metadata().is_ok();
    if existed && !overwrite {
        return Err(FerryxError {
            kind: FerryxErrorKind::AlreadyExists,
            message: format!("{} already exists", path.display()),
            path: Some(path.to_string_lossy().into_owned()),
        });
    }
    let text = checksum::format_sums(&lines.into_iter().map(|l| (l.hash, l.name)).collect::<Vec<_>>());
    let mut file = std::fs::File::create(&path).map_err(|e| ferryx_vfs::VfsError::io(&e, &path))?;
    file.write_all(text.as_bytes()).map_err(|e| ferryx_vfs::VfsError::io(&e, &path))?;
    drop(file);
    let change = if existed {
        Change::Overwritten { path: path.clone() }
    } else {
        Change::Created { path: path.clone(), fingerprint: ferryx_ops::journal::Fingerprint::of(&path) }
    };
    tasks::record(StepKind::CreateFile, std::slice::from_ref(&path), vec![change]);
    Ok(())
}
