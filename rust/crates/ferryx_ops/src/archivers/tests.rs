use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant};

use super::*;
use crate::{ConflictPolicy, OpKind, OpOptions, OpRequest, OpState, Progress, Runner};

fn request(kind: OpKind, sources: Vec<PathBuf>, destination: &Path) -> OpRequest {
    OpRequest {
        kind,
        sources,
        archive: None,
        destination: Some(destination.into()),
        new_name: Some("result".into()),
        options: OpOptions {
            conflicts: ConflictPolicy::KeepBoth,
            preserve_attributes: true,
            ..Default::default()
        },
    }
}

fn finished(runner: &Runner, id: u64) -> Progress {
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        let progress = runner.progress(id).unwrap();
        if progress.state.is_finished() {
            return progress;
        }
        if Instant::now() >= deadline {
            runner.cancel(id);
            panic!("archiver timed out: {progress:?}");
        }
        assert_ne!(progress.state, OpState::Waiting, "unexpected question: {progress:?}");
        thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn installed_writers_roundtrip_literal_names_without_shell_expansion() {
    let tools = catalog::discover(Vec::new());
    for (engine, format) in [
        (Engine::SevenZip, "7z"),
        (Engine::SevenZip, "zip"),
        (Engine::Tar, "tar"),
        (Engine::Tar, "tar.gz"),
        (Engine::BsdTar, "tar"),
        (Engine::BsdTar, "tar.gz"),
        (Engine::BsdTar, "tar.zst"),
        (Engine::Zip, "zip"),
    ] {
        let Some(tool) = tools.iter().find(|t| t.engine == engine) else { continue };
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("input");
        fs::create_dir(&input).unwrap();
        let names = ["a spaces.txt", "-leading.txt", "@list.txt", "имя.txt", "$(not-a-command).txt"];
        let sources: Vec<_> = names
            .iter()
            .map(|name| {
                let p = input.join(name);
                fs::write(&p, name).unwrap();
                p
            })
            .collect();
        let runner = Runner::new();
        let configured = matches!(engine, Engine::SevenZip | Engine::BsdTar | Engine::Zip);
        let options = Options {
            level: configured.then_some(1),
            threads: matches!(engine, Engine::SevenZip | Engine::BsdTar).then_some(2),
            solid: (engine == Engine::SevenZip).then_some(true),
            ..Default::default()
        };
        let id = start_with_options(
            &runner,
            request(OpKind::Compress, sources.clone(), directory.path()),
            tool.clone(),
            format.into(),
            options,
        );
        let done = finished(&runner, id);
        assert_eq!(done.state, OpState::Done, "{}: {:?}", tool.path.display(), done.errors);
        let archive = directory.path().join(format!("result.{format}"));
        assert!(archive.is_file());
        let output = directory.path().join("output");
        let extractor = if engine == Engine::Zip {
            tools.iter().find(|t| t.engine == Engine::Unzip).unwrap()
        } else {
            tool
        };
        let id = start(
            &runner,
            request(OpKind::Extract, vec![archive], &output),
            extractor.clone(),
            String::new(),
        );
        let done = finished(&runner, id);
        assert_eq!(done.state, OpState::Done, "{format}: {:?}", done.errors);
        for name in names {
            assert_eq!(fs::read_to_string(output.join(name)).unwrap(), name);
        }
        assert!(!runner.journal().summary().undo.is_none());
    }
}

#[test]
fn stream_compressors_roundtrip_files_and_tar_trees_with_options() {
    let tools = catalog::discover(Vec::new());
    for tool in tools.iter().filter(|tool| tool.engine.is_stream()) {
        for format in tool.engine.formats() {
            let directory = tempfile::tempdir().unwrap();
            let source = directory.path().join("данные - @file.txt");
            let contents = "literal data with spaces and Unicode\n".repeat(10_000);
            fs::write(&source, &contents).unwrap();
            let (sources, expected) = if format.starts_with("tar.") {
                let folder = directory.path().join("folder");
                fs::create_dir(&folder).unwrap();
                fs::write(folder.join("inside.txt"), &contents).unwrap();
                (vec![folder, source.clone()], "folder/inside.txt")
            } else {
                (vec![source.clone()], "result")
            };
            let threads =
                matches!(tool.engine, Engine::Pigz | Engine::Pbzip2 | Engine::Xz | Engine::Zstd).then_some(2);
            let arguments = if tool.engine == Engine::Zstd { vec!["--long=20".into()] } else { Vec::new() };
            let options = Options { level: Some(1), threads, arguments, ..Default::default() };
            let runner = Runner::new();
            let id = start_with_options(
                &runner,
                request(OpKind::Compress, sources, directory.path()),
                tool.clone(),
                (*format).into(),
                options.clone(),
            );
            let done = finished(&runner, id);
            assert_eq!(done.state, OpState::Done, "{} {format}: {:?}", tool.path.display(), done.errors);
            assert_eq!(fs::read_to_string(&source).unwrap(), contents, "source must be kept");
            let output = directory.path().join("output");
            let archive = directory.path().join(format!("result.{format}"));
            let id = start_with_options(
                &runner,
                request(OpKind::Extract, vec![archive], &output),
                tool.clone(),
                String::new(),
                options,
            );
            let done = finished(&runner, id);
            assert_eq!(done.state, OpState::Done, "{} {format}: {:?}", tool.path.display(), done.errors);
            assert_eq!(fs::read_to_string(output.join(expected)).unwrap(), contents);
            assert!(runner.journal().summary().undo.is_some());
        }
    }
}

#[test]
fn configured_zip_applies_its_level_and_rejects_unsafe_options() {
    let directory = tempfile::tempdir().unwrap();
    let source = directory.path().join("source.txt");
    fs::write(&source, "data".repeat(10_000)).unwrap();
    let runner = Runner::new();
    let id = start_configured_zip(
        &runner,
        request(OpKind::Compress, vec![source.clone()], directory.path()),
        Options { level: Some(0), ..Default::default() },
    );
    assert_eq!(finished(&runner, id).state, OpState::Done);
    let mut zip = zip::ZipArchive::new(fs::File::open(directory.path().join("result.zip")).unwrap()).unwrap();
    assert_eq!(zip.by_index(0).unwrap().compression(), zip::CompressionMethod::Stored);
    let id = start_configured_zip(
        &runner,
        request(OpKind::Compress, vec![source], directory.path()),
        Options { arguments: vec!["--rm".into()], ..Default::default() },
    );
    assert_ne!(finished(&runner, id).state, OpState::Done);
}

#[test]
fn stream_tar_paths_stay_in_staging_and_bad_streams_are_not_published() {
    let Some(tool) = catalog::discover(Vec::new()).into_iter().find(|t| t.engine == Engine::Gzip) else {
        return;
    };
    let directory = tempfile::tempdir().unwrap();
    let sentinel = directory.path().join("sentinel.txt");
    fs::write(&sentinel, "keep original").unwrap();
    let source = directory.path().join("input.tar");
    let mut builder = tar::Builder::new(fs::File::create(&source).unwrap());
    let mut header = tar::Header::new_gnu();
    header.set_size(6);
    header.set_mode(0o644);
    let path = b"../sentinel.txt";
    header.as_mut_bytes()[..path.len()].copy_from_slice(path);
    header.set_cksum();
    builder.append(&header, &b"attack"[..]).unwrap();
    builder.finish().unwrap();
    drop(builder);
    let runner = Runner::new();
    let mut job = request(OpKind::Compress, vec![source], directory.path());
    job.new_name = Some("paths.tar.gz".into());
    let id = start(&runner, job, tool.clone(), "gz".into());
    assert_eq!(finished(&runner, id).state, OpState::Done);
    let output = directory.path().join("output");
    let id = start(
        &runner,
        request(OpKind::Extract, vec![directory.path().join("paths.tar.gz")], &output),
        tool.clone(),
        String::new(),
    );
    finished(&runner, id);
    assert_eq!(fs::read_to_string(&sentinel).unwrap(), "keep original");
    let invalid = directory.path().join("broken.gz");
    fs::write(&invalid, "invalid gzip data").unwrap();
    let id = start(&runner, request(OpKind::Extract, vec![invalid], &output), tool, String::new());
    assert_ne!(finished(&runner, id).state, OpState::Done);
    assert!(fs::read_dir(output).unwrap().next().is_none());
}

#[test]
fn seven_zip_password_roundtrip_uses_stdin_and_keeps_existing_output() {
    let Some(tool) = catalog::discover(Vec::new()).into_iter().find(|t| t.engine == Engine::SevenZip) else {
        return;
    };
    for format in ["7z", "zip"] {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("private.txt");
        fs::write(&input, "private contents").unwrap();
        let secret = if format == "zip" { "ZIP secret spaces $()" } else { "секрет spaces $()" };
        let mut job = request(OpKind::Compress, vec![input], directory.path());
        job.options.password = Some(secret.into());
        let runner = Runner::new();
        let id = start(&runner, job, tool.clone(), format.into());
        let done = finished(&runner, id);
        assert_eq!(done.state, OpState::Done, "{format}: {:?}", done.errors);
        let output = directory.path().join("output");
        fs::create_dir(&output).unwrap();
        fs::write(output.join("private.txt"), "keep this").unwrap();
        let mut job =
            request(OpKind::Extract, vec![directory.path().join(format!("result.{format}"))], &output);
        job.options.password = Some(secret.into());
        let id = start(&runner, job, tool.clone(), String::new());
        let done = finished(&runner, id);
        assert_eq!(done.state, OpState::Done, "{format}: {:?}", done.errors);
        assert_eq!(fs::read_to_string(output.join("private.txt")).unwrap(), "keep this");
        assert_eq!(fs::read_to_string(output.join("private 2.txt")).unwrap(), "private contents");
        assert!(fs::read_dir(&output).unwrap().all(|entry| !entry
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".ferryx-archive-")));
    }
}

