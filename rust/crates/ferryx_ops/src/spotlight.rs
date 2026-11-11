//! Find Files through the Spotlight index (macOS): `mdfind -onlyin` with a
//! query built from the request's name mask, contents and size, its hits
//! streamed as `mdfind` prints them and checked against the request here
//! ([`Matcher`]): a regular expression, the exact mask, hidden items and
//! "not containing" as a walk would; contents only where Spotlight's
//! word-by-word clause cannot say (case, a whole phrase), in files that
//! look like plain text. Spotlight skips system folders, hidden folders
//! and the ones excluded in System Settings; a failure to run it is the
//! caller's cue to walk instead.

use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::time::Duration;

use crate::find::{self, FindHit, FindRequest, Matcher, SizeOp};

/// Where macOS keeps the Spotlight command line.
pub const MDFIND: &str = "/usr/bin/mdfind";

const QUEUED_PATHS: usize = 256;

/// Why Spotlight could not answer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SpotlightError {
    /// The request itself is wrong (a bad expression): a walk would fail
    /// the same way.
    Request(String),
    /// `mdfind` could not run or failed.
    Unavailable(String),
}

/// The Spotlight query for `request`: the name's mask parts as file-name
/// matches (a mask's `?` and `[…]` widened to `*`, the exact mask checked
/// afterwards), every word of the contents as a word prefix, the size as
/// a bound. A regular expression or "not containing" adds no clause:
/// they are checked on the hits.
pub fn query(request: &FindRequest) -> String {
    let mut clauses = Vec::new();
    let name = request.name.trim();
    if !name.is_empty() && !request.name_is_regex {
        let parts: Vec<String> = name
            .split([';', ','])
            .map(str::trim)
            .filter(|p| !p.is_empty())
            .map(|part| {
                let has_wildcard = part.contains(['*', '?', '[']);
                let mut pattern = String::new();
                if !has_wildcard {
                    pattern.push('*');
                }
                let mut in_class = false;
                for c in part.chars() {
                    match c {
                        '[' => {
                            in_class = true;
                            pattern.push('*');
                        }
                        ']' if in_class => in_class = false,
                        _ if in_class => {}
                        '?' => pattern.push('*'),
                        other => pattern.push(other),
                    }
                }
                if !has_wildcard {
                    pattern.push('*');
                }
                format!("kMDItemFSName == \"{}\"cd", escape(&pattern))
            })
            .collect();
        if !parts.is_empty() {
            clauses.push(format!("({})", parts.join(" || ")));
        }
    }
    if let Some(content) = request.content.as_ref().filter(|c| !c.text.trim().is_empty() && !c.not_containing)
    {
        for word in content.text.split_whitespace() {
            clauses.push(format!("kMDItemTextContent == \"{}*\"cdw", escape(word)));
        }
    }
    if let Some(size) = request.size {
        let op = match size.op {
            SizeOp::Less => "<",
            SizeOp::Equal => "==",
            SizeOp::Greater => ">",
        };
        clauses.push(format!("kMDItemFSSize {op} {}", size.bytes));
    }
    if clauses.is_empty() {
        "kMDItemFSName == \"*\"".to_string()
    } else {
        clauses.join(" && ")
    }
}

/// A value inside a query's double quotes.
fn escape(text: &str) -> String {
    text.replace('\\', "\\\\").replace('"', "\\\"")
}

