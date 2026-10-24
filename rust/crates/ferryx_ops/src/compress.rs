//! Compress to a zip archive, optionally with an AES-256 password. Files
//! whose kind is compressed already (photos, music, video, archives) are
//! stored as they are: deflating them again costs time and saves nothing.

use std::fs::File;
use std::io::{BufWriter, Read, Write};
use std::path::{Path, PathBuf};

use ferryx_vfs::error::{IoAt, VfsError};
use ferryx_vfs::native;
use walkdir::WalkDir;
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipWriter};

use crate::runner::{free_name, OpContext};
use crate::types::*;

const BUFFER: usize = 1024 * 1024;

/// Extensions of kinds compressed already, stored without deflate. PDF is
/// left out: its streams may or may not be compressed.
const STORED: &[&str] = &[
    "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "avif", "mp3", "m4a", "aac", "flac", "ogg", "opus",
    "mp4", "m4v", "mov", "mkv", "webm", "zip", "7z", "rar", "gz", "tgz", "bz2", "xz", "zst",
];

/// How a file goes into the archive.
fn method_for(path: &Path) -> CompressionMethod {
    let stored = path
        .extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| STORED.iter().any(|kind| e.eq_ignore_ascii_case(kind)));
    if stored {
        CompressionMethod::Stored
    } else {
        CompressionMethod::Deflated
    }
}

/// The archive's name for these sources: the single source's name, else
/// the folder they are in, with `.zip`.
pub fn default_archive_name(sources: &[PathBuf]) -> String {
    let base = match sources {
        [one] => one.file_name().map(|n| n.to_string_lossy().into_owned()),
        [first, ..] => first.parent().and_then(|p| p.file_name()).map(|n| n.to_string_lossy().into_owned()),
        [] => None,
    };
    let base = base.filter(|b| !b.is_empty()).unwrap_or_else(|| "Archive".to_string());
    format!(
        "{}.zip",
        ferryx_core::entry::split_name(&base).0.trim_end_matches('.').to_string().replace('\0', "")
    )
}

pub fn run(ctx: &OpContext, request: &OpRequest) -> Result<(), Abort> {
    let Some(dest_dir) = request.destination.as_deref() else {
        ctx.record_error(Path::new(""), "no destination".to_string());
        return Err(Abort::Stopped);
    };
    let name = request
        .new_name
        .clone()
        .filter(|n| !n.is_empty())
        .unwrap_or_else(|| default_archive_name(&request.sources));
    let name = if name.to_lowercase().ends_with(".zip") { name } else { format!("{name}.zip") };
    let mut target = dest_dir.join(&name);
    if target.exists() {
        target = free_name(dest_dir, &name);
    }
    // Everything is stored relative to the sources' common folder.
    let base = request.sources.first().and_then(|s| s.parent()).map(Path::to_path_buf).unwrap_or_default();
    let mut files: Vec<(PathBuf, String, bool)> = Vec::new();
    let mut total = 0u64;
    for source in &request.sources {
        ctx.check()?;
        for entry in WalkDir::new(source).follow_links(false).into_iter().filter_map(Result::ok) {
            let relative =
                entry.path().strip_prefix(&base).unwrap_or(entry.path()).to_string_lossy().replace('\\', "/");
            let is_dir = entry.file_type().is_dir();
            if entry.file_type().is_file() {
                total += entry.metadata().map(|m| m.len()).unwrap_or(0);
            }
            if !entry.file_type().is_symlink() {
                files.push((entry.path().to_path_buf(), relative, is_dir));
            }
        }
    }
    ctx.set_totals(total, files.len() as u64);
    ctx.update(|p| p.result_path = Some(target.clone()));
    let file = match File::create(&target) {
        Ok(f) => f,
        Err(e) => {
            ctx.record_error(&target, VfsError::io(&e, &target).message);
            return Err(Abort::Stopped);
        }
    };
    let mut zip = ZipWriter::new(BufWriter::with_capacity(BUFFER, file));
    let outcome = write_all(ctx, &mut zip, &files, request.options.password.as_deref());
    match outcome {
        Ok(()) => match zip
            .finish()
            .map_err(|e| e.to_string())
            .and_then(|written| written.into_inner().map(drop).map_err(|e| e.error().to_string()))
        {
            Ok(()) => {
                ctx.record_created(&target);
                Ok(())
            }
            Err(message) => {
                ctx.record_error(&target, message);
                let _ = std::fs::remove_file(&target);
                Err(Abort::Stopped)
            }
        },
        Err(abort) => {
            drop(zip);
            let _ = std::fs::remove_file(&target);
            Err(abort)
        }
    }
}

