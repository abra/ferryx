//! The mounted volumes, for the Volumes quick list and the footer.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use parking_lot::Mutex;
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
/// Listed afresh, they are found afresh for footers too (a volume renamed).
pub fn list() -> Vec<Volume> {
    let volumes = read_all();
    *KNOWN.lock() = None;
    volumes
}

#[cfg(test)]
static READS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

fn read_all() -> Vec<Volume> {
    #[cfg(test)]
    READS.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
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

/// The volume holding each device seen since the volumes were last
/// listed: listing them takes tens of milliseconds, a footer asks often.
static KNOWN: Mutex<Option<HashMap<u64, Option<Volume>>>> = parking_lot::const_mutex(None);

/// The volume holding `path` (as [`volume_of`] finds it), for a listing's
/// footer. The volumes are listed again only for a device not seen since
/// they were last: a volume mounted meanwhile.
pub fn volume_holding(path: &Path) -> Option<Volume> {
    let Some(device) = crate::native::device_of(path) else {
        return volume_of(path, &read_all());
    };
    let mut known = KNOWN.lock();
    let by_device = known.get_or_insert_with(HashMap::new);
    if let Some(found) = by_device.get(&device) {
        return found.clone();
    }
    let found = volume_of(path, &read_all());
    by_device.insert(device, found.clone());
    found
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::Ordering;

    // One test: `list` forgets what `volume_holding` found.
    #[test]
    fn the_root_volume_is_listed_first_and_found_again_without_a_listing() {
        let volumes = list();
        assert!(!volumes.is_empty());
        assert!(volumes[0].is_root);
        assert!(volumes[0].total_bytes > 0);
        let here = volume_of(Path::new("/usr/bin"), &volumes).unwrap();
        assert!(here.is_root);

        let listed = READS.load(Ordering::SeqCst);
        let first = volume_holding(Path::new("/usr/bin")).unwrap();
        assert_eq!(first.mount_point, here.mount_point);
        for _ in 0..100 {
            assert_eq!(
                volume_holding(Path::new("/usr/lib")).map(|v| v.mount_point),
                Some(first.mount_point.clone())
            );
        }
        assert_eq!(READS.load(Ordering::SeqCst) - listed, 1);
        list();
        volume_holding(Path::new("/usr/lib"));
        assert_eq!(READS.load(Ordering::SeqCst) - listed, 3);
    }
}
