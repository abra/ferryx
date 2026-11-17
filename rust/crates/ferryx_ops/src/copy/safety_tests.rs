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

#[cfg(unix)]
#[test]
fn retry_merges_an_arriving_directory_without_recording_it_as_created() {
    use std::os::unix::fs::PermissionsExt;

    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let destination = dir.path().join("destination");
    let target = destination.join("source");
    fs::create_dir(&source).unwrap();
    fs::write(source.join("child"), b"incoming").unwrap();
    fs::create_dir(&destination).unwrap();
    fs::set_permissions(&destination, fs::Permissions::from_mode(0o500)).unwrap();
    if fs::create_dir(destination.join("probe")).is_ok() {
        fs::set_permissions(&destination, fs::Permissions::from_mode(0o700)).unwrap();
        return; // This process can create directories without write permissions.
    }

    let mut req = request(&source, &destination);
    req.kind = OpKind::Copy;
    req.options.conflicts = ConflictPolicy::Ask;
    let runner = Runner::new();
    let (send, reports) = mpsc::channel();
    runner.set_listener(Arc::new(move |progress| {
        if progress.question.is_some() || progress.state.is_finished() {
            send.send(progress).unwrap();
        }
    }));
    let id = runner.start(req);
    let report = reports.recv_timeout(Duration::from_secs(5));
    fs::set_permissions(&destination, fs::Permissions::from_mode(0o700)).unwrap();
    let question = report.unwrap().question.unwrap();
    assert_eq!(question.kind, QuestionKind::Error);
    fs::create_dir(&target).unwrap();
    fs::write(target.join("unrelated"), b"existing").unwrap();
    runner.answer(id, question.id, Answer::Retry);
    let question = reports.recv_timeout(Duration::from_secs(5)).unwrap().question;
    if let Some(question) = &question {
        assert_eq!(question.kind, QuestionKind::Conflict);
        runner.answer(id, question.id, Answer::Merge);
    }
    assert_eq!(finished(&runner, id).state, OpState::Done);
    let step = runner.journal().peek(Direction::Undo).unwrap();
    let copied = target.join("child");
    assert!(matches!(step.changes.as_slice(), [Change::Created { path, .. }] if path == &copied));
    assert!(question.is_some());
    assert_eq!(fs::read(&copied).unwrap(), b"incoming");
    assert_eq!(fs::read(target.join("unrelated")).unwrap(), b"existing");
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
            Change::moved(&source.join("sub/moved.txt"), &target.join("sub/moved.txt")),
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
    let mut req = request(&source, dir.path());
    req.options.preserve_attributes = true;
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
fn cross_volume_undo_leaves_replacements_and_unrelated_items_in_created_folders() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    fs::create_dir_all(source.join("sub")).unwrap();
    fs::create_dir(source.join("rest")).unwrap();
    fs::write(source.join("sub/replaced"), b"original").unwrap();
    fs::write(source.join("rest/ok"), b"movable").unwrap();
    let req = request(&source, dir.path());
    let ctx = OpContext::detached(&req);
    assert!(move_job(&ctx, &source, &target, &req.options, false).unwrap());
    let step = step(ctx.recorded());
    fs::rename(target.join("sub/replaced"), dir.path().join("saved")).unwrap();
    fs::write(target.join("sub/replaced"), b"replacement").unwrap();
    fs::write(target.join("rest/unrelated"), b"external").unwrap();
    fs::create_dir(target.join("new-empty-folder")).unwrap();

    let check = crate::undo::check(&step);
    assert!(check.doable > 0);
    for path in [&target, &target.join("sub"), &target.join("rest")] {
        assert!(check.issues.iter().any(|issue| issue.kind.blocks() && &issue.path == path));
    }
    let undo = OpContext::detached(&req);
    crate::undo::run(&undo, &step).unwrap();
    assert_eq!(fs::read(source.join("rest/ok")).unwrap(), b"movable");
    assert_eq!(fs::read(target.join("sub/replaced")).unwrap(), b"replacement");
    assert_eq!(fs::read(target.join("rest/unrelated")).unwrap(), b"external");
    assert!(target.join("new-empty-folder").is_dir());
}

