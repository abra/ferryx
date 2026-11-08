//! Runs operations on threads and holds their state.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant, SystemTime};

use ferryx_vfs::VfsError;
use parking_lot::{Condvar, Mutex, MutexGuard};

use crate::journal::{Change, Direction, Fingerprint, Journal, Step, StepKind, StepRecord};
use crate::types::*;
use crate::{compress, copy, delete, extract, sizes};

/// Hears every operation's reports. A report carries its lists as news:
/// `errors` and `sizes` added since the operation's previous report, and
/// `sources` in its first and last report only (empty in between). The
/// whole lists are in [`OpContext::snapshot`] and [`Runner::progress`].
pub type Listener = Arc<dyn Fn(Progress) + Send + Sync>;

/// Work the runner runs as an operation: a module's own job, with the
/// operation's context to check, report and ask through.
pub type Job = Box<dyn FnOnce(&OpContext) -> Result<(), Abort> + Send>;

/// What becomes of an operation's changes in the journal.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Journaling {
    /// Nothing is recorded (sizes, a comparison, a permanent delete).
    Off,
    /// The changes become a new step of this kind.
    Record { kind: StepKind, items: u64, first_name: String },
    /// The operation walks `step` one way: what it does goes on the other
    /// stack, what it leaves back on the step's own.
    Walk { direction: Direction, step: Box<Step> },
}

/// More changes than this in one operation are not kept: its step is on
/// record, but cannot be undone.
const MAX_CHANGES: usize = 200_000;

/// How often progress is reported while work goes on; a change of state,
/// a question and the end are reported at once.
const REPORT_EVERY: Duration = Duration::from_millis(100);

/// Every running and finished operation.
pub struct Runner {
    ops: Mutex<HashMap<u64, Arc<OpContext>>>,
    next_id: AtomicU64,
    listener: Mutex<Option<Listener>>,
    journal: Arc<Journal>,
}

impl Default for Runner {
    fn default() -> Self {
        Runner::new()
    }
}

impl Runner {
    pub fn new() -> Runner {
        Runner {
            ops: Mutex::new(HashMap::new()),
            next_id: AtomicU64::new(1),
            listener: Mutex::new(None),
            journal: Arc::new(Journal::new()),
        }
    }

    /// The undo journal every operation records into.
    pub fn journal(&self) -> &Arc<Journal> {
        &self.journal
    }

    /// The one listener every operation reports to; a later call replaces
    /// the earlier listener.
    pub fn set_listener(&self, listener: Listener) {
        *self.listener.lock() = Some(listener);
    }

    /// Starts `request` on a thread and answers its id.
    pub fn start(&self, request: OpRequest) -> u64 {
        let journaling = journaling_of(&request);
        let job: Job = {
            let request = request.clone();
            Box::new(move |ctx: &OpContext| run(ctx, request))
        };
        self.start_job(request, journaling, job)
    }

    /// Starts `job` as an operation described by `request` (its kind,
    /// sources and destination are what the interface shows) and answers
    /// its id. At its end its changes go to the journal as `journaling`
    /// says, before the last report.
    pub fn start_job(&self, request: OpRequest, journaling: Journaling, job: Job) -> u64 {
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let ctx = Arc::new(OpContext::new(id, &request, self.listener.lock().clone()));
        self.ops.lock().insert(id, ctx.clone());
        let worker = ctx.clone();
        let journal = self.journal.clone();
        let name = format!("op {id} {:?}", request.kind);
        let spawned = thread::Builder::new().name(name).spawn(move || {
            let outcome = job(&worker);
            worker.commit(&journal, journaling);
            worker.finish(outcome);
        });
        if let Err(e) = spawned {
            ctx.fail(e.to_string());
        }
        id
    }

    pub fn pause(&self, id: u64) {
        if let Some(op) = self.get(id) {
            op.set_paused(true);
        }
    }

    pub fn resume(&self, id: u64) {
        if let Some(op) = self.get(id) {
            op.set_paused(false);
        }
    }

    pub fn cancel(&self, id: u64) {
        if let Some(op) = self.get(id) {
            op.cancel();
        }
    }

