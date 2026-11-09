import 'package:flutter/painting.dart';

import '../../fixed_layout/fixed_page_source.dart';
import 'comic_page_image.dart';
import 'comic_page_source.dart';

/// A comic's pages as [FixedPageSource]: decoded by `ComicPageImage` from
/// the bytes of a `ComicPageSource`.
class ComicPages implements FixedPageSource {
  const ComicPages(this.source);

  final ComicPageSource source;

  @override
  int get pageCount => source.pageCount;

  @override
  double? pageAspect(int index) => null;

  @override
  ImageProvider pageImage(int index, {required int targetWidth}) =>
      ComicPageImage(
        source: source,
        pageIndex: index,
        targetWidth: targetWidth,
      );

  @override
  ImageProvider pageThumbnail(int index) => ComicPageImage(
    source: source,
    pageIndex: index,
    targetWidth: ComicPageImage.thumbnailWidth,
    maxBytes: ComicPageImage.thumbnailMaxBytes,
  );

  @override
  ImageProvider? pageTile(
    int index, {
    required int fullWidth,
    required ({int x, int y, int width, int height}) region,
  }) => null;

  @override
  bool operator ==(Object other) =>
      other is ComicPages && identical(other.source, source);

  @override
  int get hashCode => identityHashCode(source);
}
