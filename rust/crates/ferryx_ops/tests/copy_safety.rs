use std::collections::VecDeque;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use ferryx_ops::{
    copy, Answer, ConflictPolicy, OpContext, OpKind, OpOptions, OpRequest, OpState, Progress, Question,
    Runner,
};

fn request(kind: OpKind, sources: Vec<PathBuf>, destination: &Path) -> OpRequest {
    OpRequest {
        kind,
        sources,
        destination: Some(destination.to_path_buf()),
        archive: None,
        new_name: None,
        options: OpOptions::default(),
    }
}

fn run(req: OpRequest, answers: Vec<Answer>) -> (Progress, Vec<Question>) {
    let runner = Arc::new(Runner::new());
    let weak = Arc::downgrade(&runner);
    let answers = Arc::new(Mutex::new(VecDeque::from(answers)));
    let questions = Arc::new(Mutex::new(Vec::new()));
    let asked = questions.clone();
    runner.set_listener(Arc::new(move |p| {
        if let Some(question) = p.question {
            asked.lock().unwrap().push(question.clone());
            let answer = answers.lock().unwrap().pop_front().unwrap_or(Answer::Abort);
            let weak = weak.clone();
            std::thread::spawn(move || {
                if let Some(runner) = weak.upgrade() {
                    runner.answer(p.id, question.id, answer);
                }
            });
        }
    }));
    let id = runner.start(req);
    let start = Instant::now();
    loop {
        let progress = runner.progress(id).unwrap();
        if progress.state.is_finished() {
            return (progress, questions.lock().unwrap().clone());
        }
        assert!(start.elapsed() < Duration::from_secs(10), "operation did not end");
        std::thread::sleep(Duration::from_millis(5));
    }
}

#[test]
fn copying_or_moving_onto_itself_keeps_the_original() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("original");
    fs::write(&source, b"irreplaceable").unwrap();
    for kind in [OpKind::Copy, OpKind::Move] {
        let mut req = request(kind, vec![source.clone()], dir.path());
        req.options.conflicts = ConflictPolicy::Overwrite;
        let ctx = OpContext::detached(&req);
        assert_eq!(copy::run(&ctx, &req), Err(ferryx_ops::Abort::Stopped));
        assert_eq!(fs::read(&source).unwrap(), b"irreplaceable");
        assert!(ctx.recorded().is_empty());
    }
}

#[test]
fn a_hard_link_is_recognized_before_replacement() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("original");
    let alias = dir.path().join("alias");
    fs::write(&source, b"irreplaceable").unwrap();
    fs::hard_link(&source, &alias).unwrap();
    let mut req = request(OpKind::Copy, vec![source.clone()], dir.path());
    req.new_name = Some("alias".into());
    req.options.conflicts = ConflictPolicy::Overwrite;
    let ctx = OpContext::detached(&req);
    assert!(copy::run(&ctx, &req).is_err());
    assert_eq!(fs::read(&source).unwrap(), b"irreplaceable");
    assert_eq!(fs::read(&alias).unwrap(), b"irreplaceable");
    assert!(ctx.recorded().is_empty());
}

#[cfg(unix)]
#[test]
fn an_unreadable_file_is_recognized_through_a_parent_alias() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::tempdir().unwrap();
    let folder = dir.path().join("real");
    let alias = dir.path().join("alias");
    fs::create_dir(&folder).unwrap();
    std::os::unix::fs::symlink(&folder, &alias).unwrap();
    let source = folder.join("original");
    fs::write(&source, b"irreplaceable").unwrap();
    fs::set_permissions(&source, fs::Permissions::from_mode(0o000)).unwrap();
    let mut req = request(OpKind::Copy, vec![source.clone()], &alias);
    req.options.conflicts = ConflictPolicy::Overwrite;
    let ctx = OpContext::detached(&req);
    assert!(copy::run(&ctx, &req).is_err());
    fs::set_permissions(&source, fs::Permissions::from_mode(0o600)).unwrap();
    assert_eq!(fs::read(&source).unwrap(), b"irreplaceable");
    assert!(ctx.recorded().is_empty());
}

#[cfg(unix)]
#[test]
fn a_dangling_link_is_recognized_through_a_parent_alias() {
    let dir = tempfile::tempdir().unwrap();
    let folder = dir.path().join("real");
    let alias = dir.path().join("alias");
    fs::create_dir(&folder).unwrap();
    std::os::unix::fs::symlink(&folder, &alias).unwrap();
    let source = folder.join("link");
    std::os::unix::fs::symlink("missing", &source).unwrap();
    let mut req = request(OpKind::Copy, vec![source.clone()], &alias);
    req.options.conflicts = ConflictPolicy::Overwrite;
    let ctx = OpContext::detached(&req);
    assert!(copy::run(&ctx, &req).is_err());
    assert_eq!(fs::read_link(&source).unwrap(), PathBuf::from("missing"));
    assert!(ctx.recorded().is_empty());
}

