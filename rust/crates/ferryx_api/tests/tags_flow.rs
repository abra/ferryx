//! Finder tags and the desktop's capabilities through the bridge.

// Tags are macOS's: elsewhere only the capability is checked.
#![cfg_attr(not(target_os = "macos"), allow(dead_code, unused_imports))]

use std::fs;
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};

use ferryx_api::api::capabilities::capabilities;
use ferryx_api::api::events::{record_events, reset_for_tests, take_recorded_events};
use ferryx_api::api::tags::{read_listing_tags, set_tags, TagView};
use ferryx_api::api::types::*;
use ferryx_api::api::{files, listing};

static SERIAL: Mutex<()> = Mutex::new(());

fn serial() -> MutexGuard<'static, ()> {
    SERIAL.lock().unwrap_or_else(|e| e.into_inner())
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

fn tag(name: &str, color: i32) -> TagView {
    TagView { name: name.into(), color }
}

#[test]
fn capabilities_follow_the_desktop() {
    let found = capabilities();
    assert_eq!(found.finder_tags, cfg!(target_os = "macos"));
    if !cfg!(target_os = "macos") {
        assert!(!found.spotlight);
    }
}

#[cfg(target_os = "macos")]
#[test]
fn tags_are_written_and_read_apart_from_the_listing() {
    let _guard = serial();
    reset_for_tests();
    let dir = tempfile::tempdir().unwrap();
    let a = dir.path().join("a.txt");
    let b = dir.path().join("b.txt");
    fs::write(&a, b"a").unwrap();
    fs::write(&b, b"b").unwrap();
    let s = |p: &std::path::Path| p.to_string_lossy().into_owned();

    let outcomes = set_tags(vec![s(&a), s(&b)], vec![tag("Red", 6), tag("work", 0)], vec![]);
    assert!(outcomes.iter().all(|o| o.failure.is_none()));
    assert_eq!(outcomes[0].tags, [tag("Red", 6), tag("work", 0)]);
    let outcomes = set_tags(vec![s(&b)], vec![], vec!["red".into()]);
    assert_eq!(outcomes[0].tags, [tag("work", 0)]);

    // The listing comes without tags; they are read apart.
    let view = listing::open_listing("t".into(), LocationView::native(dir.path()), options()).unwrap();
    assert!(view.entries.iter().all(|e| e.tags.is_empty()));
    let mut found = read_listing_tags("t".into()).unwrap();
    found.sort_by(|x, y| x.path.cmp(&y.path));
    assert_eq!(found.len(), 2);
    assert_eq!(found[0].tags, [tag("Red", 6), tag("work", 0)]);
    assert_eq!(found[1].tags, [tag("work", 0)]);
    // One item reads its own.
    assert_eq!(files::stat(s(&a)).unwrap().tags.len(), 2);
    // Read once, the rows are not read again until they change.
    assert!(read_listing_tags("t".into()).unwrap().is_empty());

    // Tags taken off elsewhere: the item the watcher named is read again
    // alone and sent with none, so the panel drops its dots.
    record_events();
    set_tags(vec![s(&a)], vec![], vec!["red".into(), "work".into()]);
    let start = Instant::now();
    while !take_recorded_events().iter().any(|e| e.kind == AppEventKind::DirectoryChanged) {
        assert!(start.elapsed() < Duration::from_secs(10), "no change reported");
        std::thread::sleep(Duration::from_millis(20));
    }
    listing::refresh_listing("t".into()).unwrap();
    let found = read_listing_tags("t".into()).unwrap();
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].path, s(&a));
    assert!(found[0].tags.is_empty());
    // ⌘R reads every row's again.
    listing::refresh_listing("t".into()).unwrap();
    let found = read_listing_tags("t".into()).unwrap();
    assert_eq!(found.iter().map(|f| f.path.clone()).collect::<Vec<_>>(), [s(&b)]);

    // A missing item fails alone, typed.
    let missing = set_tags(vec![s(&dir.path().join("gone"))], vec![tag("Red", 6)], vec![]);
    assert_eq!(missing[0].failure, Some(FerryxErrorKind::NotFound));
    listing::close_listing("t".into());
    assert!(read_listing_tags("t".into()).is_err());
}
