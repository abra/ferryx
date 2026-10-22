//! Single items: their metadata, their bytes, making, renaming, linking.

use std::path::{Path, PathBuf};

use ferryx_vfs::{archive, links, native};

use crate::api::types::{ApiResult, EntryView, FerryxError, FerryxErrorKind, LocationKind, LocationView};
use crate::app;

pub fn stat(path: String) -> ApiResult<EntryView> {
    Ok(EntryView::from(&native::stat(Path::new(&path))?))
}

/// Up to `len` bytes of the file at `location` (a file on disk, or a
/// member of an archive) from `offset`.
pub fn read_file_range(location: LocationView, offset: i64, len: i64) -> ApiResult<Vec<u8>> {
    let offset = offset.max(0) as u64;
    let len = len.max(0) as usize;
    match location.kind {
        LocationKind::Native => Ok(native::read_range(Path::new(&location.path), offset, len)?),
        LocationKind::Archive => {
            let index = app::archive_index(Path::new(&location.archive.unwrap_or_default()))?;
            Ok(index.read_range(location.path.trim_matches('/'), offset, len)?)
        }
    }
}

pub fn file_size(location: LocationView) -> ApiResult<i64> {
    match location.kind {
        LocationKind::Native => Ok(native::file_size(Path::new(&location.path))? as i64),
        LocationKind::Archive => {
            let index = app::archive_index(Path::new(&location.archive.unwrap_or_default()))?;
            let member = index.member(location.path.trim_matches('/')).ok_or_else(|| {
                FerryxError::new(
                    FerryxErrorKind::NotFound,
                    format!("{} is not in the archive", location.path),
                )
            })?;
            Ok(member.size as i64)
        }
    }
}

/// Extracts an archive member (a file or a folder) to a temporary folder
/// for opening or viewing; answers the path written.
pub fn extract_to_temp(archive_path: String, inner: String) -> ApiResult<String> {
    let archive_path = PathBuf::from(archive_path);
    let index = app::archive_index(&archive_path)?;
    let dir = archive::temp_dir_for(&archive_path);
    std::fs::create_dir_all(&dir).map_err(|e| FerryxError::new(FerryxErrorKind::Io, e.to_string()))?;
    let written = index.extract(inner.trim_matches('/'), &dir)?;
    Ok(written.to_string_lossy().into_owned())
}

/// Makes the folder at `path`, and every missing folder above it.
pub fn create_directory(path: String) -> ApiResult<()> {
    Ok(native::create_dir_all(Path::new(&path))?)
}

pub fn create_file(path: String) -> ApiResult<()> {
    Ok(native::create_file(Path::new(&path))?)
}

/// Renames the item at `path` to `new_name`; answers its new path.
pub fn rename_item(path: String, new_name: String) -> ApiResult<String> {
    Ok(native::rename(Path::new(&path), &new_name)?.to_string_lossy().into_owned())
}

pub fn create_symlink(target: String, link: String) -> ApiResult<()> {
    Ok(links::create_symlink(Path::new(&target), Path::new(&link))?)
}

pub fn create_hardlink(target: String, link: String) -> ApiResult<()> {
    Ok(links::create_hardlink(Path::new(&target), Path::new(&link))?)
}

pub fn edit_symlink(link: String, target: String) -> ApiResult<()> {
    Ok(links::edit_symlink(Path::new(&link), Path::new(&target))?)
}

pub fn read_symlink(link: String) -> ApiResult<String> {
    Ok(links::read_symlink(Path::new(&link))?.to_string_lossy().into_owned())
}

/// `path` with every symlink followed, for Follow (⌘→).
pub fn resolve_path(path: String) -> ApiResult<String> {
    let resolved = std::fs::canonicalize(Path::new(&path))
        .map_err(|e| ferryx_vfs::VfsError::io(&e, Path::new(&path)))?;
    Ok(resolved.to_string_lossy().into_owned())
}

/// The first free name in `dir` for a new item: `name`, else `name 2`…
#[flutter_rust_bridge::frb(sync)]
pub fn free_name(dir: String, name: String) -> String {
    let dir = Path::new(&dir);
    if dir.join(&name).symlink_metadata().is_err() {
        return name;
    }
    ferryx_ops::runner::free_name(dir, &name)
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or(name)
}
