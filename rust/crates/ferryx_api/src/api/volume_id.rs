//! Which volume a path is on, so a drop can tell a move (a rename on one
//! volume) from a copy across volumes before anything is written.

use std::path::Path;

use ferryx_vfs::native;

/// The volume (device) of `path`, the same number for every path on one
/// volume; `None` when the path cannot be read. Cheap (one `stat`), so a
/// drag can ask it of each folder it hovers.
#[flutter_rust_bridge::frb(sync)]
pub fn volume_id(path: String) -> Option<i64> {
    native::device_of(Path::new(&path)).map(|device| device as i64)
}
