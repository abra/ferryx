//! File masks and regular expressions, as the Select-with-mask and Find
//! Files dialogs take them.

use regex::{Regex, RegexBuilder};

/// A compiled filter over file names.
#[derive(Clone, Debug)]
pub struct NameFilter {
    regex: Regex,
}

impl NameFilter {
    /// A mask of `*` (any run), `?` (one character) and `[…]` classes, or
    /// several separated by `;` or `,` (`*.jpg;*.png`); case-insensitive.
    /// A mask without a wildcard matches names containing it, as typing
    /// `report` should find `report-2024.pdf`.
    pub fn mask(mask: &str) -> Result<NameFilter, String> {
        let parts: Vec<&str> = mask.split([';', ',']).map(str::trim).filter(|p| !p.is_empty()).collect();
        if parts.is_empty() {
            return Err("empty mask".to_string());
        }
        let alternatives: Vec<String> = parts.iter().map(|p| mask_to_regex(p)).collect();
        let pattern = format!("^(?:{})$", alternatives.join("|"));
        RegexBuilder::new(&pattern)
            .case_insensitive(true)
            .build()
            .map(|regex| NameFilter { regex })
            .map_err(|e| e.to_string())
    }

    /// A regular expression over the whole name; a partial match counts.
    pub fn regex(pattern: &str, case_sensitive: bool) -> Result<NameFilter, String> {
        RegexBuilder::new(pattern)
            .case_insensitive(!case_sensitive)
            .build()
            .map(|regex| NameFilter { regex })
            .map_err(|e| e.to_string())
    }

    pub fn matches(&self, name: &str) -> bool {
        self.regex.is_match(name)
    }
}

fn mask_to_regex(mask: &str) -> String {
    let has_wildcard = mask.contains(['*', '?', '[']);
    let mut out = String::new();
    if !has_wildcard {
        out.push_str(".*");
    }
    let mut chars = mask.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '*' => out.push_str(".*"),
            '?' => out.push('.'),
            '[' => {
                let mut class = String::from("[");
                let mut closed = false;
                for inner in chars.by_ref() {
                    if inner == ']' {
                        closed = true;
                        break;
                    }
                    if inner == '\\' || inner == '[' {
                        class.push('\\');
                    }
                    class.push(inner);
                }
                if closed && class.len() > 1 {
                    class.push(']');
                    out.push_str(&class);
                } else {
                    out.push_str(&regex::escape(&class));
                }
            }
            other => out.push_str(&regex::escape(&other.to_string())),
        }
    }
    if !has_wildcard {
        out.push_str(".*");
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn star_and_question_mark() {
        let f = NameFilter::mask("*.txt").unwrap();
        assert!(f.matches("a.txt"));
        assert!(f.matches("A.TXT"));
        assert!(!f.matches("a.txt.bak"));
        let q = NameFilter::mask("img_??.png").unwrap();
        assert!(q.matches("img_01.png"));
        assert!(!q.matches("img_001.png"));
    }

    #[test]
    fn several_masks() {
        let f = NameFilter::mask("*.jpg; *.png").unwrap();
        assert!(f.matches("x.jpg"));
        assert!(f.matches("x.png"));
        assert!(!f.matches("x.gif"));
    }

    #[test]
    fn plain_text_matches_anywhere() {
        let f = NameFilter::mask("report").unwrap();
        assert!(f.matches("Q3-Report-final.pdf"));
        assert!(!f.matches("summary.pdf"));
    }

    #[test]
    fn classes_and_escapes() {
        let f = NameFilter::mask("file[0-9].c").unwrap();
        assert!(f.matches("file3.c"));
        assert!(!f.matches("fileX.c"));
        let dot = NameFilter::mask("a.b").unwrap();
        assert!(!dot.matches("axb"));
    }

    #[test]
    fn regex_filter() {
        let f = NameFilter::regex(r"^\d{4}-\d{2}", false).unwrap();
        assert!(f.matches("2024-10 notes.md"));
        assert!(!f.matches("notes 2024-10.md"));
        assert!(NameFilter::regex("(", false).is_err());
    }
}
