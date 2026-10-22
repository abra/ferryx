//! WebDAV against an in-process server (dav-server): a login asked for
//! and kept, listings with names in many scripts, ranges, uploads,
//! folders, moves and copies on the server, HTTPS certificates.

mod common;

use std::time::{Duration, Instant};

use common::*;
use ferryx_test_servers::dav::{DavOptions, DavServer};
use ferryx_vfs::remote::connection::{self, AuthMethod, ConnectSpec};
use ferryx_vfs::remote::prompt::Question;
use ferryx_vfs::remote::secrets::SecretStore;
use ferryx_vfs::remote::{never, Protocol, ServerAddress};
use ferryx_vfs::VfsErrorKind;

fn spec(server: &DavServer, protocol: Protocol, host: &str, user: &str, path: &str) -> ConnectSpec {
    let mut address = ServerAddress::new(protocol, host, user);
    address.port = server.port;
    address.path = path.to_string();
    ConnectSpec { address, auth: AuthMethod::Password }
}

fn names(rows: Vec<ferryx_core::entry::Entry>) -> Vec<String> {
    let mut names: Vec<String> = rows.into_iter().map(|e| e.name).collect();
    names.sort();
    names
}

#[test]
fn asks_for_the_login_and_lists() {
    setup();
    let server = DavServer::start(DavOptions::default());
    sample_tree(server.root.path());
    let spec = spec(&server, Protocol::Dav, "127.0.0.1", "me", "");
    let key = spec.address.key();
    script(&key, vec![text("wrong", false), text("secret", true)]);
    let connected = connection::connect(spec.clone(), &never).unwrap();
    let asked = asked(&key);
    assert!(matches!(asked[0], Question::Password { retry: false, .. }), "{asked:?}");
    assert!(matches!(asked[1], Question::Password { retry: true, .. }), "{asked:?}");
    assert_eq!(STORE.get(&key).as_deref(), Some("secret"));
    assert_eq!(connected.fs().home(), "/");

    let rows = connected.fs().list("/", &never).unwrap();
    let hello = rows.iter().find(|e| e.name == "Привет мир.txt").unwrap();
    assert_eq!(hello.size, Some(5));
    assert!(hello.modified_ms.is_some());
    assert_eq!(hello.path.to_string_lossy(), "/Привет мир.txt");
    assert!(rows.iter().find(|e| e.name == "sub").unwrap().is_dir);
    assert_eq!(names(rows), [".hidden", "empty.bin", "sub", "Привет мир.txt", "日本語 ü.md"]);
    assert_eq!(names(connected.fs().list("/sub", &never).unwrap()), ["inner.txt"]);
    assert_eq!(connected.fs().stat("/日本語 ü.md", &never).unwrap().unwrap().size, Some(4));
    assert!(connected.fs().stat("/nothing", &never).unwrap().is_none());
    assert_eq!(connected.fs().list("/nothing", &never).unwrap_err().kind, VfsErrorKind::NotFound);
    connection::disconnect(&key);

    // The keychain answers next time.
    connection::connect(spec, &never).unwrap();
    assert_eq!(common::asked(&key).len(), 2);
    connection::disconnect(&key);
    STORE.delete(&key).unwrap();
}

#[test]
fn a_server_without_a_login_and_a_start_folder() {
    setup();
    let server = DavServer::start(DavOptions { user: None, ..DavOptions::default() });
    sample_tree(server.root.path());
    let spec = spec(&server, Protocol::Dav, "127.0.0.1", "", "/sub");
    let key = spec.address.key();
    let connected = connection::connect(spec, &never).unwrap();
    assert_eq!(connected.fs().home(), "/sub");
    assert_eq!(names(connected.fs().list("/sub", &never).unwrap()), ["inner.txt"]);
    assert!(asked(&key).is_empty());
    connection::disconnect(&key);
}

