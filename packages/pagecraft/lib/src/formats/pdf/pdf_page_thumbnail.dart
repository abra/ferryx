import 'package:flutter/widgets.dart';

import 'pdf_book.dart';
import 'pdf_page_image.dart';

/// A small preview of one PDF page for lists of bookmarks and highlights.
///
/// Rendered at `PdfPageImage.thumbnailWidth` through the same provider as
/// the pages, so it shares the image cache and costs one small bitmap.
/// A page that fails to render shows [placeholder].
class PdfPageThumbnail extends StatelessWidget {
  const PdfPageThumbnail({
    super.key,
    required this.book,
    required this.page,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.placeholder = const ColoredBox(color: Color(0x14808080)),
    this.semanticLabel,
  });

  final PdfBook book;
  final int page;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final Widget placeholder;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: PdfPageImage(
        book: book,
        pageIndex: page,
        targetWidth: PdfPageImage.thumbnailWidth,
      ),
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}