/// Asks Spotlight and calls `on_hit` for each item that meets the request,
/// `on_progress` now and then with the hits' folder and the count looked
/// at; stops (and stops `mdfind`) when `cancel` is set. Answers how many
/// items Spotlight offered.
pub fn run(
    request: &FindRequest,
    cancel: &AtomicBool,
    on_hit: &mut dyn FnMut(FindHit),
    on_progress: &mut dyn FnMut(&Path, u64),
) -> Result<u64, SpotlightError> {
    let matcher = Matcher::new(request).map_err(SpotlightError::Request)?;
    let mut child = Command::new(MDFIND)
        .arg("-0")
        .arg("-onlyin")
        .arg(&request.root)
        .arg(query(request))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| SpotlightError::Unavailable(e.to_string()))?;
    let stdout = child.stdout.take().ok_or_else(|| SpotlightError::Unavailable("no output".into()))?;
    // A thread reads, so a cancel is seen while mdfind is quiet.
    let (tx, rx) = mpsc::sync_channel::<PathBuf>(QUEUED_PATHS);
    let reader =
        match std::thread::Builder::new().name("mdfind".into()).spawn(move || read_paths(stdout, &tx)) {
            Ok(reader) => reader,
            Err(error) => {
                stop(&mut child);
                let _ = child.wait();
                return Err(SpotlightError::Unavailable(error.to_string()));
            }
        };
    let mut offered = 0u64;
    let mut cancelled = false;
    let mut offer = |submit: &mut dyn FnMut(FindHit)| loop {
        if cancel.load(Ordering::SeqCst) {
            cancelled = true;
            stop(&mut child);
            break;
        }
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(path) => {
                offered += 1;
                if offered % 64 == 0 {
                    on_progress(path.parent().unwrap_or(&request.root), offered);
                }
                if let Some(hit) = matcher.candidate(&path) {
                    submit(hit);
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    };
    match matcher.reads_contents() {
        Some((search, check)) => find::check_contents(search, check, cancel, on_hit, offer),
        None => offer(on_hit),
    }
    // A cancelled consumer may leave the reader waiting on a full queue.
    drop(rx);
    let _ = reader.join();
    let status = child.wait().map_err(|e| SpotlightError::Unavailable(e.to_string()))?;
    if !cancelled && !status.success() && offered == 0 {
        return Err(SpotlightError::Unavailable(format!("mdfind ended with {status}")));
    }
    Ok(offered)
}

fn stop(child: &mut Child) {
    let _ = child.kill();
}

/// The NUL-separated paths `mdfind -0` prints; a last one without its NUL
/// was cut short and is dropped.
fn read_paths(stdout: impl Read, tx: &mpsc::SyncSender<PathBuf>) {
    let mut reader = BufReader::with_capacity(64 * 1024, stdout);
    let mut raw = Vec::new();
    loop {
        raw.clear();
        match reader.read_until(0, &mut raw) {
            Ok(0) | Err(_) => break,
            Ok(_) if raw.last() != Some(&0) => break,
            Ok(_) => {}
        }
        let text = String::from_utf8_lossy(&raw[..raw.len() - 1]).into_owned();
        if !text.is_empty() && tx.send(PathBuf::from(text)).is_err() {
            return;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::find::{ContentQuery, SizeCondition};

    fn request() -> FindRequest {
        FindRequest {
            root: PathBuf::from("/tmp"),
            name: String::new(),
            name_is_regex: false,
            content: None,
            size: None,
            include_hidden: false,
            include_folders: true,
            max_depth: None,
            use_spotlight: true,
            modified_after_ms: None,
        }
    }

    #[test]
    fn queries_say_what_spotlight_can() {
        assert_eq!(query(&request()), "kMDItemFSName == \"*\"");
        let mut r = request();
        r.name = "*.txt; report;a?c[0-9].md".into();
        assert_eq!(
            query(&r),
            "(kMDItemFSName == \"*.txt\"cd || kMDItemFSName == \"*report*\"cd || kMDItemFSName == \"a*c*.md\"cd)"
        );
        r.name = "^re.*$".into();
        r.name_is_regex = true;
        r.content = Some(ContentQuery {
            text: "hello \"world\"".into(),
            case_sensitive: true,
            whole_phrase: true,
            not_containing: false,
        });
        r.size = Some(SizeCondition { op: SizeOp::Greater, bytes: 1024 });
        assert_eq!(
            query(&r),
            "kMDItemTextContent == \"hello*\"cdw && kMDItemTextContent == \"\\\"world\\\"*\"cdw && kMDItemFSSize > 1024"
        );
        // "Not containing" is checked on the hits only.
        r.content.as_mut().unwrap().not_containing = true;
        assert_eq!(query(&r), "kMDItemFSSize > 1024");
    }

    #[test]
    fn paths_split_on_nul() {
        let (tx, rx) = mpsc::sync_channel(QUEUED_PATHS);
        read_paths(&b"/a/one\0/b/two words\0\0/c"[..], &tx);
        drop(tx);
        let got: Vec<PathBuf> = rx.iter().collect();
        assert_eq!(got, [PathBuf::from("/a/one"), PathBuf::from("/b/two words")]);
    }

    #[test]
    fn a_full_path_queue_releases_its_reader_when_the_search_stops() {
        let (tx, rx) = mpsc::sync_channel(2);
        let (done, finished) = mpsc::channel();
        let reader = std::thread::spawn(move || {
            let paths = b"/one\0/two\0/three\0/four\0";
            read_paths(&paths[..], &tx);
            done.send(()).unwrap();
        });
        assert!(finished.recv_timeout(Duration::from_millis(30)).is_err());
        assert_eq!(rx.recv().unwrap(), PathBuf::from("/one"));
        drop(rx);
        finished.recv_timeout(Duration::from_secs(2)).unwrap();
        reader.join().unwrap();
    }

    /// Spotlight on this machine: `cargo test -p ferryx_ops spotlight_live
    /// -- --ignored --nocapture` (needs an indexed volume).
    #[cfg(target_os = "macos")]
    #[test]
    #[ignore]
    fn spotlight_live() {
        let mut r = request();
        r.root = PathBuf::from("/Applications");
        r.name = "*.app".into();
        r.include_folders = true;
        let mut hits = 0;
        let start = std::time::Instant::now();
        let offered = run(&r, &AtomicBool::new(false), &mut |_| hits += 1, &mut |_, _| {}).unwrap();
        println!("{offered} offered, {hits} hits in {:?}", start.elapsed());
    }
}