#[cfg(unix)]
#[test]
fn an_unreadable_source_leaves_the_replaced_file_in_place() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let dest = dir.path().join("destination");
    fs::create_dir(&dest).unwrap();
    let target = dest.join("source");
    fs::write(&source, b"incoming").unwrap();
    fs::write(&target, b"existing").unwrap();
    fs::set_permissions(&source, fs::Permissions::from_mode(0o000)).unwrap();
    if fs::File::open(&source).is_ok() {
        return; // This process can read files without permissions.
    }
    let mut req = request(OpKind::Copy, vec![source], &dest);
    req.options.conflicts = ConflictPolicy::Overwrite;
    let ctx = OpContext::detached(&req);
    copy::run(&ctx, &req).unwrap();
    assert_eq!(ctx.snapshot().errors.len(), 1);
    assert_eq!(fs::read(&target).unwrap(), b"existing");
    assert!(ctx.recorded().is_empty());
    assert_eq!(fs::read_dir(&dest).unwrap().count(), 1);
}

#[cfg(target_os = "linux")]
#[test]
fn local_copy_and_keep_both_preserve_native_names() {
    use std::ffi::OsStr;
    use std::os::unix::ffi::OsStrExt;
    let dir = tempfile::tempdir().unwrap();
    let name = OsStr::from_bytes(b"file\xff.txt");
    let source = dir.path().join(name);
    fs::write(&source, b"data").unwrap();
    let dest = dir.path().join("destination");
    let mut req = request(OpKind::Copy, vec![source.clone()], &dest);
    req.options.conflicts = ConflictPolicy::KeepBoth;
    copy::run(&OpContext::detached(&req), &req).unwrap();
    copy::run(&OpContext::detached(&req), &req).unwrap();
    assert_eq!(fs::read(dest.join(name)).unwrap(), b"data");
    assert_eq!(fs::read(dest.join(OsStr::from_bytes(b"file\xff 2.txt"))).unwrap(), b"data");
    let req = request(OpKind::Duplicate, vec![source], &dest);
    copy::run(&OpContext::detached(&req), &req).unwrap();
    assert_eq!(fs::read(dir.path().join(OsStr::from_bytes(b"file\xff copy.txt"))).unwrap(), b"data");
}

#[test]
fn replacement_preserves_a_destination_changed_while_asking() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let dest = dir.path().join("destination");
    fs::create_dir(&dest).unwrap();
    let target = dest.join("source");
    fs::write(&source, b"incoming").unwrap();
    fs::write(&target, b"existing").unwrap();
    let runner = Runner::new();
    let (send, receive) = std::sync::mpsc::channel();
    runner.set_listener(Arc::new(move |progress| {
        if let Some(question) = progress.question {
            send.send(question).unwrap();
        }
    }));
    let id = runner.start(request(OpKind::Copy, vec![source], &dest));
    let question = receive.recv_timeout(Duration::from_secs(5)).unwrap();
    fs::write(&target, b"changed while asking").unwrap();
    runner.answer(id, question.id, Answer::Overwrite);
    let question = receive.recv_timeout(Duration::from_secs(5)).unwrap();
    assert_eq!(question.kind, ferryx_ops::QuestionKind::Error);
    runner.answer(id, question.id, Answer::Skip);
    let start = Instant::now();
    while !runner.progress(id).unwrap().state.is_finished() {
        assert!(start.elapsed() < Duration::from_secs(5), "operation did not end");
        std::thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(fs::read(&target).unwrap(), b"changed while asking");
    assert!(runner.journal().summary().undo.is_none());
    assert_eq!(fs::read_dir(&dest).unwrap().count(), 1);
}

#[test]
fn copying_a_file_onto_a_directory_preserves_the_directory() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let dest = dir.path().join("destination");
    let target = dest.join("source");
    fs::write(&source, b"incoming").unwrap();
    fs::create_dir_all(&target).unwrap();
    fs::write(target.join("child"), b"existing").unwrap();
    let mut req = request(OpKind::Copy, vec![source], &dest);
    req.options.conflicts = ConflictPolicy::Overwrite;
    let ctx = OpContext::detached(&req);
    copy::run(&ctx, &req).unwrap();
    assert_eq!(ctx.snapshot().errors.len(), 1);
    assert_eq!(fs::read(target.join("child")).unwrap(), b"existing");
    assert!(ctx.recorded().is_empty());

    req.options.conflicts = ConflictPolicy::KeepBoth;
    copy::run(&OpContext::detached(&req), &req).unwrap();
    assert_eq!(fs::read(dest.join("source 2")).unwrap(), b"incoming");
    assert_eq!(fs::read(target.join("child")).unwrap(), b"existing");
}

