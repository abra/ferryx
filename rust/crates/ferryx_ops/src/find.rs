//! Find Files: a walk under a folder with a name, content and size
//! condition, reporting hits as they come.
//!
//! Contents are searched as bytes, never decoded: a needle exactly with
//! `memmem`, ASCII ignoring case with Aho-Corasick (several words in one
//! pass until one is found), other text ignoring case through a regular
//! expression (Unicode simple case folding). A few workers read and search
//! the files while the walk goes on, and the hits are handed on in the
//! walk's order.

use std::collections::BTreeMap;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use aho_corasick::{AhoCorasick, MatchKind};
use crossbeam_channel::{Receiver, RecvTimeoutError};
use ferryx_core::mask::NameFilter;
use memchr::memmem;
use regex::bytes::{Regex, RegexBuilder, RegexSet, RegexSetBuilder};
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

impl SizeCondition {
    fn holds(&self, len: u64) -> bool {
        match self.op {
            SizeOp::Less => len < self.bytes,
            SizeOp::Equal => len == self.bytes,
            SizeOp::Greater => len > self.bytes,
        }
    }
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

/// What a file's contents are read in, besides the overlap.
const CONTENT_WINDOW: usize = 1024 * 1024;

/// Candidates being searched or waiting for one before them: bounds what
/// a big file ahead of many small ones holds back.
const IN_FLIGHT: u64 = 256;

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
    let conditions = Conditions::new(request)?;
    let mut walker = WalkDir::new(&request.root).follow_links(false).min_depth(1);
    if let Some(depth) = request.max_depth {
        walker = walker.max_depth(depth);
    }
    let include_hidden = request.include_hidden;
    let iter = walker
        .into_iter()
        .filter_entry(move |e| include_hidden || !is_hidden(e.file_name().to_string_lossy().as_ref()));
    let walk = |submit: &mut dyn FnMut(FindHit)| {
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
            if is_dir && conditions.files_only {
                continue;
            }
            if !conditions.name_matches(&entry.file_name().to_string_lossy()) {
                continue;
            }
            let Ok(meta) = entry.metadata() else { continue };
            if !conditions.size_matches(is_dir, meta.len()) {
                continue;
            }
            if conditions.content.is_some() && (is_dir || !entry.file_type().is_file()) {
                continue;
            }
            submit(FindHit {
                path: entry.path().to_path_buf(),
                is_dir,
                size: if is_dir { 0 } else { meta.len() },
                modified_ms: meta.modified().ok().and_then(ferryx_vfs::native::system_time_ms),
            });
        }
        scanned
    };
    Ok(match &conditions.content {
        Some(search) => check_contents(search, ContentCheck::Bytes, cancel, on_hit, walk),
        None => walk(on_hit),
    })
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

/// A request's conditions, made ready once for a search.
struct Conditions {
    filter: Option<NameFilter>,
    content: Option<ContentSearch>,
    size: Option<SizeCondition>,
    /// Folders are never hits.
    files_only: bool,
}

impl Conditions {
    fn new(request: &FindRequest) -> Result<Conditions, String> {
        let filter = if request.name.trim().is_empty() {
            None
        } else if request.name_is_regex {
            Some(NameFilter::regex(request.name.trim(), false)?)
        } else {
            Some(NameFilter::mask(request.name.trim())?)
        };
        let content = match request.content.as_ref().filter(|c| !c.text.is_empty()) {
            Some(query) => Some(ContentSearch::new(query)?),
            None => None,
        };
        Ok(Conditions {
            files_only: content.is_some() || request.size.is_some() || !request.include_folders,
            filter,
            content,
            size: request.size,
        })
    }

    fn name_matches(&self, name: &str) -> bool {
        self.filter.as_ref().is_none_or(|filter| filter.matches(name))
    }

    fn size_matches(&self, is_dir: bool, len: u64) -> bool {
        self.size.is_none_or(|size| !is_dir && size.holds(len))
    }
}

