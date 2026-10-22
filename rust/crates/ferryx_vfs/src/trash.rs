//! The trash with a receipt for every item, so an item can be put back
//! where it was (undo).
//!
//! - macOS: `NSFileManager trashItemAtURL:resultingItemURL:error:` names
//!   the item's place in the Trash; putting it back is a rename on the
//!   same volume. Finder's own "Put Back" does not know such items.
//! - Linux and the other freedesktop desktops, Windows: the `trash`
//!   crate moves the item, and its listing of the trash finds the item
//!   again by its original path and deletion time; its `restore_all`
//!   puts it back.
//! - Elsewhere items go to the trash without a receipt and cannot be put
//!   back ([`put_back_supported`] is `false`).

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{VfsError, VfsErrorKind, VfsResult};

/// Where one trashed item went.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TrashReceipt {
    /// The item's path before it was trashed, its folder resolved.
    pub original: PathBuf,
    /// The platform's handle on the item in the trash: its path in the
    /// Trash on macOS, the `trash` crate's item id on the freedesktop trash
    /// and the Recycle Bin; `None` where items cannot be put back.
    pub token: Option<String>,
    /// When it was trashed, in seconds since the epoch.
    pub time_deleted: i64,
}

/// Whether trashed items can be put back on this desktop.
pub fn put_back_supported() -> bool {
    platform::SUPPORTED
}

/// Moves each of `paths` to the trash; answers a receipt or the error of
/// each, in order.
pub fn trash_items(paths: &[PathBuf]) -> Vec<VfsResult<TrashReceipt>> {
    platform::trash_items(paths)
}

/// Whether the item of `receipt` is still in the trash.
pub fn is_in_trash(receipt: &TrashReceipt) -> bool {
    are_in_trash(&[receipt]).first().copied().unwrap_or(false)
}

/// Which of `receipts` are still in the trash, in order; the trash is
/// looked at once.
pub fn are_in_trash(receipts: &[&TrashReceipt]) -> Vec<bool> {
    platform::are_in_trash(receipts)
}

/// Puts the item of `receipt` back at its original path; fails when that
/// path is taken or the item left the trash. A missing folder on the way
/// is made again.
pub fn put_back(receipt: &TrashReceipt) -> VfsResult<()> {
    put_back_all(&[receipt]).into_iter().next().unwrap_or(Ok(()))
}

/// Puts back each of `receipts` as [`put_back`] does, looking at the trash
/// once; answers each one's outcome, in order.
pub fn put_back_all(receipts: &[&TrashReceipt]) -> Vec<VfsResult<()>> {
    let present = are_in_trash(receipts);
    let mut ready = Vec::with_capacity(receipts.len());
    let mut outcomes: Vec<Option<VfsResult<()>>> = Vec::with_capacity(receipts.len());
    for (receipt, present) in receipts.iter().zip(present) {
        let refused = if !present {
            Some(not_in_trash(receipt))
        } else if receipt.original.symlink_metadata().is_ok() {
            Some(VfsError::new(
                VfsErrorKind::AlreadyExists,
                Some(&receipt.original),
                format!("{} already exists", receipt.original.display()),
            ))
        } else {
            receipt
                .original
                .parent()
                .and_then(|parent| std::fs::create_dir_all(parent).err().map(|e| VfsError::io(&e, parent)))
        };
        match refused {
            Some(error) => outcomes.push(Some(Err(error))),
            None => {
                outcomes.push(None);
                ready.push(*receipt);
            }
        }
    }
    let mut done = platform::put_back_all(&ready).into_iter();
    outcomes.into_iter().map(|o| o.unwrap_or_else(|| done.next().unwrap_or(Ok(())))).collect()
}

fn not_in_trash(receipt: &TrashReceipt) -> VfsError {
    VfsError::new(
        VfsErrorKind::NotFound,
        Some(&receipt.original),
        format!("{} is no longer in the trash", receipt.original.display()),
    )
}

fn now_seconds() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// The path with its folder resolved, as the trash will remember it.
fn canonical(path: &Path) -> PathBuf {
    match (path.parent().and_then(|p| p.canonicalize().ok()), path.file_name()) {
        (Some(parent), Some(name)) => parent.join(name),
        _ => path.to_path_buf(),
    }
}

