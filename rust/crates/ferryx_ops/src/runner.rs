//! Runs operations on threads and holds their state.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant, SystemTime};

use ferryx_vfs::VfsError;
use parking_lot::{Condvar, Mutex};

use crate::journal::{Change, Direction, Fingerprint, Journal, Step, StepKind, StepRecord};
use crate::types::*;
use crate::{compress, copy, delete, extract, sizes};

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

/// How often progress is reported while bytes flow.
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
    conflicts: Option<Answer>,
    errors: Option<Answer>,
}

/// One operation's state and controls, shared by its thread and the
/// runner.
pub struct OpContext {
    progress: Mutex<Progress>,
    cancelled: AtomicBool,
    paused: Mutex<bool>,
    unpaused: Condvar,
    pending: Mutex<Option<(u64, Option<Answer>)>>,
    answered: Condvar,
    next_question: AtomicU64,
    sticky: Mutex<Sticky>,
    listener: Option<Listener>,
    started: Instant,
    last_report: Mutex<Instant>,
    recorder: Mutex<Recorder>,
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
            progress: Mutex::new(Progress {
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
            last_report: Mutex::new(Instant::now() - REPORT_EVERY),
            recorder: Mutex::new(Recorder::default()),
        }
    }

    /// Makes a context that reports nowhere, for the modules' tests.
    pub fn detached(request: &OpRequest) -> OpContext {
        OpContext::new(0, request, None)
    }

    pub fn snapshot(&self) -> Progress {
        self.progress.lock().clone()
    }

    // ─── Controls ───

    fn set_paused(&self, paused: bool) {
        {
            let mut guard = self.paused.lock();
            *guard = paused;
        }
        self.unpaused.notify_all();
        let state = if paused { OpState::Paused } else { OpState::Running };
        self.update(|p| {
            if !p.state.is_finished() && p.question.is_none() {
                p.state = state;
            }
        });
    }

    fn cancel(&self) {
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

    /// Changes the progress and reports it at once.
    pub fn update(&self, f: impl FnOnce(&mut Progress)) {
        let snapshot = {
            let mut p = self.progress.lock();
            f(&mut p);
            p.elapsed_ms = self.started.elapsed().as_millis() as u64;
            p.clone()
        };
        *self.last_report.lock() = Instant::now();
        self.report(snapshot);
    }

    /// Adds bytes to the count and reports when enough time passed.
    pub fn add_bytes(&self, bytes: u64) {
        let mut p = self.progress.lock();
        p.bytes_done += bytes;
        let elapsed = self.started.elapsed();
        p.elapsed_ms = elapsed.as_millis() as u64;
        if elapsed.as_secs_f64() > 0.0 {
            p.bytes_per_second = (p.bytes_done as f64 / elapsed.as_secs_f64()) as u64;
        }
        let due = self.last_report.lock().elapsed() >= REPORT_EVERY;
        if due {
            let snapshot = p.clone();
            drop(p);
            *self.last_report.lock() = Instant::now();
            self.report(snapshot);
        }
    }

    pub fn set_current(&self, path: &Path) {
        let mut p = self.progress.lock();
        p.current = path.to_string_lossy().into_owned();
        let due = self.last_report.lock().elapsed() >= REPORT_EVERY;
        if due {
            let snapshot = p.clone();
            drop(p);
            *self.last_report.lock() = Instant::now();
            self.report(snapshot);
        }
    }

    pub fn item_done(&self) {
        let mut p = self.progress.lock();
        p.items_done += 1;
        let due = self.last_report.lock().elapsed() >= REPORT_EVERY;
        if due {
            let snapshot = p.clone();
            drop(p);
            *self.last_report.lock() = Instant::now();
            self.report(snapshot);
        }
    }

    pub fn set_totals(&self, bytes: u64, items: u64) {
        self.update(|p| {
            p.bytes_total = bytes;
            p.items_total = items;
            p.state = OpState::Running;
        });
    }

    pub fn record_error(&self, path: &Path, message: String) {
        self.update(|p| p.errors.push(OpError { path: path.to_string_lossy().into_owned(), message }));
    }

    /// Asks about a conflict at `existing` and waits for the answer; an
    /// "…All" answer is remembered and answers the next conflicts itself.
    /// Answers `Err` when the operation is to stop.
    pub fn ask_conflict(
        &self,
        source: ConflictSide,
        existing: ConflictSide,
        answers: Vec<Answer>,
    ) -> Result<Answer, Abort> {
        if let Some(sticky) = self.sticky.lock().conflicts {
            return Ok(sticky);
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
            self.sticky.lock().conflicts = Some(answer);
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
        self.update(|p| {
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
        self.update(|p| {
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

    /// Records the item at `from` as moved to `to`. A move across volumes
    /// copies first: what that copy recorded at `to` (or inside it)
    /// becomes the move of the item it came from.
    pub fn record_moved(&self, from: &Path, to: &Path) {
        self.convert_to_moves(from, to, true);
    }

    /// Records the items of the folder `from` as moved into the folder
    /// `to` that was there before (a merge across volumes): only what the
    /// copy recorded inside `to` moved, never `to` itself.
    pub fn record_merged(&self, from: &Path, to: &Path) {
        self.convert_to_moves(from, to, false);
    }

    fn convert_to_moves(&self, from: &Path, to: &Path, whole: bool) {
        let mut recorder = self.recorder.lock();
        let source_of = |path: &Path| {
            path.strip_prefix(to).ok().map(|rest| {
                if rest.as_os_str().is_empty() {
                    from.to_path_buf()
                } else {
                    from.join(rest)
                }
            })
        };
        let mut converted = false;
        let mut changes = Vec::with_capacity(recorder.changes.len());
        for change in std::mem::take(&mut recorder.changes) {
            match change {
                Change::Created { path, fingerprint } => match source_of(&path) {
                    Some(source) => {
                        converted = true;
                        changes.push(Change::Moved { from: source, to: path });
                    }
                    None => changes.push(Change::Created { path, fingerprint }),
                },
                Change::Overwritten { path } => {
                    let source = source_of(&path);
                    changes.push(Change::Overwritten { path: path.clone() });
                    if let Some(source) = source {
                        converted = true;
                        changes.push(Change::Moved { from: source, to: path });
                    }
                }
                other => changes.push(other),
            }
        }
        recorder.changes = changes;
        recorder.created.retain(|p| !p.starts_with(to));
        // Even into a folder this operation made: the item came from
        // elsewhere, and going back it must leave before the folder goes.
        if whole && !converted {
            recorder.push(Change::Moved { from: from.to_path_buf(), to: to.to_path_buf() });
        }
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
        self.update(|p| {
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
        self.update(|p| {
            p.errors.push(OpError { path: String::new(), message });
            p.state = OpState::Failed;
        });
    }

    fn report(&self, progress: Progress) {
        if let Some(listener) = &self.listener {
            listener(progress);
        }
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