/// How a candidate's contents are checked.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ContentCheck {
    /// Read and searched.
    Bytes,
    /// Read and searched when they look like plain text; any other file
    /// is taken to hold the text, as the index that offered it says.
    PlainText,
}

/// The request's conditions over one item, for hits that come from
/// elsewhere than a walk: Spotlight's, which already meet its content
/// clause word by word, ignoring case and diacritics. So the contents are
/// read only for what that clause cannot say: case or a whole phrase
/// (and then only in files that look like plain text: the text of a PDF
/// or an Office document is not its bytes, and the index read it there),
/// and "not containing".
pub struct Matcher {
    root: PathBuf,
    conditions: Conditions,
    include_hidden: bool,
    /// How the contents are checked; `None` when the index is taken at
    /// its word.
    check: Option<ContentCheck>,
}

impl Matcher {
    pub fn new(request: &FindRequest) -> Result<Matcher, String> {
        let conditions = Conditions::new(request)?;
        let check = conditions.content.as_ref().and_then(|search| {
            if search.not_containing {
                Some(ContentCheck::Bytes)
            } else if search.case_sensitive || search.whole_phrase {
                Some(ContentCheck::PlainText)
            } else {
                None
            }
        });
        Ok(Matcher { root: request.root.clone(), conditions, include_hidden: request.include_hidden, check })
    }

    /// The hit `path` makes, or `None` when it does not meet the request
    /// (or is not under the root, or is gone).
    pub fn check(&self, path: &Path) -> Option<FindHit> {
        let hit = self.candidate(path)?;
        match self.reads_contents() {
            Some((search, check)) => {
                let mut scratch = search.scratch();
                search.matches(&hit, check, &mut scratch, &AtomicBool::new(false)).then_some(hit)
            }
            None => Some(hit),
        }
    }

    /// The hit `path` makes as far as its name, place, kind and size go;
    /// its contents, when [`Self::reads_contents`] says so, are still to
    /// be checked.
    pub(crate) fn candidate(&self, path: &Path) -> Option<FindHit> {
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
        if is_dir && self.conditions.files_only {
            return None;
        }
        if !self.conditions.name_matches(&path.file_name()?.to_string_lossy()) {
            return None;
        }
        if !self.conditions.size_matches(is_dir, meta.len()) {
            return None;
        }
        if self.conditions.content.is_some() && (is_dir || !meta.is_file()) {
            return None;
        }
        Some(FindHit {
            path: path.to_path_buf(),
            is_dir,
            size: if is_dir { 0 } else { meta.len() },
            modified_ms: meta.modified().ok().and_then(ferryx_vfs::native::system_time_ms),
        })
    }

    /// The search a candidate's contents still go through, if any.
    pub(crate) fn reads_contents(&self) -> Option<(&ContentSearch, ContentCheck)> {
        Some((self.conditions.content.as_ref()?, self.check?))
    }
}

fn is_hidden(name: &str) -> bool {
    name.starts_with('.')
}

/// Checks the contents of the candidates `produce` hands over on a few
/// workers, and hands on to `on_hit` those that meet the condition, in the
/// order they came; answers what `produce` does. Stops handing on, and
/// taking candidates, once `cancel` is set.
pub(crate) fn check_contents<T>(
    search: &ContentSearch,
    check: ContentCheck,
    cancel: &AtomicBool,
    on_hit: &mut dyn FnMut(FindHit),
    produce: impl FnOnce(&mut dyn FnMut(FindHit)) -> T,
) -> T {
    let (jobs, job_queue) = crossbeam_channel::bounded::<(u64, FindHit)>(IN_FLIGHT as usize);
    let (done_sender, done) = crossbeam_channel::unbounded::<(u64, Option<FindHit>)>();
    std::thread::scope(|scope| {
        for _ in 0..crate::hashing::workers() {
            let (job_queue, done_sender) = (job_queue.clone(), done_sender.clone());
            scope.spawn(move || {
                let mut scratch = search.scratch();
                for (seq, candidate) in job_queue {
                    let keep = !cancel.load(Ordering::Relaxed)
                        && search.matches(&candidate, check, &mut scratch, cancel);
                    if done_sender.send((seq, keep.then_some(candidate))).is_err() {
                        break;
                    }
                }
            });
        }
        drop((job_queue, done_sender));
        let mut order = InOrder { done, sent: 0, next: 0, waiting: BTreeMap::new() };
        let out = produce(&mut |candidate| {
            while order.sent - order.next >= IN_FLIGHT {
                if !order.receive(cancel, on_hit) {
                    return;
                }
            }
            if jobs.send((order.sent, candidate)).is_ok() {
                order.sent += 1;
            }
            order.take_ready(cancel, on_hit);
        });
        drop(jobs);
        while order.next < order.sent && order.receive(cancel, on_hit) {}
        out
    })
}

