//! Archives through the bridge: an encrypted one asks for its password,
//! keeps it once given, and Extract To writes it out.

use std::fs::{self, File};
use std::io::Write;
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};

use ferryx_api::api::archives;
use ferryx_api::api::events::reset_for_tests;
use ferryx_api::api::types::*;
use ferryx_api::api::{files, listing, ops};

static SERIAL: Mutex<()> = Mutex::new(());

fn serial() -> MutexGuard<'static, ()> {
    SERIAL.lock().unwrap_or_else(|e| e.into_inner())
}

fn s(path: &std::path::Path) -> String {
    path.to_string_lossy().into_owned()
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

fn wait_for(mut done: impl FnMut() -> bool) {
    let start = Instant::now();
    while !done() {
        assert!(start.elapsed() < Duration::from_secs(10), "timed out");
        std::thread::sleep(Duration::from_millis(20));
    }
}

fn locked_zip(path: &std::path::Path) {
    let mut zip = zip::ZipWriter::new(File::create(path).unwrap());
    let opts = zip::write::SimpleFileOptions::default().with_aes_encryption(zip::AesMode::Aes256, "pw");
    zip.start_file("docs/secret.txt", opts).unwrap();
    zip.write_all(b"the secret").unwrap();
    zip.start_file("readme.txt", opts).unwrap();
    zip.write_all(b"read me").unwrap();
    zip.finish().unwrap();
}

#[test]
fn an_encrypted_archive_asks_once_and_extracts() {
    let _guard = serial();
    reset_for_tests();
    let dir = tempfile::tempdir().unwrap();
    let archive = dir.path().join("locked.zip");
    locked_zip(&archive);

    // The member list is not encrypted: it lists, and says what it holds.
    let location = LocationView {
        kind: LocationKind::Archive,
        path: String::new(),
        archive: Some(s(&archive)),
        server: None,
    };
    let view = listing::open_listing("a".into(), location, options()).unwrap();
    assert_eq!(
        view.entries.iter().map(|e| e.name.as_str()).collect::<Vec<_>>(),
        ["..", "docs", "readme.txt"]
    );
    let info = archives::archive_info(s(&archive)).unwrap();
    assert_eq!(info.format, "zip");
    assert_eq!(info.top_level_count, 2);
    assert_eq!(info.file_count, 2);
    assert!(info.encrypted && !info.needs_password && !info.has_password);

    // Its members need the password.
    let member = LocationView {
        kind: LocationKind::Archive,
        path: "readme.txt".into(),
        archive: Some(s(&archive)),
        server: None,
    };
    assert_eq!(
        files::read_file_range(member.clone(), 0, 4).unwrap_err().kind,
        FerryxErrorKind::PasswordRequired
    );
    assert_eq!(
        archives::set_archive_password(s(&archive), "wrong".into()).unwrap_err().kind,
        FerryxErrorKind::WrongPassword
    );
    archives::set_archive_password(s(&archive), "pw".into()).unwrap();
    assert_eq!(files::read_file_range(member, 0, 4).unwrap(), b"read");
    assert!(archives::archive_info(s(&archive)).unwrap().has_password);

    // Extract To: the whole archive, into a folder named after it, with
    // the password kept.
    let dest = dir.path().join("out");
    let id = ops::start_operation(OpRequestView {
        kind: OpKindView::Extract,
        sources: vec![s(&archive)],
        archive: None,
        destination: Some(s(&dest)),
        new_name: None,
        conflicts: ConflictPolicyView::Ask,
        preserve_attributes: true,
        verify: false,
        password: None,
        into_folders: true,
    });
    wait_for(|| ops::operation_progress(id).map(|p| p.state == OpStateView::Done).unwrap_or(false));
    assert_eq!(fs::read(dest.join("locked/docs/secret.txt")).unwrap(), b"the secret");
    ops::forget_operation(id);
    listing::close_listing("a".into());
}

#[test]
fn any_file_can_be_asked_if_it_is_an_archive() {
    let _guard = serial();
    reset_for_tests();
    let dir = tempfile::tempdir().unwrap();
    let hidden = dir.path().join("data.bin");
    locked_zip(&hidden);
    assert!(!listing::is_archive(s(&hidden)));
    assert!(archives::detect_archive(s(&hidden)));
    let text = dir.path().join("notes.txt");
    fs::write(&text, b"plain").unwrap();
    assert!(!archives::detect_archive(s(&text)));
    let error = archives::archive_info(s(&text)).unwrap_err();
    assert_eq!(error.kind, FerryxErrorKind::Unsupported);
}
