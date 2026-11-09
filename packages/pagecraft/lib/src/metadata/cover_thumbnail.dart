import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import 'book_metadata.dart';

/// The size and quality of the cover the library keeps.
///
/// The defaults fit a two-column grid at three device pixels per logical
/// pixel; a page scan is several megabytes, its cover at this size is tens
/// of kilobytes, and the library decodes the small file on every list.
class CoverThumbnailSpec {
  const CoverThumbnailSpec({
    this.maxWidth = 480,
    this.maxHeight = 720,
    this.quality = 85,
  }) : assert(maxWidth > 0 && maxHeight > 0),
       assert(quality >= 1 && quality <= 100);

  final int maxWidth;
  final int maxHeight;

  /// JPEG quality, 1–100.
  final int quality;

  /// The size to decode an image of [width]×[height] at: the largest size
  /// within the box that keeps the ratio, never larger than the source.
  ({int width, int height}) fit(int width, int height) {
    final scale = [
      1.0,
      maxWidth / width,
      maxHeight / height,
    ].reduce((a, b) => a < b ? a : b);
    if (scale >= 1) return (width: width, height: height);
    return (
      width: (width * scale).round().clamp(1, maxWidth),
      height: (height * scale).round().clamp(1, maxHeight),
    );
  }
}

/// Encodes [source], an image in any format the engine decodes, as a JPEG
/// that fits [spec]. Returns null when the bytes are not a decodable image.
///
/// The engine decodes straight to the target size, so a page scan never
/// becomes a full-size bitmap (JPEG scales while decoding, and EXIF
/// orientation is applied). Only the JPEG encoding of the small frame is
/// Dart, and it runs in a short-lived isolate.
Future<CoverImage?> encodeCoverThumbnail(
  Uint8List source, {
  CoverThumbnailSpec spec = const CoverThumbnailSpec(),
}) async {
  // instantiateImageCodecWithSize disposes the buffer once it has read it;
  // when it rejects the bytes instead, the buffer goes with the GC, as it
  // does for the framework's own image providers.
  final buffer = await ui.ImmutableBuffer.fromUint8List(source);
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (intrinsicWidth, intrinsicHeight) {
        final size = spec.fit(intrinsicWidth, intrinsicHeight);
        return ui.TargetImageSize(width: size.width, height: size.height);
      },
    );
    image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) return null;
    final frame = _RgbaFrame(
      width: image.width,
      height: image.height,
      pixels: pixels.buffer.asUint8List(
        pixels.offsetInBytes,
        pixels.lengthInBytes,
      ),
    );
    final jpeg = await Isolate.run(() => _encodeJpeg(frame, spec.quality));
    return CoverImage(
      bytes: jpeg,
      mimeType: 'image/jpeg',
      width: frame.width,
      height: frame.height,
    );
  } on Exception {
    // Not an image, or truncated past what the decoder tolerates.
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// Encodes a frame that was already rendered at its final size, such as a
/// PDF page pdfium drew at [CoverThumbnailSpec.fit], as a JPEG. [pixels]
/// is `width × height × 4` bytes in [order]; it is copied to the encoding
/// isolate, so the caller may free it when this returns.
Future<CoverImage> encodeCoverFromPixels(
  Uint8List pixels, {
  required int width,
  required int height,
  required CoverPixelOrder order,
  CoverThumbnailSpec spec = const CoverThumbnailSpec(),
}) async {
  if (pixels.length != width * height * 4) {
    throw ArgumentError.value(
      pixels.length,
      'pixels',
      'expected ${width * height * 4} bytes for $width×$height',
    );
  }
  final frame = _RgbaFrame(
    width: width,
    height: height,
    pixels: pixels,
    order: order,
  );
  final jpeg = await Isolate.run(() => _encodeJpeg(frame, spec.quality));
  return CoverImage(
    bytes: jpeg,
    mimeType: 'image/jpeg',
    width: width,
    height: height,
  );
}

/// Byte order of a raw 8-bit frame.
enum CoverPixelOrder { rgba, bgra }

class _RgbaFrame {
  const _RgbaFrame({
    required this.width,
    required this.height,
    required this.pixels,
    this.order = CoverPixelOrder.rgba,
  });

  final int width;
  final int height;
  final Uint8List pixels;
  final CoverPixelOrder order;
}

Uint8List _encodeJpeg(_RgbaFrame frame, int quality) {
  final image = img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: frame.pixels.buffer,
    bytesOffset: frame.pixels.offsetInBytes,
    numChannels: 4,
    order: switch (frame.order) {
      CoverPixelOrder.rgba => img.ChannelOrder.rgba,
      CoverPixelOrder.bgra => img.ChannelOrder.bgra,
    },
  );
  return img.encodeJpg(image, quality: quality, chroma: img.JpegChroma.yuv420);
}
