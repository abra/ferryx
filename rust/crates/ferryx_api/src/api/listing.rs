//! A panel's listing: opened at a location, kept while the panel shows
//! it (watched for changes), resorted without reading the disk again.
//!
//! The rows are kept in the order the panel was last sent them, under a
//! number (`version`). A read again or a resort answers an update of
//! those rows: the new order, each row the panel has by its index there,
//! and in full only the rows new or changed, so a large folder where one
//! file changed sends one row. A folder whose watcher named the items
//! that changed reads only those. One read again or resort of a listing
//! runs at a time.
//!
//! A folder on a server is read on the calling worker with a stop: a new
//! read of the same listing (the panel moved on before a slow server
//! answered) stops the earlier one, which then answers `Cancelled` and
//! leaves the listing alone. It is not watched: the panel reads it again
//! after its own operations and on ⌘R.

use std::cmp::Ordering as Order;
use std::collections::{HashMap, HashSet};
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use ferryx_core::entry::Entry;
use ferryx_core::sorting::{compare, SortOptions};
use ferryx_vfs::native::{self, ListOptions};
use ferryx_vfs::watch::{Changes, FolderWatcher};
use ferryx_vfs::{remote, volumes, Location};
use parking_lot::Mutex;

use crate::api::types::{
    ApiResult, EntryView, FerryxError, FerryxErrorKind, ListingOptionsView, ListingView, LocationView,
};
use crate::app::{self, AppState, OpenListing, Untagged};

/// Opens `location` as the listing `listing_id` (a panel's tab), replacing
/// whatever that id showed, and answers all its rows sorted by `options`.
pub fn open_listing(
    listing_id: String,
    location: LocationView,
    options: ListingOptionsView,
) -> ApiResult<ListingView> {
    let location = location.to_location();
    let current = app::begin_read(&listing_id);
    let mut rows = read(&location, &options, &current.stop)?;
    sort_rows(&mut rows, &options.sort.to_core());
    let watcher = match &location {
        Location::Native(path) => watcher_for(&listing_id, path),
        Location::Archive { archive, .. } => watcher_for(&listing_id, archive.parent().unwrap_or(archive)),
        Location::Remote { .. } => None,
    };
    let footer = Footer::of(&location);
    let entries = rows.iter().map(EntryView::from).collect();
    let mut state = app::state().lock();
    if state.reads.get(&listing_id).map(|r| r.generation) != Some(current.generation) {
        // A later read of this listing took over.
        return Err(superseded());
    }
    let open = OpenListing::new(location, options, rows, watcher, None);
    let view = footer.view(&open.location, entries, None, 0, open.version, open.watcher.is_some());
    state.listings.insert(listing_id, open);
    Ok(view)
}

/// Reads the listing's folder again and answers an update of its rows:
/// the items the watcher named since the last read, or, when it named
/// none (⌘R, a folder not watched) or could not, the whole folder.
pub fn refresh_listing(listing_id: String) -> ApiResult<ListingView> {
    let turn = turn_of(&listing_id)?;
    let _turn = turn.lock();
    let (location, options, base, before, changes) = {
        let mut state = app::state().lock();
        let open = listing_mut(&mut state, &listing_id)?;
        (
            open.location.clone(),
            open.options,
            open.version,
            open.rows.clone(),
            std::mem::take(&mut open.changes),
        )
    };
    let current = app::current_read(&listing_id);
    let sort = options.sort.to_core();
    let (update, untagged) = match (&location, changes) {
        (Location::Native(dir), Changes::Names(names)) => {
            let changed = read_names(dir, &names, &options);
            let untagged = changed.iter().map(|(name, _)| name.clone()).collect();
            (merge(&before, changed, &sort), Untagged::Names(untagged))
        }
        _ => (diff(&before, read(&location, &options, &current.stop)?, &sort), Untagged::All),
    };
    drop(before);
    let footer = Footer::of(&location);
    let mut state = app::state().lock();
    if state.reads.get(&listing_id).map(|r| r.generation) != Some(current.generation) {
        return Err(superseded());
    }
    let open = listing_mut(&mut state, &listing_id)?;
    if open.location != location || open.version != base {
        // The listing moved elsewhere meanwhile.
        return Err(superseded());
    }
    match untagged {
        Untagged::All => open.untagged = Untagged::All,
        Untagged::Names(names) => open.untagged.add(names),
    }
    Ok(update.commit(open, &footer))
}

