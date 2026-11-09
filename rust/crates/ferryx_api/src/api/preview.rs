//! Local files lent to document viewers, registered before preparation.

use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, LazyLock};

use ferryx_vfs::preview::PreviewFile;
use ferryx_vfs::VfsError;
use parking_lot::Mutex;

use super::types::{ApiResult, LocationView};

static NEXT_ID: AtomicI64 = AtomicI64::new(1);
static FILES: LazyLock<Mutex<HashMap<i64, Arc<PreviewFile>>>> = LazyLock::new(Default::default);

/// Registers a lease without I/O, so it can be cancelled before any
/// asynchronous preparation starts. Every handle must be closed.
#[flutter_rust_bridge::frb(sync)]
pub fn create_preview_file(location: LocationView) -> i64 {
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    FILES.lock().insert(id, Arc::new(PreviewFile::new(location.to_location())));
    id
}

/// Prepares once on a bridge worker. Native files retain their original
/// path; remote files and archive members get a privately owned copy.
pub fn prepare_preview_file(id: i64) -> ApiResult<String> {
    let file = FILES.lock().get(&id).cloned().ok_or_else(VfsError::cancelled)?;
    Ok(file.prepare()?.to_string_lossy().into_owned())
}

/// Stops a pending preparation immediately, independent of bridge worker
/// availability. `close_preview_file` then waits for cleanup.
#[flutter_rust_bridge::frb(sync)]
pub fn cancel_preview_file(id: i64) {
    if let Some(file) = FILES.lock().get(&id) {
        file.cancel();
    }
}

/// Releases the lease after its decoder has closed. Safe to call again.
pub fn close_preview_file(id: i64) -> ApiResult<()> {
    let file = FILES.lock().get(&id).cloned();
    if let Some(file) = file {
        let result = file.close();
        FILES.lock().remove(&id);
        result?;
    }
    Ok(())
}

#[flutter_rust_bridge::frb(ignore)]
pub(crate) fn reset() {
    let files: Vec<_> = FILES.lock().drain().map(|(_, file)| file).collect();
    for file in &files {
        file.cancel();
    }
    for file in files {
        let _ = file.close();
    }
}
