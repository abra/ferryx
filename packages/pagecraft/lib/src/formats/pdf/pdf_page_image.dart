import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'pdf_book.dart';

/// One PDF page rendered by pdfium to a target width.
///
/// A regular [ImageProvider], like `ComicPageImage`: pages go through the
/// framework's image cache, `Image`, `precacheImage` and error handling,
/// and two providers are one cache entry when they name the same book
/// object, page and width. pdfium renders in the engine's worker isolate
/// into a BGRA buffer; the frame becomes a GPU texture through
/// `decodeImageFromPixels` without a Dart-side copy of the page.
///
/// Rendering at [targetWidth] (the frame width in device pixels, a
/// thumbnail width for previews) keeps memory per page at what is shown.
/// A width that would exceed [maxPixels] is reduced; a sharper view of a
/// zoomed page is a [PdfPageTile], not a larger page.
@immutable
class PdfPageImage extends ImageProvider<PdfPageImage> {
  PdfPageImage({
    required this.book,
    required this.pageIndex,
    required int targetWidth,
  }) : assert(targetWidth > 0),
       targetWidth = boundedPdfRenderWidth(
         targetWidth,
         book.pages[pageIndex].aspectRatio,
       );

  final PdfBook book;
  final int pageIndex;

  /// Rendered width in pixels; the height follows the page's ratio.
  final int targetWidth;

  /// The width the WebView reader rendered previews at.
  static const thumbnailWidth = 240;

  /// Pixel budget of one render: about two phone screens, 24 MiB of BGRA,
  /// the same cap the WebView reader put on a page bitmap.
  static const maxPixels = 6000000;

  int get targetHeight => pdfRenderHeight(targetWidth, pageIndex, book);

  @override
  Future<PdfPageImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<PdfPageImage>(this);

  @override
  ImageStreamCompleter loadImage(
    PdfPageImage key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      _render().then((image) => ImageInfo(image: image)),
      informationCollector: () => [
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<int>('Page', pageIndex),
      ],
    );
  }

  Future<ui.Image> _render() => renderPdfPixels(
    book.document.pages[pageIndex],
    fullWidth: targetWidth,
    fullHeight: targetHeight,
  );

  @override
  bool operator ==(Object other) =>
      other is PdfPageImage &&
      identical(other.book, book) &&
      other.pageIndex == pageIndex &&
      other.targetWidth == targetWidth;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(book), pageIndex, targetWidth);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'PdfPageImage')}(page: $pageIndex, targetWidth: $targetWidth)';
}

/// A sharp piece of a zoomed PDF page.
///
/// [region] is the part to render, in pixels of the page rendered at
/// [fullWidth]; it must fit [PdfPageImage.maxPixels]. The zoom layer draws
/// it over the fitted page, as the WebView reader drew sharp tiles over
/// its blurred bitmap, so a 4× zoom never costs a 4× page.
@immutable
class PdfPageTile extends ImageProvider<PdfPageTile> {
  PdfPageTile({
    required this.book,
    required this.pageIndex,
    required this.fullWidth,
    required this.region,
  }) : assert(fullWidth > 0),
       assert(region.width > 0 && region.height > 0),
       assert(
         region.width * region.height <= PdfPageImage.maxPixels,
         'tile exceeds PdfPageImage.maxPixels',
       );

  final PdfBook book;
  final int pageIndex;

  /// Width of the whole page at this zoom, in pixels.
  final int fullWidth;

  /// The rendered part, in pixels of the page at [fullWidth].
  final ({int x, int y, int width, int height}) region;

  int get fullHeight => pdfRenderHeight(fullWidth, pageIndex, book);

  @override
  Future<PdfPageTile> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<PdfPageTile>(this);

  @override
  ImageStreamCompleter loadImage(
    PdfPageTile key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      renderPdfPixels(
        book.document.pages[pageIndex],
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        x: region.x,
        y: region.y,
        width: region.width,
        height: region.height,
      ).then((image) => ImageInfo(image: image)),
      informationCollector: () => [
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<int>('Page', pageIndex),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfPageTile &&
      identical(other.book, book) &&
      other.pageIndex == pageIndex &&
      other.fullWidth == fullWidth &&
      other.region == region;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(book), pageIndex, fullWidth, region);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'PdfPageTile')}(page: $pageIndex, fullWidth: $fullWidth, region: $region)';
}

/// [targetWidth], or the largest width whose full page of [aspectRatio]
/// stays within [PdfPageImage.maxPixels].
int boundedPdfRenderWidth(int targetWidth, double aspectRatio) {
  final height = targetWidth / aspectRatio;
  if (targetWidth * height <= PdfPageImage.maxPixels) return targetWidth;
  return math.sqrt(PdfPageImage.maxPixels * aspectRatio).floor();
}

/// The height of page [pageIndex] rendered [width] pixels wide, at least 1.
int pdfRenderHeight(int width, int pageIndex, PdfBook book) {
  final page = book.pages[pageIndex];
  return (width * page.height / page.width).round().clamp(1, 1 << 30);
}

/// Renders with pdfium and wraps the BGRA buffer as a [ui.Image].
///
/// The engine's buffer is native memory viewed from Dart, so it is freed
/// only after the framework has copied it into the image.
Future<ui.Image> renderPdfPixels(
  PdfPage page, {
  required int fullWidth,
  required int fullHeight,
  int x = 0,
  int y = 0,
  int? width,
  int? height,
}) async {
  final rendered = await page.render(
    x: x,
    y: y,
    width: width ?? fullWidth,
    height: height ?? fullHeight,
    fullWidth: fullWidth.toDouble(),
    fullHeight: fullHeight.toDouble(),
  );
  if (rendered == null) {
    throw StateError('pdfium did not render page ${page.pageNumber}');
  }
  try {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rendered.pixels,
      rendered.width,
      rendered.height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    return await completer.future;
  } finally {
    rendered.dispose();
  }
}
