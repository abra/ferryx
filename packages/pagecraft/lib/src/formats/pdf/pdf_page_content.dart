import 'dart:math' as math;

import 'pdf_book.dart';
import '../../image/page_content.dart';

/// The printed area of page [pageIndex] of [book], in page points, or
/// null for a blank page.
///
/// pdfium draws a sample with its long side at [pageContentSampleSize]
/// pixels and [detectContentBox] reads it; the result is scaled back to
/// points, so the margin crop can be planned before the page is rendered
/// at screen size.
Future<ContentBox?> detectPdfPageContent(PdfBook book, int pageIndex) async {
  final page = book.pages[pageIndex];
  final longSide = math.max(page.width, page.height);
  final scale = pageContentSampleSize / longSide;
  final width = math.max(1, (page.width * scale).round());
  final height = math.max(1, (page.height * scale).round());
  final rendered = await book.document.pages[pageIndex].render(
    width: width,
    height: height,
    fullWidth: width.toDouble(),
    fullHeight: height.toDouble(),
  );
  if (rendered == null) return null;
  try {
    final box = detectContentBox(
      rendered.pixels,
      rendered.width,
      rendered.height,
      order: PixelOrder.bgra,
    );
    return box?.scaled(1 / scale);
  } finally {
    rendered.dispose();
  }
}
