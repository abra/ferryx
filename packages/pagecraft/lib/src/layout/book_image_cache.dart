import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_svg/flutter_svg.dart'
    show PictureInfo, SvgBytesLoader, vg;

import '../image/image_dimensions.dart';

/// Reads the bytes of an image by its key, or null when there are none.
typedef BookImageReader = Future<Uint8List?> Function(String key);

/// The images of a reflowable book, for its text pages: sizes probed
/// from headers before layout (an image's box must be known before the
/// lines around it are), pixels decoded at the size they are drawn,
/// within a byte budget.
///
/// Keys are whatever the book's source resolves image sources to (a
/// path in the EPUB, an FB2 binary id). Listeners hear when an image
/// they asked for has been decoded, so pages repaint.
class BookImageCache extends ChangeNotifier {
  BookImageCache({
    required this.read,
    this.budgetBytes = 48 << 20,
    this.bytesBudget = 16 << 20,
  });

  final BookImageReader read;

  /// Decoded pixels kept, in bytes (4 per pixel).
  final int budgetBytes;

  /// Encoded bytes kept between probing and decoding.
  final int bytesBudget;

  final _sizes = <String, Size?>{};

  /// Insertion-ordered: least recently kept first.
  final _bytes = <String, Uint8List>{};
  int _bytesTotal = 0;

  /// Insertion-ordered: least recently used first.
  final _images = <String, _Decoded>{};
  int _imagesTotal = 0;
  final _decoding = <String, int>{};
  bool _disposed = false;

  /// The intrinsic sizes of [keys] that have one, probing the headers of
  /// those not seen yet. Images that cannot be read or are not a
  /// supported format have none.
  Future<Map<String, Size>> probe(Iterable<String> keys) async {
    final missing = [
      for (final k in keys.toSet())
        if (!_sizes.containsKey(k)) k,
    ];
    await Future.wait(missing.map(_probe));
    return {
      for (final k in keys) k: ?_sizes[k],
    };
  }

  Future<void> _probe(String key) async {
    Uint8List? bytes;
    try {
      bytes = await read(key);
    } on Exception {
      bytes = null;
    }
    if (_disposed) return;
    final dims = bytes == null ? null : probeImageDimensions(bytes);
    _sizes[key] = dims == null
        ? null
        : Size(dims.width.toDouble(), dims.height.toDouble());
    if (bytes != null && dims != null) _keepBytes(key, bytes);
  }

  /// The size [probe] found for [key], if any.
  Size? sizeOf(String key) => _sizes[key];

  /// [key] decoded at least about [pixelWidth] wide (never above its
  /// own size), or null while it decodes or when it cannot be:
  /// listeners hear when it is ready. A smaller decode is returned while
  /// a larger one is under way.
  ui.Image? image(String key, int pixelWidth) {
    final decoded = _images[key];
    if (decoded != null) {
      // Most recently used last.
      _images.remove(key);
      _images[key] = decoded;
      if (decoded.image.width >= pixelWidth * 0.9) return decoded.image;
    }
    if (pixelWidth > 0) {
      final pending = _decoding[key];
      if (pending == null || pending < pixelWidth) {
        unawaited(_decode(key, pixelWidth));
      }
    }
    return decoded?.image;
  }

  Future<void> _decode(String key, int width) async {
    _decoding[key] = width;
    try {
      var bytes = _bytes.remove(key);
      if (bytes != null) {
        _bytesTotal -= bytes.length;
      } else {
        bytes = await read(key);
      }
      if (bytes == null || _disposed) return;
      final image = isSvgImage(bytes)
          ? await _renderSvg(bytes, width)
          : await _decodeRaster(bytes, width);
      if (image == null) return;
      if (_disposed) {
        image.dispose();
        return;
      }
      final old = _images.remove(key);
      if (old != null) {
        _imagesTotal -= old.bytes;
        old.image.dispose();
      }
      final decoded = _Decoded(image);
      _images[key] = decoded;
      _imagesTotal += decoded.bytes;
      _evictImages(keep: key);
      _keepBytes(key, bytes);
      notifyListeners();
    } on Exception {
      // Not an image the engine decodes (a damaged file): the page keeps
      // its box empty.
    } finally {
      if (_decoding[key] == width) _decoding.remove(key);
    }
  }

  /// [bytes] decoded at most [width] pixels wide: the engine scales while
  /// decoding (JPEG natively), keeping the ratio.
  static Future<ui.Image> _decodeRaster(Uint8List bytes, int width) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (intrinsicWidth, intrinsicHeight) =>
          intrinsicWidth <= width
          ? ui.TargetImageSize(width: intrinsicWidth, height: intrinsicHeight)
          : ui.TargetImageSize(width: width),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// SVG [bytes] drawn [width] pixels wide (a vector draws sharp at any
  /// size; [_maxSvgSide] at most a side), or null when it does not parse.
  static Future<ui.Image?> _renderSvg(Uint8List bytes, int width) async {
    final PictureInfo info;
    try {
      info = await vg.loadPicture(SvgBytesLoader(bytes), null);
    } on Object {
      return null;
    }
    try {
      final size = info.size;
      if (size.isEmpty) return null;
      var scale = width / size.width;
      final longest = size.longestSide * scale;
      if (longest > _maxSvgSide) scale *= _maxSvgSide / longest;
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..scale(scale)
        ..drawPicture(info.picture);
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(
          (size.width * scale).ceil(),
          (size.height * scale).ceil(),
        );
      } finally {
        picture.dispose();
      }
    } finally {
      info.picture.dispose();
    }
  }

  static const _maxSvgSide = 4096;

  void _keepBytes(String key, Uint8List bytes) {
    final old = _bytes.remove(key);
    if (old != null) _bytesTotal -= old.length;
    if (bytes.length > bytesBudget) return;
    _bytes[key] = bytes;
    _bytesTotal += bytes.length;
    while (_bytesTotal > bytesBudget && _bytes.isNotEmpty) {
      final first = _bytes.keys.first;
      _bytesTotal -= _bytes.remove(first)!.length;
    }
  }

  void _evictImages({required String keep}) {
    while (_imagesTotal > budgetBytes && _images.length > 1) {
      final first = _images.keys.first;
      if (first == keep) break;
      final evicted = _images.remove(first)!;
      _imagesTotal -= evicted.bytes;
      evicted.image.dispose();
    }
  }

  /// Decoded pixels currently held, in bytes.
  @visibleForTesting
  int get decodedBytes => _imagesTotal;

  @override
  void dispose() {
    _disposed = true;
    for (final decoded in _images.values) {
      decoded.image.dispose();
    }
    _images.clear();
    _bytes.clear();
    super.dispose();
  }
}

class _Decoded {
  _Decoded(this.image) : bytes = image.width * image.height * 4;

  final ui.Image image;
  final int bytes;
}
