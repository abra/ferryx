//! Read-only converters run on bridge workers, over already bounded bytes.
use super::types::{ApiResult, FerryxError, FerryxErrorKind};
use ferryx_core::text_document::{self, Format};

pub enum TextDocumentFormatView {
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

pub fn render_text_document(bytes: Vec<u8>, format: TextDocumentFormatView) -> ApiResult<String> {
    let format = match format {
        TextDocumentFormatView::AsciiDoc => Format::AsciiDoc,
        TextDocumentFormatView::ReStructuredText => Format::ReStructuredText,
        TextDocumentFormatView::Rtf => Format::Rtf,
        TextDocumentFormatView::Docx => Format::Docx,
        TextDocumentFormatView::Xlsx => Format::Xlsx,
        TextDocumentFormatView::Pptx => Format::Pptx,
        TextDocumentFormatView::Doc => Format::Doc,
        TextDocumentFormatView::Xls => Format::Xls,
        TextDocumentFormatView::Ppt => Format::Ppt,
    };
    text_document::render(&bytes, format)
        .map_err(|message| FerryxError::new(FerryxErrorKind::Unsupported, message))
}
