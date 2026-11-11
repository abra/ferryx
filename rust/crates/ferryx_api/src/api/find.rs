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
            let result = ferryx_ops::find::search(
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
            let (scanned, error, spotlight_failed) = match result {
                Ok(summary) => (summary.scanned, None, summary.spotlight_failed),
                Err(message) => (0, Some(message), false),
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
                find_spotlight_failed: spotlight_failed,
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

/// Sort a bounded search snapshot with the same rules as ordinary panels.
/// Only indices cross back; no filesystem reads or listing handle is needed.
pub fn sort_find_hits(
    hits: Vec<FindHitView>,
    options: crate::api::types::SortOptionsView,
) -> Result<Vec<i32>, String> {
    use ferryx_core::entry::{extension_of, Entry, EntryKind};
    use std::path::PathBuf;
    if hits.len() > 10_000 {
        return Err("Search snapshot exceeds 10000 entries".into());
    }
    let entries: Vec<_> = hits
        .iter()
        .map(|hit| {
            let path = PathBuf::from(&hit.path);
            let name = path.file_name().unwrap_or_default().to_string_lossy().into_owned();
            let mut entry = Entry::parent(path);
            entry.is_parent = false;
            entry.is_dir = hit.is_dir;
            entry.kind = if hit.is_dir { EntryKind::Directory } else { EntryKind::File };
            entry.extension = extension_of(&name).to_owned();
            entry.name = name;
            entry.size = (!hit.is_dir).then_some(hit.size.max(0) as u64);
            entry.modified_ms = hit.modified_ms;
            entry
        })
        .collect();
    let options = options.to_core();
    let mut order: Vec<_> = (0..entries.len()).collect();
    order.sort_by(|&a, &b| {
        ferryx_core::sorting::compare(&entries[a], &entries[b], &options)
            .then_with(|| hits[a].path.cmp(&hits[b].path))
    });
    Ok(order.into_iter().map(|index| index as i32).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::{CollationView, SortFieldView, SortOptionsView};

    #[test]
    fn search_sort_uses_panel_collation_and_metadata() {
        let hits = vec![
            FindHitView { path: "/root/file10.txt".into(), is_dir: false, size: 10, modified_ms: None },
            FindHitView { path: "/root/file2.txt".into(), is_dir: false, size: 20, modified_ms: None },
            FindHitView { path: "/root/dir".into(), is_dir: true, size: 0, modified_ms: None },
        ];
        let options = SortOptionsView {
            field: SortFieldView::Name,
            descending: false,
            folders_first: true,
            extensionless_folders: true,
            collation: CollationView::Natural,
        };
        assert_eq!(sort_find_hits(hits.clone(), options).unwrap(), [2, 1, 0]);
        assert_eq!(
            sort_find_hits(hits, SortOptionsView { field: SortFieldView::Size, descending: true, ..options })
                .unwrap(),
            [2, 1, 0]
        );
    }
}
