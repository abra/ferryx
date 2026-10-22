//! Runs operations on threads and holds their state.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant, SystemTime};

use ferryx_vfs::VfsError;
use parking_lot::{Condvar, Mutex};

use crate::types::*;
use crate::{compress, copy, delete, sizes};

pub type Listener = Arc<dyn Fn(Progress) + Send + Sync>;

/// How often progress is reported while bytes flow.
const REPORT_EVERY: Duration = Duration::from_millis(100);

/// Every running and finished operation.
pub struct Runner {
    ops: Mutex<HashMap<u64, Arc<OpContext>>>,
    next_id: AtomicU64,
    listener: Mutex<Option<Listener>>,
}

impl Default for Runner {
    fn default() -> Self {
        Runner::new()
    }
}

impl Runner {
    pub fn new() -> Runner {
        Runner { ops: Mutex::new(HashMap::new()), next_id: AtomicU64::new(1), listener: Mutex::new(None) }
    }

    /// The one listener every operation reports to; a later call replaces
    /// the earlier listener.
    pub fn set_listener(&self, listener: Listener) {
        *self.listener.lock() = Some(listener);
    }

    /// Starts `request` on a thread and answers its id.
    pub fn start(&self, request: OpRequest) -> u64 {
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let ctx = Arc::new(OpContext::new(id, &request, self.listener.lock().clone()));
        self.ops.lock().insert(id, ctx.clone());
        let worker = ctx.clone();
        let name = format!("op {id} {:?}", request.kind);
        let spawned = thread::Builder::new().name(name).spawn(move || {
            let outcome = run(&worker, request);
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

fn run(ctx: &OpContext, request: OpRequest) -> Result<(), Abort> {
    match request.kind {
        OpKind::Copy | OpKind::Move | OpKind::Extract | OpKind::Duplicate => copy::run(ctx, &request),
        OpKind::Delete | OpKind::Trash => delete::run(ctx, &request),
        OpKind::Compress => compress::run(ctx, &request),
        OpKind::CalcSizes => sizes::run(ctx, &request),
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
            // Nobody to ask: the first answer offered stands.
            return Ok(answers.first().copied().unwrap_or(Answer::Abort));
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
