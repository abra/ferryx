//! Transfers with a server on one side or both, through the runner (its
//! questions answered here): uploads and downloads of trees with names in
//! many scripts and their times, server to server, moves (a rename on one
//! server), deletes, conflicts, a connection dropped mid-copy and tried
//! again, a cancel, folder sizes.

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use ferryx_ops::transfer::{self, Side, Transfer};
use ferryx_ops::types::*;
use ferryx_ops::Runner;
use ferryx_test_servers::dav::{DavOptions, DavServer};
use ferryx_test_servers::ftp::{FtpOptions, FtpServer};
use ferryx_test_servers::sftp::{SftpOptions, SftpServer};
use ferryx_vfs::remote::connection::{self, AuthMethod, ConnectSpec};
use ferryx_vfs::remote::prompt::{self, Answer as Reply, Question};
use ferryx_vfs::remote::{known_hosts, never, secrets, Protocol, Server, ServerAddress};
use parking_lot::Mutex;

static SETUP: std::sync::Once = std::sync::Once::new();

/// Secrets in memory, a known_hosts of the test's own, and every
/// question answered: host keys trusted, the test servers' password.
fn setup() {
    SETUP.call_once(|| {
        secrets::use_store(Arc::new(secrets::MemoryStore::default()));
        let dir = Box::leak(Box::new(tempfile::tempdir().unwrap()));
        known_hosts::use_files(Vec::new(), dir.path().join("known_hosts"));
        prompt::set_listener(
            Some(Arc::new(|id, question: &Question| {
                let answer = match question {
                    Question::HostKey { .. } => Reply { accept: true, texts: vec![], remember: false },
                    _ => Reply { accept: true, texts: vec!["secret".into()], remember: false },
                };
                prompt::answer(id, answer);
            })),
            None,
        );
    });
}

fn connect(protocol: Protocol, port: u16) -> Arc<Server> {
    setup();
    let mut address = ServerAddress::new(protocol, "127.0.0.1", "me");
    address.port = port;
    connection::connect(ConnectSpec { address, auth: AuthMethod::Password }, &never).unwrap()
}