/// The workers' verdicts put back in the candidates' order.
struct InOrder {
    done: Receiver<(u64, Option<FindHit>)>,
    /// Candidates sent to the workers.
    sent: u64,
    /// The next candidate to hand on.
    next: u64,
    waiting: BTreeMap<u64, Option<FindHit>>,
}

impl InOrder {
    fn put(&mut self, seq: u64, hit: Option<FindHit>, cancel: &AtomicBool, on_hit: &mut dyn FnMut(FindHit)) {
        self.waiting.insert(seq, hit);
        while let Some(hit) = self.waiting.remove(&self.next) {
            self.next += 1;
            if let Some(hit) = hit {
                if !cancel.load(Ordering::SeqCst) {
                    on_hit(hit);
                }
            }
        }
    }

    fn take_ready(&mut self, cancel: &AtomicBool, on_hit: &mut dyn FnMut(FindHit)) {
        while let Ok((seq, hit)) = self.done.try_recv() {
            self.put(seq, hit, cancel, on_hit);
        }
    }

    /// Waits for a verdict; `false` once cancelled or when the workers are
    /// gone.
    fn receive(&mut self, cancel: &AtomicBool, on_hit: &mut dyn FnMut(FindHit)) -> bool {
        loop {
            if cancel.load(Ordering::SeqCst) {
                return false;
            }
            match self.done.recv_timeout(Duration::from_millis(50)) {
                Ok((seq, hit)) => {
                    self.put(seq, hit, cancel, on_hit);
                    self.take_ready(cancel, on_hit);
                    return true;
                }
                Err(RecvTimeoutError::Timeout) => continue,
                Err(RecvTimeoutError::Disconnected) => return false,
            }
        }
    }
}

/// A content condition ready to search with: its needles built once, for
/// every file and every worker.
pub(crate) struct ContentSearch {
    not_containing: bool,
    case_sensitive: bool,
    whole_phrase: bool,
    /// `None` when there is nothing to look for (a text of spaces, word
    /// by word): every file holds it.
    needles: Option<Needles>,
    /// How many needles a file must hold.
    count: usize,
    /// The most bytes a match spans: windows overlap by one less.
    span: usize,
}

