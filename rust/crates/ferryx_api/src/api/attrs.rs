//! The File Attributes dialog: read and change permissions, flags, owners
//! and times.

use std::path::Path;

use ferryx_vfs::attrs::{self, AttributeChanges};
use ferryx_vfs::native;

use crate::api::types::{ApiResult, AttributeChangesView, AttributesView, RenameFailureView};

pub fn read_attributes(path: String) -> ApiResult<AttributesView> {
    let a = attrs::read(Path::new(&path))?;
    Ok(AttributesView {
        path,
        permissions: a.permissions,
        uid: a.uid,
        gid: a.gid,
        owner: a.owner,
        group: a.group,
        flags: a.flags,
        supports_flags: cfg!(any(target_os = "macos", target_os = "freebsd")),
        modified_ms: a.modified_ms,
        accessed_ms: a.accessed_ms,
        created_ms: a.created_ms,
        is_dir: a.is_dir,
    })
}

/// Applies `changes` to every path (and, with `recursive`, inside the
/// folders among them); answers the items that failed.
pub fn apply_attributes(
    paths: Vec<String>,
    changes: AttributeChangesView,
    recursive: bool,
) -> Vec<RenameFailureView> {
    let changes = AttributeChanges {
        permissions_set: changes.permissions_set,
        permissions_clear: changes.permissions_clear,
        uid: changes.uid,
        gid: changes.gid,
        flags_set: changes.flags_set,
        flags_clear: changes.flags_clear,
        modified_ms: changes.modified_ms,
        accessed_ms: changes.accessed_ms,
    };
    let mut failures = Vec::new();
    for path in paths {
        if let Err(e) = attrs::apply(Path::new(&path), &changes, recursive) {
            failures.push(RenameFailureView { path: e.path.unwrap_or(path), message: e.message });
        }
    }
    failures
}

/// The id of the user named `name`, if the system knows one.
pub fn lookup_user(name: String) -> Option<u32> {
    native::user_id(&name)
}

pub fn lookup_group(name: String) -> Option<u32> {
    native::group_id(&name)
}
