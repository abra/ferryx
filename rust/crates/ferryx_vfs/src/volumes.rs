//! The mounted volumes, for the Volumes quick list and the footer.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Volume {
    pub name: String,
    pub mount_point: PathBuf,
    pub total_bytes: u64,
    pub available_bytes: u64,
    pub file_system: String,
    pub removable: bool,
    /// The boot volume.
    pub is_root: bool,
}

/// Every mounted volume a user may want to browse: the system's own
/// hidden ones (`/dev`, snapshots, `/System/Volumes/…`) are left out.
pub fn list() -> Vec<Volume> {
    let disks = sysinfo::Disks::new_with_refreshed_list();
    let mut out: Vec<Volume> = Vec::new();
    for disk in disks.iter() {
        let mount: PathBuf = disk.mount_point().to_path_buf();
        if !is_user_volume(&mount) {
            continue;
        }
        if out.iter().any(|v| v.mount_point == mount) {
            continue;
        }
        let name = disk.name().to_string_lossy().trim().to_string();
        let name = if name.is_empty() {
            mount
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| mount.to_string_lossy().into_owned())
        } else {
            name
        };
        out.push(Volume {
            name,
            is_root: mount == Path::new("/"),
            mount_point: mount,
            total_bytes: disk.total_space(),
            available_bytes: disk.available_space(),
            file_system: disk.file_system().to_string_lossy().into_owned(),
            removable: disk.is_removable(),
        });
    }
    out.sort_by(|a, b| {
        b.is_root.cmp(&a.is_root).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    out
}

fn is_user_volume(mount: &Path) -> bool {
    let text = mount.to_string_lossy();
    if cfg!(target_os = "macos") {
        return text == "/" || text.starts_with("/Volumes/");
    }
    if cfg!(target_os = "linux") {
        return text == "/"
            || text.starts_with("/media/")
            || text.starts_with("/mnt/")
            || text.starts_with("/run/media/")
            || text.starts_with("/home");
    }
    true
}

/// The volume holding `path`: the one with the longest mount point that
/// is a prefix of it.
pub fn volume_of(path: &Path, volumes: &[Volume]) -> Option<Volume> {
    volumes
        .iter()
        .filter(|v| path.starts_with(&v.mount_point))
        .max_by_key(|v| v.mount_point.as_os_str().len())
        .cloned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_root_volume_is_listed_first() {
        let volumes = list();
        assert!(!volumes.is_empty());
        assert!(volumes[0].is_root);
        assert!(volumes[0].total_bytes > 0);
        let here = volume_of(Path::new("/usr/bin"), &volumes).unwrap();
        assert!(here.is_root);
    }
}