enum Needles {
    /// One needle, byte for byte.
    Exact(memmem::Finder<'static>),
    /// One needle, ASCII ignoring case.
    Ascii(AhoCorasick),
    /// Several of those: all in one pass until the first is found, then
    /// each still missing on its own, so a frequent word found early is
    /// not met again and again.
    Words(AhoCorasick, Vec<Needles>),
    /// One needle ignoring case beyond ASCII.
    Folded(Regex),
    /// Several of those, in one pass.
    FoldedSet(RegexSet),
}

/// A worker's reusable room: the read window and the needles found.
pub(crate) struct Scratch {
    buffer: Vec<u8>,
    found: Vec<bool>,
}

impl ContentSearch {
    fn new(query: &ContentQuery) -> Result<ContentSearch, String> {
        let mut needles: Vec<String> = if query.whole_phrase {
            vec![query.text.clone()]
        } else {
            query.text.split_whitespace().map(str::to_string).collect()
        };
        if !query.case_sensitive {
            needles = needles.into_iter().map(|n| n.to_lowercase()).collect();
        }
        let mut seen = std::collections::HashSet::new();
        needles.retain(|n| seen.insert(n.clone()));
        let folded = !query.case_sensitive && !needles.iter().all(|n| n.is_ascii());
        let span = needles
            .iter()
            // Folded, a character may match one of another length: four
            // bytes each at most.
            .map(|n| if folded { n.chars().count() * 4 } else { n.len() })
            .max()
            .unwrap_or(0);
        let escaped = || needles.iter().map(|n| regex::escape(n)).collect::<Vec<_>>();
        let words = || {
            let mut builder = AhoCorasick::builder();
            builder.match_kind(MatchKind::LeftmostFirst).ascii_case_insensitive(!query.case_sensitive);
            builder
        };
        let one = |needle: &String| -> Result<Needles, String> {
            Ok(if query.case_sensitive {
                Needles::Exact(memmem::Finder::new(needle.as_bytes()).into_owned())
            } else {
                Needles::Ascii(words().build([needle]).map_err(|e| e.to_string())?)
            })
        };
        let built = match needles.as_slice() {
            [] => None,
            [_] if folded => Some(Needles::Folded(
                RegexBuilder::new(&escaped()[0])
                    .case_insensitive(true)
                    .size_limit(64 << 20)
                    .build()
                    .map_err(|e| e.to_string())?,
            )),
            _ if folded => Some(Needles::FoldedSet(
                RegexSetBuilder::new(escaped())
                    .case_insensitive(true)
                    .size_limit(64 << 20)
                    .build()
                    .map_err(|e| e.to_string())?,
            )),
            [needle] => Some(one(needle)?),
            _ => Some(Needles::Words(
                words().build(&needles).map_err(|e| e.to_string())?,
                needles.iter().map(one).collect::<Result<_, _>>()?,
            )),
        };
        Ok(ContentSearch {
            not_containing: query.not_containing,
            case_sensitive: query.case_sensitive,
            whole_phrase: query.whole_phrase,
            count: needles.len(),
            span,
            needles: built,
        })
    }

    pub(crate) fn scratch(&self) -> Scratch {
        Scratch { buffer: vec![0; CONTENT_WINDOW + self.span], found: vec![false; self.count] }
    }

    /// Whether the candidate meets the condition.
    pub(crate) fn matches(
        &self,
        candidate: &FindHit,
        check: ContentCheck,
        scratch: &mut Scratch,
        cancel: &AtomicBool,
    ) -> bool {
        let text_only = check == ContentCheck::PlainText;
        self.contains(&candidate.path, candidate.size, text_only, scratch, cancel) != self.not_containing
    }

