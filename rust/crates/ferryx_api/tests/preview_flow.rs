use std::fs;

use ferryx_api::api::preview::*;
use ferryx_api::api::types::{FerryxErrorKind, LocationKind, LocationView};

#[test]
fn a_registered_lease_can_close_before_the_worker_starts() {
    let id = create_preview_file(LocationView {
        kind: LocationKind::Archive,
        path: "book.pdf".into(),
        archive: Some("archive not opened.zip".into()),
        server: None,
    });
    cancel_preview_file(id);
    assert_eq!(prepare_preview_file(id).unwrap_err().kind, FerryxErrorKind::Cancelled);
    close_preview_file(id).unwrap();
    close_preview_file(id).unwrap();
    assert_eq!(prepare_preview_file(id).unwrap_err().kind, FerryxErrorKind::Cancelled);
}

#[test]
fn releasing_a_native_lease_never_removes_the_source() {
    let directory = tempfile::tempdir().unwrap();
    let source = directory.path().join("book.pdf");
    fs::write(&source, b"PDF source").unwrap();
    let id = create_preview_file(LocationView::native(&source));
    assert_eq!(prepare_preview_file(id).unwrap(), source.to_string_lossy());
    close_preview_file(id).unwrap();
    assert_eq!(fs::read(source).unwrap(), b"PDF source");
}
