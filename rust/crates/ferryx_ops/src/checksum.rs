//! Checksums: the hashes of files (folders walked) for a table and a
//! checksum file, and the check of a checksum file against the files it
//! lists.
//!
//! Checksum files are read in the GNU coreutils form (`hash  name`, or
//! `hash *name` for binary mode, a leading `\` when the name has a
//! backslash or a line break escaped) and the BSD tag form
//! (`SHA256 (name) = hash`), and written in the GNU form with names
//! relative to the file's folder.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use ferryx_core::mask::NameFilter;
use ferryx_vfs::VfsError;
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

use crate::hashing::{self, Algorithm, HashError};

/// Hash the files under `paths`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChecksumRequest {
    /// Files, and folders whose files are hashed.
    pub paths: Vec<PathBuf>,
    /// The folder names are relative to (the panel's folder).
    pub base: PathBuf,
    pub algorithm: Algorithm,
    /// Folders are walked to the bottom; else only their own files count.
    pub recursive: bool,
    pub include_hidden: bool,
}

/// One file of a checksum table.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChecksumFile {
    pub path: PathBuf,
    /// The path relative to the base, with `/`.
    pub name: String,
    pub size: u64,
    /// Checking a checksum file: the hash it lists.
    pub expected: Option<String>,
}

/// How a file fared.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChecksumStatus {
    /// Hashed (and, when checked, the hash matches).
    Ok,
    /// Checked: the hash differs from the one listed.
    Mismatch,
    /// Checked: the file listed is not there.
    Missing,
    /// It could not be read.
    Error,
}

/// One file's outcome, by its index among the files.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChecksumOutcome {
    pub index: usize,
    pub status: ChecksumStatus,
    pub hash: Option<String>,
    pub error: Option<VfsError>,
}

/// Where a run is, for the progress line.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChecksumProgress {
    pub files_done: u64,
    pub files_total: u64,
    pub bytes_done: u64,
    pub bytes_total: u64,
    pub current: Option<String>,
}

/// The files of `request`, in the order the targets came and by name
/// inside each folder; links are not followed into folders.
pub fn expand(request: &ChecksumRequest, cancel: &AtomicBool) -> Vec<ChecksumFile> {
    let mut out = Vec::new();
    for path in &request.paths {
        if cancel.load(Ordering::Relaxed) {
            break;
        }
        let Ok(meta) = std::fs::metadata(path) else {
            out.push(ChecksumFile {
                path: path.clone(),
                name: relative(&request.base, path),
                size: 0,
                expected: None,
            });
            continue;
        };
        if !meta.is_dir() {
            out.push(ChecksumFile {
                path: path.clone(),
                name: relative(&request.base, path),
                size: meta.len(),
                expected: None,
            });
            continue;
        }
        let mut walker = WalkDir::new(path).follow_links(false).min_depth(1).sort_by_file_name();
        if !request.recursive {
            walker = walker.max_depth(1);
        }
        let include_hidden = request.include_hidden;
        let entries = walker
            .into_iter()
            .filter_entry(move |e| include_hidden || !e.file_name().to_string_lossy().starts_with('.'));
        for (n, entry) in entries.enumerate() {
            if n % 256 == 0 && cancel.load(Ordering::Relaxed) {
                break;
            }
            let Ok(entry) = entry else { continue };
            if !entry.file_type().is_file() {
                continue;
            }
            let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
            out.push(ChecksumFile {
                name: relative(&request.base, entry.path()),
                path: entry.into_path(),
                size,
                expected: None,
            });
        }
    }
    out
}

/// `path` relative to `base` with `/`, or the whole path when it is not
/// under it.
pub fn relative(base: &Path, path: &Path) -> String {
    let rest = path.strip_prefix(base).unwrap_or(path);
    let text = rest.to_string_lossy();
    if std::path::MAIN_SEPARATOR == '/' {
        text.into_owned()
    } else {
        text.replace(std::path::MAIN_SEPARATOR, "/")
    }
}

