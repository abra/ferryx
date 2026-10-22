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
/// nothing: a large listing compares names millions of times.
pub fn natural_cmp(a: &str, b: &str) -> Ordering {
    let (mut ia, mut ib) = (0usize, 0usize);
    loop {
        match (a[ia..].chars().next(), b[ib..].chars().next()) {
            (None, None) => return a.cmp(b),
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(x), Some(y)) if x.is_ascii_digit() && y.is_ascii_digit() => {
                let ea = ia + digit_run(&a[ia..]);
                let eb = ib + digit_run(&b[ib..]);
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

/// The length in bytes of the ASCII digits `text` starts with.
fn digit_run(text: &str) -> usize {
    text.bytes().take_while(u8::is_ascii_digit).count()
}

/// Two characters compared folded: punctuation before letters as Finder
/// has it (`_a` before `a`), then lower case.
fn fold_cmp(x: char, y: char) -> Ordering {
    let class = |c: char| u8::from(c.is_alphanumeric());
    class(x).cmp(&class(y)).then_with(|| x.to_lowercase().cmp(y.to_lowercase()))
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
    fn cyrillic_folds() {
        assert_eq!(
            sorted(&["Яблоко", "апельсин", "Банан"], Collation::Natural),
            ["апельсин", "Банан", "Яблоко"]
        );
    }
}