    /// Whether the file holds every needle, read up to the size the walk
    /// saw in windows that overlap by the longest match less one, so a
    /// match across a boundary is found. With `text_only` a file whose
    /// start does not look like plain text holds them; a file that cannot
    /// be read holds nothing.
    fn contains(
        &self,
        path: &Path,
        len: u64,
        text_only: bool,
        scratch: &mut Scratch,
        cancel: &AtomicBool,
    ) -> bool {
        let Some(needles) = &self.needles else { return true };
        let Ok(mut file) = File::open(path) else { return false };
        scratch.found.fill(false);
        let buffer = &mut scratch.buffer;
        let mut carry = 0usize;
        let mut total = 0u64;
        loop {
            if cancel.load(Ordering::Relaxed) {
                return false;
            }
            let read = match file.read(&mut buffer[carry..carry + CONTENT_WINDOW]) {
                Ok(0) => break,
                Ok(n) => n,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => return false,
            };
            let window_len = carry + read;
            if total == 0 && text_only && !looks_like_text(&buffer[..window_len]) {
                return true;
            }
            total += read as u64;
            if scan(needles, &buffer[..window_len], &mut scratch.found) {
                return true;
            }
            // A size of 0 may not be the truth (Linux's `/proc`): read to the end.
            if len > 0 && total >= len {
                break;
            }
            let keep = window_len.min(self.span - 1);
            buffer.copy_within(window_len - keep..window_len, 0);
            carry = keep;
        }
        false
    }
}

/// Marks the needles `window` holds; answers whether all are found.
fn scan(needles: &Needles, window: &[u8], found: &mut [bool]) -> bool {
    match needles {
        Needles::Exact(finder) => found[0] |= finder.find(window).is_some(),
        Needles::Ascii(word) => found[0] |= word.is_match(window),
        Needles::Folded(regex) => found[0] |= regex.is_match(window),
        Needles::Words(all, each) => {
            if found.iter().all(|f| !*f) {
                match all.find(window) {
                    Some(hit) => found[hit.pattern().as_usize()] = true,
                    None => return false,
                }
            }
            for (i, one) in each.iter().enumerate() {
                if !found[i] {
                    scan(one, window, &mut found[i..=i]);
                }
            }
        }
        Needles::FoldedSet(set) => {
            for i in set.matches(window).iter() {
                found[i] = true;
            }
        }
    }
    found.iter().all(|f| *f)
}

/// Whether a file's first bytes look like plain text: no NUL, and UTF-8
/// (a character cut by the end of the sample aside).
fn looks_like_text(start: &[u8]) -> bool {
    let sample = &start[..start.len().min(8 * 1024)];
    if memchr::memchr(0, sample).is_some() {
        return false;
    }
    match std::str::from_utf8(sample) {
        Ok(_) => true,
        Err(e) => e.error_len().is_none(),
    }
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

    fn query(text: &str, case_sensitive: bool, whole_phrase: bool) -> Option<ContentQuery> {
        Some(ContentQuery { text: text.into(), case_sensitive, whole_phrase, not_containing: false })
    }

    #[test]
    fn ignoring_case_folds_beyond_ascii() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("upper.txt"), "Итоги: ОТЧЁТ за год").unwrap();
        fs::write(dir.path().join("mixed.txt"), "отчёт и Report").unwrap();
        fs::write(dir.path().join("other.txt"), "отчет без ё, REPORT").unwrap();
        fs::write(dir.path().join("greek.txt"), "ΟΔΟΣ").unwrap();
        let mut req = base(dir.path());
        req.content = query("Отчёт", false, true);
        assert_eq!(hits(&req), ["mixed.txt", "upper.txt"]);
        req.content = query("Отчёт", true, true);
        assert!(hits(&req).is_empty());
        req.content = query("отчёт", true, true);
        assert_eq!(hits(&req), ["mixed.txt"]);
        // Words, ASCII and not, in one search.
        req.content = query("report ОТЧЁТ", false, false);
        assert_eq!(hits(&req), ["mixed.txt"]);
        req.content = query("report", false, false);
        assert_eq!(hits(&req), ["mixed.txt", "other.txt"]);
        // A final sigma is a sigma.
        req.content = query("οδοσ", false, true);
        assert_eq!(hits(&req), ["greek.txt"]);
    }

    /// Every word on its own: words that overlap, words repeated, a word
    /// met again and again before the one still missing.
    #[test]
    fn words_are_found_each_on_its_own() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("abc.txt"), "xabcx").unwrap();
        fs::write(dir.path().join("ab.txt"), "ab ab ab ab").unwrap();
        fs::write(dir.path().join("late.txt"), "ab ".repeat(10_000) + "omega").unwrap();
        let mut req = base(dir.path());
        req.content = query("ab bc", true, false);
        assert_eq!(hits(&req), ["abc.txt"]);
        req.content = query("BC aB", false, false);
        assert_eq!(hits(&req), ["abc.txt"]);
        req.content = query("ab ab", true, false);
        assert_eq!(hits(&req), ["ab.txt", "abc.txt", "late.txt"]);
        req.content = query("bc ab x", true, false);
        assert_eq!(hits(&req), ["abc.txt"]);
        req.content = query("OMEGA ab", false, false);
        assert_eq!(hits(&req), ["late.txt"]);
    }

    /// Needles of every kind placed across the boundary between two read
    /// windows (a multi-byte one cut inside a character).
    #[test]
    fn matches_across_windows_are_found() {
        let dir = tempfile::tempdir().unwrap();
        let cases: [(&str, &str, bool, bool); 5] = [
            ("NeedleText", "NeedleText", true, true),
            ("NeedleText", "needletext", false, true),
            ("Ёлка зимой", "ёлка ЗИМОЙ", false, true),
            ("left right", "right left", true, false),
            ("Ёлка зимой", "зимой ёлка", false, false),
        ];
        for (i, (written, searched, case_sensitive, whole_phrase)) in cases.into_iter().enumerate() {
            for cut in 1..written.len() {
                let path = dir.path().join(format!("f{i}-{cut}.txt"));
                let mut bytes = vec![b'.'; CONTENT_WINDOW - cut];
                bytes.extend_from_slice(written.as_bytes());
                bytes.extend_from_slice(&[b'.'; 100]);
                fs::write(&path, bytes).unwrap();
            }
            let mut req = base(dir.path());
            req.name = format!("f{i}-*");
            req.content = query(searched, case_sensitive, whole_phrase);
            assert_eq!(hits(&req).len(), written.len() - 1, "{searched}");
        }
        // Two words in two windows far apart.
        let mut far = b"alpha".to_vec();
        far.resize(3 * CONTENT_WINDOW, b' ');
        far.extend_from_slice(b"omega");
        fs::write(dir.path().join("far.txt"), far).unwrap();
        let mut req = base(dir.path());
        req.name = "far.txt".into();
        req.content = query("omega alpha", true, false);
        assert_eq!(hits(&req), ["far.txt"]);
        req.content = query("omega alpha", true, true);
        assert!(hits(&req).is_empty());
    }

    #[test]
    fn hits_come_in_the_walks_order() {
        let dir = tempfile::tempdir().unwrap();
        for d in 0..8 {
            fs::create_dir_all(dir.path().join(format!("d{d}"))).unwrap();
            for f in 0..60 {
                // Some big, so the workers finish out of order.
                let body = if f % 7 == 0 { "x".repeat(3 * CONTENT_WINDOW) + "match" } else { "match".into() };
                let body = if f % 3 == 0 { "no".to_string() } else { body };
                fs::write(dir.path().join(format!("d{d}/f{f}")), body).unwrap();
            }
        }
        let collect = |req: &FindRequest| {
            let mut out = Vec::new();
            run(req, &AtomicBool::new(false), &mut |h| out.push(h.path), &mut |_, _| {}).unwrap();
            out
        };
        let mut all = base(dir.path());
        all.include_folders = false;
        let walked: Vec<PathBuf> =
            collect(&all).into_iter().filter(|p| fs::read(p).unwrap().ends_with(b"match")).collect();
        let mut req = all.clone();
        req.content = query("match", true, true);
        let found = collect(&req);
        assert_eq!(found.len(), 8 * 40);
        assert_eq!(found, walked);
        req.content = Some(ContentQuery { not_containing: true, ..query("match", true, true).unwrap() });
        assert_eq!(collect(&req).len(), 8 * 20);
    }

    #[test]
    fn cancel_stops_a_content_search() {
        let dir = tempfile::tempdir().unwrap();
        for i in 0..500 {
            fs::write(dir.path().join(format!("f{i}")), b"hay needle").unwrap();
        }
        let mut req = base(dir.path());
        req.content = query("needle", false, true);
        let cancel = AtomicBool::new(false);
        let mut n = 0;
        run(
            &req,
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

    /// Spotlight's hits meet its content clause already: the contents are
    /// read only for case or a whole phrase, and then only in plain text;
    /// "not containing" is always read.
    #[test]
    fn the_matcher_takes_the_index_at_its_word_where_it_can() {
        let dir = tempfile::tempdir().unwrap();
        let text = dir.path().join("notes.txt");
        let binary = dir.path().join("report.pdf");
        fs::write(&text, "nothing to see").unwrap();
        fs::write(&binary, b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n\x00\x01compressed").unwrap();
        let check = |content: Option<ContentQuery>| {
            let mut req = base(dir.path());
            req.content = content;
            let matcher = Matcher::new(&req).unwrap();
            [&text, &binary].iter().filter_map(|p| matcher.check(p)).count()
        };
        // Ignoring case, word by word: as the index says.
        assert_eq!(check(query("quarterly", false, false)), 2);
        // Case or a phrase: plain text is read, the rest is as the index says.
        assert_eq!(check(query("Quarterly", true, false)), 1);
        assert_eq!(check(query("quarterly totals", false, true)), 1);
        assert_eq!(check(query("nothing to", false, true)), 2);
        // "Not containing" reads every file.
        let not =
            |text: &str| Some(ContentQuery { not_containing: true, ..query(text, false, false).unwrap() });
        assert_eq!(check(not("nothing")), 1);
        assert_eq!(check(not("compressed")), 1);
        assert!(looks_like_text("Отчёт".as_bytes()));
        assert!(looks_like_text(&"Отчёт".as_bytes()[..3]));
        assert!(!looks_like_text(b"a\0b"));
        assert!(!looks_like_text(b"\xff\xfeU\0"));
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

    /// Times content searches over a generated tree of text (or the tree
    /// in `FERRYX_FIND_BENCH`), warm in the cache: `cargo test --release
    /// -p ferryx_ops find_bench -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn find_bench() {
        let generated = tempfile::tempdir().unwrap();
        let root = match std::env::var("FERRYX_FIND_BENCH") {
            Ok(root) => PathBuf::from(root),
            Err(_) => {
                let words = ["alpha", "beta", "gamma", "delta", "отчёт", "Report", "the", "of", "файл"];
                let mut seed = 0x2545_f491_4f6c_dd1du64;
                let mut next = || {
                    seed ^= seed << 13;
                    seed ^= seed >> 7;
                    seed ^= seed << 17;
                    seed
                };
                for f in 0..2_000u64 {
                    let dir = generated.path().join(format!("d{}", f % 40));
                    fs::create_dir_all(&dir).unwrap();
                    // Mostly 100 KB, every hundredth 8 MB.
                    let size = if f % 100 == 0 { 8 << 20 } else { 100 << 10 };
                    let mut text = String::with_capacity(size + 16);
                    while text.len() < size {
                        text.push_str(words[(next() % words.len() as u64) as usize]);
                        text.push(if next() % 12 == 0 { '\n' } else { ' ' });
                    }
                    if f % 50 == 7 {
                        text.push_str(" needle ОТЧЁТ-2024 ");
                    }
                    fs::write(dir.join(format!("f{f}.txt")), text).unwrap();
                }
                generated.path().to_path_buf()
            }
        };
        let cases: [(&str, &str, bool, bool, bool); 7] = [
            ("absent word, ignoring case", "zqxjkv", false, true, false),
            ("rare word, ignoring case", "needle", false, true, false),
            ("rare word, case-sensitive", "needle", true, true, false),
            ("two words, ignoring case", "needle beta", false, false, false),
            ("Cyrillic, ignoring case", "отчёт-2024", false, true, false),
            ("Cyrillic absent, ignoring case", "щъэю", false, true, false),
            ("not containing", "needle", false, true, true),
        ];
        for (label, text, case_sensitive, whole_phrase, not_containing) in cases {
            let mut req = base(&root);
            req.content =
                Some(ContentQuery { text: text.into(), case_sensitive, whole_phrase, not_containing });
            let mut best = std::time::Duration::MAX;
            let mut found = 0;
            for _ in 0..3 {
                let start = std::time::Instant::now();
                let mut n = 0;
                run(&req, &AtomicBool::new(false), &mut |_| n += 1, &mut |_, _| {}).unwrap();
                best = best.min(start.elapsed());
                found = n;
            }
            println!("{label}: {found} hits in {best:?}");
        }
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
