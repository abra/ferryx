//! SFTP against an in-process server: host keys asked for, remembered,
//! refused when changed; passwords, keyboard-interactive and key files;
//! listing, reading, writing, renaming; a dropped connection opened again;
//! a large folder.

mod common;

use std::io::Write as _;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use common::*;
use ferryx_test_servers::sftp::{SftpOptions, SftpServer};
use ferryx_vfs::remote::connection::{self, AuthMethod, ConnState, ConnectSpec};
use ferryx_vfs::remote::prompt::Question;
use ferryx_vfs::remote::secrets::SecretStore;
use ferryx_vfs::remote::{never, Protocol, ServerAddress};
use ferryx_vfs::VfsErrorKind;

fn spec(server: &SftpServer, auth: AuthMethod) -> ConnectSpec {
    let mut address = ServerAddress::new(Protocol::Sftp, "127.0.0.1", "me");
    address.port = server.port;
    ConnectSpec { address, auth }
}

fn key(server: &SftpServer) -> String {
    spec(server, AuthMethod::Auto).address.key()
}

#[test]
fn trusts_a_new_key_once_and_lists_the_home_folder() {
    setup();
    let server = SftpServer::start(SftpOptions::default());
    sample_tree(server.root.path());
    let key = key(&server);
    script(&key, vec![trust(true), text("secret", false)]);

    let connected = connection::connect(spec(&server, AuthMethod::Password), &never).unwrap();
    assert_eq!(connected.state(), ConnState::Connected);
    assert_eq!(connected.fs().home(), "/");
    let asked = asked(&key);
    assert!(
        matches!(&asked[0], Question::HostKey { fingerprint, algorithm, port, .. }
            if fingerprint.starts_with("SHA256:") && algorithm == "ssh-ed25519" && *port == server.port),
        "{asked:?}"
    );
    assert!(matches!(&asked[1], Question::Password { retry: false, user, .. } if user == "me"));

    let mut names: Vec<String> =
        connected.fs().list("/", &never).unwrap().into_iter().map(|e| e.name).collect();
    names.sort();
    assert_eq!(names, [".hidden", "empty.bin", "sub", "Привет мир.txt", "日本語 ü.md"]);
    let rows = connected.fs().list("/", &never).unwrap();
    let hello = rows.iter().find(|e| e.name == "Привет мир.txt").unwrap();
    assert_eq!(hello.size, Some(5));
    assert_eq!(hello.path.to_string_lossy(), "/Привет мир.txt");
    assert!(hello.modified_ms.is_some());
    assert!(rows.iter().find(|e| e.name == ".hidden").unwrap().is_hidden);
    assert!(rows.iter().find(|e| e.name == "sub").unwrap().is_dir);
    assert_eq!(connected.fs().read_range("/Привет мир.txt", 1, 3, &never).unwrap(), b"ell");
    assert_eq!(connected.fs().stat("/sub/inner.txt", &never).unwrap().unwrap().size, Some(5));
    assert!(connected.fs().stat("/nothing", &never).unwrap().is_none());

    // The key is Ferryx's now: a new connection asks for the password
    // only.
    connection::disconnect(&key);
    assert!(std::fs::read_to_string(ferryx_vfs::remote::known_hosts::own_path())
        .unwrap()
        .contains(&format!("[127.0.0.1]:{} ssh-ed25519 ", server.port)));
    script(&key, vec![text("secret", false)]);
    let again = connection::connect(spec(&server, AuthMethod::Password), &never).unwrap();
    assert_eq!(again.state(), ConnState::Connected);
    assert_eq!(common::asked(&key).len(), 3);
    connection::disconnect(&key);
}

