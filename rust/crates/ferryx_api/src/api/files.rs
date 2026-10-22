//! Single items: their metadata, their bytes, making, renaming, linking.

use std::path::{Path, PathBuf};

use ferryx_ops::journal::{Change, Fingerprint, StepKind};
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
            let archive = PathBuf::from(location.archive.unwrap_or_default());
            let index = app::archive_index(&archive)?;
            let password = app::archive_password(&archive);
            Ok(index.read_range(location.path.trim_matches('/'), offset, len, password.as_deref())?)
        }
    }
}

/// The file's size; an archive member's as its archive keeps it, or as
/// unpacked when the format does not say (a bzip2 stream).
pub fn file_size(location: LocationView) -> ApiResult<i64> {
    match location.kind {
        LocationKind::Native => Ok(native::file_size(Path::new(&location.path))? as i64),
        LocationKind::Archive => {
            let archive = PathBuf::from(location.archive.unwrap_or_default());
            let index = app::archive_index(&archive)?;
            let password = app::archive_password(&archive);
            Ok(index.member_size(location.path.trim_matches('/'), password.as_deref())? as i64)
        }
    }
}

/// Extracts an archive member (a file or a folder) to a temporary folder
/// for opening or viewing; answers the path written. A member of a solid
/// archive decodes its block up to it: this runs on a worker of the
/// bridge, never on the interface's thread.
pub fn extract_to_temp(archive_path: String, inner: String) -> ApiResult<String> {
    let archive_path = PathBuf::from(archive_path);
    let index = app::archive_index(&archive_path)?;
    let password = app::archive_password(&archive_path);
    let dir = archive::temp_dir_for(&archive_path);
    std::fs::create_dir_all(&dir).map_err(|e| FerryxError::new(FerryxErrorKind::Io, e.to_string()))?;
    let written = index.extract_with(inner.trim_matches('/'), &dir, password.as_deref())?;
    Ok(written.to_string_lossy().into_owned())
}

/// Makes the folder at `path`, and every missing folder above it. On the
/// journal: undo trashes the topmost folder made.
pub fn create_directory(path: String) -> ApiResult<()> {
    let path = PathBuf::from(path);
    let top = crate::tasks::first_missing(&path);
    native::create_dir_all(&path)?;
    if let Some(top) = top {
        record_created(StepKind::CreateFolder, &top);
    }
    Ok(())
}

pub fn create_file(path: String) -> ApiResult<()> {
    native::create_file(Path::new(&path))?;
    record_created(StepKind::CreateFile, Path::new(&path));
    Ok(())
}

/// Renames the item at `path` to `new_name`; answers its new path. On the
/// journal: undo renames it back.
pub fn rename_item(path: String, new_name: String) -> ApiResult<String> {
    let from = PathBuf::from(&path);
    let to = native::rename(&from, &new_name)?;
    crate::tasks::record(
        StepKind::Rename,
        std::slice::from_ref(&from),
        vec![Change::Moved { from: from.clone(), to: to.clone() }],
    );
    Ok(to.to_string_lossy().into_owned())
}

pub fn create_symlink(target: String, link: String) -> ApiResult<()> {
    links::create_symlink(Path::new(&target), Path::new(&link))?;
    record_created(StepKind::CreateLink, Path::new(&link));
    Ok(())
}

pub fn create_hardlink(target: String, link: String) -> ApiResult<()> {
    links::create_hardlink(Path::new(&target), Path::new(&link))?;
    record_created(StepKind::CreateLink, Path::new(&link));
    Ok(())
}

/// Puts a new item on the journal: undo moves it to the trash.
fn record_created(kind: StepKind, path: &Path) {
    let change = Change::Created { path: path.to_path_buf(), fingerprint: Fingerprint::of(path) };
    crate::tasks::record(kind, &[path.to_path_buf()], vec![change]);
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
