//! The Operations stream end to end: undo and redo over the journal,
//! comparing and synchronizing folders, checksums, duplicates.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};

use ferryx_api::api::checksum::*;
use ferryx_api::api::duplicates::*;
use ferryx_api::api::events::{record_events, reset_for_tests, take_recorded_events};
use ferryx_api::api::journal::*;
use ferryx_api::api::sync::*;
use ferryx_api::api::types::*;
use ferryx_api::api::{files, ops, rename};

/// The bridge's state is process-wide: the tests take turns.
static SERIAL: Mutex<()> = Mutex::new(());

fn serial() -> MutexGuard<'static, ()> {
    let guard = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    reset_for_tests();
    guard
}

fn s(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn wait_for(mut done: impl FnMut() -> bool) {
    let start = Instant::now();
    while !done() {
        assert!(start.elapsed() < Duration::from_secs(20), "timed out");
        std::thread::sleep(Duration::from_millis(10));
    }
}

/// Waits for the operation `id` to end; answers its last report.
fn finish(id: i64) -> ProgressView {
    let mut last = None;
    wait_for(|| {
        last = ops::operation_progress(id);
        last.as_ref().is_some_and(|p| {
            matches!(
                p.state,
                OpStateView::Done
                    | OpStateView::DoneWithErrors
                    | OpStateView::Cancelled
                    | OpStateView::Failed
            )
        })
    });
    last.unwrap()
}

fn request(kind: OpKindView, sources: Vec<String>, destination: Option<String>) -> OpRequestView {
    OpRequestView {
        kind,
        sources,
        archive: None,
        destination,
        new_name: None,
        conflicts: ConflictPolicyView::Overwrite,
        preserve_attributes: true,
        verify: false,
        password: None,
        into_folders: false,
    }
}

/// A folder under the home folder: items trashed from it go to the user's
/// own trash, where they can be put back.
fn home_temp() -> tempfile::TempDir {
    let home = PathBuf::from(std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).unwrap());
    tempfile::Builder::new().prefix(".ferryx-ops-flow").tempdir_in(home).unwrap()
}

fn undo_step() -> i64 {
    journal_summary().undo.expect("a step to undo").id
}

fn redo_step() -> i64 {
    journal_summary().redo.expect("a step to redo").id
}

/// Whether this desktop can put trashed items back (and has a trash).
fn trash_works(dir: &Path) -> bool {
    let probe = dir.join("probe");
    fs::write(&probe, b"p").unwrap();
    let id = ops::start_operation(request(OpKindView::Trash, vec![s(&probe)], None));
    let ok = finish(id).state == OpStateView::Done;
    if !ok {
        return false;
    }
    let check = check_journal_step(false).unwrap();
    let works = check.doable == 1;
    if works {
        finish(walk_journal_step(false, check.step.id).unwrap());
    }
    // Leave the journal as it was.
    reset_for_tests();
    works
}

#[test]
fn move_undo_redo() {
    let _guard = serial();
    let dir = tempfile::tempdir().unwrap();
    let src = dir.path().join("src");
    let dest = dir.path().join("dest");
    fs::create_dir_all(&src).unwrap();
    fs::create_dir_all(&dest).unwrap();
    fs::write(src.join("a.txt"), b"a").unwrap();
    fs::create_dir(src.join("folder")).unwrap();
    fs::write(src.join("folder/b.txt"), b"b").unwrap();

    record_events();
    let id = ops::start_operation(request(
        OpKindView::Move,
        vec![s(&src.join("a.txt")), s(&src.join("folder"))],
        Some(s(&dest)),
    ));
    assert_eq!(finish(id).state, OpStateView::Done);
    let summary = journal_summary().undo.unwrap();
    assert_eq!(summary.kind, StepKindView::Move);
    assert_eq!(summary.items, 2);
    assert_eq!(summary.first_name, "a.txt");
    // The journal told the interface.
    assert!(take_recorded_events()
        .iter()
        .any(|e| e.kind == AppEventKind::JournalChanged
            && e.journal.as_ref().is_some_and(|j| j.undo.is_some())));

    let check = check_journal_step(false).unwrap();
    assert_eq!((check.doable, check.total), (2, 2));
    assert!(check.issues.is_empty());
    let op = walk_journal_step(false, check.step.id).unwrap();
    assert_eq!(finish(op).state, OpStateView::Done);
    assert!(src.join("a.txt").exists() && src.join("folder/b.txt").exists());
    assert!(!dest.join("a.txt").exists());
    let summary = journal_summary();
    assert!(summary.undo.is_none());
    assert_eq!(summary.redo.as_ref().unwrap().kind, StepKindView::Move);

    // A step taken already cannot be walked again.
    assert!(walk_journal_step(false, check.step.id).is_err());

    let op = walk_journal_step(true, redo_step()).unwrap();
    assert_eq!(finish(op).state, OpStateView::Done);
    assert!(dest.join("a.txt").exists() && dest.join("folder/b.txt").exists());
    assert!(!src.join("a.txt").exists());
    assert!(journal_summary().redo.is_none());
}