/// Hashes `files` on a few workers. `on_outcome` gets each file's result
/// as it comes; `on_progress` is called at most every `every` with the
/// counts and the file being read. A file with `expected` set is checked
/// against it. Stops when `cancel` is set.
pub fn hash_all(
    files: &[ChecksumFile],
    algorithm: Algorithm,
    cancel: &AtomicBool,
    every: Duration,
    on_outcome: &mut dyn FnMut(ChecksumOutcome),
    on_progress: &mut dyn FnMut(&ChecksumProgress),
) {
    let bytes_done = std::sync::atomic::AtomicU64::new(0);
    let mut progress = ChecksumProgress {
        files_total: files.len() as u64,
        bytes_total: files.iter().map(|f| f.size).sum(),
        ..Default::default()
    };
    let mut last = Instant::now();
    hashing::parallel(
        files,
        hashing::workers(),
        cancel,
        |file, buffer| {
            hashing::hash_file(&file.path, algorithm, None, buffer, cancel, &mut |n| {
                bytes_done.fetch_add(n, Ordering::Relaxed);
            })
        },
        |event| {
            if let Some((index, result)) = event {
                let file = &files[index];
                let outcome = match result {
                    Ok(hash) => {
                        let status = match &file.expected {
                            Some(expected) if !expected.eq_ignore_ascii_case(&hash) => {
                                ChecksumStatus::Mismatch
                            }
                            _ => ChecksumStatus::Ok,
                        };
                        ChecksumOutcome { index, status, hash: Some(hash), error: None }
                    }
                    Err(HashError::Cancelled) => return,
                    Err(HashError::Io(e)) => ChecksumOutcome {
                        index,
                        status: if e.kind == ferryx_vfs::VfsErrorKind::NotFound && file.expected.is_some() {
                            ChecksumStatus::Missing
                        } else {
                            ChecksumStatus::Error
                        },
                        hash: None,
                        error: Some(e),
                    },
                };
                on_outcome(outcome);
                progress.files_done += 1;
                progress.current = Some(file.name.clone());
            }
            // A big file still shows its bytes while nothing finishes.
            if last.elapsed() >= every {
                progress.bytes_done = bytes_done.load(Ordering::Relaxed);
                on_progress(&progress);
                last = Instant::now();
            }
        },
    );
    progress.bytes_done = bytes_done.load(Ordering::Relaxed);
    progress.current = None;
    on_progress(&progress);
}

// ─── Checksum files ───

/// The algorithm a checksum file's name says (`x.sha256`, `SHA1SUMS`,
/// `MD5SUMS.txt`, `x.b3`).
pub fn algorithm_of_name(name: &str) -> Option<Algorithm> {
    let lower = name.to_lowercase();
    let stem_and_ext = lower.rsplit_once('.');
    let ext = stem_and_ext.map(|(_, e)| e).unwrap_or("");
    let by_ext = match ext {
        "sha256" | "sha256sum" | "sha256sums" => Some(Algorithm::Sha256),
        "sha1" | "sha1sum" | "sha1sums" => Some(Algorithm::Sha1),
        "md5" | "md5sum" | "md5sums" => Some(Algorithm::Md5),
        "b3" | "b3sum" | "b3sums" | "blake3" => Some(Algorithm::Blake3),
        _ => None,
    };
    if by_ext.is_some() {
        return by_ext;
    }
    let stem = stem_and_ext.map(|(s, _)| s).filter(|_| ext == "txt").unwrap_or(&lower);
    match stem {
        "sha256sums" | "sha256sum" => Some(Algorithm::Sha256),
        "sha1sums" | "sha1sum" => Some(Algorithm::Sha1),
        "md5sums" | "md5sum" => Some(Algorithm::Md5),
        "b3sums" | "blake3sums" => Some(Algorithm::Blake3),
        _ => None,
    }
}

/// Whether a file of this name is a checksum file the command checks.
pub fn is_checksum_file(name: &str) -> bool {
    algorithm_of_name(name).is_some()
}

/// One line of a checksum file.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SumsEntry {
    /// The hash listed, lower case.
    pub hash: String,
    pub name: String,
    /// The algorithm a BSD tag line names.
    pub tagged: Option<Algorithm>,
}

/// The lines of a checksum file that list a file; answers them and how
/// many lines could not be read (comments and blank lines aside).
pub fn parse_sums(text: &str) -> (Vec<SumsEntry>, usize) {
    let mut entries = Vec::new();
    let mut bad = 0;
    for raw in text.lines() {
        let line = raw.trim_end_matches('\r');
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        match parse_line(line) {
            Some(entry) => entries.push(entry),
            None => bad += 1,
        }
    }
    (entries, bad)
}

fn parse_line(line: &str) -> Option<SumsEntry> {
    let (escaped, line) = match line.strip_prefix('\\') {
        Some(rest) => (true, rest),
        None => (false, line),
    };
    // BSD: `SHA256 (name) = hash`.
    if let Some((head, hash)) = line.rsplit_once(") = ") {
        if let Some((tag, name)) = head.split_once(" (") {
            let tagged = Algorithm::ALL.into_iter().find(|a| a.tag().eq_ignore_ascii_case(tag.trim()));
            if tagged.is_some() && is_hex(hash.trim()) {
                let name = if escaped { unescape(name) } else { name.to_string() };
                return Some(SumsEntry { hash: hash.trim().to_lowercase(), name, tagged });
            }
        }
    }
    // GNU: `hash␠␠name` or `hash␠*name`.
    let (hash, rest) = line.split_once(' ')?;
    if !is_hex(hash) {
        return None;
    }
    let name = rest.strip_prefix(' ').or_else(|| rest.strip_prefix('*')).unwrap_or(rest);
    if name.is_empty() {
        return None;
    }
    let name = if escaped { unescape(name) } else { name.to_string() };
    Some(SumsEntry { hash: hash.to_lowercase(), name, tagged: None })
}

