//! Servers through the bridge: an address read, a connection whose
//! questions come as events and are answered back, a panel's listing on
//! the server (and `NotConnected` once it is closed), the viewer's
//! ranges, items made and renamed there, a download as an operation, the
//! state events, a connection attempt cancelled.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use ferryx_api::api::events::{record_events, reset_for_tests, take_recorded_events};
use ferryx_api::api::network::*;
use ferryx_api::api::types::*;
use ferryx_api::api::{files, listing, ops};
use ferryx_test_servers::sftp::{SftpOptions, SftpServer};

/// The bridge's state is process-wide: the tests take turns.
static SERIAL: Mutex<()> = Mutex::new(());

fn serial() -> MutexGuard<'static, ()> {
    let guard = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    reset_for_tests();
    // Never the user's own files or keychain.
    static DIR: std::sync::LazyLock<tempfile::TempDir> =
        std::sync::LazyLock::new(|| tempfile::tempdir().unwrap());
    ferryx_vfs::remote::known_hosts::use_files(Vec::new(), DIR.path().join("known_hosts"));
    ferryx_vfs::remote::secrets::use_store(Arc::new(ferryx_vfs::remote::secrets::MemoryStore::default()));
    guard
}

fn options() -> ListingOptionsView {
    ListingOptionsView {
        show_hidden: false,
        show_parent: true,
        sort: SortOptionsView {
            field: SortFieldView::Name,
            descending: false,
            folders_first: true,
            extensionless_folders: true,
            collation: CollationView::Natural,
        },
    }
}

/// Collects the events and answers each question the way `answer` says,
/// as the interface's dialogs would.
struct User {
    events: Arc<Mutex<Vec<AppEvent>>>,
    done: Arc<AtomicBool>,
}

impl User {
    fn start(answer: impl Fn(&NetworkQuestionView) -> (bool, Vec<String>, bool) + Send + 'static) -> User {
        record_events();
        let events = Arc::new(Mutex::new(Vec::new()));
        let done = Arc::new(AtomicBool::new(false));
        {
            let events = events.clone();
            let done = done.clone();
            std::thread::spawn(move || {
                while !done.load(Ordering::SeqCst) {
                    for event in take_recorded_events() {
                        if let (AppEventKind::NetworkQuestion, Some(question)) =
                            (event.kind, event.network.as_ref().and_then(|n| n.question.clone()))
                        {
                            let (accept, texts, remember) = answer(&question);
                            answer_network_question(question.id, accept, texts, remember);
                        }
                        events.lock().unwrap().push(event);
                    }
                    std::thread::sleep(Duration::from_millis(5));
                }
            });
        }
        User { events, done }
    }

    fn events(&self) -> Vec<AppEvent> {
        // What the thread has not taken yet comes after a moment.
        std::thread::sleep(Duration::from_millis(50));
        self.events.lock().unwrap().clone()
    }
}

impl Drop for User {
    fn drop(&mut self) {
        self.done.store(true, Ordering::SeqCst);
    }
}

fn request(server: &SftpServer) -> ConnectRequestView {
    ConnectRequestView {
        protocol: ProtocolView::Sftp,
        host: "127.0.0.1".into(),
        port: i64::from(server.port),
        user: "me".into(),
        path: String::new(),
        password: None,
        auth: AuthMethodView::Password,
        key_path: None,
    }
}

fn remote(server: &str, path: &str) -> LocationView {
    LocationView { kind: LocationKind::Remote, path: path.into(), archive: None, server: Some(server.into()) }
}

fn names(view: &ListingView) -> Vec<&str> {
    view.entries.iter().map(|e| e.name.as_str()).collect()
}

fn wait_done(id: i64) -> ProgressView {
    let start = Instant::now();
    loop {
        let progress = ops::operation_progress(id).unwrap();
        if matches!(
            progress.state,
            OpStateView::Done | OpStateView::DoneWithErrors | OpStateView::Failed | OpStateView::Cancelled
        ) {
            return progress;
        }
        assert!(start.elapsed() < Duration::from_secs(20), "timed out");
        std::thread::sleep(Duration::from_millis(20));
    }
}

