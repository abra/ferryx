//! Bounded, in-memory document conversion. No include loaders or file access.

pub const MAX_INPUT_BYTES: usize = 512 * 1024;
const MAX_OUTPUT_BYTES: usize = 8 * 1024 * 1024;

#[derive(Clone, Copy, Debug)]
pub enum Format {
    AsciiDoc,
    ReStructuredText,
    Rtf,
}

/// Body-only HTML; the host applies its own appearance and resource policy.
pub fn render(input: &[u8], format: Format) -> Result<String, String> {
    if input.len() > MAX_INPUT_BYTES {
        return Err("document exceeds preview limit".into());
    }
    let output = match format {
        Format::AsciiDoc => {
            let source = std::str::from_utf8(input).map_err(|_| "invalid UTF-8")?;
            asciidoc_html5::convert_with(
                source,
                &asciidoc_html5::Options::new().safe_mode(asciidoc_html5::SafeMode::Secure),
            )
        }
        Format::ReStructuredText => {
            let source = std::str::from_utf8(input).map_err(|_| "invalid UTF-8")?;
            let document = rst_parser::parse(source).map_err(|e| e.to_string())?;
            let mut html = Vec::new();
            rst_renderer::render_html(&document, &mut html, false).map_err(|e| e.to_string())?;
            String::from_utf8(html).map_err(|e| e.to_string())?
        }
        Format::Rtf => render_rtf(input)?,
    };
    if output.len() > MAX_OUTPUT_BYTES {
        return Err("converted document exceeds preview limit".into());
    }
    Ok(output)
}

fn render_rtf(input: &[u8]) -> Result<String, String> {
    let document = rclip_rtf::Document::parse(input).map_err(|e| format!("{e:?}"))?;
    let mut html = String::from("<div>");
    for run in &document.runs {
        let props = run.props;
        let tags =
            [(props.bold, "strong"), (props.italic, "em"), (props.underline, "u"), (props.strike, "s")];
        for &(enabled, tag) in &tags {
            if enabled {
                html.push('<');
                html.push_str(tag);
                html.push('>');
            }
        }
        for c in document.text[run.range.clone()].chars() {
            match c {
                '&' => html.push_str("&amp;"),
                '<' => html.push_str("&lt;"),
                '>' => html.push_str("&gt;"),
                '"' => html.push_str("&quot;"),
                '\n' => html.push_str("<br>"),
                '\t' => html.push_str("&emsp;"),
                _ => html.push(c),
            }
        }
        for &(enabled, tag) in tags.iter().rev() {
            if enabled {
                html.push_str("</");
                html.push_str(tag);
                html.push('>');
            }
        }
    }
    html.push_str("</div>");
    Ok(html)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn asciidoc_sections_lists_and_emphasis() {
        let html = render(b"= Guide\n\n== Section\n\n* *bold*\n* next", Format::AsciiDoc).unwrap();
        assert!(html.contains("Section"));
        assert!(html.contains("<strong>bold</strong>"));
        assert!(html.contains("<ul"));
    }

    #[test]
    fn asciidoc_cannot_read_includes_or_docinfo() {
        let html = render(b":docinfo: shared\n\ninclude::/etc/passwd[]", Format::AsciiDoc).unwrap();
        assert!(!html.contains("root:"));
        assert!(html.contains("/etc/passwd"));
    }

    #[test]
    fn rst_sections_lists_and_links() {
        let html = render(
            b"Guide\n=====\n\n* **bold**\n* next\n\n`Link <https://example.com>`_",
            Format::ReStructuredText,
        )
        .unwrap();
        assert!(html.contains("Guide"));
        assert!(html.contains("<strong>bold</strong>"));
        assert!(html.contains("https://example.com"));
    }

    #[test]
    fn rtf_styles_paragraphs_unicode_and_ignored_destinations() {
        let html = render(br"{\rtf1\ansi{\*\generator TextEdit;}Hello {\b bold} {\i italic}\par \u1055?\u1088?\u1080?\u1074?\u1077?\u1090?}", Format::Rtf).unwrap();
        assert!(html.contains("<strong>bold</strong>"));
        assert!(html.contains("<em>italic</em>"));
        assert!(html.contains("<br>"));
        assert!(html.contains("Привет"));
        assert!(!html.contains("TextEdit"));
        assert!(!html.contains('?'));
    }

    #[test]
    fn rtf_legacy_cyrillic_and_markup_are_decoded_and_escaped() {
        let html =
            render(br"{\rtf1\ansi\ansicpg1251 \'cf\'f0\'e8\'e2\'e5\'f2 <script>}", Format::Rtf).unwrap();
        assert!(html.contains("Привет"));
        assert!(html.contains("&lt;script&gt;"));
    }

    #[test]
    fn malformed_and_excessive_input_is_rejected() {
        assert!(render(b"not RTF", Format::Rtf).is_err());
        assert!(render(b"{\\rtf1 unclosed", Format::Rtf).is_err());
        assert!(render(&vec![b'a'; MAX_INPUT_BYTES + 1], Format::AsciiDoc).is_err());
        let nested = format!("{{\\rtf1 {}x{} }}", "{".repeat(1000), "}".repeat(1000));
        assert!(render(nested.as_bytes(), Format::Rtf).is_err());
    }
}
