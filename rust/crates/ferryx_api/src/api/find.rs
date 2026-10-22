//! Find Files on a thread; hits arrive as events.

use std::cell::RefCell;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::api::types::{AppEvent, AppEventKind, FindHitView, FindRequestView};
use crate::app;

/// How long hits are collected before an event carries them.
const BATCH: Duration = Duration::from_millis(80);

/// Hits and progress gathered between two events.
struct Batch {
    id: i64,
    pending: Vec<FindHitView>,
    last_sent: Instant,
    scanned: u64,
}

impl Batch {
    fn flush(&mut self, current: Option<String>) {
        app::emit(AppEvent {
            hits: std::mem::take(&mut self.pending),
            find_id: Some(self.id),
            find_current: current,
            find_scanned: self.scanned as i64,
            ..AppEvent::of(AppEventKind::FindProgress, None)
        });
        self.last_sent = Instant::now();
    }
}

/// Starts the search and answers its id. `FindProgress` events bring the
/// hits in batches and the folder being searched; `FindDone` ends it.
pub fn start_find(request: FindRequestView) -> i64 {
    let id = app::next_find_id();
    let cancel = Arc::new(AtomicBool::new(false));
    app::state().lock().finds.insert(id, cancel.clone());
    let ops_request = request.to_ops();
    std::thread::Builder::new()
        .name(format!("find {id}"))
        .spawn(move || {
            let batch =
                RefCell::new(Batch { id, pending: Vec::new(), last_sent: Instant::now(), scanned: 0 });
            let result = ferryx_ops::find::run(
                &ops_request,
                &cancel,
                &mut |hit| {
                    let mut b = batch.borrow_mut();
                    b.pending.push(FindHitView {
                        path: hit.path.to_string_lossy().into_owned(),
                        is_dir: hit.is_dir,
                        size: hit.size as i64,
                        modified_ms: hit.modified_ms,
                    });
                    if b.pending.len() >= 200 || b.last_sent.elapsed() >= BATCH {
                        b.flush(None);
                    }
                },
                &mut |current, scanned| {
                    let mut b = batch.borrow_mut();
                    b.scanned = scanned;
                    if b.last_sent.elapsed() >= BATCH {
                        b.flush(Some(current.to_string_lossy().into_owned()));
                    }
                },
            );
            let (scanned, error) = match result {
                Ok(scanned) => (scanned, None),
                Err(message) => (0, Some(message)),
            };
            {
                let mut b = batch.borrow_mut();
                b.scanned = scanned;
                if !b.pending.is_empty() {
                    b.flush(None);
                }
            }
            app::state().lock().finds.remove(&id);
            app::emit(AppEvent {
                find_id: Some(id),
                find_scanned: scanned as i64,
                find_error: error,
                ..AppEvent::of(AppEventKind::FindDone, None)
            });
        })
        .ok();
    id
}

pub fn cancel_find(id: i64) {
    if let Some(cancel) = app::state().lock().finds.get(&id) {
        cancel.store(true, Ordering::SeqCst);
    }
}