    /// Answers the question `question_id` of operation `id`; an answer to a
    /// question no longer asked is dropped.
    pub fn answer(&self, id: u64, question_id: u64, answer: Answer) {
        if let Some(op) = self.get(id) {
            op.answer(question_id, answer);
        }
    }

    pub fn progress(&self, id: u64) -> Option<Progress> {
        self.get(id).map(|op| op.snapshot())
    }

    pub fn all(&self) -> Vec<Progress> {
        let mut out: Vec<Progress> = self.ops.lock().values().map(|op| op.snapshot()).collect();
        out.sort_by_key(|p| p.id);
        out
    }

    /// Forgets a finished operation.
    pub fn remove(&self, id: u64) {
        let mut ops = self.ops.lock();
        if ops.get(&id).map(|op| op.snapshot().state.is_finished()).unwrap_or(false) {
            ops.remove(&id);
        }
    }

    fn get(&self, id: u64) -> Option<Arc<OpContext>> {
        self.ops.lock().get(&id).cloned()
    }
}

/// How an operation of `request`'s kind goes on record.
fn journaling_of(request: &OpRequest) -> Journaling {
    let kind = match request.kind {
        OpKind::Copy => StepKind::Copy,
        OpKind::Move => StepKind::Move,
        OpKind::Trash => StepKind::Trash,
        OpKind::Duplicate => StepKind::Duplicate,
        OpKind::Compress => StepKind::Compress,
        OpKind::Extract => StepKind::Extract,
        OpKind::Synchronize => StepKind::Synchronize,
        OpKind::Delete | OpKind::CalcSizes | OpKind::CompareContents | OpKind::Undo | OpKind::Redo => {
            return Journaling::Off
        }
    };
    let record = StepRecord::for_paths(kind, &request.sources, Vec::new());
    Journaling::Record { kind, items: record.items, first_name: record.first_name }
}

fn run(ctx: &OpContext, request: OpRequest) -> Result<(), Abort> {
    match request.kind {
        OpKind::Copy | OpKind::Move | OpKind::Duplicate => copy::run(ctx, &request),
        OpKind::Extract => extract::run(ctx, &request),
        OpKind::Delete | OpKind::Trash => delete::run(ctx, &request),
        OpKind::Compress => compress::run(ctx, &request),
        OpKind::CalcSizes => sizes::run(ctx, &request),
        // Jobs of their own (`Runner::start_job`): nothing runs from the
        // request alone.
        OpKind::Synchronize | OpKind::CompareContents | OpKind::Undo | OpKind::Redo => {
            ctx.record_error(Path::new(""), format!("{:?} runs as a job of its own", request.kind));
            Err(Abort::Stopped)
        }
    }
}

#[derive(Default)]
struct Sticky {
    files: Option<Answer>,
    directories: Option<Answer>,
    errors: Option<Answer>,
}

/// One operation's state and controls, shared by its thread and the
/// runner.
pub struct OpContext {
    progress: Mutex<Reported>,
    cancelled: AtomicBool,
    paused: Mutex<bool>,
    unpaused: Condvar,
    pending: Mutex<Option<(u64, Option<Answer>)>>,
    answered: Condvar,
    next_question: AtomicU64,
    sticky: Mutex<Sticky>,
    listener: Option<Listener>,
    started: Instant,
    recorder: Mutex<Recorder>,
}

/// The progress, and how much of it the listener has heard.
struct Reported {
    progress: Progress,
    last_report: Option<Instant>,
    errors_sent: usize,
    sizes_sent: usize,
}

