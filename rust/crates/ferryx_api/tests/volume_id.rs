//! `volume_id`: what a drop asks to tell a move from a copy.

use std::fs;

use ferryx_api::api::volume_id::volume_id;

fn text(path: &std::path::Path) -> String {
    path.to_string_lossy().into_owned()
}

#[test]
fn paths_on_one_volume_share_an_id() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("a.txt");
    fs::write(&file, b"a").unwrap();
    let folder = dir.path().join("sub");
    fs::create_dir(&folder).unwrap();

    let id = volume_id(text(dir.path()));
    assert!(id.is_some());
    assert_eq!(volume_id(text(&file)), id);
    assert_eq!(volume_id(text(&folder)), id);
}

#[test]
fn a_missing_path_has_none() {
    let dir = tempfile::tempdir().unwrap();
    assert_eq!(volume_id(text(&dir.path().join("gone"))), None);
}

#[cfg(target_os = "macos")]
#[test]
fn another_file_system_has_another_id() {
    // /dev is devfs on macOS, never the volume the temporary folder is on.
    let dir = tempfile::tempdir().unwrap();
    assert_ne!(volume_id("/dev".into()), volume_id(text(dir.path())));
}
