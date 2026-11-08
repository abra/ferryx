use super::*;
use crate::journal::{Direction, Step, StepKind};
use crate::runner::{Journaling, Runner};
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant};

fn request(source: &Path, destination: &Path) -> OpRequest {
    OpRequest {
        kind: OpKind::Move,
        sources: vec![source.to_path_buf()],
        destination: Some(destination.to_path_buf()),
        archive: None,
        new_name: None,
        options: OpOptions { conflicts: ConflictPolicy::OverwriteOlder, ..Default::default() },
    }
}

fn step(changes: Vec<Change>) -> Step {
    Step {
        id: 1,
        kind: StepKind::Move,
        items: 1,
        first_name: "source".into(),
        changes,
        at_ms: 0,
        truncated: false,
    }
}

fn start_move(req: OpRequest, source: &Path, target: &Path) -> (Runner, u64, mpsc::Receiver<Question>) {
    let runner = Runner::new();
    let (tx, rx) = mpsc::channel();
    runner.set_listener(Arc::new(move |progress| {
        if let Some(question) = progress.question {
            tx.send(question).unwrap();
        }
    }));
    let (from, to, options) = (source.to_path_buf(), target.to_path_buf(), req.options.clone());
    let id = runner.start_job(
        req,
        Journaling::Record { kind: StepKind::Move, items: 1, first_name: "source".into() },
        Box::new(move |ctx| move_job(ctx, &from, &to, &options, false).map(|_| ())),
    );
    (runner, id, rx)
}

fn finished(runner: &Runner, id: u64) -> Progress {
    let start = Instant::now();
    loop {
        let progress = runner.progress(id).unwrap();
        if progress.state.is_finished() {
            return progress;
        }
        assert!(start.elapsed() < Duration::from_secs(5), "operation did not end");
        std::thread::sleep(Duration::from_millis(5));
    }
}

#[test]
fn cross_volume_merge_keeps_skips_and_undo_restores_only_moved_files() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("destination/source");
    fs::create_dir_all(source.join("sub")).unwrap();
    fs::create_dir_all(target.join("sub")).unwrap();
    fs::write(source.join("keep.txt"), b"source version").unwrap();
    fs::write(target.join("keep.txt"), b"newer destination").unwrap();
    filetime::set_file_mtime(source.join("keep.txt"), filetime::FileTime::from_unix_time(1000, 0)).unwrap();
    filetime::set_file_mtime(target.join("keep.txt"), filetime::FileTime::from_unix_time(2000, 0)).unwrap();
    fs::write(source.join("sub/moved.txt"), b"moved").unwrap();
    let req = request(&source, target.parent().unwrap());
    let ctx = OpContext::detached(&req);
    // Exercise the cross-volume branch without requiring another mount.
    assert!(!move_job(&ctx, &source, &target, &req.options, false).unwrap());
    assert_eq!(fs::read(source.join("keep.txt")).unwrap(), b"source version");
    assert_eq!(fs::read(target.join("keep.txt")).unwrap(), b"newer destination");
    assert!(!source.join("sub").exists());
    assert_eq!(fs::read(target.join("sub/moved.txt")).unwrap(), b"moved");
    assert!(ctx.snapshot().errors.is_empty());
    let changes = ctx.recorded();
    assert_eq!(
        changes,
        vec![
            Change::Moved { from: source.join("sub/moved.txt"), to: target.join("sub/moved.txt") },
            Change::FolderRemoved { path: source.join("sub") },
        ]
    );
    let undo = OpContext::detached(&req);
    crate::undo::run(&undo, &step(changes)).unwrap();
    assert!(undo.recorded_left().is_empty());
    assert_eq!(fs::read(source.join("sub/moved.txt")).unwrap(), b"moved");
    assert_eq!(fs::read(source.join("keep.txt")).unwrap(), b"source version");
    assert_eq!(fs::read(target.join("keep.txt")).unwrap(), b"newer destination");
    assert!(!target.join("sub/moved.txt").exists());
}

#[test]
fn cross_volume_move_to_a_new_tree_can_be_undone_and_redone() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    fs::create_dir_all(source.join("sub")).unwrap();
    fs::create_dir(source.join("empty")).unwrap();
    fs::write(source.join("sub/file"), b"contents").unwrap();
    let req = request(&source, dir.path());
    let ctx = OpContext::detached(&req);
    assert!(move_job(&ctx, &source, &target, &req.options, false).unwrap());
    assert!(!source.exists());
    assert_eq!(fs::read(target.join("sub/file")).unwrap(), b"contents");
    assert!(target.join("empty").is_dir());
    let moved = step(ctx.recorded());
    assert!(crate::undo::check(&moved).issues.is_empty());
    let undo = OpContext::detached(&req);
    crate::undo::run(&undo, &moved).unwrap();
    assert!(undo.recorded_left().is_empty(), "{:?}", undo.snapshot().errors);
    assert_eq!(fs::read(source.join("sub/file")).unwrap(), b"contents");
    assert!(source.join("empty").is_dir());
    assert!(!target.exists());
    let redo = OpContext::detached(&req);
    crate::undo::run(&redo, &step(undo.recorded())).unwrap();
    assert!(redo.recorded_left().is_empty(), "{:?}", redo.snapshot().errors);
    assert!(!source.exists());
    assert_eq!(fs::read(target.join("sub/file")).unwrap(), b"contents");
    assert!(target.join("empty").is_dir());
}

