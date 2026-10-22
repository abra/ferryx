//! Where a panel is: a folder on disk, or a folder inside an archive.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Location {
    Native(PathBuf),
    /// `inner` is a path inside the archive, `/`-separated, without a
    /// leading slash; empty for the archive's root.
    Archive {
        archive: PathBuf,
        inner: String,
    },
}

impl Location {
    pub fn native(path: impl Into<PathBuf>) -> Location {
        Location::Native(path.into())
    }

    pub fn is_native(&self) -> bool {
        matches!(self, Location::Native(_))
    }

    /// The folder this one is in: a folder's parent on disk, an archive
    /// member's enclosing member, the archive's own folder from its root.
    pub fn parent(&self) -> Option<Location> {
        match self {
            Location::Native(path) => path.parent().map(|p| Location::Native(p.to_path_buf())),
            Location::Archive { archive, inner } => {
                if inner.is_empty() {
                    archive.parent().map(|p| Location::Native(p.to_path_buf()))
                } else {
                    let inner = match inner.rfind('/') {
                        Some(at) => inner[..at].to_string(),
                        None => String::new(),
                    };
                    Some(Location::Archive { archive: archive.clone(), inner })
                }
            }
        }
    }

    pub fn join(&self, name: &str) -> Location {
        match self {
            Location::Native(path) => Location::Native(path.join(name)),
            Location::Archive { archive, inner } => Location::Archive {
                archive: archive.clone(),
                inner: if inner.is_empty() { name.to_string() } else { format!("{inner}/{name}") },
            },
        }
    }

    /// The last component: the folder's name, the archive's name at its
    /// root.
    pub fn name(&self) -> String {
        match self {
            Location::Native(path) => path
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| path.to_string_lossy().into_owned()),
            Location::Archive { archive, inner } => {
                if inner.is_empty() {
                    archive.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
                } else {
                    inner.rsplit('/').next().unwrap_or(inner).to_string()
                }
            }
        }
    }

    /// The path as shown in a panel's header: `/Users/me/a.zip/dir`.
    pub fn display(&self) -> String {
        match self {
            Location::Native(path) => path.to_string_lossy().into_owned(),
            Location::Archive { archive, inner } => {
                if inner.is_empty() {
                    archive.to_string_lossy().into_owned()
                } else {
                    format!("{}/{}", archive.to_string_lossy(), inner)
                }
            }
        }
    }

    /// The archive file a location is in, if any.
    pub fn archive_path(&self) -> Option<&Path> {
        match self {
            Location::Native(_) => None,
            Location::Archive { archive, .. } => Some(archive),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parents_and_joins() {
        let root = Location::native("/a/b");
        assert_eq!(root.parent(), Some(Location::native("/a")));
        assert_eq!(root.join("c"), Location::native("/a/b/c"));
        assert_eq!(root.name(), "b");

        let archive = Location::Archive { archive: PathBuf::from("/a/x.zip"), inner: String::new() };
        assert_eq!(archive.parent(), Some(Location::native("/a")));
        let deep = archive.join("d").join("e");
        assert_eq!(deep, Location::Archive { archive: PathBuf::from("/a/x.zip"), inner: "d/e".to_string() });
        assert_eq!(deep.parent(), Some(archive.join("d")));
        assert_eq!(deep.name(), "e");
        assert_eq!(deep.display(), "/a/x.zip/d/e");
        assert_eq!(archive.name(), "x.zip");
    }
}
