//! The Batch Rename language: a pattern of placeholders builds each new
//! name, then an optional search and replace and a case change run over
//! the result.
//!
//! Placeholders, in square brackets:
//!
//! - From the name: `[N]` name, `[E]` extension, `[A]` whole name, `[P]`
//!   parent folder, `[G]` grandparent; each takes a substring: `[N4]`,
//!   `[N2-4]`, `[N5,2]`, `[N5-]`, `[N05-10]` (zero padded), `[N 5-10]`
//!   (space padded), `[N-5,3]`, `[N-5-2]`, `[N2--2]`, `[N-4-]`.
//! - From the modification time: `[d]` `[Y]` `[y]` `[M]` `[D]` `[t]` `[h]`
//!   `[m]` `[s]`.
//! - A counter: `[C]`, `[C5]`, `[C5+5]`, `[C5+5/2]`, `[C5+5/2:3]`; each
//!   part is optional (`[C:3]`).
//! - Case of what follows: `[U]` upper, `[L]` lower, `[F]` first letters,
//!   `[n]` as it is.
//! - `[[` and `]]` are the brackets themselves.

use chrono::{DateTime, Datelike, Local, TimeZone, Timelike};
use regex::RegexBuilder;
use serde::{Deserialize, Serialize};

use crate::entry::split_name;

/// One file to rename.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenameItem {
    pub name: String,
    pub parent: String,
    pub grandparent: String,
    pub modified_ms: Option<i64>,
}

/// The `[C]` placeholder's defaults, from the dialog.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Counter {
    pub start: i64,
    pub step: i64,
    pub width: usize,
}