#[test]
fn cancelling_a_partial_cross_volume_move_keeps_sources_and_the_undo_record() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    fs::create_dir_all(&source).unwrap();
    fs::create_dir_all(&target).unwrap();
    for name in ["a", "b"] {
        fs::write(source.join(name), b"incoming").unwrap();
        fs::write(target.join(name), b"existing").unwrap();
    }
    let mut req = request(&source, dir.path());
    req.options.conflicts = ConflictPolicy::Ask;
    let (runner, id, rx) = start_move(req.clone(), &source, &target);
    let question = rx.recv_timeout(Duration::from_secs(5)).unwrap();
    assert!(question.source.as_ref().unwrap().is_dir);
    runner.answer(id, question.id, Answer::Merge);
    let question = rx.recv_timeout(Duration::from_secs(5)).unwrap();
    assert!(!question.source.as_ref().unwrap().is_dir);
    runner.answer(id, question.id, Answer::KeepBoth);
    let question = rx.recv_timeout(Duration::from_secs(5)).unwrap();
    let remaining = PathBuf::from(question.existing.as_ref().unwrap().path.clone());
    // One child has moved; cancel at the next conflict, without relying
    // on directory iteration order or the speed of the file system.
    runner.cancel(id);
    assert_eq!(finished(&runner, id).state, OpState::Cancelled);
    assert_eq!(fs::read(source.join(remaining.file_name().unwrap())).unwrap(), b"incoming");
    let summary = runner.journal().summary().undo.unwrap();
    let moved = runner.journal().take(Direction::Undo, summary.id).unwrap();
    assert!(matches!(moved.changes.as_slice(), [Change::Moved { .. }]));
    assert!(crate::undo::check(&moved).issues.is_empty());
    let undo = OpContext::detached(&req);
    crate::undo::run(&undo, &moved).unwrap();
    assert!(undo.recorded_left().is_empty());
    for name in ["a", "b"] {
        assert_eq!(fs::read(source.join(name)).unwrap(), b"incoming");
        assert_eq!(fs::read(target.join(name)).unwrap(), b"existing");
        assert!(!target.join(format!("{name} 2")).exists());
    }
}

#[test]
fn failed_verification_never_removes_the_source_tree() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    fs::create_dir_all(&source).unwrap();
    fs::write(source.join("file"), b"must survive").unwrap();
    let mut req = request(&source, dir.path());
    req.options.verify = true;
    super::tests::FAULTS.set(1);
    let ctx = OpContext::detached(&req);
    assert!(!move_job(&ctx, &source, &target, &req.options, false).unwrap());
    assert_eq!(fs::read(source.join("file")).unwrap(), b"must survive");
    assert!(!target.join("file").exists());
    assert_eq!(ctx.snapshot().errors.len(), 1);
    assert!(!ctx.recorded().iter().any(|c| matches!(c, Change::Moved { .. } | Change::FolderRemoved { .. })));
}

#[test]
fn a_new_source_child_during_copy_is_not_recursively_deleted() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    fs::create_dir_all(&source).unwrap();
    fs::create_dir_all(&target).unwrap();
    fs::write(source.join("file"), b"copied").unwrap();
    fs::write(target.join("file"), b"old").unwrap();
    let mut req = request(&source, dir.path());
    req.options.conflicts = ConflictPolicy::Ask;
    let (runner, id, rx) = start_move(req, &source, &target);
    let question = rx.recv_timeout(Duration::from_secs(5)).unwrap();
    assert!(question.source.as_ref().unwrap().is_dir);
    runner.answer(id, question.id, Answer::Merge);
    let question = rx.recv_timeout(Duration::from_secs(5)).unwrap();
    assert!(!question.source.as_ref().unwrap().is_dir);
    // The child list is already captured; this file is outside the move.
    fs::write(source.join("late"), b"arrived meanwhile").unwrap();
    runner.answer(id, question.id, Answer::Overwrite);
    let question = rx.recv_timeout(Duration::from_secs(5)).unwrap();
    assert_eq!(question.kind, QuestionKind::Error);
    runner.answer(id, question.id, Answer::Skip);
    assert_eq!(finished(&runner, id).state, OpState::DoneWithErrors);
    assert_eq!(fs::read(source.join("late")).unwrap(), b"arrived meanwhile");
    assert!(!source.join("file").exists());
    assert_eq!(fs::read(target.join("file")).unwrap(), b"copied");
}

#[cfg(unix)]
#[test]
fn a_folder_alias_cannot_hide_a_destination_inside_the_source() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    fs::create_dir_all(&source).unwrap();
    let alias = dir.path().join("alias");
    std::os::unix::fs::symlink(&source, &alias).unwrap();
    let mut req = request(&source, &alias.join("new/inside"));
    req.kind = OpKind::Copy;
    let ctx = OpContext::detached(&req);
    assert_eq!(run(&ctx, &req), Err(Abort::Stopped));
    assert!(!source.join("new").exists());
    assert!(ctx.recorded().is_empty());
}
