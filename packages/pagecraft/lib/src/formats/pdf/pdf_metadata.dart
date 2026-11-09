import 'pdf_book.dart';
import '../../metadata/book_metadata.dart';
import '../../metadata/cover_thumbnail.dart';

/// The title, author and cover of the PDF at [path], for the library's
/// import: the counterpart of `getMetadata` in `book.js` over `pdf.js`.
///
/// The title is the Info dictionary's, or the file name without its
/// extension when the PDF has none (the WebView import stored "Unknown"
/// for those). The cover is the first page rendered by pdfium straight at
/// the size that fits [spec], then encoded as a JPEG. Throws
/// [PdfPasswordRequiredException] for an encrypted file, which the import
/// refuses, and [PagecraftException] for a file pdfium cannot read.
Future<BookMetadata> readPdfMetadata(
  String path, {
  CoverThumbnailSpec spec = const CoverThumbnailSpec(),
}) async {
  final book = await PdfBook.open(path);
  try {
    return BookMetadata(
      title: book.title ?? _titleFromFileName(path),
      author: book.author,
      cover: await _renderCover(book, spec),
    );
  } finally {
    await book.close();
  }
}

Future<CoverImage?> _renderCover(PdfBook book, CoverThumbnailSpec spec) async {
  if (book.pageCount == 0) return null;
  final first = book.pages.first;
  final size = spec.fit(first.width.round(), first.height.round());
  final page = book.document.pages.first;
  final rendered = await page.render(
    width: size.width,
    height: size.height,
    fullWidth: size.width.toDouble(),
    fullHeight: size.height.toDouble(),
  );
  if (rendered == null) return null;
  try {
    return await encodeCoverFromPixels(
      rendered.pixels,
      width: rendered.width,
      height: rendered.height,
      order: CoverPixelOrder.bgra,
      spec: spec,
    );
  } finally {
    rendered.dispose();
  }
}

String _titleFromFileName(String path) {
  final slash = path.lastIndexOf('/');
  final name = slash < 0 ? path : path.substring(slash + 1);
  return name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
}