#[test]
fn cross_volume_undo_refuses_a_root_replaced_while_waiting() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    let saved = dir.path().join("saved");
    fs::write(&source, b"original").unwrap();
    fs::write(&target, b"existing").unwrap();
    let identity = crate::identity::FileIdentity::of(&source).unwrap();
    let runner = Runner::new();
    let (tx, rx) = mpsc::channel();
    runner.set_listener(Arc::new(move |progress| {
        if let Some(question) = progress.question {
            tx.send(question).unwrap();
        }
    }));
    let paths = (source.clone(), target.clone());
    let req = request(&source, dir.path());
    let id = runner.start_job(
        req,
        Journaling::Off,
        Box::new(move |ctx| {
            move_across_volumes(ctx, &paths.0, &paths.1, &OpOptions::default(), identity).map(|_| ())
        }),
    );
    let question = rx.recv_timeout(Duration::from_secs(5)).unwrap();
    fs::rename(&source, &saved).unwrap();
    fs::write(&source, b"replacement").unwrap();
    runner.answer(id, question.id, Answer::KeepBoth);
    let progress = finished(&runner, id);
    assert!(!progress.errors.is_empty());
    assert_eq!(fs::read(&source).unwrap(), b"replacement");
    assert_eq!(fs::read(&saved).unwrap(), b"original");
    assert_eq!(fs::read(&target).unwrap(), b"existing");
    assert!(!dir.path().join("target 2").exists());
}

#[test]
fn cross_volume_undo_does_not_copy_a_replacement_after_retry() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    let saved = dir.path().join("saved");
    fs::write(&source, b"original").unwrap();
    let identity = FileIdentity::of(&source).unwrap();
    let runner = Runner::new();
    let (send, questions) = mpsc::channel();
    runner.set_listener(Arc::new(move |progress| {
        if let Some(question) = progress.question {
            send.send(question).unwrap();
        }
    }));
    let paths = (source.clone(), target.clone());
    let mut req = request(&source, dir.path());
    req.kind = OpKind::Undo;
    req.options.verify = true;
    req.options.conflicts = ConflictPolicy::Skip;
    let options = req.options.clone();
    let id = runner.start_job(
        req,
        Journaling::Off,
        Box::new(move |ctx| {
            super::tests::FAULTS.set(1);
            move_across_volumes(ctx, &paths.0, &paths.1, &options, identity).map(|_| ())
        }),
    );
    let question = questions.recv_timeout(Duration::from_secs(5)).unwrap();
    assert_eq!(question.kind, QuestionKind::Error);
    assert!(!target.exists());
    fs::rename(&source, &saved).unwrap();
    fs::write(&source, b"unwanted").unwrap();
    runner.answer(id, question.id, Answer::Retry);
    assert_eq!(finished(&runner, id).state, OpState::Failed);
    assert!(!target.exists());
    assert_eq!(fs::read(&source).unwrap(), b"unwanted");
    assert_eq!(fs::read(&saved).unwrap(), b"original");
}

#[cfg(unix)]
#[test]
fn a_cross_volume_move_records_what_it_copied_before_source_removal_retries() {
    use std::os::unix::fs::PermissionsExt;

    if unsafe { libc::geteuid() } == 0 {
        return; // Root can unlink from a read-only directory.
    }
    let dir = tempfile::tempdir().unwrap();
    let source_dir = dir.path().join("from");
    fs::create_dir(&source_dir).unwrap();
    let source = source_dir.join("source");
    let target = dir.path().join("target");
    let saved = dir.path().join("saved");
    fs::write(&source, b"original").unwrap();
    fs::set_permissions(&source_dir, fs::Permissions::from_mode(0o500)).unwrap();
    let (runner, id, rx) = start_move(request(&source, dir.path()), &source, &target);
    let question = rx.recv_timeout(Duration::from_secs(5));
    fs::set_permissions(&source_dir, fs::Permissions::from_mode(0o700)).unwrap();
    let question = question.unwrap();
    assert_eq!(question.kind, QuestionKind::Error);
    fs::rename(&target, &saved).unwrap();
    fs::write(&target, b"replacement").unwrap();
    runner.answer(id, question.id, Answer::Retry);
    assert_eq!(finished(&runner, id).state, OpState::Done);
    let moved = runner.journal().peek(Direction::Undo).unwrap();
    let check = crate::undo::check(&moved);
    assert_eq!(check.doable, 0);
    assert_eq!(check.issues[0].kind, crate::undo::IssueKind::Replaced);
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
fn failed_verification_preserves_the_replaced_file() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    fs::write(&source, b"incoming").unwrap();
    fs::write(&target, b"existing").unwrap();
    let mut req = request(&source, dir.path());
    req.kind = OpKind::Copy;
    req.new_name = Some("target".into());
    req.options.verify = true;
    req.options.conflicts = ConflictPolicy::Overwrite;
    super::tests::FAULTS.set(1);
    let ctx = OpContext::detached(&req);
    run(&ctx, &req).unwrap();
    assert_eq!(ctx.snapshot().errors.len(), 1);
    assert_eq!(ctx.snapshot().bytes_done, 0);
    assert_eq!(fs::read(&target).unwrap(), b"existing");
    assert!(ctx.recorded().is_empty());
    assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 2);
}