#[test]
fn reads_addresses() {
    let _turn = serial();
    let address = parse_server_address("sftp://me@Host.lan:2222/srv/www".into(), ProtocolView::Sftp).unwrap();
    assert_eq!(address.protocol, ProtocolView::Sftp);
    assert_eq!((address.host.as_str(), address.port, address.user.as_str()), ("host.lan", 2222, "me"));
    assert_eq!(address.path, "/srv/www");
    assert_eq!(address.key, "sftp://me@host.lan:2222");
    assert_eq!(address.display, "sftp://me@host.lan:2222");
    let dav = parse_server_address("https://cloud.example/dav".into(), ProtocolView::Sftp).unwrap();
    assert_eq!((dav.protocol, dav.port), (ProtocolView::Davs, 443));
    assert_eq!(
        parse_server_address("gopher://x".into(), ProtocolView::Sftp).unwrap_err().kind,
        FerryxErrorKind::InvalidName
    );
    let mut bad = ConnectRequestView {
        protocol: ProtocolView::Ftp,
        host: "a b".into(),
        port: 0,
        user: String::new(),
        path: String::new(),
        password: None,
        auth: AuthMethodView::Password,
        key_path: None,
    };
    assert_eq!(server_key(bad.clone()).unwrap_err().kind, FerryxErrorKind::InvalidName);
    bad.host = "files.lan".into();
    assert_eq!(server_key(bad).unwrap(), "ftp://files.lan:21");
}

#[test]
fn connects_lists_reads_and_makes_items() {
    let _turn = serial();
    let server = SftpServer::start(SftpOptions::default());
    std::fs::create_dir(server.path("sub")).unwrap();
    std::fs::write(server.path("sub/Ünï.txt"), "hello there").unwrap();
    std::fs::write(server.path(".hidden"), "h").unwrap();
    let user = User::start(|question| match question.kind {
        NetworkQuestionKindView::HostKey => (true, vec![], true),
        _ => (true, vec!["secret".into()], false),
    });

    let connection = connect_server(begin_connect(), request(&server)).unwrap();
    assert_eq!(connection.server, format!("sftp://me@127.0.0.1:{}", server.port));
    assert_eq!(connection.home, "/");
    assert!(connection.secure);
    assert_eq!(list_servers().len(), 1);

    let root = listing::open_listing("t1".into(), remote(&connection.server, "/"), options()).unwrap();
    assert_eq!(names(&root), ["sub"]);
    assert!(!root.watched);
    assert_eq!(root.volume_name.as_deref(), Some(format!("sftp://me@127.0.0.1:{}", server.port).as_str()));
    assert_eq!(root.location.kind, LocationKind::Remote);
    let sub = listing::open_listing("t1".into(), remote(&connection.server, "/sub"), options()).unwrap();
    assert_eq!(names(&sub), ["..", "Ünï.txt"]);
    assert_eq!(sub.entries[0].path, "/");
    assert_eq!(sub.entries[1].path, "/sub/Ünï.txt");
    let file = remote(&connection.server, "/sub/Ünï.txt");
    assert_eq!(files::read_file_range(file.clone(), 6, 5).unwrap(), b"there");
    assert_eq!(files::file_size(file).unwrap(), 11);

    remote_make_folder(connection.server.clone(), "/sub/made".into()).unwrap();
    remote_make_file(connection.server.clone(), "/sub/new.txt".into()).unwrap();
    assert_eq!(
        remote_make_file(connection.server.clone(), "/sub/new.txt".into()).unwrap_err().kind,
        FerryxErrorKind::AlreadyExists
    );
    assert_eq!(
        remote_free_name(connection.server.clone(), "/sub".into(), "new.txt".into()).unwrap(),
        "new 2.txt"
    );
    assert_eq!(
        remote_rename(connection.server.clone(), "/sub/new.txt".into(), "renamed.txt".into()).unwrap(),
        "/sub/renamed.txt"
    );
    assert_eq!(
        remote_rename(connection.server.clone(), "/sub/made".into(), "a/b".into()).unwrap_err().kind,
        FerryxErrorKind::InvalidName
    );
    assert!(remote_stat(connection.server.clone(), "/sub/renamed.txt".into()).unwrap().is_some());
    let again = listing::refresh_listing("t1".into()).unwrap();
    assert_eq!(names(&again), ["..", "made", "renamed.txt", "Ünï.txt"]);

    // A download into a folder on disk, as an operation.
    let temp = remote_temp_folder(connection.server.clone()).unwrap();
    let id = start_network_operation(NetworkOpRequestView {
        kind: OpKindView::Copy,
        sources: vec!["/sub/Ünï.txt".into()],
        source_server: Some(connection.server.clone()),
        destination: Some(temp.clone()),
        destination_server: None,
        new_name: None,
        conflicts: ConflictPolicyView::Ask,
        preserve_attributes: true,
    })
    .unwrap();
    let done = wait_done(id);
    assert_eq!(done.state, OpStateView::Done, "{:?}", done.errors);
    assert_eq!(done.sources, vec![format!("{}/sub/Ünï.txt", connection.server)]);
    assert_eq!(std::fs::read_to_string(std::path::Path::new(&temp).join("Ünï.txt")).unwrap(), "hello there");

    let events = user.events();
    let questions: Vec<NetworkQuestionView> =
        events.iter().filter_map(|e| e.network.as_ref().and_then(|n| n.question.clone())).collect();
    assert_eq!(questions[0].kind, NetworkQuestionKindView::HostKey);
    assert!(questions[0].fingerprint.starts_with("SHA256:"));
    assert_eq!(questions[0].port, i64::from(server.port));
    assert_eq!(questions[1].kind, NetworkQuestionKindView::Password);
    assert_eq!(questions[1].user, "me");
    assert!(events.iter().any(|e| e.kind == AppEventKind::ConnectionChanged
        && e.network.as_ref().and_then(|n| n.state) == Some(ConnectionStateView::Connected)));

    disconnect_server(connection.server.clone());
    assert!(user.events().iter().any(|e| e.kind == AppEventKind::ConnectionChanged
        && e.network.as_ref().and_then(|n| n.state) == Some(ConnectionStateView::Closed)));
    assert_eq!(listing::refresh_listing("t1".into()).unwrap_err().kind, FerryxErrorKind::NotConnected);
    assert_eq!(
        listing::open_listing("t2".into(), remote(&connection.server, "/"), options()).unwrap_err().kind,
        FerryxErrorKind::NotConnected
    );
    assert!(list_servers().is_empty());
    listing::close_listing("t1".into());
}