fn is_hex(text: &str) -> bool {
    !text.is_empty() && text.len() % 2 == 0 && text.bytes().all(|b| b.is_ascii_hexdigit())
}

fn unescape(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    let mut chars = name.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('r') => out.push('\r'),
            Some(other) => out.push(other),
            None => out.push('\\'),
        }
    }
    out
}

/// The algorithm of a checksum file: a tag line's, else the name's, else
/// the hashes' length (64 digits read as SHA-256).
pub fn algorithm_of(name: &str, entries: &[SumsEntry]) -> Option<Algorithm> {
    if let Some(tagged) = entries.iter().find_map(|e| e.tagged) {
        return Some(tagged);
    }
    if let Some(by_name) = algorithm_of_name(name) {
        return Some(by_name);
    }
    match entries.first()?.hash.len() {
        32 => Some(Algorithm::Md5),
        40 => Some(Algorithm::Sha1),
        64 => Some(Algorithm::Sha256),
        _ => None,
    }
}

/// What a checksum file lists, ready to hash: each file under the sums
/// file's folder with the hash it should have.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SumsFile {
    pub algorithm: Algorithm,
    pub files: Vec<ChecksumFile>,
    /// Lines that list nothing readable.
    pub bad_lines: usize,
}

/// Biggest checksum file read; a bigger one is not a checksum file.
const SUMS_LIMIT: u64 = 64 * 1024 * 1024;

/// Reads the checksum file at `path`.
pub fn read_sums(path: &Path) -> Result<SumsFile, String> {
    let meta = std::fs::metadata(path).map_err(|e| ferryx_vfs::VfsError::io(&e, path).message)?;
    if meta.len() > SUMS_LIMIT {
        return Err(format!("{} is too big for a checksum file", path.display()));
    }
    let bytes = std::fs::read(path).map_err(|e| ferryx_vfs::VfsError::io(&e, path).message)?;
    let text = String::from_utf8_lossy(&bytes);
    let (entries, bad_lines) = parse_sums(&text);
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let algorithm =
        algorithm_of(&name, &entries).ok_or_else(|| format!("{} lists no checksums", path.display()))?;
    let base = path.parent().unwrap_or(Path::new("/"));
    let files = entries
        .into_iter()
        .map(|entry| {
            let file = base.join(&entry.name);
            let size = std::fs::metadata(&file).map(|m| m.len()).unwrap_or(0);
            ChecksumFile { path: file, name: entry.name, size, expected: Some(entry.hash) }
        })
        .collect();
    Ok(SumsFile { algorithm, files, bad_lines })
}

/// A checksum file in the GNU form: `hash␠␠name` a line, a name with a
/// backslash or a line break escaped behind a leading `\`.
pub fn format_sums(lines: &[(String, String)]) -> String {
    let mut out = String::new();
    for (hash, name) in lines {
        if name.contains(['\\', '\n', '\r']) {
            let escaped = name.replace('\\', "\\\\").replace('\n', "\\n").replace('\r', "\\r");
            out.push('\\');
            out.push_str(hash);
            out.push_str("  ");
            out.push_str(&escaped);
        } else {
            out.push_str(hash);
            out.push_str("  ");
            out.push_str(name);
        }
        out.push('\n');
    }
    out
}