impl Default for Counter {
    fn default() -> Self {
        Counter { start: 1, step: 1, width: 1 }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum CaseTransform {
    #[default]
    Unchanged,
    Lower,
    Upper,
    /// The first letter of each word.
    Capitalize,
}

/// Which part of the new name a [`CaseTransform`] or a search touches.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum NamePart {
    #[default]
    Whole,
    Name,
    Extension,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SearchReplace {
    pub search: String,
    pub replace: String,
    pub regex: bool,
    pub case_sensitive: bool,
    /// Only the first occurrence.
    pub once: bool,
    pub part: NamePart,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenameOptions {
    pub pattern: String,
    pub search: Option<SearchReplace>,
    pub case: CaseTransform,
    pub case_part: NamePart,
    pub counter: Counter,
}

/// Why a planned name cannot be used.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RenameProblem {
    Empty,
    /// A path separator, or a name of only dots.
    Invalid,
    /// Two items would get the same name.
    Duplicate,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenameOutcome {
    pub new_name: String,
    pub problem: Option<RenameProblem>,
}

/// The new names of `items` under `opts`, in order, each checked. An
/// invalid regular expression fails the whole plan.
pub fn plan(items: &[RenameItem], opts: &RenameOptions) -> Result<Vec<RenameOutcome>, String> {
    let tokens = tokenize(&opts.pattern);
    let search = match &opts.search {
        Some(s) if !s.search.is_empty() => Some(compile_search(s)?),
        _ => None,
    };
    let mut out: Vec<RenameOutcome> = Vec::with_capacity(items.len());
    for (index, item) in items.iter().enumerate() {
        let mut name = render(&tokens, item, index, opts.counter);
        if let Some((regex, s)) = &search {
            name = apply_search(&name, regex, s);
        }
        name = apply_case(&name, opts.case, opts.case_part);
        let problem = check(&name);
        out.push(RenameOutcome { new_name: name, problem });
    }
    mark_duplicates(&mut out);
    Ok(out)
}

fn check(name: &str) -> Option<RenameProblem> {
    if name.is_empty() {
        Some(RenameProblem::Empty)
    } else if name.contains('/') || name.contains('\0') || name.chars().all(|c| c == '.') {
        Some(RenameProblem::Invalid)
    } else {
        None
    }
}

fn mark_duplicates(out: &mut [RenameOutcome]) {
    let mut seen = std::collections::HashMap::<String, usize>::new();
    for o in out.iter() {
        *seen.entry(o.new_name.clone()).or_default() += 1;
    }
    for o in out.iter_mut() {
        if o.problem.is_none() && seen.get(&o.new_name).copied().unwrap_or(0) > 1 {
            o.problem = Some(RenameProblem::Duplicate);
        }
    }
}

// ─── Pattern ───

#[derive(Clone, Debug, PartialEq, Eq)]
enum Token {
    Literal(String),
    Source { source: Source, range: Option<Range> },
    Date(char),
    Counter { start: Option<i64>, step: Option<i64>, group: Option<usize>, width: Option<usize> },
    Case(CaseMode),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Source {
    Name,
    Extension,
    Whole,
    Parent,
    Grandparent,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CaseMode {
    Upper,
    Lower,
    First,
    Keep,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Pos {
    FromStart(usize),
    FromEnd(usize),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum End {
    Single,
    Rest,
    At(Pos),
    Count(usize),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Range {
    pad: Option<char>,
    start: Pos,
    end: End,
}

fn tokenize(pattern: &str) -> Vec<Token> {
    let chars: Vec<char> = pattern.chars().collect();
    let mut tokens = Vec::new();
    let mut literal = String::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '[' {
            if chars.get(i + 1) == Some(&'[') {
                literal.push('[');
                i += 2;
                continue;
            }
            if let Some(close) = chars[i + 1..].iter().position(|&x| x == ']') {
                let body: String = chars[i + 1..i + 1 + close].iter().collect();
                match parse_token(&body) {
                    Some(token) => {
                        if !literal.is_empty() {
                            tokens.push(Token::Literal(std::mem::take(&mut literal)));
                        }
                        tokens.push(token);
                    }
                    None => {
                        literal.push('[');
                        literal.push_str(&body);
                        literal.push(']');
                    }
                }
                i += close + 2;
                continue;
            }
            literal.push('[');
            i += 1;
            continue;
        }
        if c == ']' && chars.get(i + 1) == Some(&']') {
            literal.push(']');
            i += 2;
            continue;
        }
        literal.push(c);
        i += 1;
    }
    if !literal.is_empty() {
        tokens.push(Token::Literal(literal));
    }
    tokens
}

fn parse_token(body: &str) -> Option<Token> {
    let mut chars = body.chars();
    let head = chars.next()?;
    let rest = chars.as_str();
    match head {
        'N' | 'E' | 'A' | 'P' | 'G' => {
            let source = match head {
                'N' => Source::Name,
                'E' => Source::Extension,
                'A' => Source::Whole,
                'P' => Source::Parent,
                _ => Source::Grandparent,
            };
            if rest.is_empty() {
                Some(Token::Source { source, range: None })
            } else {
                parse_range(rest).map(|range| Token::Source { source, range: Some(range) })
            }
        }
        'd' | 'Y' | 'y' | 'M' | 'D' | 't' | 'h' | 'm' | 's' if rest.is_empty() => Some(Token::Date(head)),
        'U' if rest.is_empty() => Some(Token::Case(CaseMode::Upper)),
        'L' if rest.is_empty() => Some(Token::Case(CaseMode::Lower)),
        'F' if rest.is_empty() => Some(Token::Case(CaseMode::First)),
        'n' if rest.is_empty() => Some(Token::Case(CaseMode::Keep)),
        'C' => parse_counter(rest),
        _ => None,
    }
}

/// `x`, `x-y`, `x,y`, `x-`, `-x,y`, `-x-y`, `x--y`, `-x-`, with an optional
/// leading `0` or space that pads the result.
fn parse_range(spec: &str) -> Option<Range> {
    let mut s = spec;
    let mut pad = None;
    if let Some(first) = s.chars().next() {
        if (first == '0' || first == ' ') && s.len() > 1 {
            pad = Some(first);
            s = &s[1..];
        }
    }
    let (start, s) = parse_pos(s)?;
    if s.is_empty() {
        return Some(Range { pad, start, end: End::Single });
    }
    if let Some(count) = s.strip_prefix(',') {
        let n: usize = count.parse().ok()?;
        return Some(Range { pad, start, end: End::Count(n) });
    }
    let s = s.strip_prefix('-')?;
    if s.is_empty() {
        return Some(Range { pad, start, end: End::Rest });
    }
    let (end, s) = parse_pos(s)?;
    if !s.is_empty() {
        return None;
    }
    // `[N-5-2]`: a start counted from the end counts the end so too,
    // unless it has its own dash (`[N2--2]`).
    let end = match (start, end) {
        (Pos::FromEnd(_), Pos::FromStart(n)) => Pos::FromEnd(n),
        (_, end) => end,
    };
    Some(Range { pad, start, end: End::At(end) })
}

fn parse_pos(s: &str) -> Option<(Pos, &str)> {
    let (from_end, s) = match s.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, s),
    };
    let digits = s.chars().take_while(char::is_ascii_digit).count();
    if digits == 0 {
        return None;
    }
    let n: usize = s[..digits].parse().ok()?;
    if n == 0 {
        return None;
    }
    Some((if from_end { Pos::FromEnd(n) } else { Pos::FromStart(n) }, &s[digits..]))
}

/// `[start][+step][/group][:width]`.
fn parse_counter(spec: &str) -> Option<Token> {
    let mut s = spec;
    let number = |s: &mut &str| -> Option<i64> {
        let len = s.chars().take_while(char::is_ascii_digit).count();
        if len == 0 {
            return None;
        }
        let n = s[..len].parse().ok();
        *s = &s[len..];
        n
    };
    let start = number(&mut s);
    let mut step = None;
    let mut group = None;
    let mut width = None;
    if let Some(rest) = s.strip_prefix('+') {
        s = rest;
        step = Some(number(&mut s)?);
    }
    if let Some(rest) = s.strip_prefix('/') {
        s = rest;
        group = Some(number(&mut s)? as usize);
    }
    if let Some(rest) = s.strip_prefix(':') {
        s = rest;
        width = Some(number(&mut s)? as usize);
    }
    if !s.is_empty() {
        return None;
    }
    Some(Token::Counter { start, step, group, width })
}

// ─── Rendering ───

fn render(tokens: &[Token], item: &RenameItem, index: usize, counter: Counter) -> String {
    let mut out = String::new();
    let mut mode = CaseMode::Keep;
    let (stem, ext) = split_name(&item.name);
    for token in tokens {
        let text = match token {
            Token::Literal(s) => s.clone(),
            Token::Source { source, range } => {
                let base = match source {
                    Source::Name => stem,
                    Source::Extension => ext,
                    Source::Whole => item.name.as_str(),
                    Source::Parent => item.parent.as_str(),
                    Source::Grandparent => item.grandparent.as_str(),
                };
                match range {
                    None => base.to_string(),
                    Some(range) => substring(base, *range),
                }
            }
            Token::Date(which) => date_part(item.modified_ms, *which),
            Token::Counter { start, step, group, width } => {
                let start = start.unwrap_or(counter.start);
                let step = step.unwrap_or(counter.step);
                let group = group.unwrap_or(1).max(1);
                let width = width.unwrap_or(counter.width);
                let value = start + step * (index / group) as i64;
                format!("{value:0width$}")
            }
            Token::Case(m) => {
                mode = *m;
                continue;
            }
        };
        out.push_str(&cased(&text, mode));
    }
    out
}

fn substring(base: &str, range: Range) -> String {
    let chars: Vec<char> = base.chars().collect();
    let len = chars.len();
    let index = |pos: Pos| -> usize {
        match pos {
            Pos::FromStart(n) => n - 1,
            Pos::FromEnd(n) => len.saturating_sub(n),
        }
    };
    let start = index(range.start);
    let (end, wanted) = match range.end {
        End::Single => (start + 1, Some(1)),
        End::Rest => (len, None),
        End::Count(n) => (start + n, Some(n)),
        End::At(pos) => {
            let e = index(pos) + 1;
            let wanted = match (range.start, pos) {
                (Pos::FromStart(a), Pos::FromStart(b)) if b >= a => Some(b - a + 1),
                _ => None,
            };
            (e, wanted)
        }
    };
    let start = start.min(len);
    let end = end.min(len).max(start);
    let mut text: String = chars[start..end].iter().collect();
    if let (Some(pad), Some(wanted)) = (range.pad, wanted) {
        let have = end - start;
        if have < wanted {
            let padding: String = std::iter::repeat_n(pad, wanted - have).collect();
            text = padding + &text;
        }
    }
    text
}

fn date_part(modified_ms: Option<i64>, which: char) -> String {
    let time: DateTime<Local> = match modified_ms.and_then(|ms| Local.timestamp_millis_opt(ms).single()) {
        Some(t) => t,
        None => return String::new(),
    };
    match which {
        'd' => format!("{:04}-{:02}-{:02}", time.year(), time.month(), time.day()),
        'Y' => format!("{:04}", time.year()),
        'y' => format!("{:02}", time.year() % 100),
        'M' => format!("{:02}", time.month()),
        'D' => format!("{:02}", time.day()),
        't' => format!("{:02}.{:02}", time.hour(), time.minute()),
        'h' => format!("{:02}", time.hour()),
        'm' => format!("{:02}", time.minute()),
        's' => format!("{:02}", time.second()),
        _ => String::new(),
    }
}

fn cased(text: &str, mode: CaseMode) -> String {
    match mode {
        CaseMode::Keep => text.to_string(),
        CaseMode::Upper => text.to_uppercase(),
        CaseMode::Lower => text.to_lowercase(),
        CaseMode::First => capitalize_words(text),
    }
}

fn capitalize_words(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut at_word_start = true;
    for c in text.chars() {
        if c.is_alphanumeric() {
            if at_word_start {
                out.extend(c.to_uppercase());
            } else {
                out.extend(c.to_lowercase());
            }
            at_word_start = false;
        } else {
            out.push(c);
            at_word_start = true;
        }
    }
    out
}

// ─── Search and replace, case ───

fn compile_search(s: &SearchReplace) -> Result<(regex::Regex, SearchReplace), String> {
    let pattern = if s.regex { s.search.clone() } else { regex::escape(&s.search) };
    let regex =
        RegexBuilder::new(&pattern).case_insensitive(!s.case_sensitive).build().map_err(|e| e.to_string())?;
    Ok((regex, s.clone()))
}

fn apply_search(name: &str, regex: &regex::Regex, s: &SearchReplace) -> String {
    let replace = |text: &str| -> String {
        if s.once {
            regex.replacen(text, 1, s.replace.as_str()).into_owned()
        } else {
            regex.replace_all(text, s.replace.as_str()).into_owned()
        }
    };
    on_part(name, s.part, replace)
}

fn apply_case(name: &str, case: CaseTransform, part: NamePart) -> String {
    let mode = match case {
        CaseTransform::Unchanged => return name.to_string(),
        CaseTransform::Lower => CaseMode::Lower,
        CaseTransform::Upper => CaseMode::Upper,
        CaseTransform::Capitalize => CaseMode::First,
    };
    on_part(name, part, |text| cased(text, mode))
}

fn on_part(name: &str, part: NamePart, f: impl Fn(&str) -> String) -> String {
    match part {
        NamePart::Whole => f(name),
        NamePart::Name => {
            let (stem, ext) = split_name(name);
            if ext.is_empty() {
                f(stem)
            } else {
                format!("{}.{}", f(stem), ext)
            }
        }
        NamePart::Extension => {
            let (stem, ext) = split_name(name);
            if ext.is_empty() {
                name.to_string()
            } else {
                format!("{}.{}", stem, f(ext))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(name: &str) -> RenameItem {
        RenameItem {
            name: name.to_string(),
            parent: "Parent".to_string(),
            grandparent: "Grandparent".to_string(),
            modified_ms: Some(1_733_576_323_000), // 2024-12-07 13:58:43 UTC
        }
    }

    fn one(pattern: &str, name: &str) -> String {
        let opts = RenameOptions { pattern: pattern.to_string(), ..Default::default() };
        plan(&[item(name)], &opts).unwrap().remove(0).new_name
    }

    #[test]
    fn name_parts() {
        assert_eq!(one("[N]", "example.txt"), "example");
        assert_eq!(one("[E]", "example.txt"), "txt");
        assert_eq!(one("[A]", "example.txt"), "example.txt");
        assert_eq!(one("[P]", "example.txt"), "Parent");
        assert_eq!(one("[G]", "example.txt"), "Grandparent");
        assert_eq!(one("[N].[E]", "example.txt"), "example.txt");
        assert_eq!(one("[N]-copy.[E]", "example.txt"), "example-copy.txt");
    }

    #[test]
    fn substrings_as_the_help_lists_them() {
        assert_eq!(one("[N4]", "example.txt"), "m");
        assert_eq!(one("[N2-4]", "example.txt"), "xam");
        assert_eq!(one("[N5,2]", "example.txt"), "pl");
        assert_eq!(one("[N5-]", "example.txt"), "ple");
        assert_eq!(one("[N05-10]", "example.txt"), "000ple");
        assert_eq!(one("[N 5-10]", "example.txt"), "   ple");
        assert_eq!(one("[N-5,3]", "example.txt"), "amp");
        assert_eq!(one("[N-5-2]", "example.txt"), "ampl");
        assert_eq!(one("[N2--2]", "example.txt"), "xampl");
        assert_eq!(one("[N-4-]", "example.txt"), "mple");
    }

    #[test]
    fn out_of_range_is_empty_not_a_panic() {
        assert_eq!(one("[N20]", "ab"), "");
        assert_eq!(one("[N5-2]", "example"), "");
        assert_eq!(one("[N-9-]", "ab"), "ab");
    }

    #[test]
    fn counters() {
        let opts = RenameOptions { pattern: "[C]".to_string(), ..Default::default() };
        let items: Vec<RenameItem> = (0..5).map(|i| item(&format!("f{i}"))).collect();
        let names: Vec<String> = plan(&items, &opts).unwrap().into_iter().map(|o| o.new_name).collect();
        assert_eq!(names, ["1", "2", "3", "4", "5"]);
        let grouped = RenameOptions { pattern: "[C5+5/2:3]".to_string(), ..Default::default() };
        let names: Vec<String> = plan(&items, &grouped).unwrap().into_iter().map(|o| o.new_name).collect();
        assert_eq!(names, ["005", "005", "010", "010", "015"]);
        let defaults = RenameOptions {
            pattern: "[C:w]".to_string(),
            counter: Counter { start: 10, step: 2, width: 4 },
            ..Default::default()
        };
        // `[C:w]` is not a counter spec (no digits): literal.
        assert_eq!(plan(&items[..1], &defaults).unwrap()[0].new_name, "[C:w]");
        let widths = RenameOptions {
            pattern: "[C]".to_string(),
            counter: Counter { start: 10, step: 2, width: 4 },
            ..Default::default()
        };
        let names: Vec<String> =
            plan(&items[..2], &widths).unwrap().into_iter().map(|o| o.new_name).collect();
        assert_eq!(names, ["0010", "0012"]);
    }

    #[test]
    fn dates() {
        let d = one("[d]", "x");
        assert_eq!(d.len(), 10);
        assert_eq!(one("[Y]", "x").len(), 4);
        assert_eq!(one("[M]", "x"), "12");
        assert_eq!(one("[D]", "x"), "07");
        assert_eq!(one("[t]", "x").len(), 5);
        assert_eq!(one("[s]", "x"), "43");
        let opts = RenameOptions { pattern: "[Y]".to_string(), ..Default::default() };
        let no_time = RenameItem { modified_ms: None, ..item("x") };
        assert_eq!(plan(&[no_time], &opts).unwrap()[0].new_name, "");
    }

    #[test]
    fn case_commands_apply_to_what_follows() {
        assert_eq!(one("[U][N] [n]and [L]MORE", "some file.txt"), "SOME FILE and more");
        assert_eq!(one("[F][N]", "hello big world.txt"), "Hello Big World");
    }

    #[test]
    fn brackets_escape() {
        assert_eq!(one("[[[N]]]", "a.b"), "[a]");
        assert_eq!(one("[X]", "a.b"), "[X]");
        assert_eq!(one("[N", "a.b"), "[N");
    }

    #[test]
    fn search_replace_and_case() {
        let opts = RenameOptions {
            pattern: "[A]".to_string(),
            search: Some(SearchReplace {
                search: "img".to_string(),
                replace: "photo".to_string(),
                regex: false,
                case_sensitive: false,
                once: false,
                part: NamePart::Whole,
            }),
            case: CaseTransform::Upper,
            case_part: NamePart::Extension,
            ..Default::default()
        };
        let out = plan(&[item("IMG_img.jpg")], &opts).unwrap();
        assert_eq!(out[0].new_name, "photo_photo.JPG");
        let once = RenameOptions {
            search: Some(SearchReplace { once: true, part: NamePart::Name, ..opts.search.clone().unwrap() }),
            case: CaseTransform::Unchanged,
            ..opts.clone()
        };
        assert_eq!(plan(&[item("IMG_img.jpg")], &once).unwrap()[0].new_name, "photo_img.jpg");
        let regex = RenameOptions {
            search: Some(SearchReplace {
                search: r"(\d+)".to_string(),
                replace: "#$1".to_string(),
                regex: true,
                case_sensitive: true,
                once: false,
                part: NamePart::Whole,
            }),
            case: CaseTransform::Unchanged,
            ..opts.clone()
        };
        assert_eq!(plan(&[item("a12b3")], &regex).unwrap()[0].new_name, "a#12b#3");
        let bad = RenameOptions {
            search: Some(SearchReplace { search: "(".to_string(), regex: true, ..Default::default() }),
            ..opts
        };
        assert!(plan(&[item("x")], &bad).is_err());
    }

    #[test]
    fn problems() {
        let opts = RenameOptions { pattern: "same".to_string(), ..Default::default() };
        let out = plan(&[item("a"), item("b")], &opts).unwrap();
        assert_eq!(out[0].problem, Some(RenameProblem::Duplicate));
        assert_eq!(out[1].problem, Some(RenameProblem::Duplicate));
        assert_eq!(one("", "x"), "");
        let empty = RenameOptions { pattern: String::new(), ..Default::default() };
        assert_eq!(plan(&[item("x")], &empty).unwrap()[0].problem, Some(RenameProblem::Empty));
        let slash = RenameOptions { pattern: "a/b".to_string(), ..Default::default() };
        assert_eq!(plan(&[item("x")], &slash).unwrap()[0].problem, Some(RenameProblem::Invalid));
    }
}
