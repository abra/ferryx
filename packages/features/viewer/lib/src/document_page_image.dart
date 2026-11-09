import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pagecraft/comic.dart';

/// A comic scan decoded within both the pixel and dimension budgets. Limiting
/// width alone is insufficient for long strips with a small aspect ratio.
class DocumentComicPageImage extends ImageProvider<DocumentComicPageImage> {
  const DocumentComicPageImage({
    required this.source,
    required this.pageIndex,
    required this.targetWidth,
  });

  static const maxPixels = 6000000;
  static const maxSide = 8192;
  static const maxEncodedBytes = 64 << 20;
  final ComicPageSource source;
  final int pageIndex;
  final int targetWidth;

  @override
  Future<DocumentComicPageImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    DocumentComicPageImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _decode(decode), scale: 1);

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await source.readPage(pageIndex, maxBytes: maxEncodedBytes);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(
      buffer,
      getTargetSize: (width, height) {
        final scale = [
          1.0,
          math.max(1, targetWidth) / width,
          math.sqrt(maxPixels / (width * height)),
          maxSide / width,
          maxSide / height,
        ].reduce(math.min);
        return ui.TargetImageSize(
          width: math.max(1, (width * scale).floor()),
          height: math.max(1, (height * scale).floor()),
        );
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DocumentComicPageImage &&
      identical(source, other.source) &&
      pageIndex == other.pageIndex &&
      targetWidth == other.targetWidth;
  @override
  int get hashCode =>
      Object.hash(identityHashCode(source), pageIndex, targetWidth);
}

class DocumentComicPages implements FixedPageSource {
  const DocumentComicPages(this.source);
  final ComicPageSource source;
  @override
  int get pageCount => source.pageCount;
  @override
  double? pageAspect(int index) => null;
  @override
  ImageProvider pageImage(int index, {required int targetWidth}) =>
      DocumentComicPageImage(
        source: source,
        pageIndex: index,
        targetWidth: targetWidth,
      );
  @override
  ImageProvider pageThumbnail(int index) => pageImage(index, targetWidth: 240);
  @override
  ImageProvider? pageTile(
    int index, {
    required int fullWidth,
    required ({int x, int y, int width, int height}) region,
  }) => null;
}

/// Render failures go through Image.errorBuilder rather than throwing in build.
class DocumentUnrenderablePage extends ImageProvider<DocumentUnrenderablePage> {
  const DocumentUnrenderablePage();
  @override
  Future<DocumentUnrenderablePage> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    DocumentUnrenderablePage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future<ImageInfo>.error(
      const PagecraftException('Page dimensions exceed the rendering limits'),
    ),
  );
}
