//! Times a large folder through the bridge: `cargo test --release -p
//! ferryx_api --test listing_bench -- --ignored --nocapture`.

use std::time::{Duration, Instant};

use ferryx_api::api::listing;
use ferryx_api::api::types::*;

fn options(field: SortFieldView) -> ListingOptionsView {
    ListingOptionsView {
        show_hidden: false,
        show_parent: true,
        sort: SortOptionsView {
            field,
            descending: false,
            folders_first: true,
            extensionless_folders: true,
            collation: CollationView::Natural,
        },
    }
}

#[test]
#[ignore]
fn bench() {
    let dir = tempfile::tempdir().unwrap();
    for i in 0..100_000 {
        std::fs::write(dir.path().join(format!("file {} {i}.txt", "x".repeat(i % 13))), b"").unwrap();
    }
    // The system reports the files made above for a while; a watcher made
    // meanwhile would read them as a change of everything.
    std::thread::sleep(Duration::from_secs(5));
    let location = LocationView::native(dir.path());
    let start = Instant::now();
    let view = listing::open_listing("bench".into(), location, options(SortFieldView::Name)).unwrap();
    println!("open: {:?}, {} rows sent", start.elapsed(), view.entries.len());
    for round in 0..3 {
        std::fs::write(dir.path().join(format!("changed {round}.txt")), b"x").unwrap();
        std::thread::sleep(Duration::from_millis(1500));
        let start = Instant::now();
        let view = listing::refresh_listing("bench".into()).unwrap();
        println!("one change: {:?}, {} rows sent", start.elapsed(), view.entries.len());
    }
    let start = Instant::now();
    let view = listing::refresh_listing("bench".into()).unwrap();
    println!("read whole: {:?}, {} rows sent", start.elapsed(), view.entries.len());
    let start = Instant::now();
    let view = listing::resort_listing("bench".into(), options(SortFieldView::Size)).unwrap();
    println!("resort: {:?}, {} rows sent", start.elapsed(), view.entries.len());
    listing::close_listing("bench".into());
}
