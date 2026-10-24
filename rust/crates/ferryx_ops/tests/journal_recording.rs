//! What each operation puts on the undo journal, and that walking it back
//! (and forward again) restores the files.

use std::fs;
use std::path::{Path, PathBuf};

use ferryx_ops::journal::{Change, Step, StepKind};
use ferryx_ops::types::*;
use ferryx_ops::{compress, copy, delete, extract, undo, OpContext};

fn request(kind: OpKind, sources: Vec<PathBuf>, destination: Option<&Path>) -> OpRequest {
    OpRequest {
        kind,
        sources,
        archive: None,
        destination: destination.map(Path::to_path_buf),
        new_name: None,
        options: OpOptions {
            conflicts: ConflictPolicy::Overwrite,
            preserve_attributes: true,
            ..Default::default()
        },
    }
}

/// Runs `request` with its module and answers what it recorded.
fn recorded(request: &OpRequest) -> Vec<Change> {
    let ctx = OpContext::detached(request);
    match request.kind {
        OpKind::Compress => compress::run(&ctx, request).unwrap(),
        OpKind::Trash | OpKind::Delete => delete::run(&ctx, request).unwrap(),
        OpKind::Extract => extract::run(&ctx, request).unwrap(),
        _ => copy::run(&ctx, request).unwrap(),
    }
    ctx.recorded()
}

fn step(changes: Vec<Change>) -> Step {
    Step {
        id: 1,
        kind: StepKind::Copy,
        items: 1,
        first_name: String::new(),
        changes,
        at_ms: 0,
        truncated: false,
    }
}

/// Walks `changes` back; answers what the walk recorded (the other way).
fn walk(changes: Vec<Change>) -> Vec<Change> {
    let ctx = OpContext::detached(&request(OpKind::Undo, Vec::new(), None));
    undo::run(&ctx, &step(changes)).unwrap();
    assert!(ctx.recorded_left().is_empty(), "left: {:?}", ctx.recorded_left());
    ctx.recorded()
}

fn made(changes: &[Change], path: &Path) -> bool {
    changes.iter().any(|c| matches!(c, Change::Created { path: p, .. } if p == path))
}

#[test]
fn a_copy_records_the_topmost_item_it_made() {
    let dir = tempfile::tempdir().unwrap();
    let src = dir.path().join("src");
    fs::create_dir_all(src.join("deep")).unwrap();
    fs::write(src.join("deep/a.txt"), b"a").unwrap();
    let dest = dir.path().join("dest");
    let changes = recorded(&request(OpKind::Copy, vec![src.clone()], Some(&dest)));
    assert_eq!(changes.len(), 1);
    assert!(matches!(&changes[0], Change::Created { path, fingerprint: None } if path == &dest.join("src")));

    // Into the folder that is there now: a merge records each new item,
    // and an overwrite as lost, not as made.
    fs::write(src.join("b.txt"), b"b").unwrap();
    fs::write(src.join("deep/a.txt"), b"new a").unwrap();
    let changes = recorded(&request(OpKind::Copy, vec![src.clone()], Some(&dest)));
    assert!(changes.contains(&Change::Overwritten { path: dest.join("src/deep/a.txt") }));
    assert!(changes.iter().any(|c| matches!(
        c,
        Change::Created { path, fingerprint: Some(f) } if path == &dest.join("src/b.txt") && f.size == 1
    )));
    assert!(!made(&changes, &dest.join("src")));
}

#[test]
fn a_move_records_moves_and_the_folders_a_merge_emptied() {
    let dir = tempfile::tempdir().unwrap();
    let src = dir.path().join("src");
    fs::create_dir_all(src.join("sub")).unwrap();
    fs::write(src.join("sub/a"), b"a").unwrap();
    let dest = dir.path().join("dest");
    fs::create_dir_all(dest.join("src/sub")).unwrap();
    fs::write(dest.join("src/sub/b"), b"b").unwrap();
    let changes = recorded(&request(OpKind::Move, vec![src.clone()], Some(&dest)));
    assert!(changes.contains(&Change::Moved { from: src.join("sub/a"), to: dest.join("src/sub/a") }));
    assert!(changes.contains(&Change::FolderRemoved { path: src.join("sub") }));
    assert!(changes.contains(&Change::FolderRemoved { path: src.clone() }));
    assert!(!src.exists());

    // Back: the folders come again, the item goes home; the item that was
    // there before stays. (Redo would trash the folders made again: the
    // trash is tested on its own, below.)
    let inverse = walk(changes);
    assert_eq!(fs::read(src.join("sub/a")).unwrap(), b"a");
    assert!(dest.join("src/sub/b").exists());
    assert!(!dest.join("src/sub/a").exists());
    assert!(made(&inverse, &src));
    assert!(inverse.contains(&Change::Moved { from: dest.join("src/sub/a"), to: src.join("sub/a") }));
}