#[test]
fn replacement_preserves_an_existing_file_without_an_identity() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    fs::write(&source, b"incoming").unwrap();
    fs::write(&target, b"existing").unwrap();
    let meta = source.symlink_metadata().unwrap();
    let existing = ExistingTarget { metadata: target.symlink_metadata().unwrap(), identity: None };
    let req = request(&source, dir.path());
    let ctx = OpContext::detached(&req);
    let result =
        copy_regular(&ctx, &source, target.clone(), &meta, &req.options, Some(existing), CopyMode::Copy);
    assert_eq!(result, Ok(None));
    assert_eq!(fs::read(&target).unwrap(), b"existing");
    assert!(ctx.snapshot().errors[0].message.contains("identify"));
    assert!(ctx.recorded().is_empty());
}

#[test]
fn a_shortened_source_cannot_replace_the_destination_even_when_verified() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    fs::write(&source, b"incoming").unwrap();
    fs::write(&target, b"existing").unwrap();
    let meta = source.symlink_metadata().unwrap();
    let existing = ExistingTarget::new(&target, target.symlink_metadata().unwrap());
    fs::write(&source, b"short").unwrap();
    let mut req = request(&source, dir.path());
    req.options.verify = true;
    let ctx = OpContext::detached(&req);
    let result =
        copy_regular(&ctx, &source, target.clone(), &meta, &req.options, Some(existing), CopyMode::Copy);
    assert_eq!(result, Ok(None));
    assert_eq!(fs::read(&target).unwrap(), b"existing");
    assert_eq!(ctx.snapshot().errors.len(), 1);
    assert!(ctx.recorded().is_empty());
    assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 2);
}

#[test]
fn cancelling_as_bytes_are_copied_preserves_the_destination() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    fs::write(&source, b"incoming").unwrap();
    fs::write(&target, b"existing").unwrap();
    let mut req = request(&source, dir.path());
    req.options.preserve_attributes = true;
    let listener_context = Arc::new(std::sync::OnceLock::<std::sync::Weak<OpContext>>::new());
    let observing = listener_context.clone();
    let observing_target = target.clone();
    let ctx = Arc::new(OpContext::listened(
        &req,
        Arc::new(move |p| {
            let ctx = observing.get().unwrap().upgrade().unwrap();
            if p.bytes_done > 0 && !ctx.is_cancelled() {
                assert_eq!(fs::read(&observing_target).unwrap(), b"existing");
                ctx.cancel();
            }
        }),
    ));
    listener_context.set(Arc::downgrade(&ctx)).unwrap();
    let meta = fs::symlink_metadata(&source).unwrap();
    let existing = ExistingTarget::new(&target, target.symlink_metadata().unwrap());
    let result =
        copy_regular(&ctx, &source, target.clone(), &meta, &req.options, Some(existing), CopyMode::Copy);
    assert_eq!(result, Err(Abort::Cancelled));
    assert_eq!(fs::read(&target).unwrap(), b"existing");
    assert_eq!(ctx.snapshot().bytes_done, 0);
    assert!(ctx.recorded().is_empty());
    assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 2);
}