#[test]
fn a_taken_place_is_reported_before_undo() {
    let _guard = serial();
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("old.txt"), b"x").unwrap();
    files::rename_item(s(&dir.path().join("old.txt")), "new.txt".into()).unwrap();
    fs::write(dir.path().join("old.txt"), b"someone else").unwrap();
    let check = check_journal_step(false).unwrap();
    assert_eq!(check.step.kind, StepKindView::Rename);
    assert_eq!(check.doable, 0);
    assert_eq!(check.issues.len(), 1);
    assert_eq!(check.issues[0].kind, UndoIssueKindView::Occupied);
    assert!(check.issues[0].blocks);
    assert!(check.issues[0].path.ends_with("old.txt"));
    // Nothing can be done: the step is dropped on request.
    assert!(forget_journal_step(false, check.step.id));
    assert!(journal_summary().undo.is_none());
}

#[test]
fn renames_undo_including_swaps() {
    let _guard = serial();
    let dir = tempfile::tempdir().unwrap();
    let a = dir.path().join("a");
    let b = dir.path().join("b");
    fs::write(&a, b"A").unwrap();
    fs::write(&b, b"B").unwrap();
    let failures = rename::batch_rename_apply(vec![
        RenamePairView { path: s(&a), new_name: "b".into() },
        RenamePairView { path: s(&b), new_name: "a".into() },
    ]);
    assert!(failures.is_empty());
    assert_eq!(fs::read(&a).unwrap(), b"B");
    let summary = journal_summary().undo.unwrap();
    assert_eq!((summary.kind, summary.items), (StepKindView::Rename, 2));
    finish(walk_journal_step(false, summary.id).unwrap());
    assert_eq!(fs::read(&a).unwrap(), b"A");
    assert_eq!(fs::read(&b).unwrap(), b"B");
    assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 2);

    // A single rename, and a new step empties redo.
    let renamed = files::rename_item(s(&a), "c".into()).unwrap();
    assert!(renamed.ends_with("/c") || renamed.ends_with("\\c"));
    assert!(journal_summary().redo.is_none());
    finish(walk_journal_step(false, undo_step()).unwrap());
    assert!(a.exists());
}