#[test]
fn uploads_ranges_folders_moves_and_copies() {
    setup();
    let server = DavServer::start(DavOptions::default());
    let spec = spec(&server, Protocol::Dav, "127.0.0.1", "me", "");
    let key = spec.address.key();
    script(&key, vec![text("secret", false)]);
    let connected = connection::connect(spec, &never).unwrap();
    let fs = connected.fs();
    assert!(fs.caps().server_copy);
    assert!(!fs.caps().set_modified);

    let data = pattern(2 * 1024 * 1024 + 5);
    let mut writer = fs.create("/up load ü.bin", Some(data.len() as u64), &never).unwrap();
    for chunk in data.chunks(70_000) {
        writer.write_all(chunk, &never).unwrap();
    }
    writer.finish(&never).unwrap();
    assert!(std::fs::read(server.path("up load ü.bin")).unwrap() == data);
    assert_eq!(fs.read_range("/up load ü.bin", 1_000_000, 16, &never).unwrap(), data[1_000_000..1_000_016]);
    assert!(fs.read_range("/up load ü.bin", data.len() as u64 + 10, 16, &never).unwrap().is_empty());
    let mut reader = fs.open_read("/up load ü.bin", &never).unwrap();
    let mut back = Vec::new();
    let mut buffer = vec![0u8; 40_000];
    loop {
        let n = reader.read(&mut buffer, &never).unwrap();
        if n == 0 {
            break;
        }
        back.extend_from_slice(&buffer[..n]);
    }
    assert!(back == data);

    fs.mkdir("/made", &never).unwrap();
    assert_eq!(fs.mkdir("/made", &never).unwrap_err().kind, VfsErrorKind::AlreadyExists);
    fs.rename("/up load ü.bin", "/made/moved.bin", &never).unwrap();
    fs.copy("/made/moved.bin", "/copy.bin", &never).unwrap();
    assert!(std::fs::read(server.path("copy.bin")).unwrap() == data);
    assert_eq!(
        fs.rename("/copy.bin", "/made/moved.bin", &never).unwrap_err().kind,
        VfsErrorKind::AlreadyExists
    );
    assert_eq!(
        fs.copy("/copy.bin", "/made/moved.bin", &never).unwrap_err().kind,
        VfsErrorKind::AlreadyExists
    );
    fs.copy("/made", "/made copy", &never).unwrap();
    assert!(server.path("made copy/moved.bin").exists());
    fs.remove_file("/copy.bin", &never).unwrap();
    fs.remove_file("/made/moved.bin", &never).unwrap();
    fs.remove_dir("/made", &never).unwrap();
    assert!(!server.path("made").exists());
    assert_eq!(fs.remove_file("/nothing", &never).unwrap_err().kind, VfsErrorKind::NotFound);
    connection::disconnect(&key);
}

#[test]
fn https_checks_the_certificate() {
    setup();
    let ca = ferryx_test_servers::ca();
    let server =
        DavServer::start(DavOptions { tls: Some(ca.server_config.clone()), ..DavOptions::default() });
    sample_tree(server.root.path());
    let spec = spec(&server, Protocol::Davs, "localhost", "me", "");
    let key = spec.address.key();
    script(&key, vec![text("secret", false)]);
    let connected = connection::connect(spec, &never).unwrap();
    assert_eq!(connected.fs().list("/", &never).unwrap().len(), 5);
    connection::disconnect(&key);

    let untrusted =
        DavServer::start(DavOptions { tls: Some(ca.untrusted_config.clone()), ..DavOptions::default() });
    let spec = self::spec(&untrusted, Protocol::Davs, "localhost", "me", "");
    let error = connection::connect(spec, &never).err().unwrap();
    assert_eq!(error.kind, VfsErrorKind::CertificateInvalid, "{error:?}");
}

#[test]
fn lists_ten_thousand_items() {
    setup();
    let server = DavServer::start(DavOptions { user: None, ..DavOptions::default() });
    for i in 0..10_000 {
        std::fs::write(server.path(&format!("file {i:05}.txt")), "").unwrap();
    }
    let spec = spec(&server, Protocol::Dav, "127.0.0.1", "", "");
    let key = spec.address.key();
    let connected = connection::connect(spec, &never).unwrap();
    let started = Instant::now();
    let rows = connected.fs().list("/", &never).unwrap();
    let took = started.elapsed();
    eprintln!("WebDAV: 10 000 rows in {took:?}");
    assert_eq!(rows.len(), 10_000);
    assert!(took < Duration::from_secs(20), "{took:?}");
    connection::disconnect(&key);
}
