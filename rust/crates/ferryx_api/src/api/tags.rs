//! Finder tags (macOS): a listing's read apart from it, and edits.

use std::path::{Path, PathBuf};

use ferryx_core::entry::Tag;
use ferryx_vfs::{tags, Location};

use crate::api::types::{ApiResult, FerryxError, FerryxErrorKind};
use crate::app;

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

/// The tags of the listing's items that have any. A listing does not read
/// tags (each item costs a system call); the panel asks once it shows,
/// and this reads them on a few threads.
pub fn read_listing_tags(listing_id: String) -> ApiResult<Vec<ItemTagsView>> {
    if !tags::supported() {
        return Ok(Vec::new());
    }
    let paths: Vec<PathBuf> = {
        let state = app::state().lock();
        let open = state.listings.get(&listing_id).ok_or_else(|| {
            FerryxError::new(FerryxErrorKind::NotFound, format!("listing {listing_id} is not open"))
        })?;
        if !matches!(open.location, Location::Native(_)) {
            return Ok(Vec::new());
        }
        match &open.flat {
            Some(flat) => {
                flat.rows.lock().entries.iter().filter(|e| !e.is_parent).map(|e| e.path.clone()).collect()
            }
            None => open.raw.iter().filter(|e| !e.is_parent).map(|e| e.path.clone()).collect(),
        }
    };
    Ok(read_many(&paths))
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
