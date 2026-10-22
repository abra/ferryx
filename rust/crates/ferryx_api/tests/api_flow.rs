//! The bridge end to end: listings, operations, rename, find, events.

use std::fs;
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};

use ferryx_api::api::events::{record_events, reset_for_tests, take_recorded_events};
use ferryx_api::api::types::*;
use ferryx_api::api::{files, find, listing, ops, rename};

/// The bridge's state is process-wide: the tests take turns.
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

fn names(view: &ListingView) -> Vec<&str> {
    view.entries.iter().map(|e| e.name.as_str()).collect()
}

fn wait_for(mut done: impl FnMut() -> bool) {
    let start = Instant::now();
    while !done() {
        assert!(start.elapsed() < Duration::from_secs(10), "timed out");
        std::thread::sleep(Duration::from_millis(20));
    }
}

fn request(kind: OpKindView, sources: Vec<String>, destination: Option<String>) -> OpRequestView {
    OpRequestView {
        kind,
        sources,
        archive: None,
        destination,
        new_name: None,
        conflicts: ConflictPolicyView::Ask,
        preserve_attributes: true,
        verify: true,
        password: None,
    }
}

fn s(path: &std::path::Path) -> String {
    path.to_string_lossy().into_owned()
}

#[test]
fn listings_sort_resort_and_follow_changes() {
    let _guard = serial();
    reset_for_tests();
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("b10.txt"), b"bb").unwrap();
    fs::write(dir.path().join("b2.txt"), b"b").unwrap();
    fs::create_dir(dir.path().join("zdir")).unwrap();
    fs::write(dir.path().join(".dot"), b"").unwrap();

    let view = listing::open_listing("left".into(), LocationView::native(dir.path()), options()).unwrap();
    assert_eq!(names(&view), ["..", "zdir", "b2.txt", "b10.txt"]);
    assert!(view.watched);
    assert!(view.free_bytes.unwrap() > 0);

    let mut by_size = options();
    by_size.sort.field = SortFieldView::Size;
    by_size.sort.descending = true;
    by_size.sort.folders_first = false;
    let view = listing::resort_listing("left".into(), by_size).unwrap();
    assert_eq!(names(&view), ["..", "b10.txt", "b2.txt", "zdir"]);

    let mut hidden = options();
    hidden.show_hidden = true;
    let view = listing::resort_listing("left".into(), hidden).unwrap();
    assert!(names(&view).contains(&".dot"));

    record_events();
    fs::write(dir.path().join("new.txt"), b"n").unwrap();
    wait_for(|| {
        take_recorded_events()
            .iter()
            .any(|e| e.kind == AppEventKind::DirectoryChanged && e.listing_id.as_deref() == Some("left"))
    });
    let view = listing::refresh_listing("left".into()).unwrap();
    assert!(names(&view).contains(&"new.txt"));
    listing::close_listing("left".into());
    assert!(listing::refresh_listing("left".into()).is_err());
    assert!(listing::open_listing("x".into(), LocationView::native(&dir.path().join("b2.txt")), options())
        .is_err());
}

#[test]
fn archives_open_as_folders() {
    let _guard = serial();
    reset_for_tests();
    let dir = tempfile::tempdir().unwrap();
    let src = dir.path().join("proj");
    fs::create_dir_all(src.join("sub")).unwrap();
    fs::write(src.join("sub/x.txt"), b"xyz").unwrap();
    let id = ops::start_operation(request(OpKindView::Compress, vec![s(&src)], Some(s(dir.path()))));
    wait_for(|| ops::operation_progress(id).map(|p| p.state == OpStateView::Done).unwrap_or(false));
    let archive = dir.path().join("proj.zip");
    assert!(listing::is_archive(s(&archive)));
    let location =
        LocationView { kind: LocationKind::Archive, path: "proj/sub".into(), archive: Some(s(&archive)) };
    let view = listing::open_listing("a".into(), location.clone(), options()).unwrap();
    assert_eq!(names(&view), ["..", "x.txt"]);
    assert_eq!(view.entries[0].path, "proj");
    let member = LocationView {
        kind: LocationKind::Archive,
        path: "proj/sub/x.txt".into(),
        archive: Some(s(&archive)),
    };
    assert_eq!(files::read_file_range(member.clone(), 1, 10).unwrap(), b"yz");
    assert_eq!(files::file_size(member).unwrap(), 3);
    let out = files::extract_to_temp(s(&archive), "proj/sub/x.txt".into()).unwrap();
    assert_eq!(fs::read(out).unwrap(), b"xyz");
    ops::forget_operation(id);
}