#[test]
fn cancelled_fresh_copy_does_not_unlink_a_replacement_output() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    let moved = dir.path().join("moved");
    fs::write(&source, vec![7; BUFFER * 2]).unwrap();
    let mut req = request(&source, dir.path());
    req.kind = OpKind::Copy;
    req.options.verify = true;
    req.options.preserve_attributes = false;
    let context = Arc::new(std::sync::OnceLock::<std::sync::Weak<OpContext>>::new());
    let observing = context.clone();
    let output = target.clone();
    let ctx = Arc::new(OpContext::listened(
        &req,
        Arc::new(move |report| {
            let ctx = observing.get().unwrap().upgrade().unwrap();
            if report.bytes_done > 0 && !ctx.is_cancelled() {
                fs::rename(&output, &moved).unwrap();
                fs::write(&output, b"keep this independent file").unwrap();
                ctx.cancel();
            }
        }),
    ));
    context.set(Arc::downgrade(&ctx)).unwrap();

    let meta = fs::metadata(&source).unwrap();
    assert_eq!(
        copy_regular(&ctx, &source, target.clone(), &meta, &req.options, None, CopyMode::Copy),
        Err(Abort::Cancelled)
    );
    assert_eq!(fs::read(target).unwrap(), b"keep this independent file");
    assert!(ctx.recorded().is_empty());
}

#[test]
fn a_failed_replacement_keeps_the_destination_until_retry_publishes() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    fs::write(&source, b"incoming").unwrap();
    let mut req = request(&source, dir.path());
    req.kind = OpKind::Copy;
    req.new_name = Some("target".into());
    req.options.verify = true;
    req.options.conflicts = ConflictPolicy::Overwrite;
    for cancel in [true, false] {
        fs::write(&target, b"existing").unwrap();
        let runner = Runner::new();
        let (send, questions) = mpsc::channel();
        runner.set_listener(Arc::new(move |progress| {
            if let Some(question) = progress.question {
                send.send(question).unwrap();
            }
        }));
        let job = req.clone();
        let id = runner.start_job(
            req.clone(),
            Journaling::Record { kind: StepKind::Copy, items: 1, first_name: "source".into() },
            Box::new(move |ctx| {
                super::tests::FAULTS.set(1);
                run(ctx, &job)
            }),
        );
        let question = questions.recv_timeout(Duration::from_secs(5)).unwrap();
        assert_eq!(question.kind, QuestionKind::Error);
        assert_eq!(fs::read(&target).unwrap(), b"existing");
        if cancel {
            runner.cancel(id);
            assert_eq!(finished(&runner, id).state, OpState::Cancelled);
            assert_eq!(fs::read(&target).unwrap(), b"existing");
            assert!(runner.journal().summary().undo.is_none());
        } else {
            runner.answer(id, question.id, Answer::Retry);
            let progress = finished(&runner, id);
            assert_eq!(progress.state, OpState::Done);
            assert_eq!((progress.bytes_done, progress.items_done), (8, 1));
            assert_eq!(fs::read(&target).unwrap(), b"incoming");
            let summary = runner.journal().summary().undo.unwrap();
            let step = runner.journal().take(Direction::Undo, summary.id).unwrap();
            assert_eq!(step.changes, vec![Change::Overwritten { path: target.clone() }]);
        }
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 2);
    }
}

#[cfg(target_os = "macos")]
#[test]
fn a_replacement_preserves_the_sources_locked_flag() {
    use std::os::macos::fs::MetadataExt;
    use std::os::unix::ffi::OsStrExt;

    fn set_flags(path: &Path, flags: u32) {
        let name = std::ffi::CString::new(path.as_os_str().as_bytes()).unwrap();
        assert_eq!(unsafe { libc::chflags(name.as_ptr(), flags) }, 0);
    }

    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let target = dir.path().join("target");
    fs::write(&source, b"incoming").unwrap();
    fs::write(&target, b"existing").unwrap();
    let mut req = request(&source, dir.path());
    req.kind = OpKind::Copy;
    req.new_name = Some("target".into());
    req.options.preserve_attributes = true;
    req.options.conflicts = ConflictPolicy::Overwrite;
    set_flags(&source, libc::UF_IMMUTABLE);
    let ctx = OpContext::detached(&req);
    let result = run(&ctx, &req);
    set_flags(&source, 0);
    let flags = target.symlink_metadata().map(|meta| meta.st_flags());
    if flags.as_ref().is_ok_and(|f| f & libc::UF_IMMUTABLE != 0) {
        set_flags(&target, 0);
    }
    result.unwrap();
    assert!(ctx.snapshot().errors.is_empty(), "{:?}", ctx.snapshot().errors);
    assert_eq!(flags.unwrap() & libc::UF_IMMUTABLE, libc::UF_IMMUTABLE);
    assert_eq!(fs::read(&target).unwrap(), b"incoming");
    assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 2);
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
