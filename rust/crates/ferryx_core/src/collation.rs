//! How file names compare.

use std::cmp::Ordering;

use serde::{Deserialize, Serialize};

/// The three comparisons a panel can sort names by, from the slowest and
/// most human to the fastest.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum Collation {
    /// Case-insensitive, with runs of digits compared as numbers, as Finder
    /// orders `file2` before `file10`.
    #[default]
    Natural,
    /// Unicode case folding, character by character.
    CaseInsensitive,
    /// Characters compared as they are.
    CaseSensitive,
}

impl Collation {
    pub fn compare(self, a: &str, b: &str) -> Ordering {
        match self {
            Collation::Natural => natural_cmp(a, b),
            Collation::CaseInsensitive => case_insensitive_cmp(a, b),
            Collation::CaseSensitive => a.cmp(b),
        }
    }
}

/// Case-insensitive comparison, with `a` before `A` when the only
/// difference is case, so the order is total.
pub fn case_insensitive_cmp(a: &str, b: &str) -> Ordering {
    let mut ia = a.chars().flat_map(char::to_lowercase);
    let mut ib = b.chars().flat_map(char::to_lowercase);
    loop {
        match (ia.next(), ib.next()) {
            (None, None) => return a.cmp(b),
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(x), Some(y)) => match x.cmp(&y) {
                Ordering::Equal => continue,
                other => return other,
            },
        }
    }
}

/// Natural comparison: digit runs are compared by value (then by their
/// length, so `01` sorts before `1`), everything else case-insensitively;
/// names equal that way fall back to the exact comparison. Allocates
/// nothing and steps over ASCII byte by byte: a large listing compares
/// names millions of times.
pub fn natural_cmp(a: &str, b: &str) -> Ordering {
    let (ab, bb) = (a.as_bytes(), b.as_bytes());
    // Names of one folder often share a long start (`IMG_0`): equal bytes
    // compare equal, so the walk starts where they part, stepped back to
    // the start of a digit run (its value and zeros count whole) and of a
    // character.
    let mut same = ab.iter().zip(bb).take_while(|(x, y)| x == y).count();
    while same > 0 && ab[same - 1].is_ascii_digit() {
        same -= 1;
    }
    while !a.is_char_boundary(same) {
        same -= 1;
    }
    let (mut ia, mut ib) = (same, same);
    loop {
        match (ab.get(ia), bb.get(ib)) {
            (None, None) => return a.cmp(b),
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(x), Some(y)) if x.is_ascii_digit() && y.is_ascii_digit() => {
                let ea = ia + digit_run(&ab[ia..]);
                let eb = ib + digit_run(&bb[ib..]);
                let (da, db) = (&ab[ia..ea], &bb[ib..eb]);
                let na = trim_zeros(da);
                let nb = trim_zeros(db);
                let by_value = na.len().cmp(&nb.len()).then_with(|| na.cmp(nb));
                if by_value != Ordering::Equal {
                    return by_value;
                }
                // Same value: more leading zeros first.
                match db.len().cmp(&da.len()) {
                    Ordering::Equal => {
                        ia = ea;
                        ib = eb;
                    }
                    other => return other,
                }
            }
            (Some(&x), Some(&y)) if x.is_ascii() && y.is_ascii() => {
                ia += 1;
                ib += 1;
                if x == y {
                    continue;
                }
                match ascii_fold_cmp(x, y) {
                    Ordering::Equal => continue,
                    other => return other,
                }
            }
            _ => {
                // Both indices stay on character boundaries: ASCII steps
                // one byte, everything else a whole character.
                let x = a[ia..].chars().next().unwrap_or_default();
                let y = b[ib..].chars().next().unwrap_or_default();
                ia += x.len_utf8();
                ib += y.len_utf8();
                if x == y {
                    continue;
                }
                match fold_cmp(x, y) {
                    Ordering::Equal => continue,
                    other => return other,
                }
            }
        }
    }
}

fn trim_zeros(digits: &[u8]) -> &[u8] {
    let zeros = digits.iter().take_while(|&&d| d == b'0').count();
    &digits[zeros..]
}

/// The length in bytes of the ASCII digits `text` starts with.
fn digit_run(text: &[u8]) -> usize {
    text.iter().take_while(|d| d.is_ascii_digit()).count()
}

/// Two characters compared folded: punctuation before letters as Finder
/// has it (`_a` before `a`), then lower case.
fn fold_cmp(x: char, y: char) -> Ordering {
    let class = |c: char| u8::from(c.is_alphanumeric());
    class(x).cmp(&class(y)).then_with(|| x.to_lowercase().cmp(y.to_lowercase()))
}