/// Runs `transfer` to its end, answering its questions with `answers` in
/// order (Abort once they run out); answers the last report and the
/// questions asked.
fn run(transfer: Transfer, answers: Vec<Answer>) -> (Progress, Vec<ferryx_ops::Question>) {
    let runner = Runner::new();
    let answers = Arc::new(Mutex::new(VecDeque::from(answers)));
    let asked = Arc::new(Mutex::new(Vec::new()));
    let runner = Arc::new(runner);
    {
        let runner_for_listener = Arc::downgrade(&runner);
        let answers = answers.clone();
        let asked = asked.clone();
        runner.set_listener(Arc::new(move |progress: Progress| {
            if let (OpState::Waiting, Some(question)) = (progress.state, progress.question.clone()) {
                asked.lock().push(question.clone());
                let answer = answers.lock().pop_front().unwrap_or(Answer::Abort);
                let runner = runner_for_listener.clone();
                std::thread::spawn(move || {
                    if let Some(runner) = runner.upgrade() {
                        runner.answer(progress.id, question.id, answer);
                    }
                });
            }
        }));
    }
    let shown = transfer.shown_as();
    let id = runner.start_job(
        shown,
        ferryx_ops::runner::Journaling::Off,
        Box::new(move |ctx| transfer::run(ctx, &transfer)),
    );
    for _ in 0..3000 {
        let progress = runner.progress(id).unwrap();
        if progress.state.is_finished() {
            return (progress, asked.lock().clone());
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    panic!("the transfer did not end");
}

fn options(conflicts: ConflictPolicy) -> OpOptions {
    OpOptions { conflicts, preserve_attributes: true, ..Default::default() }
}

/// `a/`, `a/Ünïcödé файл.txt` (4 KiB), `a/b/deep.bin` (300 KiB), `a/b/c/`
/// (empty), with a fixed modification time.
fn tree(root: &Path) -> PathBuf {
    let a = root.join("a");
    std::fs::create_dir_all(a.join("b/c")).unwrap();
    std::fs::write(a.join("Ünïcödé файл.txt"), vec![b'x'; 4096]).unwrap();
    std::fs::write(a.join("b/deep.bin"), pattern(300 * 1024)).unwrap();
    let time = filetime::FileTime::from_unix_time(1_600_000_000, 0);
    filetime::set_file_mtime(a.join("Ünïcödé файл.txt"), time).unwrap();
    a
}

fn pattern(len: usize) -> Vec<u8> {
    (0..len).map(|i| ((i * 31 + i / 7919) % 251) as u8).collect()
}

fn same_tree(a: &Path, b: &Path) {
    assert_eq!(
        std::fs::read(a.join("Ünïcödé файл.txt")).unwrap(),
        std::fs::read(b.join("Ünïcödé файл.txt")).unwrap()
    );
    assert!(std::fs::read(a.join("b/deep.bin")).unwrap() == std::fs::read(b.join("b/deep.bin")).unwrap());
    assert!(b.join("b/c").is_dir());
}

fn mtime(path: &Path) -> i64 {
    filetime::FileTime::from_last_modification_time(&std::fs::metadata(path).unwrap()).unix_seconds()
}

#[test]
fn ftp_selected_siblings_share_one_fresh_listing_per_scan() {
    for mlsd in [true, false] {
        let ftp = FtpServer::start(FtpOptions { mlsd, ..FtpOptions::default() });
        let server = connect(Protocol::Ftp, ftp.port);
        let names: Vec<String> = (0..20).map(|i| format!("file {i}.txt")).collect();
        for name in &names {
            std::fs::write(ftp.path(name), name).unwrap();
        }
        for round in 0..2 {
            if round == 1 {
                std::fs::write(ftp.path(&names[0]), "changed between operations").unwrap();
            }
            ftp.commands.lock().clear();
            let local = tempfile::tempdir().unwrap();
            let (progress, asked) = run(
                Transfer {
                    kind: OpKind::Copy,
                    from: Side::Remote(server.clone()),
                    sources: names.iter().map(|name| format!("/{name}")).collect(),
                    to: Some((Side::Native, local.path().to_string_lossy().into_owned())),
                    new_name: None,
                    options: options(ConflictPolicy::Ask),
                },
                vec![],
            );
            assert_eq!(progress.state, OpState::Done, "{:?}", progress.errors);
            assert!(asked.is_empty());
            let commands = ftp.commands.lock();
            let lists = commands.iter().filter(|c| c.starts_with("MLSD") || c.starts_with("LIST")).count();
            assert_eq!(lists, 1, "{commands:?}");
            for name in &names {
                assert_eq!(
                    std::fs::read(local.path().join(name)).unwrap(),
                    std::fs::read(ftp.path(name)).unwrap()
                );
            }
            let expected: u64 = names.iter().map(|n| std::fs::metadata(ftp.path(n)).unwrap().len()).sum();
            assert_eq!(progress.bytes_total, expected);
        }
        connection::disconnect(server.key());
    }
}

#[test]
fn uploads_and_downloads_a_tree_with_its_times() {
    let sftp = SftpServer::start(SftpOptions::default());
    let server = connect(Protocol::Sftp, sftp.port);
    let local = tempfile::tempdir().unwrap();
    let source = tree(local.path());

    let (up, asked) = run(
        Transfer {
            kind: OpKind::Copy,
            from: Side::Native,
            sources: vec![source.to_string_lossy().into_owned()],
            to: Some((Side::Remote(server.clone()), "/".into())),
            new_name: None,
            options: options(ConflictPolicy::Ask),
        },
        vec![],
    );
    assert_eq!(up.state, OpState::Done, "{:?}", up.errors);
    assert!(asked.is_empty());
    assert_eq!(up.items_total, 5);
    assert_eq!(up.items_done, 5);
    assert_eq!(up.bytes_total, 4096 + 300 * 1024);
    assert_eq!(up.bytes_done, up.bytes_total);
    assert_eq!(up.result_path, Some(PathBuf::from(format!("{}/a", server.key()))));
    assert_eq!(up.destination, Some(PathBuf::from(format!("{}/", server.key()))));
    same_tree(&source, &sftp.path("a"));
    assert_eq!(mtime(&sftp.path("a/Ünïcödé файл.txt")), 1_600_000_000);

    let back = tempfile::tempdir().unwrap();
    let (down, _) = run(
        Transfer {
            kind: OpKind::Copy,
            from: Side::Remote(server.clone()),
            sources: vec!["/a".into()],
            to: Some((Side::Native, back.path().to_string_lossy().into_owned())),
            new_name: Some("copy of a".into()),
            options: options(ConflictPolicy::Ask),
        },
        vec![],
    );
    assert_eq!(down.state, OpState::Done, "{:?}", down.errors);
    same_tree(&source, &back.path().join("copy of a"));
    assert_eq!(mtime(&back.path().join("copy of a/Ünïcödé файл.txt")), 1_600_000_000);
    connection::disconnect(server.key());
}

#[test]
fn server_to_server_and_moves() {
    let sftp = SftpServer::start(SftpOptions::default());
    let ftp = FtpServer::start(FtpOptions::default());
    let from = connect(Protocol::Sftp, sftp.port);
    let to = connect(Protocol::Ftp, ftp.port);
    tree(sftp.root.path());

    let (copied, _) = run(
        Transfer {
            kind: OpKind::Copy,
            from: Side::Remote(from.clone()),
            sources: vec!["/a".into()],
            to: Some((Side::Remote(to.clone()), "/".into())),
            new_name: None,
            options: options(ConflictPolicy::Ask),
        },
        vec![],
    );
    assert_eq!(copied.state, OpState::Done, "{:?}", copied.errors);
    same_tree(&sftp.path("a"), &ftp.path("a"));
    // FTP keeps times with MFMT.
    assert_eq!(mtime(&ftp.path("a/Ünïcödé файл.txt")), 1_600_000_000);

    // On one server a move is a rename.
    std::fs::create_dir(sftp.path("into")).unwrap();
    let (moved, _) = run(
        Transfer {
            kind: OpKind::Move,
            from: Side::Remote(from.clone()),
            sources: vec!["/a".into()],
            to: Some((Side::Remote(from.clone()), "/into".into())),
            new_name: None,
            options: options(ConflictPolicy::Ask),
        },
        vec![],
    );
    assert_eq!(moved.state, OpState::Done, "{:?}", moved.errors);
    assert!(!sftp.path("a").exists());
    assert!(sftp.path("into/a/b/deep.bin").exists());
    assert_eq!(moved.items_done, 5);

    // Across sides a move copies, then takes the source away.
    let local = tempfile::tempdir().unwrap();
    let (fetched, _) = run(
        Transfer {
            kind: OpKind::Move,
            from: Side::Remote(to.clone()),
            sources: vec!["/a".into()],
            to: Some((Side::Native, local.path().to_string_lossy().into_owned())),
            new_name: None,
            options: options(ConflictPolicy::Ask),
        },
        vec![],
    );
    assert_eq!(fetched.state, OpState::Done, "{:?}", fetched.errors);
    assert!(!ftp.path("a").exists());
    same_tree(&sftp.path("into/a"), &local.path().join("a"));

    // A folder into itself never starts.
    let (refused, _) = run(
        Transfer {
            kind: OpKind::Copy,
            from: Side::Remote(from.clone()),
            sources: vec!["/into".into()],
            to: Some((Side::Remote(from.clone()), "/into/a".into())),
            new_name: None,
            options: options(ConflictPolicy::Ask),
        },
        vec![],
    );
    assert_eq!(refused.state, OpState::Failed);
    connection::disconnect(from.key());
    connection::disconnect(to.key());
}

#[test]
fn conflicts_ask_and_keep_both() {
    let sftp = SftpServer::start(SftpOptions::default());
    let server = connect(Protocol::Sftp, sftp.port);
    let local = tempfile::tempdir().unwrap();
    std::fs::write(local.path().join("note.txt"), "new").unwrap();
    std::fs::write(local.path().join("other.txt"), "other").unwrap();
    std::fs::write(sftp.path("note.txt"), "old").unwrap();
    std::fs::write(sftp.path("other.txt"), "kept").unwrap();
    let sources = vec![
        local.path().join("note.txt").to_string_lossy().into_owned(),
        local.path().join("other.txt").to_string_lossy().into_owned(),
    ];
    let (done, asked) = run(
        Transfer {
            kind: OpKind::Copy,
            from: Side::Native,
            sources: sources.clone(),
            to: Some((Side::Remote(server.clone()), "/".into())),
            new_name: None,
            options: options(ConflictPolicy::Ask),
        },
        vec![Answer::KeepBoth, Answer::Skip],
    );
    assert_eq!(done.state, OpState::Done, "{:?}", done.errors);
    assert_eq!(asked.len(), 2);
    assert_eq!(asked[0].kind, QuestionKind::Conflict);
    assert_eq!(asked[0].existing.as_ref().unwrap().path, format!("{}/note.txt", server.key()));
    assert_eq!(asked[0].existing.as_ref().unwrap().size, Some(3));
    assert_eq!(std::fs::read_to_string(sftp.path("note.txt")).unwrap(), "old");
    assert_eq!(std::fs::read_to_string(sftp.path("note 2.txt")).unwrap(), "new");
    assert_eq!(std::fs::read_to_string(sftp.path("other.txt")).unwrap(), "kept");

    let (over, asked) = run(
        Transfer {
            kind: OpKind::Copy,
            from: Side::Native,
            sources,
            to: Some((Side::Remote(server.clone()), "/".into())),
            new_name: None,
            options: options(ConflictPolicy::Overwrite),
        },
        vec![],
    );
    assert_eq!(over.state, OpState::Done);
    assert!(asked.is_empty());
    assert_eq!(std::fs::read_to_string(sftp.path("note.txt")).unwrap(), "new");
    assert_eq!(std::fs::read_to_string(sftp.path("other.txt")).unwrap(), "other");
    connection::disconnect(server.key());
}

#[test]
fn a_connection_dropped_mid_copy_is_tried_again() {
    let sftp =
        SftpServer::start(SftpOptions { drop_after_bytes: Some(256 * 1024), ..SftpOptions::default() });
    std::fs::write(sftp.path("big.bin"), pattern(1024 * 1024)).unwrap();
    let server = connect(Protocol::Sftp, sftp.port);
    let local = tempfile::tempdir().unwrap();
    let (done, asked) = run(
        Transfer {
            kind: OpKind::Copy,
            from: Side::Remote(server.clone()),
            sources: vec!["/big.bin".into()],
            to: Some((Side::Native, local.path().to_string_lossy().into_owned())),
            new_name: None,
            options: options(ConflictPolicy::Ask),
        },
        // The server drops each connection after 256 KiB: retried on a
        // new connection the file starts over, and drops again; then it
        // is skipped.
        vec![Answer::Retry, Answer::Skip],
    );
    assert_eq!(asked.len(), 2, "{asked:?}");
    assert_eq!(asked[0].kind, QuestionKind::Error);
    assert_eq!(done.state, OpState::DoneWithErrors);
    // What a broken copy left is gone, and its bytes no longer count.
    assert!(!local.path().join("big.bin").exists());
    assert_eq!(done.bytes_done, 1024 * 1024);
    assert!(sftp.logins.load(std::sync::atomic::Ordering::SeqCst) >= 2);
    connection::disconnect(server.key());
}

#[test]
fn a_cancel_stops_the_copy_and_takes_the_part_away() {
    let sftp = SftpServer::start(SftpOptions::default());
    let server = connect(Protocol::Sftp, sftp.port);
    let local = tempfile::tempdir().unwrap();
    let big = local.path().join("big.bin");
    std::fs::write(&big, pattern(64 * 1024 * 1024)).unwrap();
    let runner = Runner::new();
    let transfer = Transfer {
        kind: OpKind::Copy,
        from: Side::Native,
        sources: vec![big.to_string_lossy().into_owned()],
        to: Some((Side::Remote(server.clone()), "/".into())),
        new_name: None,
        options: options(ConflictPolicy::Ask),
    };
    let id = runner.start_job(
        transfer.shown_as(),
        ferryx_ops::runner::Journaling::Off,
        Box::new(move |ctx| transfer::run(ctx, &transfer)),
    );
    // Once some bytes are across.
    for _ in 0..500 {
        if runner.progress(id).unwrap().bytes_done > 0 {
            break;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    runner.cancel(id);
    let mut last = runner.progress(id).unwrap();
    for _ in 0..500 {
        last = runner.progress(id).unwrap();
        if last.state.is_finished() {
            break;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(last.state, OpState::Cancelled);
    assert!(!sftp.path("big.bin").exists());
    connection::disconnect(server.key());
}

#[test]
fn deletes_trees_and_sizes_folders() {
    let sftp = SftpServer::start(SftpOptions::default());
    let dav = DavServer::start(DavOptions::default());
    tree(sftp.root.path());
    tree(dav.root.path());
    let over_sftp = connect(Protocol::Sftp, sftp.port);
    let over_dav = connect(Protocol::Dav, dav.port);

    let (sizes, _) = run(
        Transfer {
            kind: OpKind::CalcSizes,
            from: Side::Remote(over_sftp.clone()),
            sources: vec!["/a".into()],
            to: None,
            new_name: None,
            options: OpOptions::default(),
        },
        vec![],
    );
    // Named with the server, as the sources are.
    assert_eq!(
        sizes.sizes,
        vec![FolderSize { path: PathBuf::from(format!("{}/a", over_sftp.key())), bytes: 4096 + 300 * 1024 }]
    );

    for (server, root) in [(over_sftp.clone(), sftp.root.path()), (over_dav.clone(), dav.root.path())] {
        let (gone, _) = run(
            Transfer {
                kind: OpKind::Delete,
                from: Side::Remote(server.clone()),
                sources: vec!["/a".into()],
                to: None,
                new_name: None,
                options: OpOptions::default(),
            },
            vec![],
        );
        assert_eq!(gone.state, OpState::Done, "{:?}", gone.errors);
        assert!(!root.join("a").exists());
        connection::disconnect(server.key());
    }
}

#[test]
fn a_copy_on_one_webdav_server_is_made_there() {
    let dav = DavServer::start(DavOptions::default());
    tree(dav.root.path());
    let server = connect(Protocol::Dav, dav.port);
    std::fs::create_dir(dav.path("copies")).unwrap();
    let (done, _) = run(
        Transfer {
            kind: OpKind::Copy,
            from: Side::Remote(server.clone()),
            sources: vec!["/a/Ünïcödé файл.txt".into(), "/a/b".into()],
            to: Some((Side::Remote(server.clone()), "/copies".into())),
            new_name: None,
            options: options(ConflictPolicy::Ask),
        },
        vec![],
    );
    assert_eq!(done.state, OpState::Done, "{:?}", done.errors);
    assert!(dav.path("copies/Ünïcödé файл.txt").exists());
    assert!(dav.path("copies/b/deep.bin").exists());
    connection::disconnect(server.key());
}