/// A name mask as the dialogs take it, for the modules that filter by
/// name; empty for every name.
pub(crate) fn name_filter(mask: &str) -> Result<Option<NameFilter>, String> {
    if mask.trim().is_empty() {
        Ok(None)
    } else {
        NameFilter::mask(mask.trim()).map(Some)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn names_tell_the_algorithm() {
        assert_eq!(algorithm_of_name("disk.iso.sha256"), Some(Algorithm::Sha256));
        assert_eq!(algorithm_of_name("SHA256SUMS"), Some(Algorithm::Sha256));
        assert_eq!(algorithm_of_name("sha1sums.txt"), Some(Algorithm::Sha1));
        assert_eq!(algorithm_of_name("MD5SUMS"), Some(Algorithm::Md5));
        assert_eq!(algorithm_of_name("x.md5"), Some(Algorithm::Md5));
        assert_eq!(algorithm_of_name("x.b3"), Some(Algorithm::Blake3));
        assert_eq!(algorithm_of_name("B3SUMS"), Some(Algorithm::Blake3));
        assert_eq!(algorithm_of_name("notes.txt"), None);
        assert_eq!(algorithm_of_name("sha256"), None);
        assert!(!is_checksum_file("readme.md"));
    }

    #[test]
    fn parses_both_forms_and_escapes() {
        let text = "\
# made by hand
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  a b.txt
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015AD *bin.dat
\\ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  odd\\\\name\\nline
SHA256 (tagged (1).txt) = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
not a line

nothinghex  x
";
        let (entries, bad) = parse_sums(text);
        assert_eq!(bad, 2);
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert_eq!(names, ["a b.txt", "bin.dat", "odd\\name\nline", "tagged (1).txt"]);
        assert!(entries.iter().all(|e| e.hash == entries[0].hash));
        assert_eq!(entries[3].tagged, Some(Algorithm::Sha256));
        assert_eq!(algorithm_of("list", &entries), Some(Algorithm::Sha256));
    }

    #[test]
    fn writes_what_it_reads() {
        let lines = vec![
            ("00ff".to_string(), "plain.txt".to_string()),
            ("aa11".to_string(), "back\\slash\nbreak".to_string()),
        ];
        let text = format_sums(&lines);
        assert_eq!(text, "00ff  plain.txt\n\\aa11  back\\\\slash\\nbreak\n");
        let (entries, bad) = parse_sums(&text);
        assert_eq!(bad, 0);
        assert_eq!(entries[1].name, "back\\slash\nbreak");
    }

    #[test]
    fn hashes_a_tree_and_checks_a_sums_file() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("sub/.hidden")).unwrap();
        fs::write(dir.path().join("a.txt"), b"abc").unwrap();
        fs::write(dir.path().join("sub/b.txt"), b"abc").unwrap();
        fs::write(dir.path().join("sub/.hidden/c.txt"), b"abc").unwrap();
        let request = ChecksumRequest {
            paths: vec![dir.path().join("a.txt"), dir.path().join("sub")],
            base: dir.path().to_path_buf(),
            algorithm: Algorithm::Md5,
            recursive: true,
            include_hidden: false,
        };
        let cancel = AtomicBool::new(false);
        let files = expand(&request, &cancel);
        let names: Vec<&str> = files.iter().map(|f| f.name.as_str()).collect();
        assert_eq!(names, ["a.txt", "sub/b.txt"]);
        let mut outcomes = Vec::new();
        let mut reports = 0;
        hash_all(&files, Algorithm::Md5, &cancel, Duration::ZERO, &mut |o| outcomes.push(o), &mut |_| {
            reports += 1
        });
        assert!(reports >= 1);
        outcomes.sort_by_key(|o| o.index);
        assert!(outcomes.iter().all(|o| o.hash.as_deref() == Some("900150983cd24fb0d6963f7d28e17f72")));

        // A sums file naming one good, one bad, one missing file.
        let sums = dir.path().join("MD5SUMS");
        fs::write(
            &sums,
            "900150983cd24fb0d6963f7d28e17f72  a.txt\n\
             00000000000000000000000000000000  sub/b.txt\n\
             900150983cd24fb0d6963f7d28e17f72  gone.txt\n",
        )
        .unwrap();
        let read = read_sums(&sums).unwrap();
        assert_eq!(read.algorithm, Algorithm::Md5);
        let mut checked = Vec::new();
        hash_all(&read.files, read.algorithm, &cancel, Duration::ZERO, &mut |o| checked.push(o), &mut |_| {});
        checked.sort_by_key(|o| o.index);
        let statuses: Vec<ChecksumStatus> = checked.iter().map(|o| o.status).collect();
        assert_eq!(statuses, [ChecksumStatus::Ok, ChecksumStatus::Mismatch, ChecksumStatus::Missing]);
    }

    #[test]
    fn without_recursion_a_folder_gives_its_own_files() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("f/deep")).unwrap();
        fs::write(dir.path().join("f/top.txt"), b"1").unwrap();
        fs::write(dir.path().join("f/deep/low.txt"), b"2").unwrap();
        let request = ChecksumRequest {
            paths: vec![dir.path().join("f")],
            base: dir.path().to_path_buf(),
            algorithm: Algorithm::Sha1,
            recursive: false,
            include_hidden: true,
        };
        let names: Vec<String> =
            expand(&request, &AtomicBool::new(false)).into_iter().map(|f| f.name).collect();
        assert_eq!(names, ["f/top.txt"]);
    }
}