#[test]
fn copy_trash_and_new_folders_undo_through_the_trash() {
    let _guard = serial();
    let dir = home_temp();
    if !trash_works(dir.path()) {
        return;
    }
    let src = dir.path().join("src");
    let dest = dir.path().join("dest");
    fs::create_dir_all(src.join("tree")).unwrap();
    fs::create_dir_all(&dest).unwrap();
    fs::write(src.join("tree/x.txt"), b"x").unwrap();
    fs::write(src.join("y.txt"), b"y").unwrap();
    fs::write(dest.join("y.txt"), b"old y").unwrap();

    // Copy over an existing file: partly reversible.
    let id = ops::start_operation(request(
        OpKindView::Copy,
        vec![s(&src.join("tree")), s(&src.join("y.txt"))],
        Some(s(&dest)),
    ));
    assert_eq!(finish(id).state, OpStateView::Done);
    let check = check_journal_step(false).unwrap();
    assert!(check.step.partial);
    assert_eq!(check.doable, 1);
    assert!(check.issues.iter().any(|i| i.kind == UndoIssueKindView::Lost && !i.blocks));
    finish(walk_journal_step(false, check.step.id).unwrap());
    // The copied tree went to the trash; the overwritten file stays as copied.
    assert!(!dest.join("tree").exists());
    assert_eq!(fs::read(dest.join("y.txt")).unwrap(), b"y");
    // Redo puts the tree back from the trash, and it stays here: the
    // user's trash keeps nothing of the test.
    finish(walk_journal_step(true, redo_step()).unwrap());
    assert_eq!(fs::read(dest.join("tree/x.txt")).unwrap(), b"x");

    // Trash, then undo: back where it was.
    let id = ops::start_operation(request(OpKindView::Trash, vec![s(&src.join("y.txt"))], None));
    assert_eq!(finish(id).state, OpStateView::Done);
    assert!(!src.join("y.txt").exists());
    assert_eq!(journal_summary().undo.unwrap().kind, StepKindView::Trash);
    finish(walk_journal_step(false, undo_step()).unwrap());
    assert_eq!(fs::read(src.join("y.txt")).unwrap(), b"y");

    // New nested folders: undo trashes the topmost one made.
    files::create_directory(s(&dir.path().join("n1/n2/n3"))).unwrap();
    let summary = journal_summary().undo.unwrap();
    assert_eq!((summary.kind, summary.first_name.as_str()), (StepKindView::CreateFolder, "n1"));
    finish(walk_journal_step(false, summary.id).unwrap());
    assert!(!dir.path().join("n1").exists());
    // Leave the user's trash as it was: redo and remove for good.
    finish(walk_journal_step(true, redo_step()).unwrap());
    assert!(dir.path().join("n1/n2/n3").is_dir());
}

#[test]
fn compares_and_synchronizes_folders() {
    let _guard = serial();
    let dir = tempfile::tempdir().unwrap();
    let left = dir.path().join("L");
    let right = dir.path().join("R");
    fs::create_dir_all(left.join("sub")).unwrap();
    fs::create_dir_all(&right).unwrap();
    fs::write(left.join("only.txt"), b"1").unwrap();
    fs::write(left.join("sub/deep.txt"), b"2").unwrap();
    fs::write(right.join("theirs.txt"), b"3").unwrap();

    record_events();
    let task = start_folder_compare(FolderCompareRequestView {
        left: s(&left),
        right: s(&right),
        recursive: true,
        compare_content: false,
        time_tolerance_ms: 1000,
        name_mask: String::new(),
        include_hidden: false,
        case_sensitive: false,
    });
    let mut rows = Vec::new();
    let mut done = false;
    wait_for(|| {
        for event in take_recorded_events() {
            if let Some(update) = event.compare.filter(|u| u.task_id == task) {
                rows.extend(update.rows);
                done |= update.done;
            }
        }
        done
    });
    let names: Vec<(&str, CompareStateView)> = rows.iter().map(|r| (r.left_rel.as_str(), r.state)).collect();
    assert_eq!(
        names,
        [
            ("only.txt", CompareStateView::LeftOnly),
            ("theirs.txt", CompareStateView::RightOnly),
            ("sub/deep.txt", CompareStateView::LeftOnly)
        ]
    );

    let plan = SyncPlanView {
        left: s(&left),
        right: s(&right),
        recursive: true,
        preserve_attributes: true,
        verify: true,
        items: rows
            .iter()
            .map(|r| SyncItemView {
                left_rel: r.left_rel.clone(),
                right_rel: r.right_rel.clone(),
                is_dir: r.is_dir,
                action: if r.left.is_some() {
                    SyncActionView::CopyToRight
                } else {
                    SyncActionView::CopyToLeft
                },
                left: r.left,
                right: r.right,
            })
            .collect(),
    };
    let op = start_synchronize(plan);
    let report = finish(op);
    assert_eq!(report.kind, OpKindView::Synchronize);
    assert_eq!(report.state, OpStateView::Done);
    assert_eq!(fs::read(right.join("sub/deep.txt")).unwrap(), b"2");
    assert_eq!(fs::read(left.join("theirs.txt")).unwrap(), b"3");
    assert_eq!(journal_summary().undo.unwrap().kind, StepKindView::Synchronize);

    // The panels' content comparison: the indexes of the pairs that differ.
    fs::write(left.join("a"), b"same").unwrap();
    fs::write(right.join("a"), b"same").unwrap();
    fs::write(left.join("b"), b"left").unwrap();
    fs::write(right.join("b"), b"rite").unwrap();
    let op = start_content_compare(vec![
        ContentPairView { left: s(&left.join("a")), right: s(&right.join("a")) },
        ContentPairView { left: s(&left.join("b")), right: s(&right.join("b")) },
    ]);
    assert_eq!(finish(op).kind, OpKindView::CompareContents);
    assert_eq!(take_content_differences(op), vec![1]);
    assert!(take_content_differences(op).is_empty());
    // A comparison is not a step.
    assert_eq!(journal_summary().undo.unwrap().kind, StepKindView::Synchronize);
}

