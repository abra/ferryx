import 'package:flutter/widgets.dart';

import 'comic_page_source.dart';
import 'comic_page_image.dart';

/// A small preview of one page for lists of bookmarks and highlights.
///
/// Decoded at `ComicPageImage.thumbnailWidth` through the same provider as
/// the pages, so it shares the image cache and costs one small bitmap.
/// Pages above `ComicPageImage.thumbnailMaxBytes` and pages that fail to
/// decode show [placeholder].
class ComicPageThumbnail extends StatelessWidget {
  const ComicPageThumbnail({
    super.key,
    required this.source,
    required this.page,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.placeholder = const ColoredBox(color: Color(0x14808080)),
    this.semanticLabel,
  });

  final ComicPageSource source;
  final int page;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final Widget placeholder;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ComicPageImage(
        source: source,
        pageIndex: page,
        targetWidth: ComicPageImage.thumbnailWidth,
        maxBytes: ComicPageImage.thumbnailMaxBytes,
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
