//! FTP and FTPS against an in-process server: `MLSD` and the `LIST`
//! fallback of a server without it, names in many scripts, passwords asked
//! again, certificates checked, transfers both ways, a transfer cut short,
//! two transfers at once, a large folder, a stop that ends a wait on a
//! server gone silent.

mod common;

use std::net::TcpListener;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use common::*;
use ferryx_test_servers::ftp::{FtpOptions, FtpServer};
use ferryx_vfs::remote::connection::{self, AuthMethod, ConnState, ConnectSpec};
use ferryx_vfs::remote::prompt::Question;
use ferryx_vfs::remote::{never, Protocol, ServerAddress};
use ferryx_vfs::VfsErrorKind;

fn spec(server: &FtpServer, protocol: Protocol, host: &str) -> ConnectSpec {
    let mut address = ServerAddress::new(protocol, host, "me");
    address.port = server.port;
    ConnectSpec { address, auth: AuthMethod::Password }
}

fn names(rows: Vec<ferryx_core::entry::Entry>) -> Vec<String> {
    let mut names: Vec<String> = rows.into_iter().map(|e| e.name).collect();
    names.sort();
    names
}

#[test]
fn lists_with_mlsd_and_without_it() {
    setup();
    for mlsd in [true, false] {
        let server = FtpServer::start(FtpOptions { mlsd, ..FtpOptions::default() });
        sample_tree(server.root.path());
        let spec = spec(&server, Protocol::Ftp, "127.0.0.1");
        let key = spec.address.key();
        script(&key, vec![text("secret", false)]);
        let connected = connection::connect(spec, &never).unwrap();
        assert_eq!(connected.fs().home(), "/");
        let rows = connected.fs().list("/", &never).unwrap();
        let hello = rows.iter().find(|e| e.name == "Привет мир.txt").unwrap();
        assert_eq!(hello.size, Some(5));
        assert!(hello.modified_ms.is_some());
        assert_eq!(hello.owner, "me");
        assert!(rows.iter().find(|e| e.name == "sub").unwrap().is_dir);
        assert_eq!(names(rows), [".hidden", "empty.bin", "sub", "Привет мир.txt", "日本語 ü.md"]);
        assert_eq!(names(connected.fs().list("/sub", &never).unwrap()), ["inner.txt"]);
        let commands = server.commands.lock().clone();
        assert_eq!(commands.contains(&"MLSD".to_string()), mlsd, "{commands:?}");
        assert_eq!(commands.contains(&"LIST".to_string()), !mlsd, "{commands:?}");
        assert!(commands.contains(&"OPTS".to_string()));
        assert_eq!(connected.fs().stat("/sub/inner.txt", &never).unwrap().unwrap().size, Some(5));
        assert!(connected.fs().stat("/nothing", &never).unwrap().is_none());
        connection::disconnect(&key);
    }
}

#[test]
fn a_wrong_password_is_asked_again() {
    setup();
    let server = FtpServer::start(FtpOptions::default());
    let spec = spec(&server, Protocol::Ftp, "127.0.0.1");
    let key = spec.address.key();
    script(&key, vec![text("wrong", false), text("secret", false)]);
    connection::connect(spec.clone(), &never).unwrap();
    let asked = asked(&key);
    assert!(matches!(asked[0], Question::Password { retry: false, .. }));
    assert!(matches!(asked[1], Question::Password { retry: true, .. }));
    connection::disconnect(&key);

    script(&key, vec![text("wrong", false), cancel()]);
    assert_eq!(connection::connect(spec, &never).err().unwrap().kind, VfsErrorKind::Cancelled);
}

