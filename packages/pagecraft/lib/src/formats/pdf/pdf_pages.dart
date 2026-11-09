import 'package:flutter/painting.dart';

import 'pdf_book.dart';
import '../../fixed_layout/fixed_page_source.dart';
import 'pdf_page_image.dart';

/// A PDF's pages as [FixedPageSource]: rendered by pdfium through
/// `PdfPageImage`, with sharp tiles for zoom through `PdfPageTile`.
class PdfPages implements FixedPageSource {
  const PdfPages(this.book);

  final PdfBook book;

  @override
  int get pageCount => book.pageCount;

  @override
  double? pageAspect(int index) => book.pages[index].aspectRatio;

  @override
  ImageProvider pageImage(int index, {required int targetWidth}) =>
      PdfPageImage(book: book, pageIndex: index, targetWidth: targetWidth);

  @override
  ImageProvider pageThumbnail(int index) => PdfPageImage(
    book: book,
    pageIndex: index,
    targetWidth: PdfPageImage.thumbnailWidth,
  );

  @override
  ImageProvider? pageTile(
    int index, {
    required int fullWidth,
    required ({int x, int y, int width, int height}) region,
  }) => PdfPageTile(
    book: book,
    pageIndex: index,
    fullWidth: fullWidth,
    region: region,
  );

  @override
  bool operator ==(Object other) =>
      other is PdfPages && identical(other.book, book);

  @override
  int get hashCode => identityHashCode(book);
}