fn write_all(
    ctx: &OpContext,
    zip: &mut ZipWriter<BufWriter<File>>,
    files: &[(PathBuf, String, bool)],
    password: Option<&str>,
) -> Result<(), Abort> {
    let mut buffer = vec![0u8; BUFFER];
    for (path, relative, is_dir) in files {
        ctx.check()?;
        ctx.set_current(path);
        let meta = match std::fs::metadata(path) {
            Ok(m) => m,
            Err(e) => {
                ctx.ask_error(path, &VfsError::io(&e, path))?;
                continue;
            }
        };
        let mut options = SimpleFileOptions::default()
            .compression_method(method_for(path))
            .large_file(meta.len() >= u32::MAX as u64);
        if let Some(mode) = unix_mode(&meta) {
            options = options.unix_permissions(mode);
        }
        if let Some(time) = meta.modified().ok().and_then(zip_time) {
            options = options.last_modified_time(time);
        }
        if let Some(password) = password {
            options = options.with_aes_encryption(zip::AesMode::Aes256, password);
        }
        let result: Result<(), VfsError> = (|| {
            if *is_dir {
                zip.add_directory(relative.as_str(), options)
                    .map_err(|e| VfsError::new(ferryx_vfs::VfsErrorKind::Io, Some(path), e.to_string()))?;
                return Ok(());
            }
            zip.start_file(relative.as_str(), options)
                .map_err(|e| VfsError::new(ferryx_vfs::VfsErrorKind::Io, Some(path), e.to_string()))?;
            let mut input = File::open(path).at(path)?;
            loop {
                ctx.check().map_err(|_| VfsError::cancelled())?;
                let read = match input.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(n) => n,
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(e) => return Err(VfsError::io(&e, path)),
                };
                zip.write_all(&buffer[..read]).at(path)?;
                ctx.add_bytes(read as u64);
            }
            Ok(())
        })();
        match result {
            Ok(()) => ctx.item_done(),
            Err(e) if e.kind == ferryx_vfs::VfsErrorKind::Cancelled => return Err(Abort::Cancelled),
            Err(e) => {
                // The entry is left half written; the error is on record.
                ctx.ask_error(path, &e)?;
            }
        }
    }
    Ok(())
}

#[cfg(unix)]
fn unix_mode(meta: &std::fs::Metadata) -> Option<u32> {
    use std::os::unix::fs::MetadataExt;
    Some(meta.mode() & 0o7777)
}

#[cfg(not(unix))]
fn unix_mode(_meta: &std::fs::Metadata) -> Option<u32> {
    None
}

fn zip_time(time: std::time::SystemTime) -> Option<zip::DateTime> {
    let ms = native::system_time_ms(time)?;
    let secs = ms.div_euclid(1000);
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    zip::DateTime::from_date_and_time(
        y as u16,
        m as u8,
        d as u8,
        (rem / 3600) as u8,
        ((rem % 3600) / 60) as u8,
        (rem % 60) as u8,
    )
    .ok()
}

