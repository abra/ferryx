//! The indexes read lately and the passwords given, for the whole process.
//!
//! An index is keyed by the archive's path and kept while the file's
//! modification time and length stay the same. Reading one happens
//! outside the lock, so a large archive being read never holds up a
//! listing elsewhere; a few are kept, the least recently used going first.

use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock};

use parking_lot::Mutex;

use super::ArchiveIndex;
use crate::error::{VfsErrorKind, VfsResult};

/// How many indexes stay in memory (a large archive's index takes a few
/// tens of megabytes).
const KEEP: usize = 8;

#[derive(Default)]
struct Shared {
    /// The most recently used last.
    indexes: VecDeque<Arc<ArchiveIndex>>,
    passwords: HashMap<PathBuf, String>,
}

static SHARED: LazyLock<Mutex<Shared>> = LazyLock::new(|| Mutex::new(Shared::default()));

/// The index of `archive`: the one kept, else read now (with the password
/// given for it earlier, when its member list is encrypted).
pub fn index(archive: &Path) -> VfsResult<Arc<ArchiveIndex>> {
    let (kept, password) = {
        let mut shared = SHARED.lock();
        let kept = shared.indexes.iter().position(|i| i.archive == archive).map(|at| {
            let index = shared.indexes.remove(at).expect("position is in range");
            shared.indexes.push_back(index.clone());
            index
        });
        (kept, shared.passwords.get(archive).cloned())
    };
    if let Some(index) = kept {
        if !index.is_stale() {
            return Ok(index);
        }
    }
    let index = Arc::new(ArchiveIndex::open_with(archive, password.as_deref())?);
    keep(index.clone());
    Ok(index)
}

fn keep(index: Arc<ArchiveIndex>) {
    let mut shared = SHARED.lock();
    shared.indexes.retain(|i| i.archive != index.archive);
    shared.indexes.push_back(index);
    while shared.indexes.len() > KEEP {
        shared.indexes.pop_front();
    }
}

/// Tries `password` on `archive` and, when it opens it, keeps it for the
/// archive's listings and extractions from now on. A wrong one is a
/// [`VfsErrorKind::WrongPassword`] error and is not kept.
pub fn set_password(archive: &Path, password: &str) -> VfsResult<()> {
    let index = match index(archive) {
        Ok(index) => index,
        Err(e) if e.kind == VfsErrorKind::PasswordRequired => {
            let index = Arc::new(ArchiveIndex::open_with(archive, Some(password))?);
            keep(index.clone());
            index
        }
        Err(e) => return Err(e),
    };
    index.check_password(password)?;
    SHARED.lock().passwords.insert(archive.to_path_buf(), password.to_string());
    Ok(())
}

/// The password kept for `archive`, if one was given.
pub fn password(archive: &Path) -> Option<String> {
    SHARED.lock().passwords.get(archive).cloned()
}

/// Forgets every index and password (tests start clean).
pub fn clear() {
    let mut shared = SHARED.lock();
    shared.indexes.clear();
    shared.passwords.clear();
}