/// Sorts or filters the rows already read, under new `options`, and
/// answers their new order. A change of hidden items reads the folder
/// again.
pub fn resort_listing(listing_id: String, options: ListingOptionsView) -> ApiResult<ListingView> {
    let turn = turn_of(&listing_id)?;
    let held = turn.lock();
    let (location, base, before) = {
        let mut state = app::state().lock();
        let open = listing_mut(&mut state, &listing_id)?;
        if open.options.show_hidden != options.show_hidden || open.options.show_parent != options.show_parent
        {
            open.options = options;
            open.changes = Changes::Everything;
            drop(state);
            drop(held);
            return refresh_listing(listing_id);
        }
        (open.location.clone(), open.version, open.rows.clone())
    };
    let sort = options.sort.to_core();
    let mut order: Vec<usize> = (0..before.len()).collect();
    order.sort_by(|&a, &b| compare(&before[a], &before[b], &sort));
    let mut update = Update::with_capacity(before.len());
    for at in order {
        update.kept(at, before[at].clone());
    }
    drop(before);
    let footer = Footer::of(&location);
    let mut state = app::state().lock();
    let open = listing_mut(&mut state, &listing_id)?;
    if open.version != base {
        return Err(superseded());
    }
    open.options = options;
    Ok(update.commit(open, &footer))
}

/// All the rows of the listing as last sent, under their number: for a
/// panel that missed an update (its answers came out of turn).
pub fn listing_rows(listing_id: String) -> ApiResult<ListingView> {
    let (location, rows, version, watched) = {
        let mut state = app::state().lock();
        let open = listing_mut(&mut state, &listing_id)?;
        (open.location.clone(), open.rows.clone(), open.version, open.watcher.is_some())
    };
    let entries = rows.iter().map(EntryView::from).collect();
    Ok(Footer::of(&location).view(&location, entries, None, 0, version, watched))
}

/// Forgets the listing and stops watching its folder (and reading it).
pub fn close_listing(listing_id: String) {
    app::begin_read(&listing_id).stop.store(true, Ordering::SeqCst);
    let mut state = app::state().lock();
    state.listings.remove(&listing_id);
    state.reads.remove(&listing_id);
}

/// The rows of `location` once, unwatched: for a dialog that needs a
/// folder's names (the Go To folder's completion).
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
    let mut rows = read(&location, &options, &AtomicBool::new(false))?;
    sort_rows(&mut rows, &options.sort.to_core());
    Ok(rows.iter().map(EntryView::from).collect())
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

/// A flat view's first answer: its folder's footer, without rows.
pub(crate) fn header_view(location: &Location, version: i64, watched: bool) -> ListingView {
    Footer::of(location).view(location, Vec::new(), None, 0, version, watched)
}

/// The rows a panel is shown, in its order: an unstable sort would do (the
/// order is total, names falling back to their bytes) but for an archive,
/// which may hold one name twice.
fn sort_rows(rows: &mut [Entry], sort: &SortOptions) {
    rows.sort_by(|a, b| compare(a, b, sort));
}

/// Rows in their new order, and what the panel is sent of them.
struct Update {
    rows: Vec<Entry>,
    order: Vec<i32>,
    fresh: Vec<EntryView>,
}

impl Update {
    fn with_capacity(rows: usize) -> Update {
        Update { rows: Vec::with_capacity(rows), order: Vec::with_capacity(rows), fresh: Vec::new() }
    }

    /// Row `at` of the rows the panel has, next.
    fn kept(&mut self, at: usize, row: Entry) {
        self.order.push(at as i32);
        self.rows.push(row);
    }

    /// A row the panel has not got, next.
    fn fresh(&mut self, row: Entry) {
        self.order.push(-1 - self.fresh.len() as i32);
        self.fresh.push(EntryView::from(&row));
        self.rows.push(row);
    }

    /// The rows become the listing's, under a new number; the panel is
    /// sent the update.
    fn commit(self, open: &mut OpenListing, footer: &Footer) -> ListingView {
        let base = open.version;
        open.rows = Arc::new(self.rows);
        open.version = app::next_version();
        footer.view(&open.location, self.fresh, Some(self.order), base, open.version, open.watcher.is_some())
    }
}

/// `rows` read anew, sorted, against `before`: a row as it was keeps its
/// index there.
fn diff(before: &[Entry], mut rows: Vec<Entry>, sort: &SortOptions) -> Update {
    sort_rows(&mut rows, sort);
    let at: HashMap<&str, usize> = before.iter().enumerate().map(|(i, row)| (row.name.as_str(), i)).collect();
    let mut update = Update::with_capacity(rows.len());
    for row in rows {
        match at.get(row.name.as_str()).copied().filter(|&i| before[i] == row) {
            Some(i) => update.kept(i, row),
            None => update.fresh(row),
        }
    }
    update
}

