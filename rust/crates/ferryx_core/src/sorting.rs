//! The order of a panel's rows.

use std::cmp::Ordering;

use serde::{Deserialize, Serialize};

use crate::collation::Collation;
use crate::entry::Entry;

/// What a panel sorts by. Each field has the order it is first shown in
/// ([`SortField::default_descending`]): names and extensions ascend, sizes
/// and times descend, the newest and the largest first.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum SortField {
    #[default]
    Name,
    Extension,
    Size,
    Modified,
    Created,
    Added,
    Accessed,
}

impl SortField {
    pub fn default_descending(self) -> bool {
        !matches!(self, SortField::Name | SortField::Extension)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SortOptions {
    pub field: SortField,
    pub descending: bool,
    /// Every folder before any file, whatever the field.
    pub folders_first: bool,
    /// Sorting by extension treats folders as having none.
    pub extensionless_folders: bool,
    pub collation: Collation,
}

impl Default for SortOptions {
    fn default() -> Self {
        SortOptions {
            field: SortField::Name,
            descending: false,
            folders_first: true,
            extensionless_folders: true,
            collation: Collation::Natural,
        }
    }
}

impl SortOptions {
    /// The options after the user picks [`field`]: the field's own default
    /// order when it changes, the opposite order when it is picked again.
    pub fn toggled(self, field: SortField) -> SortOptions {
        if self.field == field {
            SortOptions { descending: !self.descending, ..self }
        } else {
            SortOptions { field, descending: field.default_descending(), ..self }
        }
    }
}

/// Sorts `entries` in place. The `..` row stays first.
pub fn sort_entries(entries: &mut [Entry], opts: &SortOptions) {
    entries.sort_by(|a, b| compare(a, b, opts));
}

pub fn compare(a: &Entry, b: &Entry, opts: &SortOptions) -> Ordering {
    match (a.is_parent, b.is_parent) {
        (true, true) => return Ordering::Equal,
        (true, false) => return Ordering::Less,
        (false, true) => return Ordering::Greater,
        _ => {}
    }
    if opts.folders_first && a.is_dir != b.is_dir {
        return if a.is_dir { Ordering::Less } else { Ordering::Greater };
    }
    let by_field = match opts.field {
        SortField::Name => Ordering::Equal,
        SortField::Extension => {
            let ea = if opts.extensionless_folders && a.is_dir { "" } else { a.extension.as_str() };
            let eb = if opts.extensionless_folders && b.is_dir { "" } else { b.extension.as_str() };
            opts.collation.compare(ea, eb)
        }
        SortField::Size => a.size.unwrap_or(0).cmp(&b.size.unwrap_or(0)),
        SortField::Modified => a.modified_ms.cmp(&b.modified_ms),
        SortField::Created => a.created_ms.cmp(&b.created_ms),
        SortField::Added => a.added_ms.cmp(&b.added_ms),
        SortField::Accessed => a.accessed_ms.cmp(&b.accessed_ms),
    };
    let by_field = if opts.descending { by_field.reverse() } else { by_field };
    if by_field != Ordering::Equal {
        return by_field;
    }
    // Ties and the name itself: by name, in the chosen direction for the
    // name field and ascending otherwise, so equal sizes still read a to z.
    let by_name = opts.collation.compare(&a.name, &b.name);
    if opts.field == SortField::Name && opts.descending {
        by_name.reverse()
    } else {
        by_name
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entry::{Entry, EntryKind};
    use std::path::PathBuf;

    fn entry(name: &str, dir: bool, size: u64, modified: i64) -> Entry {
        let mut e = Entry::parent(PathBuf::from(name));
        e.name = name.to_string();
        e.is_parent = false;
        e.is_dir = dir;
        e.kind = if dir { EntryKind::Directory } else { EntryKind::File };
        e.size = if dir { None } else { Some(size) };
        e.modified_ms = Some(modified);
        e.extension = crate::entry::extension_of(name).to_string();
        e
    }

    fn names(entries: &[Entry]) -> Vec<&str> {
        entries.iter().map(|e| e.name.as_str()).collect()
    }

    #[test]
    fn parent_first_then_folders_then_names() {
        let mut v = vec![
            entry("b.txt", false, 1, 1),
            entry("docs", true, 0, 1),
            Entry::parent(PathBuf::from("/")),
            entry("a.txt", false, 2, 2),
        ];
        sort_entries(&mut v, &SortOptions::default());
        assert_eq!(names(&v), ["..", "docs", "a.txt", "b.txt"]);
    }

    #[test]
    fn size_descends_by_default_and_ties_read_by_name() {
        let mut v = vec![entry("b", false, 5, 0), entry("a", false, 5, 0), entry("c", false, 9, 0)];
        let opts = SortOptions::default().toggled(SortField::Size);
        assert!(opts.descending);
        sort_entries(&mut v, &opts);
        assert_eq!(names(&v), ["c", "a", "b"]);
    }

    #[test]
    fn toggling_the_same_field_flips_the_order() {
        let opts = SortOptions::default();
        let again = opts.toggled(SortField::Name);
        assert!(again.descending);
        assert!(!again.toggled(SortField::Name).descending);
        assert!(opts.toggled(SortField::Modified).descending);
    }

    #[test]
    fn extension_sorts_folders_as_extensionless() {
        let mut v = vec![entry("x.zip", false, 1, 0), entry("a.b", true, 0, 0), entry("y.csv", false, 1, 0)];
        let opts =
            SortOptions { folders_first: false, ..SortOptions::default() }.toggled(SortField::Extension);
        sort_entries(&mut v, &opts);
        assert_eq!(names(&v), ["a.b", "y.csv", "x.zip"]);
    }

    #[test]
    fn name_descending_reverses_names_only() {
        let mut v = vec![entry("a", false, 1, 0), entry("b", false, 1, 0), entry("d", true, 0, 0)];
        let opts = SortOptions::default().toggled(SortField::Name);
        sort_entries(&mut v, &opts);
        assert_eq!(names(&v), ["d", "b", "a"]);
    }
}