#[test]
fn copying_a_directory_onto_a_file_preserves_the_file() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let dest = dir.path().join("destination");
    let target = dest.join("source");
    fs::create_dir(&source).unwrap();
    fs::write(source.join("child"), b"incoming").unwrap();
    fs::create_dir(&dest).unwrap();
    fs::write(&target, b"existing").unwrap();
    let mut req = request(OpKind::Copy, vec![source], &dest);
    req.options.conflicts = ConflictPolicy::Overwrite;
    let ctx = OpContext::detached(&req);
    copy::run(&ctx, &req).unwrap();
    assert_eq!(fs::read(&target).unwrap(), b"existing");
    assert_eq!(ctx.snapshot().errors.len(), 1);
    assert!(ctx.recorded().is_empty());

    req.options.conflicts = ConflictPolicy::KeepBoth;
    copy::run(&OpContext::detached(&req), &req).unwrap();
    assert_eq!(fs::read(dest.join("source 2/child")).unwrap(), b"incoming");
    assert_eq!(fs::read(&target).unwrap(), b"existing");
}

#[cfg(unix)]
#[test]
fn a_failed_symlink_copy_keeps_the_destination_until_retry() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let dest = dir.path().join("destination");
    let target = dest.join("source");
    let link_value = Path::new("relative/target");
    std::os::unix::fs::symlink(link_value, &source).unwrap();
    fs::create_dir(&dest).unwrap();
    fs::write(&target, b"existing").unwrap();
    let runner = Runner::new();
    let (send, receive) = std::sync::mpsc::channel();
    runner.set_listener(Arc::new(move |progress| {
        if let Some(question) = progress.question {
            send.send(question).unwrap();
        }
    }));
    let id = runner.start(request(OpKind::Copy, vec![source.clone()], &dest));
    let question = receive.recv_timeout(Duration::from_secs(5)).unwrap();
    fs::remove_file(&source).unwrap();
    runner.answer(id, question.id, Answer::Overwrite);
    let question = receive.recv_timeout(Duration::from_secs(5)).unwrap();
    assert_eq!(question.kind, ferryx_ops::QuestionKind::Error);
    assert_eq!(fs::read(&target).unwrap(), b"existing");
    std::os::unix::fs::symlink(link_value, &source).unwrap();
    runner.answer(id, question.id, Answer::Retry);
    let start = Instant::now();
    loop {
        let progress = runner.progress(id).unwrap();
        if progress.state.is_finished() {
            assert_eq!(progress.state, OpState::Done);
            break;
        }
        assert!(start.elapsed() < Duration::from_secs(5), "operation did not end");
        std::thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(fs::read_link(&target).unwrap(), link_value);
    assert_eq!(fs::read_dir(&dest).unwrap().count(), 1);
}

#[test]
fn merge_all_and_file_answers_remain_independent() {
    for kind in [OpKind::Copy, OpKind::Move] {
        let dir = tempfile::tempdir().unwrap();
        let dest = dir.path().join("destination");
        let sources: Vec<_> = ["one", "two"].iter().map(|name| dir.path().join(name)).collect();
        for source in &sources {
            fs::create_dir_all(source).unwrap();
            let target = dest.join(source.file_name().unwrap());
            fs::create_dir_all(&target).unwrap();
            fs::write(source.join("report.txt"), b"incoming").unwrap();
            fs::write(target.join("report.txt"), b"existing").unwrap();
        }
        let (progress, asked) =
            run(request(kind, sources.clone(), &dest), vec![Answer::MergeAll, Answer::SkipAll]);
        assert_eq!(progress.state, OpState::Done);
        assert_eq!(asked.len(), 2, "one directory question and one file question");
        assert!(asked[0].source.as_ref().unwrap().is_dir);
        assert!(!asked[1].source.as_ref().unwrap().is_dir);
        for source in sources {
            assert_eq!(fs::read(source.join("report.txt")).unwrap(), b"incoming");
            assert_eq!(
                fs::read(dest.join(source.file_name().unwrap()).join("report.txt")).unwrap(),
                b"existing"
            );
        }
    }
}
