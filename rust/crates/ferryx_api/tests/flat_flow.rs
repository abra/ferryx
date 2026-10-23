//! Flat views through the bridge: the rows stream in batches, the order
//! comes as indices, a new walk stops the old one.

use std::fs;
use std::sync::mpsc;
use std::sync::{Mutex, MutexGuard};
use std::time::Duration;

use ferryx_api::api::events::reset_for_tests;
use ferryx_api::api::flat::{self, FlatBatchView};
use ferryx_api::api::listing;
use ferryx_api::api::types::*;

static SERIAL: Mutex<()> = Mutex::new(());

fn serial() -> MutexGuard<'static, ()> {
    SERIAL.lock().unwrap_or_else(|e| e.into_inner())
}

fn options(field: SortFieldView, show_hidden: bool) -> ListingOptionsView {
    ListingOptionsView {
        show_hidden,
        show_parent: true,
        sort: SortOptionsView {
            field,
            descending: field != SortFieldView::Name,
            folders_first: true,
            extensionless_folders: true,
            collation: CollationView::Natural,
        },
    }
}

/// Every batch of a walk until its end.
fn walk(id: &str, generation: i64) -> Vec<FlatBatchView> {
    let (tx, rx) = mpsc::channel();
    flat::stream_flat_listing_with(
        id.to_string(),
        generation,
        Box::new(move |batch| {
            let _ = tx.send(batch);
        }),
    );
    let mut batches = Vec::new();
    loop {
        let batch = rx.recv_timeout(Duration::from_secs(10)).expect("the walk ends");
        let done = batch.done;
        batches.push(batch);
        if done {
            return batches;
        }
    }
}

/// Times a flat view of a large folder end to end (walk, then sort):
/// `FERRYX_FLAT_BENCH=~/Library cargo test --release -p ferryx_api --test
/// flat_flow bench -- --ignored --nocapture`.
#[test]
#[ignore]
fn bench() {
    let _guard = serial();
    reset_for_tests();
    let root = std::env::var("FERRYX_FLAT_BENCH").unwrap_or_else(|_| "/usr".to_string());
    let start = std::time::Instant::now();
    let open = flat::open_flat_listing(
        "bench".into(),
        LocationView::native(std::path::Path::new(&root)),
        options(SortFieldView::Name, true),
    )
    .unwrap();
    let batches = walk("bench", open.generation);
    let walked = start.elapsed();
    let count = batches.last().unwrap().count;
    let sorting = std::time::Instant::now();
    let order =
        flat::sort_flat_listing("bench".into(), open.generation, options(SortFieldView::Name, true)).unwrap();
    println!(
        "{root}: {count} rows in {} batches, walked in {walked:?}, sorted by name in {:?}",
        batches.len(),
        sorting.elapsed()
    );
    assert_eq!(order.len() as i64, count);
}

fn tree() -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    fs::create_dir_all(root.join("b/deep")).unwrap();
    fs::create_dir_all(root.join("a")).unwrap();
    fs::write(root.join("same.txt"), b"root").unwrap();
    fs::write(root.join("a/same.txt"), b"in a, larger").unwrap();
    fs::write(root.join("b/deep/zeta.md"), b"z").unwrap();
    fs::write(root.join("b/.hidden"), b"").unwrap();
    dir
}