/// Howard Hinnant's days-to-civil, for a zip's local-less time stamp.
fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn makes_a_zip_with_the_tree() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("proj");
        fs::create_dir_all(src.join("sub")).unwrap();
        fs::write(src.join("a.txt"), b"aaa").unwrap();
        fs::write(src.join("sub/b.txt"), b"bb").unwrap();
        let req = OpRequest {
            kind: OpKind::Compress,
            sources: vec![src.clone()],
            archive: None,
            destination: Some(dir.path().to_path_buf()),
            new_name: None,
            options: OpOptions::default(),
        };
        let ctx = OpContext::detached(&req);
        run(&ctx, &req).unwrap();
        let p = ctx.snapshot();
        let archive = p.result_path.unwrap();
        assert_eq!(archive.file_name().unwrap(), "proj.zip");
        assert_eq!(p.bytes_done, 5);
        let index = ferryx_vfs::archive::ArchiveIndex::open(&archive).unwrap();
        assert_eq!(index.read("proj/sub/b.txt").unwrap(), b"bb");
        // A second run keeps the first archive and takes a free name.
        run(&OpContext::detached(&req), &req).unwrap();
        assert!(dir.path().join("proj 2.zip").exists());
    }

    #[test]
    fn password_protects() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("s.txt"), b"secret").unwrap();
        let req = OpRequest {
            kind: OpKind::Compress,
            sources: vec![dir.path().join("s.txt")],
            archive: None,
            destination: Some(dir.path().to_path_buf()),
            new_name: Some("locked".to_string()),
            options: OpOptions { password: Some("pw".to_string()), ..Default::default() },
        };
        run(&OpContext::detached(&req), &req).unwrap();
        let index = ferryx_vfs::archive::ArchiveIndex::open(&dir.path().join("locked.zip")).unwrap();
        assert!(index.member("s.txt").unwrap().encrypted);
        assert!(index.read("s.txt").is_err());
    }

    #[test]
    fn stores_what_is_compressed_already() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("media");
        fs::create_dir_all(&src).unwrap();
        let text = b"words words words words ".repeat(200);
        fs::write(src.join("notes.txt"), &text).unwrap();
        fs::write(src.join("photo.JPG"), &text).unwrap();
        fs::write(src.join("report.pdf"), &text).unwrap();
        for password in [None, Some("pw")] {
            let req = OpRequest {
                kind: OpKind::Compress,
                sources: vec![src.clone()],
                archive: None,
                destination: Some(dir.path().to_path_buf()),
                new_name: Some(format!("media-{}", password.is_some())),
                options: OpOptions { password: password.map(str::to_string), ..Default::default() },
            };
            let ctx = OpContext::detached(&req);
            run(&ctx, &req).unwrap();
            let archive = ctx.snapshot().result_path.unwrap();
            let mut zip = zip::ZipArchive::new(File::open(&archive).unwrap()).unwrap();
            let mut method = |name: &str| {
                let at = zip.index_for_name(name).unwrap();
                zip.by_index_raw(at).unwrap().compression()
            };
            assert_eq!(method("media/notes.txt"), CompressionMethod::Deflated);
            assert_eq!(method("media/photo.JPG"), CompressionMethod::Stored);
            assert_eq!(method("media/report.pdf"), CompressionMethod::Deflated);
            let index = ferryx_vfs::archive::ArchiveIndex::open(&archive).unwrap();
            for name in ["media/notes.txt", "media/photo.JPG", "media/report.pdf"] {
                assert_eq!(index.member(name).unwrap().encrypted, password.is_some());
                assert_eq!(index.read_with(name, password).unwrap(), text, "{name}");
            }
        }
    }

    /// Times compressing a generated folder of text and of media already
    /// compressed (random bytes as `.jpg` and `.mp4`), with and without a
    /// password: `cargo test --release -p ferryx_ops compress_bench --
    /// --ignored --nocapture`.
    #[test]
    #[ignore]
    fn compress_bench() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("src");
        fs::create_dir_all(&src).unwrap();
        let mut seed = 0x9e37_79b9_7f4a_7c15u64;
        let mut random = |len: usize| {
            let mut out = vec![0u8; len];
            for chunk in out.chunks_mut(8) {
                seed ^= seed << 13;
                seed ^= seed >> 7;
                seed ^= seed << 17;
                chunk.copy_from_slice(&seed.to_le_bytes()[..chunk.len()]);
            }
            out
        };
        let line = "fn main() { println!(\"a line of source text, repeated\"); }\n";
        for i in 0..100 {
            fs::write(src.join(format!("text{i}.rs")), line.repeat((1 << 20) / line.len())).unwrap();
        }
        for i in 0..50 {
            fs::write(src.join(format!("photo{i}.jpg")), random(4 << 20)).unwrap();
        }
        for i in 0..10 {
            fs::write(src.join(format!("clip{i}.mp4")), random(16 << 20)).unwrap();
        }
        for password in [None, Some("pw")] {
            let start = std::time::Instant::now();
            let req = OpRequest {
                kind: OpKind::Compress,
                sources: vec![src.clone()],
                archive: None,
                destination: Some(dir.path().to_path_buf()),
                new_name: Some(if password.is_some() { "locked" } else { "open" }.to_string()),
                options: OpOptions { password: password.map(str::to_string), ..Default::default() },
            };
            let ctx = OpContext::detached(&req);
            run(&ctx, &req).unwrap();
            let elapsed = start.elapsed();
            let archive = ctx.snapshot().result_path.unwrap();
            let size = fs::metadata(&archive).unwrap().len();
            println!("password {}: {elapsed:?}, {} MB", password.is_some(), size >> 20);
        }
    }

    #[test]
    fn civil_dates() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(civil_from_days(19_723), (2024, 1, 1));
        assert_eq!(default_archive_name(&[PathBuf::from("/a/b/c.txt")]), "c.zip");
        assert_eq!(default_archive_name(&[PathBuf::from("/a/b/c.txt"), PathBuf::from("/a/b/d")]), "b.zip");
    }
}