impl Reported {
    /// The next report: the progress with its lists cut to the news (see
    /// [`Listener`]).
    fn next_report(&mut self) -> Progress {
        let p = &self.progress;
        let sources =
            if self.last_report.is_none() || p.state.is_finished() { p.sources.clone() } else { Vec::new() };
        let report = Progress {
            id: p.id,
            kind: p.kind,
            state: p.state,
            bytes_done: p.bytes_done,
            bytes_total: p.bytes_total,
            items_done: p.items_done,
            items_total: p.items_total,
            current: p.current.clone(),
            started_ms: p.started_ms,
            elapsed_ms: p.elapsed_ms,
            bytes_per_second: p.bytes_per_second,
            errors: p.errors[self.errors_sent.min(p.errors.len())..].to_vec(),
            question: p.question.clone(),
            sizes: p.sizes[self.sizes_sent.min(p.sizes.len())..].to_vec(),
            result_path: p.result_path.clone(),
            sources,
            destination: p.destination.clone(),
        };
        self.errors_sent = p.errors.len();
        self.sizes_sent = p.sizes.len();
        self.last_report = Some(Instant::now());
        report
    }

    fn due(&self) -> bool {
        self.last_report.is_none_or(|at| at.elapsed() >= REPORT_EVERY)
    }
}

/// The changes an operation made, for the journal.
#[derive(Default)]
struct Recorder {
    changes: Vec<Change>,
    /// Items this operation created: what is made inside them needs no
    /// record of its own.
    created: HashSet<PathBuf>,
    /// Items this operation replaced: what takes their place is not new.
    overwritten: HashSet<PathBuf>,
    /// Walking a step: the changes it did not get to.
    left: Vec<Change>,
    overflow: bool,
}

impl Recorder {
    fn push(&mut self, change: Change) {
        if self.changes.len() >= MAX_CHANGES {
            self.overflow = true;
            return;
        }
        self.changes.push(change);
    }

    fn inside_created(&self, path: &Path) -> bool {
        !self.created.is_empty() && path.ancestors().skip(1).any(|a| self.created.contains(a))
    }
}

