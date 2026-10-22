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
            Ok(()) => staged.push((temp, target.clone(), path.clone())),
            Err(e) => failures.push(RenameFailure { path: path.clone(), message: e.message }),
        }
    }
    for (temp, target, old) in staged {
        match rename_checked(&temp, &target) {
            Ok(()) => done.push((old, target)),
            Err(e) => {
                failures.push(RenameFailure { path: target.clone(), message: e.message });
                // Leave nothing under a temporary name: back to the old
                // name when it is free (another item may have taken it).
                if old.symlink_metadata().is_err() {
                    let _ = std::fs::rename(&temp, &old);
                }
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
    fn reports_a_taken_name() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("a"), b"A").unwrap();
        fs::write(dir.path().join("c"), b"C").unwrap();
        let failures = apply(&[(dir.path().join("a"), "c".to_string())]);
        assert_eq!(failures.len(), 1);
        assert!(dir.path().join("a").exists());
    }
}