#[test]
fn a_changed_key_is_refused_without_asking() {
    setup();
    let server = SftpServer::start(SftpOptions::default());
    let other = russh::keys::PrivateKey::from_openssh(ferryx_test_servers::OTHER_HOST_KEY).unwrap();
    let line = format!("[127.0.0.1]:{} {}\n", server.port, other.public_key().to_openssh().unwrap());
    let path = user_known_hosts();
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .unwrap()
        .write_all(line.as_bytes())
        .unwrap();
    let key = key(&server);
    script(&key, vec![trust(true), text("secret", false)]);

    let error = connection::connect(spec(&server, AuthMethod::Password), &never).err().unwrap();
    assert_eq!(error.kind, VfsErrorKind::HostKeyChanged);
    // The message names the record the key differs from, for the alarm.
    let recorded = path.display().to_string();
    assert!(error.message.starts_with(&recorded) && error.message.contains(':'), "{}", error.message);
    assert!(asked(&key).is_empty());
}

#[test]
fn an_unknown_key_not_trusted_ends_the_connection() {
    setup();
    let server = SftpServer::start(SftpOptions::default());
    let key = key(&server);
    script(&key, vec![cancel()]);
    let error = connection::connect(spec(&server, AuthMethod::Password), &never).err().unwrap();
    assert_eq!(error.kind, VfsErrorKind::HostKeyUnknown);
    assert_eq!(server.logins.load(Ordering::SeqCst), 0);
}

#[test]
fn a_wrong_password_is_asked_again_and_a_kept_one_goes_to_the_keychain() {
    setup();
    let server = SftpServer::start(SftpOptions::default());
    let key = key(&server);
    script(&key, vec![trust(false), text("wrong", false), text("secret", true)]);
    let connected = connection::connect(spec(&server, AuthMethod::Password), &never).unwrap();
    assert_eq!(connected.state(), ConnState::Connected);
    let asked = asked(&key);
    assert!(matches!(asked[1], Question::Password { retry: false, .. }));
    assert!(matches!(asked[2], Question::Password { retry: true, .. }));
    assert_eq!(STORE.get(&key).as_deref(), Some("secret"));
    // A key trusted for this run only stays out of the file.
    assert!(!std::fs::read_to_string(ferryx_vfs::remote::known_hosts::own_path())
        .unwrap_or_default()
        .contains(&format!("[127.0.0.1]:{} ", server.port)));
    connection::disconnect(&key);

    // Next time the keychain answers (the key is asked again: it was
    // trusted for that connection only).
    script(&key, vec![trust(false)]);
    connection::connect(spec(&server, AuthMethod::Password), &never).unwrap();
    assert_eq!(common::asked(&key).len(), 4);
    connection::disconnect(&key);
    STORE.delete(&key).unwrap();
}

#[test]
fn giving_up_on_the_password_cancels_and_three_wrong_ones_fail() {
    setup();
    let server = SftpServer::start(SftpOptions::default());
    let key = key(&server);
    script(&key, vec![trust(false), cancel()]);
    let error = connection::connect(spec(&server, AuthMethod::Password), &never).err().unwrap();
    assert_eq!(error.kind, VfsErrorKind::Cancelled);

    script(&key, vec![trust(false), text("a", false), text("b", false), text("c", false), text("d", false)]);
    let error = connection::connect(spec(&server, AuthMethod::Password), &never).err().unwrap();
    assert_eq!(error.kind, VfsErrorKind::AuthFailed);
}

#[test]
fn a_password_prompt_and_a_one_time_code() {
    setup();
    let server = SftpServer::start(SftpOptions {
        password_by_prompt: true,
        one_time_code: Some("123456".into()),
        ..SftpOptions::default()
    });
    let key = key(&server);
    script(&key, vec![trust(false), text("secret", false), texts(&["123456"])]);
    let connected = connection::connect(spec(&server, AuthMethod::Auto), &never).unwrap();
    assert_eq!(connected.state(), ConnState::Connected);
    let asked = asked(&key);
    // The hidden "Password:" prompt is asked as a password, the code as
    // the server's own prompt.
    assert!(matches!(&asked[1], Question::Password { .. }), "{asked:?}");
    assert!(
        matches!(&asked[2], Question::KeyboardInteractive { prompts, .. } if prompts[0].0 == "Verification code: "),
        "{asked:?}"
    );
    connection::disconnect(&key);
}

