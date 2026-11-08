#![cfg(unix)]

use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};

use ferryx_ops::{extract, ConflictPolicy, OpContext, OpKind, OpOptions, OpRequest};

fn request(archive: &Path, destination: &Path) -> OpRequest {
    OpRequest {
        kind: OpKind::Extract,
        sources: vec![archive.to_path_buf()],
        archive: None,
        destination: Some(destination.to_path_buf()),
        new_name: None,
        options: OpOptions::default(),
    }
}

fn zip_at(path: &Path, link: Option<&str>, name: &str) {
    let mut zip = zip::ZipWriter::new(File::create(path).unwrap());
    let options = zip::write::SimpleFileOptions::default().unix_permissions(0o640);
    if let Some(link) = link {
        zip.add_symlink("link", link, options).unwrap();
    }
    zip.start_file(name, options).unwrap();
    zip.write_all(b"archive contents").unwrap();
    zip.finish().unwrap();
}

#[test]
fn archive_symlinks_do_not_allow_writes_outside_the_destination() {
    let dir = tempfile::tempdir().unwrap();
    let outside = dir.path().join("outside");
    fs::create_dir(&outside).unwrap();
    for extension in ["zip", "tar"] {
        let archive = dir.path().join(format!("input.{extension}"));
        if extension == "zip" {
            zip_at(&archive, Some("../outside"), "link/created.txt");
        } else {
            let mut tar = tar::Builder::new(File::create(&archive).unwrap());
            let mut link = tar::Header::new_gnu();
            link.set_entry_type(tar::EntryType::Symlink);
            link.set_size(0);
            link.set_mode(0o777);
            tar.append_link(&mut link, "link", "../outside").unwrap();
            let mut file = tar::Header::new_gnu();
            file.set_size(4);
            file.set_mode(0o644);
            tar.append_data(&mut file, "link/created.txt", &b"data"[..]).unwrap();
            tar.finish().unwrap();
        }
        let destination = dir.path().join(extension);
        let req = request(&archive, &destination);
        let ctx = OpContext::detached(&req);
        extract::run(&ctx, &req).unwrap();
        assert!(!outside.join("created.txt").exists(), "{extension}");
        assert!(!ctx.snapshot().errors.is_empty(), "unsafe member must be reported");
        assert_eq!(fs::read_link(destination.join("link")).unwrap(), PathBuf::from("../outside"));
    }
}

#[test]
fn existing_symlinks_cannot_redirect_members_or_archive_subfolders() {
    let dir = tempfile::tempdir().unwrap();
    let outside = dir.path().join("outside");
    fs::create_dir(&outside).unwrap();
    fs::write(outside.join("victim.txt"), b"private contents").unwrap();
    for into_folders in [false, true] {
        let destination = dir.path().join(format!("out-{into_folders}"));
        fs::create_dir(&destination).unwrap();
        std::os::unix::fs::symlink(&outside, destination.join("link")).unwrap();
        let archive = dir.path().join("link.zip");
        zip_at(&archive, None, if into_folders { "victim.txt" } else { "link/victim.txt" });
        let mut req = request(&archive, &destination);
        req.options.into_folders = into_folders;
        req.options.conflicts = ConflictPolicy::Overwrite;
        let ctx = OpContext::detached(&req);
        extract::run(&ctx, &req).unwrap();
        assert_eq!(fs::read(outside.join("victim.txt")).unwrap(), b"private contents");
        assert!(!ctx.snapshot().errors.is_empty());
    }
}

#[test]
fn ordinary_files_and_internal_links_keep_their_contents_and_modes() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::tempdir().unwrap();
    let archive = dir.path().join("input.zip");
    zip_at(&archive, Some("real"), "real/file.txt");
    let destination = dir.path().join("out");
    let req = request(&archive, &destination);
    let ctx = OpContext::detached(&req);
    extract::run(&ctx, &req).unwrap();
    assert!(ctx.snapshot().errors.is_empty());
    assert_eq!(fs::read(destination.join("link/file.txt")).unwrap(), b"archive contents");
    assert_eq!(fs::metadata(destination.join("real/file.txt")).unwrap().permissions().mode() & 0o777, 0o640);
}
