//! One row of a file panel.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

/// What an entry is on the file system. A symbolic link keeps its own kind
/// and says what it points at through [`Entry::is_dir`].
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum EntryKind {
    File,
    Directory,
    Symlink,
    Other,
}

/// A file, folder or link as a panel shows it. Every timestamp is Unix
/// milliseconds; a time the file system does not keep is `None`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    /// The file name, as the file system spells it.
    pub name: String,
    /// The full path; for an archive member, the path inside the archive.
    pub path: PathBuf,
    pub kind: EntryKind,
    /// A directory, or a symlink that resolves to one: Enter goes inside.
    pub is_dir: bool,
    /// The `..` row at the top of a listing.
    pub is_parent: bool,
    /// Where a symlink points, as written in the link.
    pub symlink_target: Option<String>,
    /// Bytes of a file; of a folder only once its size was calculated.
    pub size: Option<u64>,
    pub modified_ms: Option<i64>,
    pub created_ms: Option<i64>,
    pub accessed_ms: Option<i64>,
    /// When the item was added to its folder (macOS keeps it).
    pub added_ms: Option<i64>,
    /// Unix mode bits (type and permissions).
    pub mode: u32,
    pub uid: u32,
    pub gid: u32,
    pub owner: String,
    pub group: String,
    /// BSD file flags (`UF_HIDDEN`, `UF_IMMUTABLE`…); 0 elsewhere.
    pub flags: u32,
    /// A dot file, or the hidden flag set.
    pub is_hidden: bool,
    /// The extension without its dot, as spelled; empty when there is none.
    pub extension: String,
    /// Finder tags on macOS, in the order Finder keeps them.
    pub tags: Vec<Tag>,
}

/// A Finder tag: its name and its colour, in Finder's numbering (0 none,
/// 1 grey, 2 green, 3 purple, 4 blue, 5 yellow, 6 red, 7 orange).
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Tag {
    pub name: String,
    pub color: u8,
}

impl Tag {
    pub fn new(name: impl Into<String>, color: u8) -> Tag {
        Tag { name: name.into(), color: color.min(7) }
    }
}

impl Entry {
    /// The `..` row: a folder that leads to [`parent`].
    pub fn parent(parent: PathBuf) -> Entry {
        Entry {
            name: "..".to_string(),
            path: parent,
            kind: EntryKind::Directory,
            is_dir: true,
            is_parent: true,
            symlink_target: None,
            size: None,
            modified_ms: None,
            created_ms: None,
            accessed_ms: None,
            added_ms: None,
            mode: 0o40755,
            uid: 0,
            gid: 0,
            owner: String::new(),
            group: String::new(),
            flags: 0,
            is_hidden: false,
            extension: String::new(),
            tags: Vec::new(),
        }
    }

    /// The name without its extension (the whole name when there is none,
    /// or when the name is nothing but an extension, as `.profile` is).
    pub fn stem(&self) -> &str {
        split_name(&self.name).0
    }
}

/// Splits a file name into its stem and its extension (without the dot). A
/// leading dot is part of the stem, so `.profile` has no extension and
/// `archive.tar.gz` ends in `gz`.
pub fn split_name(name: &str) -> (&str, &str) {
    match name.rfind('.') {
        Some(0) | None => (name, ""),
        Some(dot) => (&name[..dot], &name[dot + 1..]),
    }
}

/// The extension of a file name, as [`split_name`] finds it.
pub fn extension_of(name: &str) -> &str {
    split_name(name).1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_names() {
        assert_eq!(split_name("a.txt"), ("a", "txt"));
        assert_eq!(split_name("archive.tar.gz"), ("archive.tar", "gz"));
        assert_eq!(split_name(".profile"), (".profile", ""));
        assert_eq!(split_name("README"), ("README", ""));
        assert_eq!(split_name("trailing."), ("trailing", ""));
    }
}
