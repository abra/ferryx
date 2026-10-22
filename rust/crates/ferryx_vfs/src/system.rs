//! The desktop around the files: standard folders, opening items with
//! other apps, revealing them, the trash, ejecting.

use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{Deserialize, Serialize};

use crate::error::{VfsError, VfsErrorKind, VfsResult};

/// The folders the Go menu names.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StandardFolders {
    pub home: PathBuf,
    pub desktop: PathBuf,
    pub documents: PathBuf,
    pub downloads: PathBuf,
    pub applications: PathBuf,
    pub utilities: PathBuf,
    pub library: PathBuf,
    pub root: PathBuf,
    pub temporary: PathBuf,
}

pub fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

pub fn standard_folders() -> StandardFolders {
    let home = home_dir();
    let (applications, utilities, library) = if cfg!(target_os = "macos") {
        (PathBuf::from("/Applications"), PathBuf::from("/Applications/Utilities"), home.join("Library"))
    } else if cfg!(windows) {
        (PathBuf::from("C:\\Program Files"), PathBuf::from("C:\\Windows\\System32"), home.join("AppData"))
    } else {
        (PathBuf::from("/usr/share/applications"), PathBuf::from("/usr/bin"), home.join(".local/share"))
    };
    StandardFolders {
        desktop: home.join("Desktop"),
        documents: home.join("Documents"),
        downloads: home.join("Downloads"),
        applications,
        utilities,
        library,
        root: PathBuf::from(if cfg!(windows) { "C:\\" } else { "/" }),
        temporary: std::env::temp_dir(),
        home,
    }
}

/// The user's short name, for the footer and the attributes dialog.
pub fn user_name() -> String {
    std::env::var("USER").or_else(|_| std::env::var("USERNAME")).unwrap_or_default()
}

/// Opens `path` as a double click in the desktop's file manager would.
pub fn open_default(path: &Path) -> VfsResult<()> {
    open::that_detached(path).map_err(|e| VfsError::new(VfsErrorKind::Io, Some(path), e.to_string()))
}

/// Opens `path` with the application at `app` (a `.app` bundle on macOS,
/// an executable elsewhere).
pub fn open_with(path: &Path, app: &Path) -> VfsResult<()> {
    let result = if cfg!(target_os = "macos") {
        Command::new("open").arg("-a").arg(app).arg(path).spawn().map(|_| ())
    } else {
        Command::new(app).arg(path).spawn().map(|_| ())
    };
    result.map_err(|e| VfsError::new(VfsErrorKind::Io, Some(path), e.to_string()))
}

/// Shows `path` selected in Finder, Explorer or the desktop's files app.
pub fn reveal(path: &Path) -> VfsResult<()> {
    let result = if cfg!(target_os = "macos") {
        Command::new("open").arg("-R").arg(path).spawn().map(|_| ())
    } else if cfg!(windows) {
        Command::new("explorer").arg(format!("/select,{}", path.display())).spawn().map(|_| ())
    } else {
        let uri = format!("file://{}", path.display());
        let dbus = Command::new("dbus-send")
            .args([
                "--session",
                "--dest=org.freedesktop.FileManager1",
                "--type=method_call",
                "/org/freedesktop/FileManager1",
                "org.freedesktop.FileManager1.ShowItems",
            ])
            .arg(format!("array:string:{uri}"))
            .arg("string:")
            .status();
        match dbus {
            Ok(status) if status.success() => Ok(()),
            _ => open::that_detached(path.parent().unwrap_or(path)),
        }
    };
    result.map_err(|e| VfsError::new(VfsErrorKind::Io, Some(path), e.to_string()))
}

/// Moves `paths` to the trash.
pub fn trash(paths: &[PathBuf]) -> VfsResult<()> {
    trash::delete_all(paths).map_err(|e| match e {
        trash::Error::CouldNotAccess { target } => VfsError::new(
            VfsErrorKind::PermissionDenied,
            Some(Path::new(&target)),
            format!("could not access {target}"),
        ),
        trash::Error::Unknown { description } => VfsError::new(VfsErrorKind::Io, None, description),
        other => VfsError::new(VfsErrorKind::Unsupported, None, other.to_string()),
    })
}

/// Ejects the volume mounted at `mount_point`.
pub fn eject(mount_point: &Path) -> VfsResult<()> {
    let output = if cfg!(target_os = "macos") {
        Command::new("diskutil").arg("eject").arg(mount_point).output()
    } else if cfg!(target_os = "linux") {
        Command::new("udisksctl").arg("unmount").arg("-p").arg(mount_point).output()
    } else {
        return Err(VfsError::unsupported("ejecting is not supported here"));
    };
    match output {
        Ok(out) if out.status.success() => Ok(()),
        Ok(out) => Err(VfsError::new(
            VfsErrorKind::Io,
            Some(mount_point),
            String::from_utf8_lossy(&out.stderr).trim().to_string(),
        )),
        Err(e) => Err(VfsError::new(VfsErrorKind::Io, Some(mount_point), e.to_string())),
    }
}

/// The applications that can open files of the given kind on macOS, each
/// as its bundle path; other desktops answer nothing (their menus do it).
pub fn applications_for(path: &Path) -> Vec<PathBuf> {
    if !cfg!(target_os = "macos") {
        return Vec::new();
    }
    // `mdls` and Launch Services have no CLI for this; a Spotlight query
    // over the application bundles claiming the extension is the closest.
    let extension = path.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
    if extension.is_empty() {
        return Vec::new();
    }
    let query = format!("kMDItemContentType == 'com.apple.application-bundle' && kMDItemCFBundleDocumentTypes.LSItemContentTypes == '*{extension}*'cd");
    let Ok(output) = Command::new("mdfind").arg(query).output() else { return Vec::new() };
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(PathBuf::from)
        .filter(|p| p.exists())
        .take(20)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn standard_folders_hang_off_home() {
        let folders = standard_folders();
        assert!(folders.desktop.starts_with(&folders.home));
        assert!(folders.root.is_absolute());
    }
}
