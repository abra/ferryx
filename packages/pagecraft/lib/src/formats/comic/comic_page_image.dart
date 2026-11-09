import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'comic_page_source.dart';

/// One comic page decoded to a target width.
///
/// A regular [ImageProvider], so pages go through the framework's image
/// cache, `Image` widgets, `precacheImage` and error handling. Decoding at
/// [targetWidth] (the screen width in device pixels for a page, a
/// thumbnail width for previews) bounds memory per page to what is shown
/// instead of the scan's full resolution; the engine decodes off the UI
/// thread. Two providers are the same cache key when they name the same
/// source object, page and width.
///
/// Bytes come straight from the source: reading a stored ZIP entry is a
/// file read, and decoding, the costly part, already runs on the engine's
/// worker. If a measurement ever shows the read itself on the UI thread,
/// the source can move its reads into an isolate without changing this.
@immutable
class ComicPageImage extends ImageProvider<ComicPageImage> {
  const ComicPageImage({
    required this.source,
    required this.pageIndex,
    required this.targetWidth,
    this.maxBytes,
  }) : assert(targetWidth > 0);

  final ComicPageSource source;
  final int pageIndex;

  /// Decoded width in pixels when the page is wider; narrower pages keep
  /// their size.
  final int targetWidth;

  /// Pages above this many encoded bytes are refused before reading, as
  /// an error on the image stream.
  final int? maxBytes;

  /// The width the WebView reader rendered previews at.
  static const thumbnailWidth = 240;

  /// Previews skip pages above this size, as the former WebView reader did.
  static const thumbnailMaxBytes = 16 * 1024 * 1024;

  @override
  Future<ComicPageImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ComicPageImage>(this);

  @override
  ImageStreamCompleter loadImage(
    ComicPageImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _decode(decode),
      scale: 1,
      debugLabel: 'ComicPageImage($pageIndex@$targetWidth)',
      informationCollector: () => [
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<int>('Page', pageIndex),
      ],
    );
  }

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await source.readPage(pageIndex, maxBytes: maxBytes);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(
      buffer,
      getTargetSize: (intrinsicWidth, intrinsicHeight) =>
          intrinsicWidth > targetWidth
          ? ui.TargetImageSize(width: targetWidth)
          : ui.TargetImageSize(width: intrinsicWidth, height: intrinsicHeight),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ComicPageImage &&
      identical(other.source, source) &&
      other.pageIndex == pageIndex &&
      other.targetWidth == targetWidth &&
      other.maxBytes == maxBytes;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(source), pageIndex, targetWidth, maxBytes);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'ComicPageImage')}(page: $pageIndex, targetWidth: $targetWidth)';
}