/// [`fold_cmp`] of two ASCII characters.
fn ascii_fold_cmp(x: u8, y: u8) -> Ordering {
    let class = |c: u8| u8::from(c.is_ascii_alphanumeric());
    class(x).cmp(&class(y)).then_with(|| x.to_ascii_lowercase().cmp(&y.to_ascii_lowercase()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sorted(names: &[&str], collation: Collation) -> Vec<String> {
        let mut v: Vec<String> = names.iter().map(|s| s.to_string()).collect();
        v.sort_by(|a, b| collation.compare(a, b));
        v
    }

    #[test]
    fn natural_orders_numbers_by_value() {
        assert_eq!(
            sorted(&["file10", "file2", "file1", "File3"], Collation::Natural),
            ["file1", "file2", "File3", "file10"]
        );
    }

    #[test]
    fn natural_leading_zeros_come_first_among_equal_values() {
        assert_eq!(sorted(&["a1", "a01", "a001"], Collation::Natural), ["a001", "a01", "a1"]);
    }

    #[test]
    fn natural_is_case_insensitive_but_total() {
        assert_eq!(sorted(&["b", "A", "a", "B"], Collation::Natural), ["A", "a", "B", "b"]);
    }

    #[test]
    fn case_sensitive_puts_capitals_first() {
        assert_eq!(sorted(&["b", "A", "a", "B"], Collation::CaseSensitive), ["A", "B", "a", "b"]);
    }

    #[test]
    fn case_insensitive_ignores_case() {
        assert_eq!(sorted(&["b", "A", "a", "B"], Collation::CaseInsensitive), ["A", "a", "B", "b"]);
        assert_eq!(sorted(&["file10", "file2"], Collation::CaseInsensitive), ["file10", "file2"]);
    }

    #[test]
    fn natural_steps_over_ascii_as_it_does_over_any_character() {
        let alphabet = [
            "a", "A", "b", "B", "z", "0", "1", "9", "00", "_", " ", ".", "-", "~", "é", "É", "e\u{301}", "ß",
            "я", "Я", "ё", "😀", "İ", "ǅ", "IMG_0", "IMG_00", "file 1",
        ];
        // A fixed walk over names made of those pieces: no seed to chase.
        let mut state = 0x9e37_79b9_7f4a_7c15u64;
        let mut next = move || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        };
        let mut names = Vec::new();
        for _ in 0..3000 {
            let parts = (next() % 7) as usize;
            names.push(
                (0..parts).map(|_| alphabet[(next() % alphabet.len() as u64) as usize]).collect::<String>(),
            );
        }
        for a in &names {
            for b in names.iter().take(300) {
                assert_eq!(natural_cmp(a, b), reference_natural_cmp(a, b), "{a:?} vs {b:?}");
            }
        }
    }

    /// Natural comparison: digit runs are compared by value (then by their
    /// length, so `01` sorts before `1`), everything else case-insensitively;
    /// names equal that way fall back to the exact comparison. Allocates
    /// nothing: a large listing compares names millions of times.
    fn reference_natural_cmp(a: &str, b: &str) -> Ordering {
        let (mut ia, mut ib) = (0usize, 0usize);
        loop {
            match (a[ia..].chars().next(), b[ib..].chars().next()) {
                (None, None) => return a.cmp(b),
                (None, Some(_)) => return Ordering::Less,
                (Some(_), None) => return Ordering::Greater,
                (Some(x), Some(y)) if x.is_ascii_digit() && y.is_ascii_digit() => {
                    let ea = ia + a[ia..].bytes().take_while(u8::is_ascii_digit).count();
                    let eb = ib + b[ib..].bytes().take_while(u8::is_ascii_digit).count();
                    let (da, db) = (&a[ia..ea], &b[ib..eb]);
                    let na = da.trim_start_matches('0');
                    let nb = db.trim_start_matches('0');
                    let by_value = na.len().cmp(&nb.len()).then_with(|| na.cmp(nb));
                    if by_value != Ordering::Equal {
                        return by_value;
                    }
                    // Same value: more leading zeros first.
                    match db.len().cmp(&da.len()) {
                        Ordering::Equal => {
                            ia = ea;
                            ib = eb;
                        }
                        other => return other,
                    }
                }
                (Some(x), Some(y)) => {
                    ia += x.len_utf8();
                    ib += y.len_utf8();
                    if x == y {
                        continue;
                    }
                    match fold_cmp(x, y) {
                        Ordering::Equal => continue,
                        other => return other,
                    }
                }
            }
        }
    }

    #[test]
    fn cyrillic_folds() {
        assert_eq!(
            sorted(&["Яблоко", "апельсин", "Банан"], Collation::Natural),
            ["апельсин", "Банан", "Яблоко"]
        );
    }
}
