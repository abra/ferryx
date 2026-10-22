//! A panel's flat view: every file under its folder in one list.
//!
//! `open_flat_listing` replaces what the listing showed and answers its
//! header and a generation; `stream_flat_listing` then walks the subtree
//! on a thread of its own and sends the rows in batches as they are found
//! (in walk order), and a last batch that says the walk ended;
//! `sort_flat_listing` answers the order of the rows under the listing's
//! sort, which the panel applies to the rows it holds, so a sort never
//! sends the rows again. Replacing or closing the listing stops the walk.
//!
//! The folder is watched (not its subfolders): a change there reads the
//! whole tree again, as ⌘R does.

use std::cmp::Ordering;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use ferryx_core::entry::Entry;
use ferryx_core::sorting::compare;
use ferryx_vfs::flat::{self, Batcher, FlatEnd, FlatOptions, FlatRow};
use ferryx_vfs::{native, Location};
use parking_lot::Mutex;

use crate::api::listing::{build_view, watcher_for};
use crate::api::types::{
    ApiResult, EntryView, FerryxError, FerryxErrorKind, ListingOptionsView, ListingView, LocationView,
};
use crate::app::{self, FlatListing, FlatRows, OpenListing};
use crate::frb_generated::StreamSink;

/// What a flat listing starts with: the folder's header (free space, the
/// volume) without rows, and the walk's generation.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FlatStartView {
    pub listing: ListingView,
    pub generation: i64,
}

/// Rows a flat walk found, or its end.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FlatBatchView {
    pub generation: i64,
    pub entries: Vec<EntryView>,
    /// Each entry's folder relative to the root, in step with `entries`
    /// (empty for the root's own files).
    pub folders: Vec<String>,
    /// The walk ended: no rows come after this batch.
    pub done: bool,
    /// The rows found so far.
    pub count: i64,
    /// The walk stopped at [`flat::CAP`] rows.
    pub capped: bool,
}

/// Opens the folder `location` as a flat list for `listing_id`, replacing
/// what it showed (a walk under way stops); answers the header and the
/// generation `stream_flat_listing` then walks.
pub fn open_flat_listing(
    listing_id: String,
    location: LocationView,
    options: ListingOptionsView,
) -> ApiResult<FlatStartView> {
    let location = location.to_location();
    let watcher = match &location {
        Location::Native(path) => {
            if !native::is_dir(path) {
                return Err(FerryxError::new(
                    FerryxErrorKind::NotADirectory,
                    format!("{} is not a folder", path.display()),
                ));
            }
            watcher_for(&listing_id, path)
        }
        Location::Archive { archive, inner } => {
            let index = app::archive_index(archive)?;
            if !index.is_dir(inner) {
                return Err(FerryxError::new(
                    FerryxErrorKind::NotADirectory,
                    format!("{inner} is not a folder in the archive"),
                ));
            }
            None
        }
        // ─── Network ───
        // A whole tree over the network, a folder a round trip: not
        // offered.
        Location::Remote { .. } => {
            return Err(FerryxError::new(
                FerryxErrorKind::Unsupported,
                "a flat view of a folder on a server is not offered",
            ));
        }
    };
    let generation = app::next_generation();
    let header = build_view(&location, &[], &options, watcher.is_some());
    let flat = FlatListing {
        generation,
        cancel: Arc::new(AtomicBool::new(false)),
        rows: Arc::new(Mutex::new(FlatRows::default())),
    };
    app::state()
        .lock()
        .listings
        .insert(listing_id, OpenListing { location, options, raw: Vec::new(), watcher, flat: Some(flat) });
    Ok(FlatStartView { listing: header, generation })
}

/// Walks the flat listing's folder and sends its rows to `sink` in
/// batches; the last batch says `done`. A listing replaced meanwhile ends
/// the walk silently.
pub fn stream_flat_listing(listing_id: String, generation: i64, sink: StreamSink<FlatBatchView>) {
    stream_flat_listing_with(
        listing_id,
        generation,
        Box::new(move |batch| {
            // A closed sink only means the panel went elsewhere.
            let _ = sink.add(batch);
        }),
    );
}

