//! A panel's listing: opened at a location, kept while the panel shows
//! it (watched for changes), resorted without reading the disk again.

use std::path::Path;
use std::sync::Arc;

use ferryx_core::entry::Entry;
use ferryx_core::sorting::sort_entries;
use ferryx_vfs::native::{self, ListOptions};
use ferryx_vfs::watch::FolderWatcher;
use ferryx_vfs::{volumes, Location};

use crate::api::types::{
    ApiResult, EntryView, FerryxError, FerryxErrorKind, ListingOptionsView, ListingView, LocationView,
};
use crate::app::{self, OpenListing};

/// Opens `location` as the listing `listing_id` (a panel's tab), replacing
/// whatever that id showed, and answers its rows sorted by `options`.
pub fn open_listing(
    listing_id: String,
    location: LocationView,
    options: ListingOptionsView,
) -> ApiResult<ListingView> {
    let location = location.to_location();
    let raw = read(&location, &options)?;
    let watcher = match &location {
        Location::Native(path) => watcher_for(&listing_id, path),
        Location::Archive { archive, .. } => watcher_for(&listing_id, archive.parent().unwrap_or(archive)),
    };
    let view = build_view(&location, &raw, &options, watcher.is_some());
    app::state()
        .lock()
        .listings
        .insert(listing_id, OpenListing { location, options, raw, watcher, flat: None });
    Ok(view)
}

/// Reads the listing's folder again (after a change on disk, or ⌘R).
pub fn refresh_listing(listing_id: String) -> ApiResult<ListingView> {
    let (location, options) = {
        let state = app::state().lock();
        let open = state.listings.get(&listing_id).ok_or_else(|| not_open(&listing_id))?;
        if open.flat.is_some() {
            return Err(flat_elsewhere(&listing_id));
        }
        (open.location.clone(), open.options)
    };
    let raw = read(&location, &options)?;
    let mut state = app::state().lock();
    let open = state.listings.get_mut(&listing_id).ok_or_else(|| not_open(&listing_id))?;
    let watched = open.watcher.is_some();
    open.raw = raw;
    Ok(build_view(&location, &open.raw, &options, watched))
}

/// Sorts or filters the rows already read, under new `options`. A change
/// of hidden items reads the folder again.
pub fn resort_listing(listing_id: String, options: ListingOptionsView) -> ApiResult<ListingView> {
    let needs_read = {
        let state = app::state().lock();
        let open = state.listings.get(&listing_id).ok_or_else(|| not_open(&listing_id))?;
        if open.flat.is_some() {
            return Err(flat_elsewhere(&listing_id));
        }
        open.options.show_hidden != options.show_hidden || open.options.show_parent != options.show_parent
    };
    if needs_read {
        {
            let mut state = app::state().lock();
            let open = state.listings.get_mut(&listing_id).ok_or_else(|| not_open(&listing_id))?;
            open.options = options;
        }
        return refresh_listing(listing_id);
    }
    let mut state = app::state().lock();
    let open = state.listings.get_mut(&listing_id).ok_or_else(|| not_open(&listing_id))?;
    open.options = options;
    let watched = open.watcher.is_some();
    Ok(build_view(&open.location, &open.raw, &options, watched))
}

/// Forgets the listing and stops watching its folder.
pub fn close_listing(listing_id: String) {
    app::state().lock().listings.remove(&listing_id);
}

/// The rows of `location` once, unsorted and unwatched: for a dialog
/// that needs a folder's names (the Go To folder's completion).
pub fn peek_listing(location: LocationView, show_hidden: bool) -> ApiResult<Vec<EntryView>> {
    let location = location.to_location();
    let options = ListingOptionsView {
        show_hidden,
        show_parent: false,
        sort: crate::api::types::SortOptionsView {
            field: crate::api::types::SortFieldView::Name,
            descending: false,
            folders_first: true,
            extensionless_folders: true,
            collation: crate::api::types::CollationView::Natural,
        },
    };
    let mut raw = read(&location, &options)?;
    sort_entries(&mut raw, &options.sort.to_core());
    Ok(raw.iter().map(EntryView::from).collect())
}

/// Whether `path` is a folder one can enter (a symlink to one too).
#[flutter_rust_bridge::frb(sync)]
pub fn is_directory(path: String) -> bool {
    native::is_dir(Path::new(&path))
}

/// Whether `path` is an archive the panels can enter.
#[flutter_rust_bridge::frb(sync)]
pub fn is_archive(path: String) -> bool {
    ferryx_vfs::archive::is_archive(Path::new(&path))
}

/// A flat view is walked and sorted by `api::flat`, not here.
fn flat_elsewhere(listing_id: &str) -> FerryxError {
    FerryxError::new(FerryxErrorKind::Unsupported, format!("listing {listing_id} is a flat view"))
}

fn not_open(listing_id: &str) -> FerryxError {
    FerryxError::new(FerryxErrorKind::NotFound, format!("listing {listing_id} is not open"))
}

fn read(location: &Location, options: &ListingOptionsView) -> ApiResult<Vec<Entry>> {
    match location {
        Location::Native(path) => {
            if !native::is_dir(path) {
                return Err(FerryxError::new(
                    FerryxErrorKind::NotADirectory,
                    format!("{} is not a folder", path.display()),
                ));
            }
            Ok(native::list_dir(
                path,
                &ListOptions { show_hidden: options.show_hidden, show_parent: options.show_parent },
            )?)
        }
        Location::Archive { archive, inner } => {
            let index = app::archive_index(archive)?;
            Ok(index.list(inner, options.show_parent, options.show_hidden)?)
        }
    }
}

pub(crate) fn watcher_for(listing_id: &str, path: &Path) -> Option<FolderWatcher> {
    let id = listing_id.to_string();
    FolderWatcher::new(path, Arc::new(move || app::emit_directory_changed(&id))).ok()
}

pub(crate) fn build_view(
    location: &Location,
    raw: &[Entry],
    options: &ListingOptionsView,
    watched: bool,
) -> ListingView {
    let mut entries: Vec<Entry> = raw.to_vec();
    sort_entries(&mut entries, &options.sort.to_core());
    let (free_bytes, total_bytes, volume_name) = match location {
        Location::Native(path) => {
            let vols = volumes::list();
            let volume = volumes::volume_of(path, &vols);
            (
                native::free_space(path).map(|b| b as i64),
                volume.as_ref().map(|v| v.total_bytes as i64),
                volume.map(|v| v.name),
            )
        }
        Location::Archive { .. } => (None, None, None),
    };
    ListingView {
        location: LocationView::from(location),
        entries: entries.iter().map(EntryView::from).collect(),
        free_bytes,
        total_bytes,
        volume_name,
        watched,
    }
}