#[cfg_attr(target_os = "macos", allow(dead_code))]
fn crate_error(error: trash::Error, path: &Path) -> VfsError {
    match error {
        trash::Error::CouldNotAccess { target } => VfsError::new(
            VfsErrorKind::PermissionDenied,
            Some(Path::new(&target)),
            format!("could not access {target}"),
        ),
        trash::Error::Unknown { description } => VfsError::new(VfsErrorKind::Io, Some(path), description),
        other => VfsError::new(VfsErrorKind::Unsupported, Some(path), other.to_string()),
    }
}

#[cfg(target_os = "macos")]
mod platform {
    use std::path::{Path, PathBuf};

    use objc2::rc::{autoreleasepool, Retained};
    use objc2_foundation::{NSFileManager, NSString, NSURL};

    use super::{canonical, not_in_trash, now_seconds, TrashReceipt};
    use crate::error::{VfsError, VfsErrorKind, VfsResult};

    pub const SUPPORTED: bool = true;

    pub fn trash_items(paths: &[PathBuf]) -> Vec<VfsResult<TrashReceipt>> {
        paths.iter().map(|path| trash_one(path)).collect()
    }

    fn trash_one(path: &Path) -> VfsResult<TrashReceipt> {
        if let Err(e) = path.symlink_metadata() {
            return Err(VfsError::io(&e, path));
        }
        let original = canonical(path);
        autoreleasepool(|_| {
            let manager = NSFileManager::defaultManager();
            let url = NSURL::fileURLWithPath(&NSString::from_str(&original.to_string_lossy()));
            let mut resulting: Option<Retained<NSURL>> = None;
            manager.trashItemAtURL_resultingItemURL_error(&url, Some(&mut resulting)).map_err(|error| {
                VfsError::new(
                    VfsErrorKind::Io,
                    Some(path),
                    format!("{}: {}", path.display(), error.localizedDescription()),
                )
            })?;
            let token = resulting.and_then(|url| url.path()).map(|p| p.to_string());
            Ok(TrashReceipt { original: original.clone(), token, time_deleted: now_seconds() })
        })
    }

    pub fn are_in_trash(receipts: &[&TrashReceipt]) -> Vec<bool> {
        receipts
            .iter()
            .map(|r| r.token.as_deref().is_some_and(|p| Path::new(p).symlink_metadata().is_ok()))
            .collect()
    }

    pub fn put_back_all(receipts: &[&TrashReceipt]) -> Vec<VfsResult<()>> {
        receipts
            .iter()
            .map(|receipt| {
                let Some(trashed) = receipt.token.as_deref().map(Path::new) else {
                    return Err(not_in_trash(receipt));
                };
                std::fs::rename(trashed, &receipt.original).map_err(|e| VfsError::io(&e, trashed))
            })
            .collect()
    }
}

#[cfg(any(windows, all(unix, not(target_os = "macos"), not(target_os = "ios"), not(target_os = "android"))))]
mod platform {
    use std::collections::HashMap;
    use std::ffi::OsString;
    use std::path::PathBuf;

    use trash::os_limited;
    use trash::TrashItem;

    use super::{canonical, crate_error, not_in_trash, now_seconds, TrashReceipt};
    use crate::error::{VfsError, VfsErrorKind, VfsResult};

    pub const SUPPORTED: bool = true;

    pub fn trash_items(paths: &[PathBuf]) -> Vec<VfsResult<TrashReceipt>> {
        let started = now_seconds();
        let moved: Vec<VfsResult<PathBuf>> = paths
            .iter()
            .map(|path| {
                let original = canonical(path);
                trash::delete(path).map(|()| original).map_err(|e| crate_error(e, path))
            })
            .collect();
        // One look at the trash finds every item just moved there.
        let listed = os_limited::list().unwrap_or_default();
        moved
            .into_iter()
            .map(|result| {
                result.map(|original| {
                    let found = listed
                        .iter()
                        .filter(|item| item.original_path() == original && item.time_deleted >= started - 1)
                        .max_by_key(|item| item.time_deleted);
                    TrashReceipt {
                        token: found.map(|item| item.id.to_string_lossy().into_owned()),
                        time_deleted: found.map(|item| item.time_deleted).unwrap_or(started),
                        original,
                    }
                })
            })
            .collect()
    }

    fn listed() -> HashMap<OsString, TrashItem> {
        os_limited::list().unwrap_or_default().into_iter().map(|item| (item.id.clone(), item)).collect()
    }

    pub fn are_in_trash(receipts: &[&TrashReceipt]) -> Vec<bool> {
        let listed = listed();
        receipts
            .iter()
            .map(|r| r.token.as_deref().is_some_and(|t| listed.contains_key(&OsString::from(t))))
            .collect()
    }