#[test]
fn thousands_of_items_moved_and_merged_go_back() {
    const N: usize = 3000;
    let dir = tempfile::tempdir().unwrap();
    let flat = dir.path().join("flat");
    let src = dir.path().join("src");
    fs::create_dir_all(&flat).unwrap();
    fs::create_dir_all(src.join("sub")).unwrap();
    let dest = dir.path().join("dest");
    fs::create_dir_all(dest.join("src/sub")).unwrap();
    let mut sources = Vec::new();
    for i in 0..N {
        fs::write(flat.join(format!("f{i}")), format!("{i}")).unwrap();
        sources.push(flat.join(format!("f{i}")));
        fs::write(src.join(format!("sub/m{i}")), format!("{i}")).unwrap();
    }
    // Every tenth merged item takes the place of one there.
    for i in (0..N).step_by(10) {
        fs::write(dest.join(format!("src/sub/m{i}")), b"there").unwrap();
    }
    sources.push(src.clone());
    let changes = recorded(&request(OpKind::Move, sources, Some(&dest)));
    let moved = changes.iter().filter(|c| matches!(c, Change::Moved { .. })).count();
    let overwritten = changes.iter().filter(|c| matches!(c, Change::Overwritten { .. })).count();
    assert_eq!((moved, overwritten), (2 * N, N / 10));
    assert!(changes.contains(&Change::FolderRemoved { path: src.clone() }));
    assert_eq!(fs::read(dest.join("src/sub/m10")).unwrap(), b"10");

    walk(changes);
    for i in (0..N).step_by(97) {
        assert_eq!(fs::read(flat.join(format!("f{i}"))).unwrap(), format!("{i}").as_bytes());
        assert_eq!(fs::read(src.join(format!("sub/m{i}"))).unwrap(), format!("{i}").as_bytes());
        assert!(!dest.join(format!("f{i}")).exists());
    }
    assert_eq!(fs::read_dir(&flat).unwrap().count(), N);
    assert_eq!(fs::read_dir(src.join("sub")).unwrap().count(), N);
}

#[test]
fn a_move_over_an_item_records_the_loss_and_the_move() {
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("a"), b"mine").unwrap();
    let dest = dir.path().join("d");
    fs::create_dir(&dest).unwrap();
    fs::write(dest.join("a"), b"theirs").unwrap();
    let changes = recorded(&request(OpKind::Move, vec![dir.path().join("a")], Some(&dest)));
    assert_eq!(
        changes,
        vec![
            Change::Overwritten { path: dest.join("a") },
            Change::Moved { from: dir.path().join("a"), to: dest.join("a") },
        ]
    );
    walk(changes);
    assert_eq!(fs::read(dir.path().join("a")).unwrap(), b"mine");
    assert!(!dest.join("a").exists());
}

#[test]
fn duplicates_and_archives_record_what_they_made() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("note.md");
    fs::write(&file, b"n").unwrap();
    let changes = recorded(&request(OpKind::Duplicate, vec![file.clone()], None));
    assert!(made(&changes, &dir.path().join("note copy.md")));
    let changes = recorded(&request(OpKind::Compress, vec![file.clone()], Some(dir.path())));
    assert!(made(&changes, &dir.path().join("note.zip")));

    // Into a folder that was there: each item it wrote.
    let out = dir.path().join("out");
    fs::create_dir(&out).unwrap();
    let mut extract = request(OpKind::Extract, vec![PathBuf::from("note.md")], Some(&out));
    extract.archive = Some(dir.path().join("note.zip"));
    let changes = recorded(&extract);
    assert!(made(&changes, &out.join("note.md")));
    assert!(!made(&changes, &out));

    // Into a folder it made (Extract To, a folder per archive): the folder
    // alone, as a copy records its topmost item.
    let mut whole =
        request(OpKind::Extract, vec![dir.path().join("note.zip")], Some(&dir.path().join("new")));
    whole.options.into_folders = true;
    let changes = recorded(&whole);
    assert!(made(&changes, &dir.path().join("new")));
    assert!(!made(&changes, &dir.path().join("new/note/note.md")));
    assert_eq!(fs::read(dir.path().join("new/note/note.md")).unwrap(), b"n");
}

#[test]
fn trashed_items_come_back_and_go_again() {
    let home = PathBuf::from(std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).unwrap());
    let Ok(dir) = tempfile::Builder::new().prefix(".ferryx-journal-test").tempdir_in(home) else { return };
    let file = dir.path().join("t.txt");
    fs::write(&file, b"t").unwrap();
    let ctx = OpContext::detached(&request(OpKind::Trash, vec![file.clone()], None));
    delete::run(&ctx, &request(OpKind::Trash, vec![file.clone()], None)).unwrap();
    if !ctx.snapshot().errors.is_empty() || !ferryx_vfs::trash::put_back_supported() {
        // No trash on this desktop (a bare container): nothing to walk.
        return;
    }
    let changes = ctx.recorded();
    assert!(matches!(&changes[..], [Change::Trashed { .. }]));
    assert!(undo::check(&step(changes.clone())).issues.is_empty());
    let inverse = walk(changes);
    assert_eq!(fs::read(&file).unwrap(), b"t");
    assert!(matches!(&inverse[..], [Change::Created { .. }]));
    // Redo trashes it again; undo once more leaves the trash as it was.
    let again = walk(inverse);
    assert!(!file.exists());
    walk(again);
    assert!(file.exists());
}