#[test]
fn a_refused_password_is_asked_again_and_cancel_withdraws_the_question() {
    let _turn = serial();
    let server = SftpServer::start(SftpOptions::default());
    let asked = Arc::new(Mutex::new(Vec::new()));
    let seen = asked.clone();
    let user = User::start(move |question| {
        seen.lock().unwrap().push(question.clone());
        match question.kind {
            NetworkQuestionKindView::HostKey => (true, vec![], false),
            _ if !question.retry => (true, vec!["wrong".into()], false),
            _ => (false, vec![], false),
        }
    });
    let error = connect_server(begin_connect(), request(&server)).unwrap_err();
    assert_eq!(error.kind, FerryxErrorKind::Cancelled);
    let asked = asked.lock().unwrap().clone();
    assert_eq!(asked.len(), 3);
    assert!(asked[2].retry);
    drop(user);

    // A connection that hangs is given up from the interface: the attempt
    // stops at once.
    let silent = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = silent.local_addr().unwrap().port();
    std::thread::spawn(move || {
        let _held: Vec<_> = silent.incoming().take(1).collect();
        std::thread::sleep(Duration::from_secs(30));
    });
    let attempt = begin_connect();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(200));
        cancel_connect(attempt);
    });
    let mut hanging = request(&server);
    hanging.port = i64::from(port);
    let started = Instant::now();
    assert_eq!(connect_server(attempt, hanging).unwrap_err().kind, FerryxErrorKind::Cancelled);
    assert!(started.elapsed() < Duration::from_secs(3));
}