#[test]
fn rows_stream_then_sort_by_index() {
    let _guard = serial();
    reset_for_tests();
    let dir = tree();
    let start = flat::open_flat_listing(
        "left".into(),
        LocationView::native(dir.path()),
        options(SortFieldView::Name, false),
    )
    .unwrap();
    assert!(start.listing.entries.is_empty());
    assert!(start.listing.watched);
    let batches = walk("left", start.generation);
    let last = batches.last().unwrap();
    assert!(last.done && !last.capped);
    assert_eq!(last.count, 4, "the parent row and three files");
    let rows: Vec<(String, String)> = batches
        .iter()
        .flat_map(|b| b.entries.iter().zip(&b.folders).map(|(e, f)| (f.clone(), e.name.clone())))
        .collect();
    assert_eq!(rows.len(), 4);
    assert!(!rows.iter().any(|(_, name)| name == ".hidden"));

    // By name: `..` first, then names, a name's folders in order.
    let order = flat::sort_flat_listing("left".into(), start.generation, options(SortFieldView::Name, false))
        .unwrap();
    let sorted: Vec<&(String, String)> = order.iter().map(|&i| &rows[i as usize]).collect();
    assert_eq!(sorted[0].1, "..");
    assert_eq!(
        sorted[1..].iter().map(|(f, n)| format!("{f}/{n}")).collect::<Vec<_>>(),
        ["/same.txt", "a/same.txt", "b/deep/zeta.md"]
    );
    // By size, largest first.
    let order = flat::sort_flat_listing("left".into(), start.generation, options(SortFieldView::Size, false))
        .unwrap();
    assert_eq!(rows[order[1] as usize], ("a".to_string(), "same.txt".to_string()));
    // A stale generation is refused.
    assert!(flat::sort_flat_listing(
        "left".into(),
        start.generation + 100,
        options(SortFieldView::Name, false)
    )
    .is_err());
    // The listing is not refreshed or resorted the plain way.
    assert_eq!(listing::refresh_listing("left".into()).unwrap_err().kind, FerryxErrorKind::Unsupported);
    listing::close_listing("left".into());
}

#[test]
fn a_new_walk_replaces_the_old_and_inside_archives_too() {
    let _guard = serial();
    reset_for_tests();
    let dir = tree();
    let first = flat::open_flat_listing(
        "r".into(),
        LocationView::native(dir.path()),
        options(SortFieldView::Name, true),
    )
    .unwrap();
    let second = flat::open_flat_listing(
        "r".into(),
        LocationView::native(dir.path()),
        options(SortFieldView::Name, true),
    )
    .unwrap();
    assert_ne!(first.generation, second.generation);
    // The old generation streams nothing but its end.
    let stale = walk("r", first.generation);
    assert_eq!(stale.len(), 1);
    assert_eq!(stale[0].count, 0);
    let fresh = walk("r", second.generation);
    assert_eq!(fresh.last().unwrap().count, 5, "hidden files shown when asked");

    // A plain listing replaces a flat one.
    let plain = listing::open_listing(
        "r".into(),
        LocationView::native(dir.path()),
        options(SortFieldView::Name, false),
    )
    .unwrap();
    assert!(plain.entries.iter().any(|e| e.name == "a"));
    assert!(
        flat::sort_flat_listing("r".into(), second.generation, options(SortFieldView::Name, false)).is_err()
    );

    // Not a folder.
    assert_eq!(
        flat::open_flat_listing(
            "x".into(),
            LocationView::native(&dir.path().join("same.txt")),
            options(SortFieldView::Name, false)
        )
        .unwrap_err()
        .kind,
        FerryxErrorKind::NotADirectory
    );

    // Inside an archive: the index's subtree.
    let archive = dir.path().join("pack.zip");
    {
        use std::io::Write;
        let mut zip = zip::ZipWriter::new(fs::File::create(&archive).unwrap());
        let opts = zip::write::SimpleFileOptions::default();
        for name in ["top.txt", "d/one.txt", "d/e/two.txt"] {
            zip.start_file(name, opts).unwrap();
            zip.write_all(b"x").unwrap();
        }
        zip.finish().unwrap();
    }
    let location = LocationView {
        kind: LocationKind::Archive,
        path: "d".into(),
        archive: Some(archive.to_string_lossy().into_owned()),
        server: None,
    };
    let start = flat::open_flat_listing("z".into(), location, options(SortFieldView::Name, false)).unwrap();
    assert!(!start.listing.watched);
    let batches = walk("z", start.generation);
    let rows: Vec<(String, String)> = batches
        .iter()
        .flat_map(|b| b.entries.iter().zip(&b.folders).map(|(e, f)| (f.clone(), e.name.clone())))
        .collect();
    assert_eq!(
        rows,
        [
            (String::new(), "..".to_string()),
            ("e".to_string(), "two.txt".to_string()),
            (String::new(), "one.txt".to_string())
        ]
    );
}