#[test]
fn writes_reads_renames_and_removes() {
    setup();
    let server = FtpServer::start(FtpOptions::default());
    let spec = spec(&server, Protocol::Ftp, "127.0.0.1");
    let key = spec.address.key();
    script(&key, vec![text("secret", false)]);
    let connected = connection::connect(spec, &never).unwrap();
    let fs = connected.fs();
    assert!(fs.caps().set_modified);

    let data = pattern(1024 * 1024 + 17);
    let mut writer = fs.create("/up load.bin", Some(data.len() as u64), &never).unwrap();
    for chunk in data.chunks(60_000) {
        writer.write_all(chunk, &never).unwrap();
    }
    writer.finish(&never).unwrap();
    assert!(std::fs::read(server.path("up load.bin")).unwrap() == data);

    let mut reader = fs.open_read("/up load.bin", &never).unwrap();
    let mut back = Vec::new();
    let mut buffer = vec![0u8; 32_768];
    loop {
        let n = reader.read(&mut buffer, &never).unwrap();
        if n == 0 {
            break;
        }
        back.extend_from_slice(&buffer[..n]);
    }
    drop(reader);
    assert!(back == data);
    assert_eq!(fs.read_range("/up load.bin", 500_000, 8, &never).unwrap(), data[500_000..500_008]);

    fs.mkdir("/made", &never).unwrap();
    assert_eq!(fs.mkdir("/made", &never).unwrap_err().kind, VfsErrorKind::AlreadyExists);
    fs.rename("/up load.bin", "/made/ü.bin", &never).unwrap();
    std::fs::write(server.path("taken"), "x").unwrap();
    // The server would replace it: the client refuses first.
    assert_eq!(fs.rename("/made/ü.bin", "/taken", &never).unwrap_err().kind, VfsErrorKind::AlreadyExists);
    assert_eq!(std::fs::read(server.path("taken")).unwrap(), b"x");
    fs.set_modified("/made/ü.bin", 1_600_000_000_000, &never).unwrap();
    assert_eq!(fs.stat("/made/ü.bin", &never).unwrap().unwrap().modified_ms, Some(1_600_000_000_000));
    fs.remove_file("/made/ü.bin", &never).unwrap();
    fs.remove_dir("/made", &never).unwrap();
    assert!(!server.path("made").exists());
    assert_eq!(fs.remove_file("/nothing", &never).unwrap_err().kind, VfsErrorKind::NotFound);
    connection::disconnect(&key);
}

#[test]
fn ftps_checks_the_certificate() {
    setup();
    let ca = ferryx_test_servers::ca();
    let server =
        FtpServer::start(FtpOptions { tls: Some(ca.server_config.clone()), ..FtpOptions::default() });
    sample_tree(server.root.path());
    let spec = spec(&server, Protocol::Ftps, "localhost");
    let key = spec.address.key();
    script(&key, vec![text("secret", false)]);
    let connected = connection::connect(spec, &never).unwrap();
    assert_eq!(connected.fs().list("/", &never).unwrap().len(), 5);
    assert_eq!(connected.fs().read_range("/Привет мир.txt", 0, 100, &never).unwrap(), b"hello");
    let commands = server.commands.lock().clone();
    assert!(commands.contains(&"AUTH".to_string()) && commands.contains(&"PROT".to_string()));
    connection::disconnect(&key);

    let untrusted =
        FtpServer::start(FtpOptions { tls: Some(ca.untrusted_config.clone()), ..FtpOptions::default() });
    let spec = self::spec(&untrusted, Protocol::Ftps, "localhost");
    let error = connection::connect(spec, &never).err().unwrap();
    assert_eq!(error.kind, VfsErrorKind::CertificateInvalid, "{error:?}");
    // Refused before any password crossed.
    assert!(!untrusted.commands.lock().contains(&"PASS".to_string()));
}

#[test]
fn a_transfer_cut_short_fails_and_the_next_call_reconnects() {
    setup();
    let server = FtpServer::start(FtpOptions { drop_after_bytes: Some(200_000), ..FtpOptions::default() });
    std::fs::write(server.path("big.bin"), pattern(1_000_000)).unwrap();
    let spec = spec(&server, Protocol::Ftp, "127.0.0.1");
    let key = spec.address.key();
    script(&key, vec![text("secret", false)]);
    let connected = connection::connect(spec, &never).unwrap();
    let mut reader = connected.fs().open_read("/big.bin", &never).unwrap();
    let mut buffer = vec![0u8; 16_384];
    let mut read = 0;
    let failed = loop {
        match reader.read(&mut buffer, &never) {
            Ok(0) => break None,
            Ok(n) => read += n,
            Err(error) => break Some(error),
        }
    };
    drop(reader);
    // Cut mid-way: either an error, or an end too early.
    assert!(failed.is_some() || read < 1_000_000, "{failed:?} {read}");
    if let Some(error) = failed {
        assert!(error.is_connection_error(), "{error:?}");
    }
    assert_eq!(connected.fs().list("/", &never).unwrap().len(), 1);
    assert!(server.connections.load(Ordering::SeqCst) >= 2);
    assert_eq!(connected.state(), ConnState::Connected);
    connection::disconnect(&key);
}

