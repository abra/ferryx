//! Bounded, in-memory document conversion. No include loaders or file access.

pub const MAX_INPUT_BYTES: usize = 512 * 1024;
pub const MAX_OFFICE_BYTES: usize = 32 * 1024 * 1024;
const MAX_OUTPUT_BYTES: usize = 8 * 1024 * 1024;
// Office HTML also carries base64-encoded pictures. Keep that transport budget
// separate from the smaller text-only converter output budget.
const MAX_OFFICE_OUTPUT_BYTES: usize = 32 * 1024 * 1024;

#[derive(Clone, Copy, Debug)]
pub enum Format {
    AsciiDoc,
    ReStructuredText,
    Rtf,
    Docx,
    Xlsx,
    Pptx,
    Doc,
    Xls,
    Ppt,
}

impl Format {
    fn office(self) -> Option<office_oxide::DocumentFormat> {
        use office_oxide::DocumentFormat as Office;
        Some(match self {
            Self::Docx => Office::Docx,
            Self::Xlsx => Office::Xlsx,
            Self::Pptx => Office::Pptx,
            Self::Doc => Office::Doc,
            Self::Xls => Office::Xls,
            Self::Ppt => Office::Ppt,
            _ => return None,
        })
    }
}

/// Body-only HTML; the host applies its own appearance and resource policy.
pub fn render(input: &[u8], format: Format) -> Result<String, String> {
    let office = format.office();
    if input.len() > if office.is_some() { MAX_OFFICE_BYTES } else { MAX_INPUT_BYTES } {
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
        _ => render_office(input, office.expect("office format"))?,
    };
    let max_output_bytes = if office.is_some() { MAX_OFFICE_OUTPUT_BYTES } else { MAX_OUTPUT_BYTES };
    if output.len() > max_output_bytes {
        return Err("converted document exceeds preview limit".into());
    }
    Ok(output)
}

fn render_office(input: &[u8], format: office_oxide::DocumentFormat) -> Result<String, String> {
    use office_oxide::ir_render::{HtmlOptions, ImageEmbed};
    let mut options = office_oxide::options::ParseOptions::strict();
    options.include_hidden_text = false;
    options.include_deleted_text = false;
    options.limits.package_entries = 4096;
    options.limits.package_bytes = 128 * 1024 * 1024;
    options.limits.part_bytes = 32 * 1024 * 1024;
    options.limits.text_chars = 2 * 1024 * 1024;
    options.limits.memory_bytes = 64 * 1024 * 1024;
    options.limits.embedded_depth = 0;
    let document =
        office_oxide::Document::from_reader_with(std::io::Cursor::new(input.to_vec()), format, &options)
            .map_err(|error| error.to_string())?;
    let mut output = LimitedOutput { bytes: Vec::new(), max_bytes: MAX_OFFICE_OUTPUT_BYTES };
    document
        .write_html_with(HtmlOptions { image_embed: ImageEmbed::Base64 }, &mut output)
        .map_err(|error| error.to_string())?;
    String::from_utf8(output.bytes).map_err(|error| error.to_string())
}

struct LimitedOutput {
    bytes: Vec<u8>,
    max_bytes: usize,
}

impl std::io::Write for LimitedOutput {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        if bytes.len() > self.max_bytes.saturating_sub(self.bytes.len()) {
            return Err(std::io::Error::other("converted document exceeds preview limit"));
        }
        self.bytes.extend_from_slice(bytes);
        Ok(bytes.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
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

    fn office_fixture(name: &str) -> Vec<u8> {
        use std::io::Read;
        let mut archive =
            zip::ZipArchive::new(std::io::Cursor::new(include_bytes!("../tests/fixtures/office.zip")))
                .unwrap();
        let mut bytes = Vec::new();
        archive.by_name(name).unwrap().read_to_end(&mut bytes).unwrap();
        bytes
    }

    #[test]
    fn office_formats_render_text_tables_sheets_and_slides_without_external_programs() {
        for (extension, format, heading, next) in [
            ("docx", Format::Docx, "Ferryx office preview", "Second document page"),
            ("doc", Format::Doc, "Ferryx office preview", "Second document page"),
            ("xlsx", Format::Xlsx, "Summary", "Second worksheet"),
            ("xls", Format::Xls, "Summary", "Second worksheet"),
            ("pptx", Format::Pptx, "Ferryx presentation", "Second slide"),
            ("ppt", Format::Ppt, "Ferryx presentation", "Second slide"),
        ] {
            let html = render(&office_fixture(&format!("fixture.{extension}")), format).unwrap();
            assert!(html.contains(heading), "{extension}: {html}");
            assert!(html.contains(next), "{extension}: {html}");
            if !matches!(format, Format::Pptx | Format::Ppt) {
                assert!(html.contains("<table"), "{extension}");
            }
            assert!(!html.contains("<script"), "{extension}");
        }
    }

    #[test]
    fn office_embedded_images_are_inlined_and_hidden_runs_are_excluded() {
        let html = render(&office_fixture("image.docx"), Format::Docx).unwrap();
        assert!(html.contains("data:image/png;base64,"), "{html}");
        assert!(!html.contains("HIDDEN_PREVIEW_TEXT"));
    }

    #[test]
    fn office_invalid_and_oversized_inputs_are_rejected() {
        for format in [Format::Docx, Format::Xlsx, Format::Pptx, Format::Doc, Format::Xls, Format::Ppt] {
            assert!(render(b"not an office document", format).is_err());
        }
        assert!(render(&vec![0; MAX_OFFICE_BYTES + 1], Format::Docx).is_err());
        let mut output = LimitedOutput { bytes: vec![0; 4], max_bytes: 4 };
        assert!(std::io::Write::write_all(&mut output, b"overflow").is_err());
        assert_eq!(output.bytes.len(), 4);
    }

    #[test]
    fn office_image_payload_can_exceed_the_text_only_html_budget() {
        use std::io::{Read, Write};
        let mut source = zip::ZipArchive::new(std::io::Cursor::new(office_fixture("image.docx"))).unwrap();
        let mut target = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
        for index in 0..source.len() {
            let mut entry = source.by_index(index).unwrap();
            let name = entry.name().to_owned();
            let mut bytes = Vec::new();
            entry.read_to_end(&mut bytes).unwrap();
            if name.starts_with("word/media/") && name.ends_with(".png") {
                // PNG decoders ignore trailing bytes. The document remains a
                // valid image fixture without checking a large binary into git.
                bytes.resize(3 * 1024 * 1024, 0);
            } else if name == "word/document.xml" {
                let mut xml = String::from_utf8(bytes).unwrap();
                let drawing = xml.find("<w:drawing").unwrap();
                let start = xml[..drawing].rfind("<w:p>").unwrap();
                let end = drawing + xml[drawing..].find("</w:p>").unwrap() + "</w:p>".len();
                let picture = xml[start..end].to_owned();
                // Two references fit the per-image allowance but their
                // combined base64 payload exceeds the old HTML allowance.
                xml = xml.replace("</w:body>", &format!("{picture}</w:body>"));
                bytes = xml.into_bytes();
            }
            target.start_file(name, zip::write::SimpleFileOptions::default()).unwrap();
            target.write_all(&bytes).unwrap();
        }
        let bytes = target.finish().unwrap().into_inner();
        let html = render(&bytes, Format::Docx).unwrap();
        assert!(html.len() > MAX_OUTPUT_BYTES);
        assert!(html.len() <= MAX_OFFICE_OUTPUT_BYTES);
        assert!(html.contains("data:image/png;base64,"));
        assert!(html.contains("Ferryx office preview"));
    }

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
