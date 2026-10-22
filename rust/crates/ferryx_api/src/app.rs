//! Process-wide state: the event sink, open listings, the operations
//! runner and the searches under way. Archive indexes and passwords are
//! kept by `ferryx_vfs::archive::shared`, which the operations use too.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, LazyLock};

use ferryx_core::entry::Entry;
use ferryx_ops::Runner;
use ferryx_vfs::archive::ArchiveIndex;
use ferryx_vfs::watch::FolderWatcher;
use ferryx_vfs::Location;
use parking_lot::Mutex;

use crate::api::types::{AppEvent, AppEventKind, ListingOptionsView};
use crate::frb_generated::StreamSink;

/// One open panel listing: its rows as read from disk, before sorting.
pub struct OpenListing {
    pub location: Location,
    pub options: ListingOptionsView,
    pub raw: Vec<Entry>,
    pub watcher: Option<FolderWatcher>,
}

#[derive(Default)]
pub struct AppState {
    pub listings: HashMap<String, OpenListing>,
    pub finds: HashMap<i64, Arc<AtomicBool>>,
}

static STATE: LazyLock<Mutex<AppState>> = LazyLock::new(|| Mutex::new(AppState::default()));
static EVENTS: Mutex<Option<StreamSink<AppEvent>>> = parking_lot::const_mutex(None);
static RUNNER: std::sync::OnceLock<Runner> = std::sync::OnceLock::new();
static NEXT_FIND: AtomicI64 = AtomicI64::new(1);
/// Events kept for a test instead of a listener; see [`record_events`].
static RECORDED: Mutex<Option<Vec<AppEvent>>> = parking_lot::const_mutex(None);

pub fn state() -> &'static Mutex<AppState> {
    &STATE
}

/// The operations runner, made on first use; its listener forwards every
/// progress report as an event.
pub fn runner() -> &'static Runner {
    RUNNER.get_or_init(|| {
        let runner = Runner::new();
        runner.set_listener(Arc::new(|progress| {
            emit(AppEvent::progress(crate::api::types::ProgressView::from(progress)));
        }));
        runner
    })
}

pub fn next_find_id() -> i64 {
    NEXT_FIND.fetch_add(1, Ordering::SeqCst)
}

/// Registers the Dart-side listener; only the latest sink receives events.
pub fn set_event_sink(sink: StreamSink<AppEvent>) {
    *EVENTS.lock() = Some(sink);
}

/// Sends `event` to Dart; silently dropped when nobody listens.
pub fn emit(event: AppEvent) {
    if let Some(recorded) = RECORDED.lock().as_mut() {
        recorded.push(event.clone());
    }
    if let Some(sink) = EVENTS.lock().as_ref() {
        // A closed sink only means the listener went away; nothing to do.
        let _ = sink.add(event);
    }
}

pub fn emit_directory_changed(listing_id: &str) {
    emit(AppEvent::of(AppEventKind::DirectoryChanged, Some(listing_id.to_string())));
}

/// The index of `archive`, read once and again when the file changed;
/// shared with the operations (see `ferryx_vfs::archive::shared`), read
/// without holding the state's lock.
pub fn archive_index(archive: &std::path::Path) -> Result<Arc<ArchiveIndex>, ferryx_vfs::VfsError> {
    ferryx_vfs::archive::shared::index(archive)
}

/// The password given for `archive`, if any.
pub fn archive_password(archive: &std::path::Path) -> Option<String> {
    ferryx_vfs::archive::shared::password(archive)
}

/// Keeps every event from now on for [`take_events`].
pub fn record_events() {
    *RECORDED.lock() = Some(Vec::new());
}

/// The events kept since the last call (see [`record_events`]).
pub fn take_events() -> Vec<AppEvent> {
    RECORDED.lock().as_mut().map(std::mem::take).unwrap_or_default()
}

pub fn reset_for_tests() {
    let mut guard = state().lock();
    guard.listings.clear();
    ferryx_vfs::archive::shared::clear();
    guard.finds.clear();
    *EVENTS.lock() = None;
    *RECORDED.lock() = None;
}