/// `before` with the rows of `changed` put in: a row the change left as
/// it was keeps its place, the others go, and the new ones come in where
/// the sort puts them (`before` is sorted so).
fn merge(before: &[Entry], changed: Vec<(String, Option<Entry>)>, sort: &SortOptions) -> Update {
    let at: HashMap<&str, usize> = before
        .iter()
        .enumerate()
        .filter(|(_, row)| !row.is_parent)
        .map(|(i, row)| (row.name.as_str(), i))
        .collect();
    let mut gone = HashSet::new();
    let mut coming = Vec::new();
    for (name, row) in changed {
        let old = at.get(name.as_str()).copied();
        if let (Some(i), Some(row)) = (old, &row) {
            if before[i] == *row {
                continue;
            }
        }
        gone.extend(old);
        coming.extend(row);
    }
    sort_rows(&mut coming, sort);
    let mut update = Update::with_capacity(before.len() + coming.len());
    let mut coming = coming.into_iter().peekable();
    for (i, row) in before.iter().enumerate() {
        if gone.contains(&i) {
            continue;
        }
        while let Some(new) = coming.next_if(|new| compare(new, row, sort) == Order::Less) {
            update.fresh(new);
        }
        update.kept(i, row.clone());
    }
    for new in coming {
        update.fresh(new);
    }
    update
}

/// The rows of the items `names` of `dir` as a read of the folder makes
/// them; `None` for an item gone or one `options` hides.
fn read_names(
    dir: &Path,
    names: &HashSet<OsString>,
    options: &ListingOptionsView,
) -> Vec<(String, Option<Entry>)> {
    let mut owners = native::Names::default();
    names
        .iter()
        .map(|name| {
            let shown = name.to_string_lossy().into_owned();
            let path = dir.join(name);
            let row = std::fs::symlink_metadata(&path)
                .ok()
                .map(|meta| native::entry_from_metadata(shown.clone(), path, &meta, &mut owners))
                .filter(|row| options.show_hidden || !row.is_hidden);
            (shown, row)
        })
        .collect()
}

/// What a listing's footer shows of its volume.
struct Footer {
    free_bytes: Option<i64>,
    total_bytes: Option<i64>,
    volume_name: Option<String>,
}

impl Footer {
    fn of(location: &Location) -> Footer {
        match location {
            Location::Native(path) => {
                let volume = volumes::volume_holding(path);
                Footer {
                    free_bytes: native::free_space(path).map(|b| b as i64),
                    total_bytes: volume.as_ref().map(|v| v.total_bytes as i64),
                    volume_name: volume.map(|v| v.name),
                }
            }
            Location::Archive { .. } => Footer { free_bytes: None, total_bytes: None, volume_name: None },
            // The server's address names its "volume"; its free space is
            // not asked for (only some servers answer, at a round trip a
            // read).
            Location::Remote { server, .. } => Footer {
                free_bytes: None,
                total_bytes: None,
                volume_name: Some(
                    remote::address::parse_key(server).map(|a| a.display_root()).unwrap_or_default(),
                ),
            },
        }
    }

    fn view(
        &self,
        location: &Location,
        entries: Vec<EntryView>,
        order: Option<Vec<i32>>,
        base: i64,
        version: i64,
        watched: bool,
    ) -> ListingView {
        ListingView {
            location: LocationView::from(location),
            entries,
            order,
            base,
            version,
            free_bytes: self.free_bytes,
            total_bytes: self.total_bytes,
            volume_name: self.volume_name.clone(),
            watched,
        }
    }
}

/// The lock a read again or a resort of `listing_id` holds.
fn turn_of(listing_id: &str) -> ApiResult<Arc<Mutex<()>>> {
    let mut state = app::state().lock();
    Ok(listing_mut(&mut state, listing_id)?.turn.clone())
}

/// The listing `listing_id`, unless it is gone or a flat view.
fn listing_mut<'a>(state: &'a mut AppState, listing_id: &str) -> ApiResult<&'a mut OpenListing> {
    let open = state.listings.get_mut(listing_id).ok_or_else(|| not_open(listing_id))?;
    if open.flat.is_some() {
        return Err(flat_elsewhere(listing_id));
    }
    Ok(open)
}

/// A flat view is walked and sorted by `api::flat`, not here.
fn flat_elsewhere(listing_id: &str) -> FerryxError {
    FerryxError::new(FerryxErrorKind::Unsupported, format!("listing {listing_id} is a flat view"))
}

fn not_open(listing_id: &str) -> FerryxError {
    FerryxError::new(FerryxErrorKind::NotFound, format!("listing {listing_id} is not open"))
}