#[test]
fn key_files_with_and_without_a_passphrase() {
    setup();
    let dir = tempfile::tempdir().unwrap();
    let plain = dir.path().join("id_plain");
    let encrypted = dir.path().join("id_encrypted");
    std::fs::write(&plain, ferryx_test_servers::CLIENT_KEY).unwrap();
    std::fs::write(&encrypted, ferryx_test_servers::CLIENT_KEY_ENCRYPTED).unwrap();
    let server = SftpServer::start(SftpOptions {
        client_keys: vec![ferryx_test_servers::CLIENT_KEY_PUB, ferryx_test_servers::CLIENT_KEY_ENCRYPTED_PUB],
        ..SftpOptions::default()
    });
    let key = key(&server);

    script(&key, vec![trust(false)]);
    connection::connect(spec(&server, AuthMethod::Key(Some(plain))), &never).unwrap();
    connection::disconnect(&key);

    script(
        &key,
        vec![trust(false), text("not it", false), text(ferryx_test_servers::CLIENT_KEY_PASSPHRASE, false)],
    );
    connection::connect(spec(&server, AuthMethod::Key(Some(encrypted))), &never).unwrap();
    let asked = asked(&key);
    assert!(
        matches!(&asked[2], Question::Passphrase { retry: false, key_path, .. } if key_path.ends_with("id_encrypted"))
    );
    assert!(matches!(&asked[3], Question::Passphrase { retry: true, .. }));
    connection::disconnect(&key);
}

#[test]
fn writes_reads_renames_and_removes() {
    setup();
    let server = SftpServer::start(SftpOptions::default());
    let key = key(&server);
    script(&key, vec![trust(false), text("secret", false)]);
    let connected = connection::connect(spec(&server, AuthMethod::Password), &never).unwrap();
    let fs = connected.fs();

    // A file larger than the requests in flight, written and read back.
    let data = pattern(3 * 1024 * 1024 + 123);
    let mut writer = fs.create("/big.bin", Some(data.len() as u64), &never).unwrap();
    for chunk in data.chunks(100_000) {
        writer.write_all(chunk, &never).unwrap();
    }
    writer.finish(&never).unwrap();
    assert_eq!(std::fs::read(server.path("big.bin")).unwrap(), data);
    let mut reader = fs.open_read("/big.bin", &never).unwrap();
    let mut back = Vec::new();
    let mut buffer = vec![0u8; 50_000];
    loop {
        let n = reader.read(&mut buffer, &never).unwrap();
        if n == 0 {
            break;
        }
        back.extend_from_slice(&buffer[..n]);
    }
    assert_eq!(back.len(), data.len());
    assert!(back == data);
    assert_eq!(fs.read_range("/big.bin", 2_000_000, 10, &never).unwrap(), data[2_000_000..2_000_010]);
    assert!(fs.read_range("/big.bin", data.len() as u64 + 5, 10, &never).unwrap().is_empty());

    fs.mkdir("/made", &never).unwrap();
    assert_eq!(fs.mkdir("/made", &never).unwrap_err().kind, VfsErrorKind::AlreadyExists);
    fs.rename("/big.bin", "/made/moved.bin", &never).unwrap();
    std::fs::write(server.path("taken"), "x").unwrap();
    assert_eq!(fs.rename("/made/moved.bin", "/taken", &never).unwrap_err().kind, VfsErrorKind::AlreadyExists);
    fs.set_modified("/made/moved.bin", 1_600_000_000_000, &never).unwrap();
    assert_eq!(fs.stat("/made/moved.bin", &never).unwrap().unwrap().modified_ms, Some(1_600_000_000_000));
    assert_eq!(fs.remove_dir("/made", &never).unwrap_err().kind, VfsErrorKind::Io);
    fs.remove_file("/made/moved.bin", &never).unwrap();
    fs.remove_dir("/made", &never).unwrap();
    assert!(!server.path("made").exists());
    assert_eq!(fs.list("/nowhere", &never).unwrap_err().kind, VfsErrorKind::NotFound);
    connection::disconnect(&key);
}