#[test]
fn checksums_verify_and_save() {
    let _guard = serial();
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("a.txt"), b"abc").unwrap();
    fs::create_dir(dir.path().join("sub")).unwrap();
    fs::write(dir.path().join("sub/b.txt"), b"abc").unwrap();

    record_events();
    let task = start_checksums(ChecksumRequestView {
        paths: vec![s(&dir.path().join("a.txt")), s(&dir.path().join("sub"))],
        base: s(dir.path()),
        algorithm: ChecksumAlgorithmView::Sha256,
        recursive: true,
        include_hidden: false,
    });
    let (files_seen, outcomes) = collect_checksums(task);
    assert_eq!(files_seen.iter().map(|f| f.name.as_str()).collect::<Vec<_>>(), ["a.txt", "sub/b.txt"]);
    let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    assert!(outcomes.iter().all(|o| o.hash.as_deref() == Some(abc) && o.status == ChecksumStatusView::Ok));

    let sums = dir.path().join("dir.sha256");
    save_checksum_file(
        s(&sums),
        files_seen.iter().map(|f| ChecksumLineView { hash: abc.to_string(), name: f.name.clone() }).collect(),
        false,
    )
    .unwrap();
    assert_eq!(fs::read_to_string(&sums).unwrap(), format!("{abc}  a.txt\n{abc}  sub/b.txt\n"));
    // Not over an existing file unless asked; a new one is a step.
    assert!(save_checksum_file(s(&sums), Vec::new(), false).is_err());
    assert_eq!(journal_summary().undo.unwrap().kind, StepKindView::CreateFile);

    fs::write(dir.path().join("sub/b.txt"), b"tampered").unwrap();
    let task = start_checksum_verify(s(&sums));
    let (_, outcomes) = collect_checksums(task);
    let mut statuses: Vec<(i64, ChecksumStatusView)> = outcomes.iter().map(|o| (o.index, o.status)).collect();
    statuses.sort_by_key(|(index, _)| *index);
    assert_eq!(statuses, [(0, ChecksumStatusView::Ok), (1, ChecksumStatusView::Mismatch)]);
}

fn collect_checksums(task: i64) -> (Vec<ChecksumFileView>, Vec<ChecksumOutcomeView>) {
    let mut files = Vec::new();
    let mut outcomes = Vec::new();
    let mut done = false;
    wait_for(|| {
        for event in take_recorded_events() {
            if let Some(update) = event.checksum.filter(|u| u.task_id == task) {
                assert!(update.error.is_none(), "{:?}", update.error);
                files.extend(update.files);
                outcomes.extend(update.outcomes);
                done |= update.done;
            }
        }
        done
    });
    (files, outcomes)
}

#[test]
fn finds_duplicates() {
    let _guard = serial();
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("a"), b"twin").unwrap();
    fs::write(dir.path().join("b"), b"twin").unwrap();
    fs::write(dir.path().join("c"), b"solo").unwrap();
    record_events();
    let task = start_duplicates(DuplicatesRequestView {
        roots: vec![s(dir.path())],
        min_size: 1,
        name_mask: String::new(),
        include_hidden: false,
    });
    let mut groups = Vec::new();
    let mut done = false;
    let mut phases = Vec::new();
    wait_for(|| {
        for event in take_recorded_events() {
            if let Some(update) = event.duplicates.filter(|u| u.task_id == task) {
                groups.extend(update.groups);
                phases.extend(update.phase);
                done |= update.done;
            }
        }
        done
    });
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0].size, 4);
    assert_eq!(groups[0].files.len(), 2);
    assert!(phases.contains(&DuplicatesPhaseView::Scanning));
}