#[cfg(unix)]
#[test]
fn cancellation_kills_the_worker_group_and_removes_unpublished_output() {
    use std::os::unix::fs::PermissionsExt;
    let directory = tempfile::tempdir().unwrap();
    let executable = directory.path().join("slow");
    fs::write(&executable, "#!/bin/sh\nsleep 30\n").unwrap();
    fs::set_permissions(&executable, fs::Permissions::from_mode(0o755)).unwrap();
    let input = directory.path().join("input");
    fs::write(&input, "data").unwrap();
    let tool = Tool { name: "Slow test".into(), path: executable, engine: Engine::SevenZip };
    let runner = Runner::new();
    let id = start(&runner, request(OpKind::Compress, vec![input], directory.path()), tool, "7z".into());
    thread::sleep(Duration::from_millis(100));
    let began = Instant::now();
    runner.cancel(id);
    assert_eq!(finished(&runner, id).state, OpState::Cancelled);
    assert!(began.elapsed() < Duration::from_secs(2));
    assert!(!directory.path().join("result.7z").exists());
}

#[test]
fn external_extractors_do_not_write_through_archive_paths_or_symlinks() {
    let tools = catalog::discover(Vec::new());
    for tool in tools.iter().filter(|tool| matches!(tool.engine, Engine::SevenZip | Engine::Unzip)) {
        let directory = tempfile::tempdir().unwrap();
        let outside = directory.path().join("outside");
        fs::create_dir(&outside).unwrap();
        let sentinel = outside.join("sentinel.txt");
        fs::write(&sentinel, "keep original").unwrap();
        let archive = directory.path().join("paths.zip");
        let file = fs::File::create(&archive).unwrap();
        let mut zip = zip::ZipWriter::new(file);
        let options = zip::write::SimpleFileOptions::default();
        zip.start_file(sentinel.to_string_lossy(), options).unwrap();
        zip.write_all(b"absolute path attack").unwrap();
        #[cfg(unix)]
        {
            zip.add_symlink("link", outside.to_string_lossy(), options).unwrap();
            zip.start_file("link/sentinel.txt", options).unwrap();
            zip.write_all(b"symlink attack").unwrap();
        }
        zip.finish().unwrap();
        let runner = Runner::new();
        let id = start(
            &runner,
            request(OpKind::Extract, vec![archive], &directory.path().join("out")),
            tool.clone(),
            String::new(),
        );
        finished(&runner, id);
        assert_eq!(
            fs::read_to_string(&sentinel).unwrap(),
            "keep original",
            "{} escaped its staging directory",
            tool.path.display()
        );
    }
}
