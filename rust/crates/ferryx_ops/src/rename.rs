//! Applying a batch rename: every item renamed, in an order that lets
//! names swap places.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use ferryx_vfs::error::{IoAt, VfsError};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenameFailure {
    pub path: PathBuf,
    pub message: String,
}

/// Renames each `(path, new name)` pair in its own folder. Pairs whose
/// name is unchanged are skipped. When a new name is the old name of
/// another item (a swap, a shift), the items are moved through temporary
/// names first. Answers what failed.
pub fn apply(pairs: &[(PathBuf, String)]) -> Vec<RenameFailure> {
    apply_recorded(pairs).0
}

/// [`apply`], answering also each rename done, as `(old path, new path)`,
/// for the journal.
pub fn apply_recorded(pairs: &[(PathBuf, String)]) -> (Vec<RenameFailure>, Vec<(PathBuf, PathBuf)>) {
    let mut done = Vec::new();
    let failures = apply_inner(pairs, &mut done);
    (failures, done)
}

fn apply_inner(pairs: &[(PathBuf, String)], done: &mut Vec<(PathBuf, PathBuf)>) -> Vec<RenameFailure> {
    let mut failures = Vec::new();
    let active: Vec<&(PathBuf, String)> = pairs
        .iter()
        .filter(|(p, n)| p.file_name().map(|f| f.to_string_lossy() != n.as_str()).unwrap_or(false))
        .collect();
    let old_paths: HashSet<PathBuf> = active.iter().map(|(p, _)| p.clone()).collect();
    let targets: Vec<PathBuf> = active.iter().map(|(p, n)| p.with_file_name(n)).collect();
    let needs_staging = targets.iter().any(|t| old_paths.contains(t));
    if !needs_staging {
        for ((path, _), target) in active.iter().zip(&targets) {
            match rename_checked(path, target) {
                Ok(()) => done.push((path.clone(), target.clone())),
                Err(e) => failures.push(RenameFailure { path: path.clone(), message: e.message }),
            }
        }
        return failures;
    }
    // Stage through unique temporary names, then land each on its target.
    let mut staged: Vec<(PathBuf, PathBuf, PathBuf)> = Vec::new();
    for (i, ((path, _), target)) in active.iter().zip(&targets).enumerate() {
        let temp = path.with_file_name(format!(".ferryx-rename-{}-{i}", std::process::id()));
        match std::fs::rename(path, &temp).at(path) {
            Ok(()) => staged.push((path.clone(), temp, target.clone())),
            Err(e) => failures.push(RenameFailure { path: path.clone(), message: e.message }),
        }
    }
    for (original, temp, target) in staged {
        match rename_checked(&temp, &target) {
            Ok(()) => done.push((original, target)),
            Err(e) => {
                // Back to the old name while it is free; never over another
                // item. Taken meanwhile, it stays under the temporary name,
                // which the message gives.
                let message = match rename_checked(&temp, &original) {
                    Ok(()) => e.message,
                    Err(_) => format!("{} (kept as {})", e.message, temp.display()),
                };
                failures.push(RenameFailure { path: original, message });
            }
        }
    }
    failures
}

fn rename_checked(from: &Path, to: &Path) -> Result<(), VfsError> {
    if to.symlink_metadata().is_ok() && !same_case_insensitive(from, to) {
        return Err(VfsError::new(
            ferryx_vfs::VfsErrorKind::AlreadyExists,
            Some(to),
            format!("{} already exists", to.display()),
        ));
    }
    std::fs::rename(from, to).at(from)
}

fn same_case_insensitive(a: &Path, b: &Path) -> bool {
    a.parent() == b.parent()
        && a.file_name().map(|n| n.to_string_lossy().to_lowercase())
            == b.file_name().map(|n| n.to_string_lossy().to_lowercase())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn swaps_names() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("a"), b"A").unwrap();
        fs::write(dir.path().join("b"), b"B").unwrap();
        let failures =
            apply(&[(dir.path().join("a"), "b".to_string()), (dir.path().join("b"), "a".to_string())]);
        assert!(failures.is_empty());
        assert_eq!(fs::read(dir.path().join("a")).unwrap(), b"B");
        assert_eq!(fs::read(dir.path().join("b")).unwrap(), b"A");
        assert!(fs::read_dir(dir.path()).unwrap().count() == 2);
    }

    #[test]
    fn a_staged_item_that_cannot_land_goes_back_never_over_another() {
        let dir = tempfile::tempdir().unwrap();
        for (name, body) in [("a", "A"), ("b", "B"), ("c", "C"), ("d", "D")] {
            fs::write(dir.path().join(name), body).unwrap();
        }
        // The swap stages every item; `d` is taken and not renamed.
        let failures = apply(&[
            (dir.path().join("a"), "b".to_string()),
            (dir.path().join("b"), "a".to_string()),
            (dir.path().join("c"), "d".to_string()),
        ]);
        assert_eq!(failures.len(), 1);
        assert_eq!(failures[0].path, dir.path().join("c"));
        assert_eq!(fs::read(dir.path().join("a")).unwrap(), b"B");
        assert_eq!(fs::read(dir.path().join("b")).unwrap(), b"A");
        assert_eq!(fs::read(dir.path().join("c")).unwrap(), b"C");
        assert_eq!(fs::read(dir.path().join("d")).unwrap(), b"D");
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 4);
    }

    #[test]
    fn two_items_for_one_name_leave_the_second_where_it_was() {
        let dir = tempfile::tempdir().unwrap();
        for (name, body) in [("a", "A"), ("b", "B"), ("c", "C")] {
            fs::write(dir.path().join(name), body).unwrap();
        }
        let failures = apply(&[
            (dir.path().join("a"), "c".to_string()),
            (dir.path().join("b"), "c".to_string()),
            (dir.path().join("c"), "a".to_string()),
        ]);
        assert_eq!(failures.len(), 1);
        assert_eq!(failures[0].path, dir.path().join("b"));
        assert_eq!(fs::read(dir.path().join("c")).unwrap(), b"A");
        assert_eq!(fs::read(dir.path().join("a")).unwrap(), b"C");
        assert_eq!(fs::read(dir.path().join("b")).unwrap(), b"B");
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 3);
    }

    #[test]
    fn a_rotation_lands_every_item() {
        let dir = tempfile::tempdir().unwrap();
        for (name, body) in [("1", "one"), ("2", "two"), ("3", "three")] {
            fs::write(dir.path().join(name), body).unwrap();
        }
        let failures = apply(&[
            (dir.path().join("1"), "2".to_string()),
            (dir.path().join("2"), "3".to_string()),
            (dir.path().join("3"), "1".to_string()),
        ]);
        assert!(failures.is_empty());
        assert_eq!(fs::read(dir.path().join("2")).unwrap(), b"one");
        assert_eq!(fs::read(dir.path().join("3")).unwrap(), b"two");
        assert_eq!(fs::read(dir.path().join("1")).unwrap(), b"three");
    }

    #[test]
    fn reports_a_taken_name() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("a"), b"A").unwrap();
        fs::write(dir.path().join("c"), b"C").unwrap();
        let failures = apply(&[(dir.path().join("a"), "c".to_string())]);
        assert_eq!(failures.len(), 1);
        assert!(dir.path().join("a").exists());
    }
}