#[test]
fn a_dropped_connection_fails_the_read_and_opens_again() {
    setup();
    let server =
        SftpServer::start(SftpOptions { drop_after_bytes: Some(256 * 1024), ..SftpOptions::default() });
    std::fs::write(server.path("big.bin"), pattern(2 * 1024 * 1024)).unwrap();
    let key = key(&server);
    let states = Arc::new(parking_lot::Mutex::new(Vec::new()));
    {
        let states = states.clone();
        let key = key.clone();
        connection::set_listener(Some(Arc::new(move |server, state| {
            if server == key {
                states.lock().push(state);
            }
        })));
    }
    script(&key, vec![trust(true), text("secret", false)]);
    let connected = connection::connect(spec(&server, AuthMethod::Password), &never).unwrap();
    let mut reader = connected.fs().open_read("/big.bin", &never).unwrap();
    let mut buffer = vec![0u8; 64 * 1024];
    let error = loop {
        match reader.read(&mut buffer, &never) {
            Ok(0) => panic!("the read should fail"),
            Ok(_) => continue,
            Err(error) => break error,
        }
    };
    drop(reader);
    assert!(error.is_connection_error(), "{error:?}");
    // The next call logs in again with the password kept: no question.
    let rows = connected.fs().list("/", &never).unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(server.logins.load(Ordering::SeqCst), 2);
    assert_eq!(asked(&key).len(), 2);
    let seen = states.lock().clone();
    assert!(seen.contains(&ConnState::Lost) && seen.last() == Some(&ConnState::Connected), "{seen:?}");
    connection::set_listener(None);
    connection::disconnect(&key);
}

#[test]
fn a_connection_that_hangs_stops_when_asked_and_a_closed_port_is_unreachable() {
    setup();
    // Takes the connection and says nothing.
    let silent = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = silent.local_addr().unwrap().port();
    std::thread::spawn(move || {
        let _held: Vec<_> = silent.incoming().take(1).collect();
        std::thread::sleep(Duration::from_secs(30));
    });
    let mut address = ServerAddress::new(Protocol::Sftp, "127.0.0.1", "me");
    address.port = port;
    let stop = Arc::new(AtomicBool::new(false));
    {
        let stop = stop.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(300));
            stop.store(true, Ordering::SeqCst);
        });
    }
    let started = Instant::now();
    let flag = stop.clone();
    let error = connection::connect(ConnectSpec { address, auth: AuthMethod::Password }, &move || {
        flag.load(Ordering::SeqCst)
    })
    .err()
    .unwrap();
    assert_eq!(error.kind, VfsErrorKind::Cancelled);
    assert!(started.elapsed() < Duration::from_secs(3));

    let closed = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = closed.local_addr().unwrap().port();
    drop(closed);
    let mut address = ServerAddress::new(Protocol::Sftp, "127.0.0.1", "me");
    address.port = port;
    let error =
        connection::connect(ConnectSpec { address, auth: AuthMethod::Password }, &never).err().unwrap();
    assert_eq!(error.kind, VfsErrorKind::HostUnreachable);
    assert_eq!(connection::get("sftp://me@127.0.0.1:1").err().unwrap().kind, VfsErrorKind::NotConnected);
}

#[test]
fn lists_ten_thousand_items() {
    setup();
    let server = SftpServer::start(SftpOptions::default());
    for i in 0..10_000 {
        std::fs::write(server.path(&format!("file {i:05}.txt")), "").unwrap();
    }
    let key = key(&server);
    script(&key, vec![trust(false), text("secret", false)]);
    let connected = connection::connect(spec(&server, AuthMethod::Password), &never).unwrap();
    let started = Instant::now();
    let rows = connected.fs().list("/", &never).unwrap();
    let took = started.elapsed();
    eprintln!("SFTP: 10 000 rows in {took:?}");
    assert_eq!(rows.len(), 10_000);
    assert!(took < Duration::from_secs(20), "{took:?}");
    connection::disconnect(&key);
}