impl OpContext {
    fn new(id: u64, request: &OpRequest, listener: Option<Listener>) -> OpContext {
        let started_ms = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);
        OpContext {
            progress: Mutex::new(Reported {
                progress: Progress {
                    id,
                    kind: request.kind,
                    state: OpState::Scanning,
                    bytes_done: 0,
                    bytes_total: 0,
                    items_done: 0,
                    items_total: 0,
                    current: String::new(),
                    started_ms,
                    elapsed_ms: 0,
                    bytes_per_second: 0,
                    errors: Vec::new(),
                    question: None,
                    sizes: Vec::new(),
                    result_path: None,
                    sources: request.sources.clone(),
                    destination: request.destination.clone(),
                },
                last_report: None,
                errors_sent: 0,
                sizes_sent: 0,
            }),
            cancelled: AtomicBool::new(false),
            paused: Mutex::new(false),
            unpaused: Condvar::new(),
            pending: Mutex::new(None),
            answered: Condvar::new(),
            next_question: AtomicU64::new(1),
            sticky: Mutex::new(Sticky::default()),
            listener,
            started: Instant::now(),
            recorder: Mutex::new(Recorder::default()),
        }
    }

    /// Makes a context that reports nowhere, for the modules' tests.
    pub fn detached(request: &OpRequest) -> OpContext {
        OpContext::new(0, request, None)
    }

    /// Makes a context that reports to `listener`, for the modules' tests.
    pub fn listened(request: &OpRequest, listener: Listener) -> OpContext {
        OpContext::new(0, request, Some(listener))
    }

    /// The whole progress, its lists complete.
    pub fn snapshot(&self) -> Progress {
        self.progress.lock().progress.clone()
    }

    // ─── Controls ───

    fn set_paused(&self, paused: bool) {
        {
            let mut guard = self.paused.lock();
            *guard = paused;
        }
        self.unpaused.notify_all();
        let state = if paused { OpState::Paused } else { OpState::Running };
        self.update_now(|p| {
            if !p.state.is_finished() && p.question.is_none() {
                p.state = state;
            }
        });
    }

    pub(crate) fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
        self.set_paused(false);
        // A question waits no longer.
        {
            let mut pending = self.pending.lock();
            if let Some((_, answer)) = pending.as_mut() {
                *answer = Some(Answer::Abort);
            }
        }
        self.answered.notify_all();
    }

    fn answer(&self, question_id: u64, answer: Answer) {
        let mut pending = self.pending.lock();
        match pending.as_mut() {
            Some((id, slot)) if *id == question_id => *slot = Some(answer),
            _ => return,
        }
        drop(pending);
        self.answered.notify_all();
    }

    // ─── Used by the operations ───

    /// Stops the operation when it was cancelled; waits while it is paused.
    pub fn check(&self) -> Result<(), Abort> {
        if self.cancelled.load(Ordering::SeqCst) {
            return Err(Abort::Cancelled);
        }
        let mut paused = self.paused.lock();
        while *paused {
            self.unpaused.wait(&mut paused);
            if self.cancelled.load(Ordering::SeqCst) {
                return Err(Abort::Cancelled);
            }
        }
        Ok(())
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }

    /// Changes the progress; reports it when the last report is old enough.
    pub fn update(&self, f: impl FnOnce(&mut Progress)) {
        let mut reported = self.progress.lock();
        f(&mut reported.progress);
        self.report(reported, false);
    }

    /// Changes the progress and reports it at once: a change of state.
    pub fn update_now(&self, f: impl FnOnce(&mut Progress)) {
        let mut reported = self.progress.lock();
        f(&mut reported.progress);
        self.report(reported, true);
    }

    /// Adds bytes to the count; reports when the last report is old enough.
    pub fn add_bytes(&self, bytes: u64) {
        let mut reported = self.progress.lock();
        let p = &mut reported.progress;
        p.bytes_done += bytes;
        let elapsed = self.started.elapsed().as_secs_f64();
        if elapsed > 0.0 {
            p.bytes_per_second = (p.bytes_done as f64 / elapsed) as u64;
        }
        self.report(reported, false);
    }

    /// Takes back bytes counted by an attempt that failed.
    pub fn take_back_bytes(&self, bytes: u64) {
        if bytes > 0 {
            self.update(|p| p.bytes_done = p.bytes_done.saturating_sub(bytes));
        }
    }

    pub fn set_current(&self, path: &Path) {
        self.update(|p| p.current = path.to_string_lossy().into_owned());
    }

    pub fn item_done(&self) {
        self.update(|p| p.items_done += 1);
    }

    pub fn set_totals(&self, bytes: u64, items: u64) {
        self.update_now(|p| {
            p.bytes_total = bytes;
            p.items_total = items;
            p.state = OpState::Running;
        });
    }

    /// Records an error skipped on the way. The first is reported at once
    /// (the interface shows it); the rest come with the next report.
    pub fn record_error(&self, path: &Path, message: String) {
        let mut reported = self.progress.lock();
        let errors = &mut reported.progress.errors;
        errors.push(OpError { path: path.to_string_lossy().into_owned(), message });
        let first = errors.len() == 1;
        self.report(reported, first);
    }

    /// Asks about a conflict at `existing` and waits for the answer; an
    /// "…All" answer applies to the same kind of conflict: merging folders
    /// never authorizes replacing files inside them.
    /// Answers `Err` when the operation is to stop.
    pub fn ask_conflict(
        &self,
        source: ConflictSide,
        existing: ConflictSide,
        answers: Vec<Answer>,
    ) -> Result<Answer, Abort> {
        let directories = source.is_dir && existing.is_dir;
        let remembered = {
            let sticky = self.sticky.lock();
            if directories {
                sticky.directories
            } else {
                sticky.files
            }
        };
        if let Some(answer) = remembered.filter(|a| answers.contains(a)) {
            return Ok(answer);
        }
        let message = format!(
            "“{}” already exists in the destination",
            Path::new(&existing.path)
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default()
        );
        let answer = self.ask(QuestionKind::Conflict, message, Some(source), Some(existing), answers)?;
        if matches!(
            answer,
            Answer::OverwriteAll
                | Answer::OverwriteOlderAll
                | Answer::SkipAll
                | Answer::KeepBothAll
                | Answer::MergeAll
        ) {
            let mut sticky = self.sticky.lock();
            if directories {
                sticky.directories = Some(answer);
            } else {
                sticky.files = Some(answer);
            }
        }
        Ok(answer)
    }

    /// Asks what to do about `error` at `path`: retry, skip or stop. Skip
    /// records the error. Answers `Ok(true)` to retry, `Ok(false)` to go on.
    pub fn ask_error(&self, path: &Path, error: &VfsError) -> Result<bool, Abort> {
        let sticky = self.sticky.lock().errors;
        let answer = match sticky {
            Some(answer) => answer,
            None => {
                let side = ConflictSide {
                    path: path.to_string_lossy().into_owned(),
                    size: None,
                    modified_ms: None,
                    is_dir: false,
                };
                self.ask(
                    QuestionKind::Error,
                    error.message.clone(),
                    Some(side),
                    None,
                    vec![Answer::Retry, Answer::Skip, Answer::SkipAll, Answer::Abort],
                )?
            }
        };
        match answer {
            Answer::Retry => Ok(true),
            Answer::Abort => Err(Abort::Stopped),
            Answer::SkipAll => {
                self.sticky.lock().errors = Some(Answer::SkipAll);
                self.record_error(path, error.message.clone());
                Ok(false)
            }
            _ => {
                self.record_error(path, error.message.clone());
                Ok(false)
            }
        }
    }

    /// Asks what to do about `error` at `path` where trying again cannot
    /// help (a stream already read past): skip or stop. Skip records the
    /// error.
    pub fn ask_skip(&self, path: &Path, error: &VfsError) -> Result<(), Abort> {
        let sticky = self.sticky.lock().errors;
        let answer = match sticky {
            Some(answer) => answer,
            None => {
                let side = ConflictSide {
                    path: path.to_string_lossy().into_owned(),
                    size: None,
                    modified_ms: None,
                    is_dir: false,
                };
                self.ask(
                    QuestionKind::Error,
                    error.message.clone(),
                    Some(side),
                    None,
                    vec![Answer::Skip, Answer::SkipAll, Answer::Abort],
                )?
            }
        };
        match answer {
            Answer::Abort => Err(Abort::Stopped),
            Answer::SkipAll => {
                self.sticky.lock().errors = Some(Answer::SkipAll);
                self.record_error(path, error.message.clone());
                Ok(())
            }
            _ => {
                self.record_error(path, error.message.clone());
                Ok(())
            }
        }
    }

    fn ask(
        &self,
        kind: QuestionKind,
        message: String,
        source: Option<ConflictSide>,
        existing: Option<ConflictSide>,
        answers: Vec<Answer>,
    ) -> Result<Answer, Abort> {
        if self.cancelled.load(Ordering::SeqCst) {
            return Err(Abort::Cancelled);
        }
        if self.listener.is_none() {
            // Nobody to ask: the first answer offered stands, but never
            // Retry, which would try the same thing for ever.
            return Ok(answers.iter().copied().find(|a| *a != Answer::Retry).unwrap_or(Answer::Abort));
        }
        let id = self.next_question.fetch_add(1, Ordering::SeqCst);
        let question = Question { id, kind, message, source, existing, answers };
        *self.pending.lock() = Some((id, None));
        self.update_now(|p| {
            p.question = Some(question);
            p.state = OpState::Waiting;
        });
        let answer = {
            let mut pending = self.pending.lock();
            loop {
                if let Some((_, Some(answer))) = pending.as_ref() {
                    break *answer;
                }
                self.answered.wait(&mut pending);
            }
        };
        *self.pending.lock() = None;
        self.update_now(|p| {
            p.question = None;
            p.state = if *self.paused.lock() { OpState::Paused } else { OpState::Running };
        });
        if self.cancelled.load(Ordering::SeqCst) {
            return Err(Abort::Cancelled);
        }
        Ok(answer)
    }

    // ─── The journal ───

    /// Records `change` as done by this operation.
    pub fn record(&self, change: Change) {
        self.recorder.lock().push(change);
    }

    /// Records the item at `path` as made by this operation, unless it is
    /// inside an item the operation made. Called once the item is complete
    /// (attributes set), so its fingerprint is the final one.
    pub fn record_created(&self, path: &Path) {
        let mut recorder = self.recorder.lock();
        if recorder.created.contains(path)
            || recorder.overwritten.contains(path)
            || recorder.inside_created(path)
        {
            return;
        }
        recorder.created.insert(path.to_path_buf());
        recorder.push(Change::Created { path: path.to_path_buf(), fingerprint: Fingerprint::of(path) });
    }

    /// Records the item at `path` as replaced: its earlier contents are
    /// lost, and what takes its place is no new item.
    pub fn record_overwritten(&self, path: &Path) {
        let mut recorder = self.recorder.lock();
        if !recorder.inside_created(path) && recorder.overwritten.insert(path.to_path_buf()) {
            recorder.push(Change::Overwritten { path: path.to_path_buf() });
        }
    }

    /// Records the item at `from` as renamed to `to` (what it replaced is
    /// on record already, as overwritten).
    pub fn record_moved(&self, from: &Path, to: &Path) {
        self.recorder.lock().push(Change::Moved { from: from.to_path_buf(), to: to.to_path_buf() });
    }

    /// Where the record stands: a move across volumes takes it before its
    /// copy, for [`OpContext::record_moved_by_copy`].
    pub(crate) fn record_mark(&self) -> usize {
        self.recorder.lock().changes.len()
    }

    /// After a copied file or link is removed from its source, replace
    /// its creation with a move. Keep any overwrite on record. Folders
    /// have their own creation/removal records, even for a partial move.
    pub(crate) fn record_moved_by_copy(&self, mark: usize, from: &Path, to: &Path) {
        let mut recorder = self.recorder.lock();
        let mark = mark.min(recorder.changes.len());
        let created = recorder.changes[mark..]
            .iter()
            .position(|c| matches!(c, Change::Created { path, .. } if path == to));
        if let Some(offset) = created {
            recorder.changes.remove(mark + offset);
            recorder.created.remove(to);
        }
        // Even into a folder this operation made: the item came from
        // elsewhere, and going back it must leave before the folder goes.
        recorder.push(Change::Moved { from: from.to_path_buf(), to: to.to_path_buf() });
    }

    /// Walking a step: records `change` as not done, for the next walk.
    pub fn record_left(&self, change: Change) {
        self.recorder.lock().left.push(change);
    }

    /// Hands the recorded changes to `journal` as `journaling` says.
    fn commit(&self, journal: &Journal, journaling: Journaling) {
        let recorder = std::mem::take(&mut *self.recorder.lock());
        match journaling {
            Journaling::Off => {}
            Journaling::Record { kind, items, first_name } => {
                journal.record(StepRecord {
                    kind,
                    items,
                    first_name,
                    changes: if recorder.overflow { Vec::new() } else { recorder.changes },
                    truncated: recorder.overflow,
                });
            }
            Journaling::Walk { direction, step } => {
                journal.finish_walk(direction, &step, recorder.changes, recorder.left);
            }
        }
    }

    /// The changes recorded so far, for the modules' tests.
    pub fn recorded(&self) -> Vec<Change> {
        self.recorder.lock().changes.clone()
    }

    /// The changes recorded as not done, for the modules' tests.
    pub fn recorded_left(&self) -> Vec<Change> {
        self.recorder.lock().left.clone()
    }

    fn finish(&self, outcome: Result<(), Abort>) {
        self.update_now(|p| {
            p.question = None;
            p.current.clear();
            p.state = match outcome {
                Ok(()) if p.errors.is_empty() => OpState::Done,
                Ok(()) => OpState::DoneWithErrors,
                Err(Abort::Cancelled) => OpState::Cancelled,
                Err(Abort::Stopped) => OpState::Failed,
            };
        });
    }

    fn fail(&self, message: String) {
        self.update_now(|p| {
            p.errors.push(OpError { path: String::new(), message });
            p.state = OpState::Failed;
        });
    }

    /// Reports the progress when `now` or when the last report is old
    /// enough; the listener is called with the lock released.
    fn report(&self, mut reported: MutexGuard<'_, Reported>, now: bool) {
        reported.progress.elapsed_ms = self.started.elapsed().as_millis() as u64;
        let Some(listener) = &self.listener else { return };
        if !now && !reported.due() {
            return;
        }
        let report = reported.next_report();
        drop(reported);
        listener(report);
    }
}