#[test]
fn a_listing_runs_while_a_file_is_read() {
    setup();
    let server = FtpServer::start(FtpOptions::default());
    std::fs::write(server.path("a.bin"), pattern(300_000)).unwrap();
    let spec = spec(&server, Protocol::Ftp, "127.0.0.1");
    let key = spec.address.key();
    script(&key, vec![text("secret", false)]);
    let connected = connection::connect(spec, &never).unwrap();
    let mut reader = connected.fs().open_read("/a.bin", &never).unwrap();
    let mut buffer = vec![0u8; 1000];
    reader.read(&mut buffer, &never).unwrap();
    // The control connection is busy with the read: another one lists.
    assert_eq!(connected.fs().list("/", &never).unwrap().len(), 1);
    drop(reader);
    assert!(server.connections.load(Ordering::SeqCst) >= 2);
    connection::disconnect(&key);
}

#[test]
fn lists_ten_thousand_items() {
    setup();
    for mlsd in [true, false] {
        let server = FtpServer::start(FtpOptions { mlsd, ..FtpOptions::default() });
        for i in 0..10_000 {
            std::fs::write(server.path(&format!("file {i:05}.txt")), "").unwrap();
        }
        let spec = spec(&server, Protocol::Ftp, "127.0.0.1");
        let key = spec.address.key();
        script(&key, vec![text("secret", false)]);
        let connected = connection::connect(spec, &never).unwrap();
        let started = Instant::now();
        let rows = connected.fs().list("/", &never).unwrap();
        let took = started.elapsed();
        eprintln!("FTP ({}): 10 000 rows in {took:?}", if mlsd { "MLSD" } else { "LIST" });
        assert_eq!(rows.len(), 10_000);
        assert!(took < Duration::from_secs(20), "{took:?}");
        connection::disconnect(&key);
    }
}

/// A stop that says yes `after` from now.
fn stop_after(after: Duration) -> impl Fn() -> bool + Sync {
    let at = Instant::now() + after;
    move || Instant::now() >= at
}

#[test]
fn a_stop_ends_the_wait_for_a_greeting_that_never_comes() {
    setup();
    let silent = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = silent.local_addr().unwrap().port();
    let held = std::thread::spawn(move || silent.accept().map(|(socket, _)| socket));
    let mut address = ServerAddress::new(Protocol::Ftp, "127.0.0.1", "me");
    address.port = port;
    address.password = Some("secret".into());
    let started = Instant::now();
    let stop = stop_after(Duration::from_millis(200));
    let error = connection::connect(ConnectSpec { address, auth: AuthMethod::Password }, &stop)
        .err()
        .expect("stopped");
    assert_eq!(error.kind, VfsErrorKind::Cancelled);
    // Long before the request timeout would have ended it.
    assert!(started.elapsed() < Duration::from_secs(3), "{:?}", started.elapsed());
    drop(held.join());
}

#[test]
fn a_stop_ends_a_read_from_a_server_that_hangs() {
    setup();
    let server = FtpServer::start(FtpOptions { stall_after_bytes: Some(100_000), ..FtpOptions::default() });
    std::fs::write(server.path("big.bin"), pattern(1_000_000)).unwrap();
    let spec = spec(&server, Protocol::Ftp, "127.0.0.1");
    let key = spec.address.key();
    script(&key, vec![text("secret", false)]);
    let connected = connection::connect(spec, &never).unwrap();
    let mut reader = connected.fs().open_read("/big.bin", &never).unwrap();
    let mut buffer = vec![0u8; 16_384];
    let stopped = AtomicBool::new(false);
    let stop = || stopped.load(Ordering::SeqCst);
    let mut read = 0;
    let begun = Instant::now();
    let started = std::thread::scope(|scope| {
        // What the server sends comes at once; then it hangs, and the
        // stop comes while the read waits.
        scope.spawn(|| {
            std::thread::sleep(Duration::from_millis(300));
            stopped.store(true, Ordering::SeqCst);
        });
        let error = loop {
            match reader.read(&mut buffer, &stop) {
                Ok(0) => panic!("the server hangs; the file does not end"),
                Ok(n) => read += n,
                Err(error) => break error,
            }
        };
        assert_eq!(error.kind, VfsErrorKind::Cancelled);
        // Seen within a poll of the stop, not at the request timeout.
        assert!(begun.elapsed() < Duration::from_secs(2), "{:?}", begun.elapsed());
        assert!(read > 0 && read < 1_000_000, "{read}");
        Instant::now()
    });
    drop(reader);
    // Letting go of the hung transfer does not wait on the server either.
    assert!(started.elapsed() < Duration::from_secs(1));
    // The server is still there for the next call.
    assert_eq!(connected.fs().list("/", &never).unwrap().len(), 1);
    connection::disconnect(&key);
}