/// [`stream_flat_listing`] with any receiver, for the flows under
/// `tests/`. Not part of the bridge.
#[flutter_rust_bridge::frb(ignore)]
pub fn stream_flat_listing_with(
    listing_id: String,
    generation: i64,
    mut send: Box<dyn FnMut(FlatBatchView) + Send>,
) {
    let found = {
        let state = app::state().lock();
        state.listings.get(&listing_id).and_then(|open| {
            let flat = open.flat.as_ref().filter(|f| f.generation == generation)?;
            Some((open.location.clone(), open.options, flat.cancel.clone(), flat.rows.clone()))
        })
    };
    let Some((location, options, cancel, rows)) = found else {
        send(FlatBatchView::end(generation, 0, false));
        return;
    };
    let spawned = std::thread::Builder::new().name(format!("flat {listing_id}")).spawn(move || {
        let mut deliver = |batch: Vec<FlatRow>| {
            let (entries, folders): (Vec<Entry>, Vec<String>) = batch.into_iter().unzip();
            let views: Vec<EntryView> = entries.iter().map(EntryView::from).collect();
            let count = {
                let mut rows = rows.lock();
                rows.entries.extend(entries);
                rows.folders.extend(folders.iter().cloned());
                rows.entries.len()
            };
            if !cancel.load(std::sync::atomic::Ordering::SeqCst) {
                send(FlatBatchView {
                    generation,
                    entries: views,
                    folders,
                    done: false,
                    count: count as i64,
                    capped: false,
                });
            }
        };
        let walk_options = FlatOptions { show_hidden: options.show_hidden, cap: flat::CAP };
        let parent = options.show_parent.then(|| location.parent()).flatten();
        let end = match &location {
            Location::Native(root) => {
                let mut batcher = Batcher::new(&mut deliver);
                if let Some(Location::Native(parent)) = parent {
                    batcher.push((Entry::parent(parent), String::new()));
                }
                batcher.flush();
                drop(batcher);
                flat::walk(root, &walk_options, &cancel, &mut deliver).unwrap_or(FlatEnd::Done)
            }
            Location::Archive { archive, inner } => {
                let mut batcher = Batcher::new(&mut deliver);
                if parent.is_some() {
                    let up = match inner.rfind('/') {
                        Some(at) => inner[..at].to_string(),
                        None => String::new(),
                    };
                    batcher.push((Entry::parent(up.into()), String::new()));
                }
                let mut end = FlatEnd::Done;
                if let Ok(index) = app::archive_index(archive) {
                    for (i, row) in index.files_in_subtree(inner, options.show_hidden).into_iter().enumerate()
                    {
                        if i >= flat::CAP {
                            end = FlatEnd::Capped;
                            break;
                        }
                        batcher.push(row);
                    }
                }
                batcher.flush();
                end
            }
            // ─── Network ───
            // Never opened (see `open_flat_listing`).
            Location::Remote { .. } => FlatEnd::Done,
        };
        let (count, capped) = {
            let mut rows = rows.lock();
            rows.done = true;
            rows.capped = end == FlatEnd::Capped;
            (rows.entries.len(), rows.capped)
        };
        if end != FlatEnd::Cancelled && !cancel.load(std::sync::atomic::Ordering::SeqCst) {
            send(FlatBatchView::end(generation, count, capped));
        }
    });
    if spawned.is_err() {
        // No thread: the listing ends empty rather than waiting forever.
        app::state().lock().listings.remove(&listing_id);
    }
}

impl FlatBatchView {
    fn end(generation: i64, count: usize, capped: bool) -> FlatBatchView {
        FlatBatchView {
            generation,
            entries: Vec::new(),
            folders: Vec::new(),
            done: true,
            count: count as i64,
            capped,
        }
    }
}

/// The order of the flat listing's rows under `options`' sort: indices
/// into the rows as they were sent, the first row first. By name, rows of
/// one name keep their folders' order. Fails while the walk is under way
/// or when `generation` is not the listing's.
pub fn sort_flat_listing(
    listing_id: String,
    generation: i64,
    options: ListingOptionsView,
) -> ApiResult<Vec<i32>> {
    let rows = {
        let mut state = app::state().lock();
        let open = state.listings.get_mut(&listing_id).ok_or_else(|| {
            FerryxError::new(FerryxErrorKind::NotFound, format!("listing {listing_id} is not open"))
        })?;
        let flat =
            open.flat.as_ref().filter(|f| f.generation == generation).ok_or_else(|| {
                FerryxError::new(FerryxErrorKind::Cancelled, "the flat view was read again")
            })?;
        let rows = flat.rows.clone();
        open.options = options;
        rows
    };
    // Sorted outside the state's lock: a large list takes a moment.
    let rows = rows.lock();
    if !rows.done {
        return Err(FerryxError::new(FerryxErrorKind::Unsupported, "the flat view is still being read"));
    }
    let sort = options.sort.to_core();
    let mut order: Vec<u32> = (0..rows.entries.len() as u32).collect();
    // The order is total (names fall back to their exact bytes), so an
    // unstable sort gives the same result, faster.
    order.sort_unstable_by(|&a, &b| {
        let (a, b) = (a as usize, b as usize);
        match compare(&rows.entries[a], &rows.entries[b], &sort) {
            Ordering::Equal => sort.collation.compare(&rows.folders[a], &rows.folders[b]),
            other => other,
        }
    });
    Ok(order.into_iter().map(|i| i as i32).collect())
}