/// `name 2.ext`, `name 3.ext`… the first that is free in `dir`.
pub fn free_name(dir: &Path, name: &str) -> PathBuf {
    let (stem, ext) = ferryx_core::entry::split_name(name);
    for n in 2.. {
        let candidate = if ext.is_empty() { format!("{stem} {n}") } else { format!("{stem} {n}.{ext}") };
        let path = dir.join(&candidate);
        if !path.exists() && path.symlink_metadata().is_err() {
            return path;
        }
    }
    unreachable!()
}

/// `name copy.ext`, `name copy 2.ext`… as Finder names a duplicate.
pub fn copy_name(dir: &Path, name: &str) -> PathBuf {
    let (stem, ext) = ferryx_core::entry::split_name(name);
    let first = if ext.is_empty() { format!("{stem} copy") } else { format!("{stem} copy.{ext}") };
    if dir.join(&first).symlink_metadata().is_err() {
        return dir.join(first);
    }
    for n in 2.. {
        let candidate =
            if ext.is_empty() { format!("{stem} copy {n}") } else { format!("{stem} copy {n}.{ext}") };
        let path = dir.join(&candidate);
        if path.symlink_metadata().is_err() {
            return path;
        }
    }
    unreachable!()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(kind: OpKind) -> OpRequest {
        OpRequest {
            kind,
            sources: Vec::new(),
            archive: None,
            destination: None,
            new_name: None,
            options: OpOptions::default(),
        }
    }

    /// A context whose listener keeps every report.
    fn listening(request: &OpRequest) -> (OpContext, Arc<Mutex<Vec<Progress>>>) {
        let reports = Arc::new(Mutex::new(Vec::new()));
        let sink = reports.clone();
        (OpContext::listened(request, Arc::new(move |p| sink.lock().push(p))), reports)
    }

    #[test]
    fn reports_are_throttled_but_changes_of_state_go_at_once() {
        let (ctx, reports) = listening(&request(OpKind::Copy));
        ctx.set_totals(3000, 3000);
        let start = Instant::now();
        for i in 0..1000 {
            ctx.add_bytes(1);
            ctx.item_done();
            ctx.update(|p| p.items_done += i % 2);
        }
        // One report for the totals, then one per period at most.
        let allowed = 2 + start.elapsed().as_millis() as usize / REPORT_EVERY.as_millis() as usize;
        assert!(reports.lock().len() <= allowed, "{} reports", reports.lock().len());
        let before = reports.lock().len();
        ctx.set_paused(true);
        assert_eq!(reports.lock().len(), before + 1);
        assert_eq!(reports.lock().last().unwrap().state, OpState::Paused);
        ctx.set_paused(false);
        ctx.finish(Ok(()));
        let last = reports.lock().last().cloned().unwrap();
        assert_eq!(last.state, OpState::Done);
        assert_eq!((last.bytes_done, last.items_done), (1000, 1500));
    }

    #[test]
    fn reports_carry_their_lists_as_news() {
        let mut req = request(OpKind::CalcSizes);
        req.sources = vec![PathBuf::from("/a"), PathBuf::from("/b")];
        let (ctx, reports) = listening(&req);
        ctx.set_totals(0, 2);
        ctx.update(|p| p.sizes.push(FolderSize { path: PathBuf::from("/a"), bytes: 1 }));
        ctx.record_error(Path::new("/x"), "first".to_string());
        ctx.update(|p| p.sizes.push(FolderSize { path: PathBuf::from("/b"), bytes: 2 }));
        ctx.record_error(Path::new("/y"), "second".to_string());
        ctx.finish(Ok(()));

        let whole = ctx.snapshot();
        assert_eq!(whole.sources, req.sources);
        assert_eq!(whole.sizes.len(), 2);
        assert_eq!(whole.errors.len(), 2);
        let reports = reports.lock();
        assert!(reports.len() >= 3);
        // The first error is shown at once, before the end.
        assert!(reports
            .iter()
            .any(|r| !r.state.is_finished() && r.errors.iter().any(|e| e.message == "first")));
        // Each size and error comes once; the sources first and last.
        let sizes: Vec<FolderSize> = reports.iter().flat_map(|r| r.sizes.clone()).collect();
        let errors: Vec<OpError> = reports.iter().flat_map(|r| r.errors.clone()).collect();
        assert_eq!((sizes, errors), (whole.sizes, whole.errors));
        assert_eq!(reports[0].sources, req.sources);
        assert_eq!(reports.last().unwrap().sources, req.sources);
        assert!(reports[1..reports.len() - 1].iter().all(|r| r.sources.is_empty()));
    }

    #[test]
    fn a_move_across_volumes_turns_what_its_copy_recorded_into_moves() {
        let (from, to) = (Path::new("/v1/src"), Path::new("/v2/dest/src"));
        let ctx = OpContext::detached(&request(OpKind::Move));
        // An item before it, renamed: not the copy's.
        ctx.record_moved(Path::new("/v2/a"), Path::new("/v2/dest/a"));
        // Each successfully copied and removed file records its move.
        let mark = ctx.record_mark();
        ctx.record_created(&to.join("new"));
        ctx.record_moved_by_copy(mark, &from.join("new"), &to.join("new"));
        let mark = ctx.record_mark();
        ctx.record_overwritten(&to.join("old"));
        ctx.record_moved_by_copy(mark, &from.join("old"), &to.join("old"));
        ctx.record_created(&to.join("deep"));
        let mark = ctx.record_mark();
        ctx.record_created(&to.join("deep/inner"));
        ctx.record_moved_by_copy(mark, &from.join("deep/inner"), &to.join("deep/inner"));
        assert_eq!(
            ctx.recorded(),
            vec![
                Change::Moved { from: PathBuf::from("/v2/a"), to: PathBuf::from("/v2/dest/a") },
                Change::Moved { from: from.join("new"), to: to.join("new") },
                Change::Overwritten { path: to.join("old") },
                Change::Moved { from: from.join("old"), to: to.join("old") },
                Change::Created { path: to.join("deep"), fingerprint: None },
                Change::Moved { from: from.join("deep/inner"), to: to.join("deep/inner") },
            ]
        );

        // Into a folder the operation made: the copy recorded nothing of
        // its own, the item moved all the same, after the folder came.
        let ctx = OpContext::detached(&request(OpKind::Move));
        ctx.record_created(Path::new("/v2/made"));
        let mark = ctx.record_mark();
        ctx.record_created(Path::new("/v2/made/x"));
        ctx.record_moved_by_copy(mark, Path::new("/v1/x"), Path::new("/v2/made/x"));
        assert_eq!(
            ctx.recorded(),
            vec![
                Change::Created { path: PathBuf::from("/v2/made"), fingerprint: None },
                Change::Moved { from: PathBuf::from("/v1/x"), to: PathBuf::from("/v2/made/x") },
            ]
        );
    }

    /// Times recording many moves: `cargo test --release -p ferryx_ops
    /// record_bench -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn record_bench() {
        let from = Path::new("/nowhere/from");
        let to = Path::new("/nowhere/to");
        for n in [10_000, 50_000] {
            let ctx = OpContext::detached(&request(OpKind::Move));
            let start = Instant::now();
            for i in 0..n {
                let name = format!("f{i}");
                ctx.record_moved(&from.join(&name), &to.join(&name));
            }
            println!("{n} renames recorded: {:?}", start.elapsed());
            let ctx = OpContext::detached(&request(OpKind::Move));
            let start = Instant::now();
            for i in 0..n {
                let name = format!("f{i}");
                let mark = ctx.record_mark();
                ctx.record_created(&to.join(&name));
                ctx.record_moved_by_copy(mark, &from.join(&name), &to.join(&name));
            }
            println!("{n} moves across volumes recorded: {:?}", start.elapsed());
        }
    }
}
