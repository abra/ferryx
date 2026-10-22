//! Quick Search: a few typed letters find rows of the panel.

use serde::{Deserialize, Serialize};

/// Where the typed query must appear in a name.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum QuickSearchWhere {
    /// The query's letters appear in order, anywhere.
    Fuzzy,
    /// The query appears whole, anywhere.
    #[default]
    Anywhere,
    Beginning,
    Ending,
    BeginningOrEnding,
}

/// Whether `name` matches `query` (case-insensitively), and if so the
/// character ranges of the name to underline, as `(start, end)` indices
/// into the name's characters.
pub fn quick_match(query: &str, name: &str, place: QuickSearchWhere) -> Option<Vec<(usize, usize)>> {
    if query.is_empty() {
        return Some(Vec::new());
    }
    let q: Vec<char> = query.chars().flat_map(char::to_lowercase).collect();
    let n: Vec<char> = name.chars().flat_map(char::to_lowercase).collect();
    match place {
        QuickSearchWhere::Fuzzy => fuzzy(&q, &n),
        QuickSearchWhere::Anywhere => find(&q, &n).map(|at| vec![(at, at + q.len())]),
        QuickSearchWhere::Beginning => n.starts_with(&q).then(|| vec![(0, q.len())]),
        QuickSearchWhere::Ending => n.ends_with(&q).then(|| vec![(n.len() - q.len(), n.len())]),
        QuickSearchWhere::BeginningOrEnding => {
            if n.starts_with(&q) {
                Some(vec![(0, q.len())])
            } else if n.ends_with(&q) {
                Some(vec![(n.len() - q.len(), n.len())])
            } else {
                None
            }
        }
    }
}

fn find(q: &[char], n: &[char]) -> Option<usize> {
    if q.len() > n.len() {
        return None;
    }
    (0..=n.len() - q.len()).find(|&i| &n[i..i + q.len()] == q)
}

fn fuzzy(q: &[char], n: &[char]) -> Option<Vec<(usize, usize)>> {
    let mut ranges: Vec<(usize, usize)> = Vec::new();
    let mut qi = 0;
    for (i, c) in n.iter().enumerate() {
        if qi < q.len() && *c == q[qi] {
            match ranges.last_mut() {
                Some(last) if last.1 == i => last.1 = i + 1,
                _ => ranges.push((i, i + 1)),
            }
            qi += 1;
        }
    }
    (qi == q.len()).then_some(ranges)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn anywhere_is_case_insensitive() {
        assert_eq!(quick_match("col", "Colors.txt", QuickSearchWhere::Anywhere), Some(vec![(0, 3)]));
        assert_eq!(quick_match("ors", "Colors.txt", QuickSearchWhere::Anywhere), Some(vec![(3, 6)]));
        assert_eq!(quick_match("xyz", "Colors.txt", QuickSearchWhere::Anywhere), None);
    }

    #[test]
    fn beginning_and_ending() {
        assert!(quick_match("col", "Colors.txt", QuickSearchWhere::Beginning).is_some());
        assert!(quick_match("ors", "Colors.txt", QuickSearchWhere::Beginning).is_none());
        assert_eq!(quick_match("txt", "Colors.txt", QuickSearchWhere::Ending), Some(vec![(7, 10)]));
        assert!(quick_match("txt", "Colors.txt", QuickSearchWhere::BeginningOrEnding).is_some());
        assert!(quick_match("col", "Colors.txt", QuickSearchWhere::BeginningOrEnding).is_some());
        assert!(quick_match("lor", "Colors.txt", QuickSearchWhere::BeginningOrEnding).is_none());
    }

    #[test]
    fn fuzzy_keeps_order_and_merges_runs() {
        assert_eq!(
            quick_match("cls", "Colors.txt", QuickSearchWhere::Fuzzy),
            Some(vec![(0, 1), (2, 3), (5, 6)])
        );
        assert_eq!(quick_match("colo", "Colors.txt", QuickSearchWhere::Fuzzy), Some(vec![(0, 4)]));
        assert!(quick_match("slc", "Colors.txt", QuickSearchWhere::Fuzzy).is_none());
    }

    #[test]
    fn empty_query_matches_everything() {
        assert_eq!(quick_match("", "x", QuickSearchWhere::Anywhere), Some(vec![]));
    }

    #[test]
    fn unicode_counts_characters() {
        assert_eq!(quick_match("лет", "Отчёт о полёте.pdf", QuickSearchWhere::Anywhere), None);
        assert_eq!(quick_match("ПОЛ", "Отчёт о полёте.pdf", QuickSearchWhere::Anywhere), Some(vec![(8, 11)]));
    }
}
