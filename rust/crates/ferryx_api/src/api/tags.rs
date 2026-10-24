//! Finder tags (macOS): a listing's read apart from it, and edits.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use ferryx_core::entry::Tag;
use ferryx_vfs::{tags, Location};

use crate::api::types::{ApiResult, FerryxError, FerryxErrorKind};
use crate::app::{self, Untagged};

/// A Finder tag: its name and its colour in Finder's numbering (0 none,
/// 1 grey, 2 green, 3 purple, 4 blue, 5 yellow, 6 red, 7 orange).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TagView {
    pub name: String,
    pub color: i32,
}

impl TagView {
    #[flutter_rust_bridge::frb(ignore)]
    pub fn to_core(&self) -> Tag {
        Tag::new(self.name.clone(), self.color.clamp(0, 7) as u8)
    }
}

impl From<&Tag> for TagView {
    fn from(tag: &Tag) -> Self {
        TagView { name: tag.name.clone(), color: tag.color as i32 }
    }
}

/// An item's tags.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ItemTagsView {
    pub path: String,
    pub tags: Vec<TagView>,
}

/// What an edit did to one item: its tags after, or why it failed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TagOutcomeView {
    pub path: String,
    pub tags: Vec<TagView>,
    pub failure: Option<FerryxErrorKind>,
    pub message: String,
}

/// The tags of the listing's items that have any, and an empty list for
/// an item whose tags are gone. A listing does not read tags (each item
/// costs a system call); the panel asks once it shows, and this reads the
/// rows not read since they were: all after the folder was read whole,
/// the items the watcher named after it read only those. Read on a few
/// threads.
pub fn read_listing_tags(listing_id: String) -> ApiResult<Vec<ItemTagsView>> {
    if !tags::supported() {
        return Ok(Vec::new());
    }
    let (rows, tagged): (Vec<(String, PathBuf)>, Option<HashSet<String>>) = {
        let mut state = app::state().lock();
        let open = state.listings.get_mut(&listing_id).ok_or_else(|| {
            FerryxError::new(FerryxErrorKind::NotFound, format!("listing {listing_id} is not open"))
        })?;
        if !matches!(open.location, Location::Native(_)) {
            return Ok(Vec::new());
        }
        match &open.flat {
            Some(flat) => (
                flat.rows
                    .lock()
                    .entries
                    .iter()
                    .filter(|e| !e.is_parent)
                    .map(|e| (String::new(), e.path.clone()))
                    .collect(),
                None,
            ),
            None => {
                let wanted = std::mem::replace(&mut open.untagged, Untagged::Names(HashSet::new()));
                let rows = open
                    .rows
                    .iter()
                    .filter(|e| {
                        !e.is_parent
                            && match &wanted {
                                Untagged::All => true,
                                Untagged::Names(names) => names.contains(&e.name),
                            }
                    })
                    .map(|e| (e.name.clone(), e.path.clone()))
                    .collect();
                (rows, Some(open.tagged.clone()))
            }
        }
    };
    let paths: Vec<PathBuf> = rows.iter().map(|(_, path)| path.clone()).collect();
    let mut found = read_many(&paths);
    let Some(tagged) = tagged else {
        return Ok(found);
    };
    let with_tags: HashSet<&str> = found.iter().map(|item| item.path.as_str()).collect();
    let mut now_tagged = Vec::new();
    let mut lost = Vec::new();
    for (name, path) in &rows {
        let path = path.to_string_lossy();
        if with_tags.contains(path.as_ref()) {
            now_tagged.push(name.clone());
        } else if tagged.contains(name) {
            lost.push(ItemTagsView { path: path.into_owned(), tags: Vec::new() });
        }
    }
    if let Some(open) = app::state().lock().listings.get_mut(&listing_id) {
        for (name, _) in &rows {
            open.tagged.remove(name);
        }
        open.tagged.extend(now_tagged);
    }
    found.extend(lost);
    Ok(found)
}

/// The tags of `paths` that have any, read on up to four threads.
fn read_many(paths: &[PathBuf]) -> Vec<ItemTagsView> {
    let threads = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1).min(4);
    let chunk = paths.len().div_ceil(threads).max(256);
    std::thread::scope(|scope| {
        let workers: Vec<_> = paths
            .chunks(chunk)
            .map(|part| {
                scope.spawn(move || {
                    part.iter()
                        .filter_map(|path| {
                            let found = tags::read(path);
                            (!found.is_empty()).then(|| ItemTagsView {
                                path: path.to_string_lossy().into_owned(),
                                tags: found.iter().map(TagView::from).collect(),
                            })
                        })
                        .collect::<Vec<_>>()
                })
            })
            .collect();
        workers.into_iter().flat_map(|w| w.join().unwrap_or_default()).collect()
    })
}

/// Adds `add` to every item of `paths` (a tag already there takes the
/// colour given) and takes off the tags named in `remove`; answers each
/// item's tags after, or why it could not be changed (a read-only volume,
/// a file system without extended attributes).
pub fn set_tags(paths: Vec<String>, add: Vec<TagView>, remove: Vec<String>) -> Vec<TagOutcomeView> {
    let add: Vec<Tag> = add.iter().map(TagView::to_core).collect();
    paths
        .into_iter()
        .map(|path| match tags::apply(Path::new(&path), &add, &remove) {
            Ok(after) => TagOutcomeView {
                path,
                tags: after.iter().map(TagView::from).collect(),
                failure: None,
                message: String::new(),
            },
            Err(e) => {
                let error = FerryxError::from(e);
                TagOutcomeView { path, tags: Vec::new(), failure: Some(error.kind), message: error.message }
            }
        })
        .collect()
}
