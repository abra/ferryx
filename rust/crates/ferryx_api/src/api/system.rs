//! Volumes, standard folders, opening and revealing items, ejecting.

use std::path::Path;

use ferryx_vfs::{system, volumes};

use crate::api::types::{ApiResult, StandardFoldersView, VolumeView};

pub fn list_volumes() -> Vec<VolumeView> {
    volumes::list()
        .into_iter()
        .map(|v| VolumeView {
            name: v.name,
            mount_point: v.mount_point.to_string_lossy().into_owned(),
            total_bytes: v.total_bytes as i64,
            available_bytes: v.available_bytes as i64,
            file_system: v.file_system,
            removable: v.removable,
            is_root: v.is_root,
        })
        .collect()
}

#[flutter_rust_bridge::frb(sync)]
pub fn standard_folders() -> StandardFoldersView {
    let f = system::standard_folders();
    let s = |p: std::path::PathBuf| p.to_string_lossy().into_owned();
    StandardFoldersView {
        home: s(f.home),
        desktop: s(f.desktop),
        documents: s(f.documents),
        downloads: s(f.downloads),
        applications: s(f.applications),
        utilities: s(f.utilities),
        library: s(f.library),
        root: s(f.root),
        temporary: s(f.temporary),
        user_name: system::user_name(),
    }
}

pub fn free_space(path: String) -> Option<i64> {
    ferryx_vfs::native::free_space(Path::new(&path)).map(|b| b as i64)
}

/// Opens the item as a double click in the desktop's file manager would.
pub fn open_default(path: String) -> ApiResult<()> {
    Ok(system::open_default(Path::new(&path))?)
}

pub fn open_with(path: String, app: String) -> ApiResult<()> {
    Ok(system::open_with(Path::new(&path), Path::new(&app))?)
}

/// Shows the item selected in Finder, Explorer or the desktop's files app.
pub fn reveal_in_file_manager(path: String) -> ApiResult<()> {
    Ok(system::reveal(Path::new(&path))?)
}

pub fn eject_volume(mount_point: String) -> ApiResult<()> {
    Ok(system::eject(Path::new(&mount_point))?)
}

/// Applications that open files like `path` (macOS; empty elsewhere).
pub fn applications_for(path: String) -> Vec<String> {
    system::applications_for(Path::new(&path)).into_iter().map(|p| p.to_string_lossy().into_owned()).collect()
}