/// A read stopped because a later one of its listing took over.
fn superseded() -> FerryxError {
    FerryxError::new(FerryxErrorKind::Cancelled, "a later read of the listing took over")
}

fn read(location: &Location, options: &ListingOptionsView, stop: &AtomicBool) -> ApiResult<Vec<Entry>> {
    match location {
        Location::Native(path) => {
            if !native::is_dir(path) {
                return Err(FerryxError::new(
                    FerryxErrorKind::NotADirectory,
                    format!("{} is not a folder", path.display()),
                ));
            }
            Ok(native::list_dir_until(
                path,
                &ListOptions { show_hidden: options.show_hidden, show_parent: options.show_parent },
                &|| stop.load(Ordering::SeqCst),
            )?)
        }
        Location::Archive { archive, inner } => {
            let index = app::archive_index(archive)?;
            Ok(index.list(inner, options.show_parent, options.show_hidden)?)
        }
        Location::Remote { server, path } => {
            let server = remote::connection::get(server)?;
            let mut rows = server.fs().list(path, &|| stop.load(Ordering::SeqCst))?;
            if !options.show_hidden {
                rows.retain(|row| !row.is_hidden);
            }
            if options.show_parent {
                if let Some(parent) = remote::address::parent(path) {
                    rows.insert(0, Entry::parent(PathBuf::from(parent)));
                }
            }
            Ok(rows)
        }
    }
}

pub(crate) fn watcher_for(listing_id: &str, path: &Path) -> Option<FolderWatcher> {
    let id = listing_id.to_string();
    FolderWatcher::new(path, Arc::new(move |changes| app::note_changes(&id, changes))).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use ferryx_core::entry::EntryKind;

    fn row(name: &str, size: u64) -> Entry {
        Entry { size: Some(size), ..Entry::parent(PathBuf::from(format!("/f/{name}"))) }.named(name)
    }

    trait Named {
        fn named(self, name: &str) -> Entry;
    }

    impl Named for Entry {
        fn named(mut self, name: &str) -> Entry {
            self.name = name.to_string();
            self.is_parent = false;
            self.is_dir = false;
            self.kind = EntryKind::File;
            self
        }
    }

    fn names(rows: &[Entry]) -> Vec<&str> {
        rows.iter().map(|r| r.name.as_str()).collect()
    }

    /// The rows the panel builds from its old rows and an update.
    fn applied(before: &[Entry], update: &Update) -> Vec<String> {
        update
            .order
            .iter()
            .map(|&i| {
                if i >= 0 {
                    before[i as usize].name.clone()
                } else {
                    update.fresh[(-1 - i) as usize].name.clone()
                }
            })
            .collect()
    }

    #[test]
    fn a_read_again_sends_only_the_rows_that_changed() {
        let sort = SortOptions::default();
        let mut before = vec![row("a", 1), row("b", 1), row("c", 1), row("d", 1)];
        sort_rows(&mut before, &sort);
        let update = diff(&before, vec![row("d", 1), row("b", 2), row("a", 1), row("bb", 1)], &sort);
        assert_eq!(names(&update.rows), ["a", "b", "bb", "d"]);
        assert_eq!(update.order, [0, -1, -2, 3]);
        assert_eq!(update.fresh.iter().map(|e| e.name.as_str()).collect::<Vec<_>>(), ["b", "bb"]);
        assert_eq!(applied(&before, &update), ["a", "b", "bb", "d"]);
    }

    #[test]
    fn named_changes_merge_into_the_order_as_a_read_again_would() {
        let sort = SortOptions::default();
        let mut before =
            vec![Entry::parent(PathBuf::from("/")), row("a", 1), row("c", 1), row("e", 1), row("g", 1)];
        sort_rows(&mut before, &sort);
        let changed = vec![
            ("b".to_string(), Some(row("b", 1))),
            ("e".to_string(), None),
            ("g".to_string(), Some(row("g", 5))),
            ("c".to_string(), Some(row("c", 1))),
            ("z".to_string(), Some(row("z", 1))),
            ("0".to_string(), Some(row("0", 1))),
        ];
        let update = merge(&before, changed, &sort);
        assert_eq!(names(&update.rows), ["..", "0", "a", "b", "c", "g", "z"]);
        // `c` came back as it was: kept, not sent.
        assert_eq!(update.order, [0, -1, 1, -2, 2, -3, -4]);
        assert_eq!(applied(&before, &update), ["..", "0", "a", "b", "c", "g", "z"]);
        let whole = diff(&before, update.rows.clone(), &sort);
        assert_eq!(names(&whole.rows), names(&update.rows));
    }
}