#[test]
fn operations_report_progress_and_answer_questions() {
    let _guard = serial();
    reset_for_tests();
    record_events();
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("a.txt"), b"first").unwrap();
    let dest = dir.path().join("dest");
    fs::create_dir(&dest).unwrap();
    fs::write(dest.join("a.txt"), b"old").unwrap();
    let id =
        ops::start_operation(request(OpKindView::Copy, vec![s(&dir.path().join("a.txt"))], Some(s(&dest))));
    wait_for(|| ops::operation_progress(id).map(|p| p.state == OpStateView::Waiting).unwrap_or(false));
    let progress = ops::operation_progress(id).unwrap();
    let question = progress.question.unwrap();
    assert_eq!(question.kind, QuestionKindView::Conflict);
    assert!(question.answers.contains(&AnswerView::Overwrite));
    ops::answer_operation(id, question.id, AnswerView::Overwrite);
    wait_for(|| ops::operation_progress(id).map(|p| p.state == OpStateView::Done).unwrap_or(false));
    assert_eq!(fs::read(dest.join("a.txt")).unwrap(), b"first");
    let events = take_recorded_events();
    assert!(events.iter().any(|e| e.kind == AppEventKind::OperationProgress
        && e.progress.as_ref().map(|p| p.id == id).unwrap_or(false)));
    assert!(ops::list_operations().iter().any(|p| p.id == id));
    ops::forget_operation(id);
    assert!(!ops::list_operations().iter().any(|p| p.id == id));

    // Sizes come back through the progress.
    let sizes = ops::start_operation(request(OpKindView::CalcSizes, vec![s(&dest)], None));
    wait_for(|| ops::operation_progress(sizes).map(|p| p.state == OpStateView::Done).unwrap_or(false));
    let p = ops::operation_progress(sizes).unwrap();
    assert_eq!(p.sizes[0].bytes, 5);
}

#[test]
fn batch_rename_previews_then_applies() {
    let _guard = serial();
    reset_for_tests();
    let dir = tempfile::tempdir().unwrap();
    for name in ["IMG_1.jpg", "IMG_2.jpg"] {
        fs::write(dir.path().join(name), b"").unwrap();
    }
    let items: Vec<RenameItemView> =
        ["IMG_1.jpg", "IMG_2.jpg"].iter().map(|n| RenameItemView { path: s(&dir.path().join(n)) }).collect();
    let options = RenameOptionsView {
        pattern: "[P]-[C:3].[E]".into(),
        search: String::new(),
        replace: String::new(),
        search_regex: false,
        search_case_sensitive: false,
        search_once: false,
        search_part: NamePartView::Whole,
        case: CaseTransformView::Unchanged,
        case_part: NamePartView::Whole,
        counter_start: 1,
        counter_step: 1,
        counter_width: 2,
    };
    let preview = rename::batch_rename_preview(items.clone(), options.clone()).unwrap();
    let folder = dir.path().file_name().unwrap().to_string_lossy();
    assert_eq!(preview[0].new_name, format!("{folder}-001.jpg"));
    assert_eq!(preview[1].problem, RenameProblemView::None);
    let bad = RenameOptionsView { search: "(".into(), search_regex: true, ..options };
    assert_eq!(rename::batch_rename_preview(items, bad).unwrap_err().kind, FerryxErrorKind::InvalidPattern);
    let failures = rename::batch_rename_apply(
        preview
            .iter()
            .map(|o| RenamePairView { path: o.path.clone(), new_name: o.new_name.clone() })
            .collect(),
    );
    assert!(failures.is_empty());
    assert!(dir.path().join(format!("{folder}-002.jpg")).exists());
}

#[test]
fn find_streams_hits() {
    let _guard = serial();
    reset_for_tests();
    record_events();
    let dir = tempfile::tempdir().unwrap();
    fs::create_dir_all(dir.path().join("deep/er")).unwrap();
    fs::write(dir.path().join("deep/er/needle.md"), b"hay needle hay").unwrap();
    fs::write(dir.path().join("other.md"), b"hay").unwrap();
    let id = find::start_find(FindRequestView {
        root: s(dir.path()),
        name: "*.md".into(),
        name_is_regex: false,
        content_text: Some("needle".into()),
        content_case_sensitive: false,
        content_whole_phrase: true,
        content_not_containing: false,
        size_op: None,
        size_bytes: 0,
        include_hidden: false,
        include_folders: true,
    });
    let mut hits = Vec::new();
    wait_for(|| {
        let mut done = false;
        for e in take_recorded_events() {
            if e.find_id != Some(id) {
                continue;
            }
            hits.extend(e.hits);
            done |= e.kind == AppEventKind::FindDone;
        }
        done
    });
    assert_eq!(hits.len(), 1);
    assert!(hits[0].path.ends_with("needle.md"));
    assert_eq!(hits[0].size, 14);
}
