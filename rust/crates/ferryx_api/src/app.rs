//! Process-wide state: the event sink, open listings, the operations
//! runner and the searches under way. Archive indexes and passwords are
//! kept by `ferryx_vfs::archive::shared`, which the operations use too.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, LazyLock};

use ferryx_core::entry::Entry;
use ferryx_ops::Runner;
use ferryx_vfs::archive::ArchiveIndex;
use ferryx_vfs::watch::{Changes, FolderWatcher};
use ferryx_vfs::Location;
use parking_lot::Mutex;

use crate::api::types::{AppEvent, AppEventKind, ListingOptionsView};
use crate::frb_generated::StreamSink;

/// One open panel listing: its rows, sorted as the panel was last sent
/// them, and what changed since.
pub struct OpenListing {
    pub location: Location,
    pub options: ListingOptionsView,
    /// The rows in the order last sent; a flat view's stay empty.
    pub rows: Arc<Vec<Entry>>,
    /// The number of the rows last sent: an update names the rows it
    /// changes by it (see `api::listing`).
    pub version: i64,
    /// What the watcher reported since the rows were read.
    pub changes: Changes,
    /// Rows whose tags were not read since they were (see `api::tags`).
    pub untagged: Untagged,
    /// Names of the rows that had tags when they were last read.
    pub tagged: HashSet<String>,
    /// Held by a read again or a resort: one at a time changes the rows.
    pub turn: Arc<Mutex<()>>,
    pub watcher: Option<FolderWatcher>,
    /// A flat view's walk and rows (see `api::flat`).
    pub flat: Option<FlatListing>,
}

impl OpenListing {
    pub fn new(
        location: Location,
        options: ListingOptionsView,
        rows: Vec<Entry>,
        watcher: Option<FolderWatcher>,
        flat: Option<FlatListing>,
    ) -> OpenListing {
        OpenListing {
            location,
            options,
            rows: Arc::new(rows),
            version: next_version(),
            changes: Changes::Nothing,
            untagged: Untagged::All,
            tagged: HashSet::new(),
            turn: Arc::new(Mutex::new(())),
            watcher,
            flat,
        }
    }
}

/// The rows whose tags are still to be read.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Untagged {
    All,
    Names(HashSet<String>),
}

impl Untagged {
    pub fn add(&mut self, names: impl IntoIterator<Item = String>) {
        if let Untagged::Names(pending) = self {
            pending.extend(names);
        }
    }
}

static NEXT_VERSION: AtomicI64 = AtomicI64::new(1);

/// A number no rows sent had, of any listing.
pub fn next_version() -> i64 {
    NEXT_VERSION.fetch_add(1, Ordering::SeqCst)
}

/// The rows of a flat view, filled by its walk while the panel shows the
/// first ones; sorted (into an order the panel applies) once complete.
pub struct FlatListing {
    pub generation: i64,
    pub cancel: Arc<AtomicBool>,
    pub rows: Arc<Mutex<FlatRows>>,
}

#[derive(Default)]
pub struct FlatRows {
    pub entries: Vec<Entry>,
    /// Each row's folder relative to the root, in step with `entries`.
    pub folders: Vec<String>,
    pub done: bool,
    pub capped: bool,
}

impl Drop for FlatListing {
    /// A flat listing replaced or closed stops its walk.
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::SeqCst);
    }
}

static NEXT_GENERATION: AtomicI64 = AtomicI64::new(1);

/// A number no flat walk had: the panel tells a walk's rows from an older
/// one's by it.
pub fn next_generation() -> i64 {
    NEXT_GENERATION.fetch_add(1, Ordering::SeqCst)
}

#[derive(Default)]
pub struct AppState {
    pub listings: HashMap<String, OpenListing>,
    pub finds: HashMap<i64, Arc<AtomicBool>>,
    // ─── Network ───
    /// Each listing's latest read: its number and its stop. A read that is
    /// no longer the latest leaves the listing alone.
    pub reads: HashMap<String, Read>,
}

/// A listing's read under way (see [`begin_read`]).
#[derive(Clone)]
pub struct Read {
    pub generation: u64,
    pub stop: Arc<AtomicBool>,
}

static NEXT_READ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

/// A new read of `listing_id` (the panel opens a folder): the read under
/// way stops, and only this one may fill the listing from now on.
pub fn begin_read(listing_id: &str) -> Read {
    let read =
        Read { generation: NEXT_READ.fetch_add(1, Ordering::SeqCst), stop: Arc::new(AtomicBool::new(false)) };
    let earlier = state().lock().reads.insert(listing_id.to_string(), read.clone());
    if let Some(earlier) = earlier {
        earlier.stop.store(true, Ordering::SeqCst);
    }
    read
}

/// The read `listing_id` has under way, or a new one when none is (a
/// refresh reads as the latest read and stops with it).
pub fn current_read(listing_id: &str) -> Read {
    let mut state = state().lock();
    state
        .reads
        .entry(listing_id.to_string())
        .or_insert_with(|| Read {
            generation: NEXT_READ.fetch_add(1, Ordering::SeqCst),
            stop: Arc::new(AtomicBool::new(false)),
        })
        .clone()
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
/// progress report as an event, its journal every change of what undo and
/// redo would do.
pub fn runner() -> &'static Runner {
    RUNNER.get_or_init(|| {
        let runner = Runner::new();
        runner.set_listener(Arc::new(|progress| {
            emit(AppEvent::progress(crate::api::types::ProgressView::from(progress)));
        }));
        runner.journal().set_listener(Arc::new(|summary| {
            emit(AppEvent {
                journal: Some(crate::api::journal::JournalSummaryView::from_ops(summary)),
                ..AppEvent::of(AppEventKind::JournalChanged, None)
            });
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
    crate::api::network::install_listeners();
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

/// The watcher of `listing_id` reported `changes`: kept for its next read
/// again, and the panel told.
pub fn note_changes(listing_id: &str, changes: Changes) {
    if let Some(open) = state().lock().listings.get_mut(listing_id) {
        open.changes.merge(changes);
    }
    emit_directory_changed(listing_id);
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
    crate::api::network::install_listeners();
}

/// The events kept since the last call (see [`record_events`]).
pub fn take_events() -> Vec<AppEvent> {
    RECORDED.lock().as_mut().map(std::mem::take).unwrap_or_default()
}

pub fn reset_for_tests() {
    crate::api::preview::reset();
    let mut guard = state().lock();
    guard.listings.clear();
    ferryx_vfs::archive::shared::clear();
    guard.finds.clear();
    guard.reads.clear();
    drop(guard);
    *EVENTS.lock() = None;
    *RECORDED.lock() = None;
    crate::tasks::reset();
    runner().journal().clear();
    ferryx_vfs::remote::connection::disconnect_all();
}