    pub fn put_back_all(receipts: &[&TrashReceipt]) -> Vec<VfsResult<()>> {
        let mut listed = listed();
        receipts
            .iter()
            .map(|receipt| {
                let item = receipt.token.as_deref().and_then(|t| listed.remove(&OsString::from(t)));
                let Some(item) = item else { return Err(not_in_trash(receipt)) };
                os_limited::restore_all([item]).map_err(|e| crate_error(e, &receipt.original))?;
                if receipt.original.symlink_metadata().is_err() {
                    return Err(VfsError::new(
                        VfsErrorKind::Io,
                        Some(&receipt.original),
                        format!("{} was not put back", receipt.original.display()),
                    ));
                }
                Ok(())
            })
            .collect()
    }
}

#[cfg(not(any(
    target_os = "macos",
    windows,
    all(unix, not(target_os = "macos"), not(target_os = "ios"), not(target_os = "android"))
)))]
mod platform {
    use std::path::PathBuf;

    use super::{canonical, crate_error, not_in_trash, now_seconds, TrashReceipt};
    use crate::error::VfsResult;

    pub const SUPPORTED: bool = false;

    pub fn trash_items(paths: &[PathBuf]) -> Vec<VfsResult<TrashReceipt>> {
        paths
            .iter()
            .map(|path| {
                let original = canonical(path);
                trash::delete(path)
                    .map(|()| TrashReceipt { original, token: None, time_deleted: now_seconds() })
                    .map_err(|e| crate_error(e, path))
            })
            .collect()
    }

    pub fn are_in_trash(receipts: &[&TrashReceipt]) -> Vec<bool> {
        vec![false; receipts.len()]
    }

    pub fn put_back_all(receipts: &[&TrashReceipt]) -> Vec<VfsResult<()>> {
        receipts.iter().map(|r| Err(not_in_trash(r))).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Trashes files of a temporary folder under the home folder (so they
    /// go to the user's own trash, not a volume's), then puts them back.
    #[test]
    fn trashes_with_receipts_and_puts_back() {
        let home = crate::system::home_dir();
        let Ok(dir) = tempfile::Builder::new().prefix(".ferryx-trash-test").tempdir_in(&home) else {
            return;
        };
        let a = dir.path().join("receipt a.txt");
        let b = dir.path().join("receipt b.txt");
        std::fs::write(&a, b"keep me").unwrap();
        std::fs::write(&b, b"and me").unwrap();
        let receipts = trash_items(&[a.clone(), b.clone()]);
        let receipts: Vec<TrashReceipt> = match receipts.into_iter().collect::<VfsResult<Vec<_>>>() {
            Ok(receipts) => receipts,
            // A desktop without a trash (a bare container): nothing to check.
            Err(e) if e.kind == VfsErrorKind::Unsupported => return,
            Err(e) => panic!("trash failed: {e}"),
        };
        assert!(!a.exists() && !b.exists());
        assert_eq!(receipts[0].original.file_name(), a.file_name());
        if !put_back_supported() {
            return;
        }
        let refs: Vec<&TrashReceipt> = receipts.iter().collect();
        assert_eq!(are_in_trash(&refs), vec![true, true]);
        // `b`'s place is taken meanwhile: only `a` comes back.
        std::fs::write(&b, b"newcomer").unwrap();
        let outcomes = put_back_all(&refs);
        assert!(outcomes[0].is_ok());
        assert_eq!(outcomes[1].as_ref().unwrap_err().kind, VfsErrorKind::AlreadyExists);
        assert_eq!(std::fs::read(&a).unwrap(), b"keep me");
        assert!(!is_in_trash(&receipts[0]));
        // Twice is an error, not a guess.
        assert_eq!(put_back(&receipts[0]).unwrap_err().kind, VfsErrorKind::NotFound);
        std::fs::remove_file(&b).unwrap();
        put_back(&receipts[1]).unwrap();
        assert_eq!(std::fs::read(&b).unwrap(), b"and me");
    }

    #[test]
    fn put_back_refuses_without_a_receipt() {
        let dir = tempfile::tempdir().unwrap();
        let receipt = TrashReceipt { original: dir.path().join("gone"), token: None, time_deleted: 0 };
        assert!(!is_in_trash(&receipt));
        assert_eq!(put_back(&receipt).unwrap_err().kind, VfsErrorKind::NotFound);
        assert!(!dir.path().join("gone").exists());
    }
}
