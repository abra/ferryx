//! Find Files through the Spotlight index (macOS): `mdfind -onlyin` with a
//! query built from the request's name mask, contents and size, its hits
//! streamed as `mdfind` prints them and checked against the request here,
//! so what Spotlight cannot express (a regular expression, case, a whole
//! phrase, "not containing", hidden items) gives the same answers a walk
//! would. Spotlight skips system folders, hidden folders and the ones
//! excluded in System Settings; a failure to run it is the caller's cue to
//! walk instead.

use std::io::{BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::time::Duration;

use crate::find::{FindHit, FindRequest, Matcher, SizeOp};

/// Where macOS keeps the Spotlight command line.
pub const MDFIND: &str = "/usr/bin/mdfind";

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
    let (tx, rx) = mpsc::channel::<PathBuf>();
    let reader = std::thread::Builder::new()
        .name("mdfind".into())
        .spawn(move || read_paths(stdout, &tx))
        .map_err(|e| SpotlightError::Unavailable(e.to_string()))?;
    let mut offered = 0u64;
    let mut cancelled = false;
    loop {
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
                if let Some(hit) = matcher.check(&path) {
                    on_hit(hit);
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }
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

/// The NUL-separated paths `mdfind -0` prints.
fn read_paths(stdout: impl Read, tx: &mpsc::Sender<PathBuf>) {
    let mut reader = BufReader::new(stdout);
    let mut buffer = Vec::new();
    let mut chunk = [0u8; 16 * 1024];
    loop {
        let n = match reader.read(&mut chunk) {
            Ok(0) | Err(_) => break,
            Ok(n) => n,
        };
        buffer.extend_from_slice(&chunk[..n]);
        while let Some(end) = buffer.iter().position(|&b| b == 0) {
            let raw: Vec<u8> = buffer.drain(..=end).collect();
            let text = String::from_utf8_lossy(&raw[..raw.len() - 1]).into_owned();
            if !text.is_empty() && tx.send(PathBuf::from(text)).is_err() {
                return;
            }
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
        let (tx, rx) = mpsc::channel();
        read_paths(&b"/a/one\0/b/two words\0\0/c"[..], &tx);
        drop(tx);
        let got: Vec<PathBuf> = rx.iter().collect();
        assert_eq!(got, [PathBuf::from("/a/one"), PathBuf::from("/b/two words")]);
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
