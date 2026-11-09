import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../fixed_layout/fixed_page_source.dart';
import 'djvu_book.dart';

class DjvuPages implements FixedPageSource {
  const DjvuPages(this.book);
  final DjvuBook book;

  @override
  int get pageCount => book.pageCount;
  @override
  double pageAspect(int index) => book.pages[index].aspectRatio;
  @override
  ImageProvider pageImage(int index, {required int targetWidth}) =>
      DjvuPageImage(book: book, pageIndex: index, targetWidth: targetWidth);
  @override
  ImageProvider pageThumbnail(int index) =>
      DjvuPageImage(book: book, pageIndex: index, targetWidth: 240);
  @override
  ImageProvider pageTile(
    int index, {
    required int fullWidth,
    required ({int x, int y, int width, int height}) region,
  }) => DjvuPageImage(
    book: book,
    pageIndex: index,
    targetWidth: fullWidth,
    region: region,
  );

  @override
  bool operator ==(Object other) =>
      other is DjvuPages && identical(book, other.book);
  @override
  int get hashCode => identityHashCode(book);
}

/// Cache identity includes document, page, scale and region. The native decoder
/// runs off the UI isolate; only the final frame is uploaded by Flutter here.
@immutable
class DjvuPageImage extends ImageProvider<DjvuPageImage> {
  DjvuPageImage({
    required this.book,
    required this.pageIndex,
    required int targetWidth,
    this.region,
  }) : targetWidth = region == null
           ? boundedDjvuRenderWidth(
               targetWidth,
               book.pages[pageIndex].aspectRatio,
             )
           : targetWidth;

  final DjvuBook book;
  final int pageIndex;
  final int targetWidth;
  final ({int x, int y, int width, int height})? region;

  @override
  Future<DjvuPageImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    DjvuPageImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    _render().then((image) => ImageInfo(image: image)),
    informationCollector: () => [IntProperty('DjVu page', pageIndex)],
  );

  Future<ui.Image> _render() async {
    final frame = await book.renderPage(
      pageIndex,
      targetWidth: targetWidth,
      region: region,
    );
    final ready = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.pixels,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      ready.complete,
    );
    return ready.future;
  }

  @override
  bool operator ==(Object other) =>
      other is DjvuPageImage &&
      identical(book, other.book) &&
      pageIndex == other.pageIndex &&
      targetWidth == other.targetWidth &&
      region == other.region;
  @override
  int get hashCode =>
      Object.hash(identityHashCode(book), pageIndex, targetWidth, region);
}
