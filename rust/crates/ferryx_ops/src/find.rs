//! Find Files: a walk under a folder with a name, content and size
//! condition, reporting hits as they come.

use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use ferryx_core::mask::NameFilter;
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContentQuery {
    pub text: String,
    pub case_sensitive: bool,
    /// The text as one phrase; else every word of it, in any order.
    pub whole_phrase: bool,
    /// Files that do *not* contain the text.
    pub not_containing: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SizeOp {
    Less,
    Equal,
    Greater,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SizeCondition {
    pub op: SizeOp,
    pub bytes: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FindRequest {
    pub root: PathBuf,
    /// A mask (`*.txt;*.md`) or, with `name_is_regex`, a regular
    /// expression; empty for every name.
    pub name: String,
    pub name_is_regex: bool,
    pub content: Option<ContentQuery>,
    pub size: Option<SizeCondition>,
    pub include_hidden: bool,
    /// Folders too, when nothing about contents or size is asked.
    pub include_folders: bool,
    pub max_depth: Option<usize>,
    /// Ask the Spotlight index first (macOS); see [`search`].
    pub use_spotlight: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FindHit {
    pub path: PathBuf,
    pub is_dir: bool,
    pub size: u64,
    pub modified_ms: Option<i64>,
}

/// Reads at most this much of a file for its contents.
const CONTENT_WINDOW: usize = 8 * 1024 * 1024;

/// Walks the tree and calls `on_hit` for each match and `on_progress`
/// now and then with the folder being searched and the count so far;
/// stops when `cancel` is set. Answers how many items were looked at, or
/// the reason the filter could not be built.
pub fn run(
    request: &FindRequest,
    cancel: &AtomicBool,
    on_hit: &mut dyn FnMut(FindHit),
    on_progress: &mut dyn FnMut(&Path, u64),
) -> Result<u64, String> {
    let filter = if request.name.trim().is_empty() {
        None
    } else if request.name_is_regex {
        Some(NameFilter::regex(request.name.trim(), false)?)
    } else {
        Some(NameFilter::mask(request.name.trim())?)
    };
    let content = request.content.as_ref().filter(|c| !c.text.is_empty()).map(|c| {
        let needles: Vec<String> = if c.whole_phrase {
            vec![c.text.clone()]
        } else {
            c.text.split_whitespace().map(str::to_string).collect()
        };
        let needles =
            if c.case_sensitive { needles } else { needles.into_iter().map(|n| n.to_lowercase()).collect() };
        (c.clone(), needles)
    });
    let files_only = content.is_some() || request.size.is_some() || !request.include_folders;
    let mut walker = WalkDir::new(&request.root).follow_links(false).min_depth(1);
    if let Some(depth) = request.max_depth {
        walker = walker.max_depth(depth);
    }
    let include_hidden = request.include_hidden;
    let iter = walker
        .into_iter()
        .filter_entry(move |e| include_hidden || !is_hidden(e.file_name().to_string_lossy().as_ref()));
    let mut scanned = 0u64;
    let mut last_dir: Option<PathBuf> = None;
    for entry in iter {
        if cancel.load(Ordering::SeqCst) {
            break;
        }
        let Ok(entry) = entry else { continue };
        scanned += 1;
        let is_dir = entry.file_type().is_dir();
        if is_dir {
            let dir = entry.path().to_path_buf();
            if last_dir.as_ref() != Some(&dir) {
                on_progress(&dir, scanned);
                last_dir = Some(dir);
            }
        } else if scanned % 256 == 0 {
            on_progress(entry.path().parent().unwrap_or(&request.root), scanned);
        }
        if is_dir && files_only {
            continue;
        }
        let name = entry.file_name().to_string_lossy();
        if let Some(filter) = &filter {
            if !filter.matches(&name) {
                continue;
            }
        }
        let Ok(meta) = entry.metadata() else { continue };
        if let Some(size) = request.size {
            if is_dir {
                continue;
            }
            let ok = match size.op {
                SizeOp::Less => meta.len() < size.bytes,
                SizeOp::Equal => meta.len() == size.bytes,
                SizeOp::Greater => meta.len() > size.bytes,
            };
            if !ok {
                continue;
            }
        }
        if let Some((query, needles)) = &content {
            if is_dir || !entry.file_type().is_file() {
                continue;
            }
            let contains = file_contains(entry.path(), needles, query.case_sensitive);
            if contains == query.not_containing {
                continue;
            }
        }
        on_hit(FindHit {
            path: entry.path().to_path_buf(),
            is_dir,
            size: if is_dir { 0 } else { meta.len() },
            modified_ms: meta.modified().ok().and_then(ferryx_vfs::native::system_time_ms),
        });
    }
    Ok(scanned)
}

/// How a search went: how many items were looked at, and whether the
/// Spotlight index was asked for and could not answer (the folders were
/// walked instead).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FindSummary {
    pub scanned: u64,
    pub spotlight_failed: bool,
}

/// Finds through the Spotlight index when the request asks for it and
/// Spotlight answers, else by walking the folders ([`run`]).
pub fn search(
    request: &FindRequest,
    cancel: &AtomicBool,
    on_hit: &mut dyn FnMut(FindHit),
    on_progress: &mut dyn FnMut(&Path, u64),
) -> Result<FindSummary, String> {
    let mut spotlight_failed = false;
    if request.use_spotlight {
        match crate::spotlight::run(request, cancel, on_hit, on_progress) {
            Ok(scanned) => return Ok(FindSummary { scanned, spotlight_failed: false }),
            Err(crate::spotlight::SpotlightError::Request(message)) => return Err(message),
            Err(crate::spotlight::SpotlightError::Unavailable(_)) => spotlight_failed = true,
        }
    }
    let scanned = run(request, cancel, on_hit, on_progress)?;
    Ok(FindSummary { scanned, spotlight_failed })
}

/// The request's conditions over one item, for hits that come from
/// elsewhere than a walk (Spotlight): the same answers a walk gives.
pub struct Matcher {
    root: PathBuf,
    filter: Option<NameFilter>,
    content: Option<(ContentQuery, Vec<String>)>,
    size: Option<SizeCondition>,
    files_only: bool,
    include_hidden: bool,
}

impl Matcher {
    pub fn new(request: &FindRequest) -> Result<Matcher, String> {
        let filter = if request.name.trim().is_empty() {
            None
        } else if request.name_is_regex {
            Some(NameFilter::regex(request.name.trim(), false)?)
        } else {
            Some(NameFilter::mask(request.name.trim())?)
        };
        let content = request.content.as_ref().filter(|c| !c.text.is_empty()).map(|c| {
            let needles: Vec<String> = if c.whole_phrase {
                vec![c.text.clone()]
            } else {
                c.text.split_whitespace().map(str::to_string).collect()
            };
            let needles = if c.case_sensitive {
                needles
            } else {
                needles.into_iter().map(|n| n.to_lowercase()).collect()
            };
            (c.clone(), needles)
        });
        Ok(Matcher {
            root: request.root.clone(),
            files_only: content.is_some() || request.size.is_some() || !request.include_folders,
            filter,
            content,
            size: request.size,
            include_hidden: request.include_hidden,
        })
    }

    /// The hit `path` makes, or `None` when it does not meet the request
    /// (or is not under the root, or is gone).
    pub fn check(&self, path: &Path) -> Option<FindHit> {
        let relative = path.strip_prefix(&self.root).ok()?;
        if relative.as_os_str().is_empty() {
            return None;
        }
        if !self.include_hidden && relative.components().any(|c| is_hidden(&c.as_os_str().to_string_lossy()))
        {
            return None;
        }
        let meta = std::fs::symlink_metadata(path).ok()?;
        let is_dir = meta.is_dir();
        if is_dir && self.files_only {
            return None;
        }
        let name = path.file_name()?.to_string_lossy();
        if let Some(filter) = &self.filter {
            if !filter.matches(&name) {
                return None;
            }
        }
        if let Some(size) = self.size {
            let ok = match size.op {
                SizeOp::Less => meta.len() < size.bytes,
                SizeOp::Equal => meta.len() == size.bytes,
                SizeOp::Greater => meta.len() > size.bytes,
            };
            if is_dir || !ok {
                return None;
            }
        }
        if let Some((query, needles)) = &self.content {
            if is_dir || !meta.is_file() {
                return None;
            }
            if file_contains(path, needles, query.case_sensitive) == query.not_containing {
                return None;
            }
        }
        Some(FindHit {
            path: path.to_path_buf(),
            is_dir,
            size: if is_dir { 0 } else { meta.len() },
            modified_ms: meta.modified().ok().and_then(ferryx_vfs::native::system_time_ms),
        })
    }
}

fn is_hidden(name: &str) -> bool {
    name.starts_with('.')
}

/// Whether the file holds every needle, read in windows that overlap by
/// the longest needle so a match on a boundary is still found.
fn file_contains(path: &Path, needles: &[String], case_sensitive: bool) -> bool {
    let Ok(mut file) = File::open(path) else { return false };
    let longest = needles.iter().map(|n| n.len()).max().unwrap_or(0);
    if longest == 0 {
        return true;
    }
    let mut found = vec![false; needles.len()];
    let mut buffer = vec![0u8; CONTENT_WINDOW + longest];
    let mut carry = 0usize;
    loop {
        let read = match file.read(&mut buffer[carry..]) {
            Ok(0) => break,
            Ok(n) => n,
            Err(_) => return false,
        };
        let window_len = carry + read;
        {
            let window = &buffer[..window_len];
            let haystack: std::borrow::Cow<str> = String::from_utf8_lossy(window);
            let haystack =
                if case_sensitive { haystack } else { std::borrow::Cow::Owned(haystack.to_lowercase()) };
            for (i, needle) in needles.iter().enumerate() {
                if !found[i] && haystack.contains(needle.as_str()) {
                    found[i] = true;
                }
            }
        }
        if found.iter().all(|f| *f) {
            return true;
        }
        let keep = window_len.min(longest.saturating_sub(1));
        buffer.copy_within(window_len - keep..window_len, 0);
        carry = keep;
    }
    found.iter().all(|f| *f)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn hits(req: &FindRequest) -> Vec<String> {
        let mut out = Vec::new();
        let cancel = AtomicBool::new(false);
        run(
            req,
            &cancel,
            &mut |h| out.push(h.path.file_name().unwrap().to_string_lossy().into_owned()),
            &mut |_, _| {},
        )
        .unwrap();
        out.sort();
        out
    }

    fn base(root: &Path) -> FindRequest {
        FindRequest {
            root: root.to_path_buf(),
            name: String::new(),
            name_is_regex: false,
            content: None,
            size: None,
            include_hidden: false,
            include_folders: true,
            max_depth: None,
            use_spotlight: false,
        }
    }

    #[test]
    fn finds_by_name_content_and_size() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("sub/.hidden")).unwrap();
        fs::write(dir.path().join("a.txt"), b"Hello World").unwrap();
        fs::write(dir.path().join("sub/b.txt"), b"hello there, world").unwrap();
        fs::write(dir.path().join("sub/c.md"), b"nothing").unwrap();
        fs::write(dir.path().join("sub/.hidden/d.txt"), b"hello").unwrap();

        let mut req = base(dir.path());
        req.name = "*.txt".to_string();
        assert_eq!(hits(&req), ["a.txt", "b.txt"]);
        req.include_hidden = true;
        assert_eq!(hits(&req), ["a.txt", "b.txt", "d.txt"]);

        let mut all = base(dir.path());
        all.include_hidden = false;
        assert_eq!(hits(&all), ["a.txt", "b.txt", "c.md", "sub"]);

        let mut content = base(dir.path());
        content.content = Some(ContentQuery {
            text: "world hello".to_string(),
            case_sensitive: false,
            whole_phrase: false,
            not_containing: false,
        });
        assert_eq!(hits(&content), ["a.txt", "b.txt"]);
        content.content = Some(ContentQuery {
            text: "hello world".to_string(),
            case_sensitive: false,
            whole_phrase: true,
            not_containing: false,
        });
        assert_eq!(hits(&content), ["a.txt"]);
        content.content = Some(ContentQuery {
            text: "Hello".to_string(),
            case_sensitive: true,
            whole_phrase: true,
            not_containing: false,
        });
        assert_eq!(hits(&content), ["a.txt"]);
        content.content = Some(ContentQuery {
            text: "hello".to_string(),
            case_sensitive: false,
            whole_phrase: true,
            not_containing: true,
        });
        assert_eq!(hits(&content), ["c.md"]);

        let mut size = base(dir.path());
        size.size = Some(SizeCondition { op: SizeOp::Greater, bytes: 10 });
        assert_eq!(hits(&size), ["a.txt", "b.txt"]);
        size.size = Some(SizeCondition { op: SizeOp::Equal, bytes: 7 });
        assert_eq!(hits(&size), ["c.md"]);

        let mut regex = base(dir.path());
        regex.name = "^[ab]\\.".to_string();
        regex.name_is_regex = true;
        assert_eq!(hits(&regex), ["a.txt", "b.txt"]);
        regex.name = "(".to_string();
        assert!(run(&regex, &AtomicBool::new(false), &mut |_| {}, &mut |_, _| {}).is_err());
    }

    #[test]
    fn the_matcher_answers_as_the_walk_does() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("sub/.hidden")).unwrap();
        fs::write(dir.path().join("a.txt"), b"Hello World").unwrap();
        fs::write(dir.path().join("sub/b.txt"), b"hello there").unwrap();
        fs::write(dir.path().join("sub/.hidden/d.txt"), b"hello").unwrap();
        let all = [
            dir.path().join("a.txt"),
            dir.path().join("sub"),
            dir.path().join("sub/b.txt"),
            dir.path().join("sub/.hidden/d.txt"),
            dir.path().join("elsewhere.txt"),
            PathBuf::from("/not/under/root.txt"),
        ];
        let names = |req: &FindRequest| {
            let matcher = Matcher::new(req).unwrap();
            let mut out: Vec<String> = all
                .iter()
                .filter_map(|p| matcher.check(p))
                .map(|h| h.path.file_name().unwrap().to_string_lossy().into_owned())
                .collect();
            out.sort();
            out
        };
        let mut req = base(dir.path());
        assert_eq!(names(&req), hits(&req));
        req.name = "*.txt".into();
        assert_eq!(names(&req), hits(&req));
        req.include_hidden = true;
        assert_eq!(names(&req), hits(&req));
        req.content = Some(ContentQuery {
            text: "Hello".into(),
            case_sensitive: true,
            whole_phrase: true,
            not_containing: false,
        });
        assert_eq!(names(&req), ["a.txt"]);
        req.name = "(".into();
        req.name_is_regex = true;
        assert!(Matcher::new(&req).is_err());
    }

    #[test]
    fn search_walks_unless_asked_for_spotlight() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("x.md"), b"").unwrap();
        let mut found = 0;
        let summary =
            search(&base(dir.path()), &AtomicBool::new(false), &mut |_| found += 1, &mut |_, _| {}).unwrap();
        assert_eq!(found, 1);
        assert!(!summary.spotlight_failed);
    }

    #[test]
    fn cancel_stops_the_walk() {
        let dir = tempfile::tempdir().unwrap();
        for i in 0..50 {
            fs::write(dir.path().join(format!("f{i}")), b"").unwrap();
        }
        let cancel = AtomicBool::new(false);
        let mut n = 0;
        run(
            &base(dir.path()),
            &cancel,
            &mut |_| {
                n += 1;
                cancel.store(true, Ordering::SeqCst);
            },
            &mut |_, _| {},
        )
        .unwrap();
        assert_eq!(n, 1);
    }
}
