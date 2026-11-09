import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Pixel size of an encoded image, as it should be displayed.
@immutable
class ImageDimensions {
  const ImageDimensions(this.width, this.height);

  final int width;
  final int height;

  double get aspectRatio => width / height;

  /// Wider than tall: a scanned two-page spread or a landscape panel.
  bool get isLandscape => width > height;

  @override
  bool operator ==(Object other) =>
      other is ImageDimensions &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'ImageDimensions($width×$height)';
}

/// Reads an image's displayed size from its header without decoding it.
///
/// Supports PNG, JPEG (with EXIF orientation: a rotated photo reports the
/// size it is shown at), GIF, BMP, WebP (VP8, VP8L, VP8X) and SVG (its
/// root's `width` and `height`, or its `viewBox`). Returns null
/// for other formats and for headers too short or damaged to trust, so a
/// caller falls back to decoding. Used to plan spreads and page frames
/// before the image bytes are decoded.
ImageDimensions? probeImageDimensions(Uint8List bytes) {
  if (bytes.length < 16) return null;
  final data = ByteData.sublistView(bytes);
  if (_startsWith(bytes, _pngSignature)) return _png(data, bytes.length);
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return _jpeg(data, bytes.length);
  if (_startsWith(bytes, _gifSignature)) {
    return _valid(
      data.getUint16(6, Endian.little),
      data.getUint16(8, Endian.little),
    );
  }
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    if (bytes.length < 26) return null;
    return _valid(
      data.getInt32(18, Endian.little),
      data.getInt32(22, Endian.little).abs(),
    );
  }
  if (_startsWith(bytes, _riffSignature) &&
      bytes.length >= 30 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return _webp(data, bytes);
  }
  if (isSvgImage(bytes)) return _svg(bytes);
  return null;
}

/// Whether [bytes] are an SVG document: an `<svg` root within the first
/// kilobytes, after any XML declaration, comments and doctype.
bool isSvgImage(Uint8List bytes) => _svgStartTag(bytes) != null;

final _svgRoot = RegExp(r'<svg\b([^>]*)>', caseSensitive: false);
final _svgAttribute = RegExp(r'''([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');

/// The attributes of the `<svg>` start tag, or null when it is not one.
String? _svgStartTag(Uint8List bytes) {
  // A byte order mark and white space may come first.
  var start = 0;
  while (start < bytes.length &&
      start < 64 &&
      const {0xEF, 0xBB, 0xBF, 0x20, 0x09, 0x0A, 0x0D}.contains(bytes[start])) {
    start++;
  }
  if (start >= bytes.length || bytes[start] != 0x3C) return null;
  final head = String.fromCharCodes(
    bytes,
    start,
    bytes.length < start + 8192 ? bytes.length : start + 8192,
  );
  final match = _svgRoot.firstMatch(head);
  if (match == null) return null;
  // Only markup before the root: a declaration, comments, a doctype.
  final before = head.substring(0, match.start);
  if (before.contains(RegExp(r'<(?![?!])'))) return null;
  return match.group(1);
}

/// An SVG's size: `width` and `height` in px (or pt, in, cm, mm), one of
/// them with the `viewBox` ratio, else the `viewBox`, else 300×150, the
/// size CSS gives a replaced element without one.
ImageDimensions? _svg(Uint8List bytes) {
  final tag = _svgStartTag(bytes)!;
  final attributes = {
    for (final m in _svgAttribute.allMatches(tag))
      m.group(1)!.toLowerCase(): m.group(2) ?? m.group(3)!,
  };
  double? length(String? value) {
    if (value == null) return null;
    final m = RegExp(
      r'^\s*([0-9]*\.?[0-9]+)\s*(px|pt|in|cm|mm)?\s*$',
    ).firstMatch(value);
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    return switch (m.group(2)) {
      'pt' => n * 4 / 3,
      'in' => n * 96,
      'cm' => n * 96 / 2.54,
      'mm' => n * 96 / 25.4,
      _ => n,
    };
  }

  final box = attributes['viewbox']
      ?.trim()
      .split(RegExp(r'[\s,]+'))
      .map(double.tryParse)
      .toList();
  final viewBox = box != null && box.length == 4 && !box.contains(null)
      ? (width: box[2]!, height: box[3]!)
      : null;
  var width = length(attributes['width']);
  var height = length(attributes['height']);
  if (viewBox != null && viewBox.width > 0 && viewBox.height > 0) {
    final ratio = viewBox.width / viewBox.height;
    if (width != null && height == null) height = width / ratio;
    if (height != null && width == null) width = height * ratio;
    width ??= viewBox.width;
    height ??= viewBox.height;
  }
  return _valid((width ?? 300).round(), (height ?? 150).round());
}

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _gifSignature = [0x47, 0x49, 0x46, 0x38];
const _riffSignature = [0x52, 0x49, 0x46, 0x46];

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

ImageDimensions? _valid(int width, int height) =>
    width > 0 && height > 0 ? ImageDimensions(width, height) : null;

ImageDimensions? _png(ByteData data, int length) {
  // IHDR is always the first chunk: length, 'IHDR', width, height.
  if (length < 24) return null;
  if (data.getUint32(12) != 0x49484452) return null;
  return _valid(data.getUint32(16), data.getUint32(20));
}

ImageDimensions? _jpeg(ByteData data, int length) {
  var offset = 2;
  int? orientation;
  while (offset + 4 <= length) {
    if (data.getUint8(offset) != 0xFF) return null;
    final marker = data.getUint8(offset + 1);
    if (marker == 0xFF) {
      offset++;
      continue;
    }
    // Markers without a payload: SOI, TEM, RSTn.
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
      continue;
    }
    final segmentLength = data.getUint16(offset + 2);
    if (segmentLength < 2) return null;
    final isFrameHeader =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isFrameHeader) {
      if (offset + 9 > length) return null;
      final height = data.getUint16(offset + 5);
      final width = data.getUint16(offset + 7);
      final rotated = orientation != null && orientation >= 5;
      return rotated ? _valid(height, width) : _valid(width, height);
    }
    if (marker == 0xE1) {
      orientation ??= _exifOrientation(
        data,
        offset + 4,
        offset + 2 + segmentLength,
        length,
      );
    }
    if (marker == 0xDA) {
      // Scan data before any frame header: not a decodable image.
      return null;
    }
    offset += 2 + segmentLength;
  }
  return null;
}

/// Reads EXIF tag 0x0112 from an APP1 segment, or null.
int? _exifOrientation(ByteData data, int start, int end, int length) {
  end = end < length ? end : length;
  // 'Exif\0\0' then a TIFF header.
  if (start + 14 > end || data.getUint32(start) != 0x45786966) return null;
  final tiff = start + 6;
  final Endian endian;
  switch (data.getUint16(tiff)) {
    case 0x4949:
      endian = Endian.little;
    case 0x4D4D:
      endian = Endian.big;
    default:
      return null;
  }
  if (data.getUint16(tiff + 2, endian) != 0x2A) return null;
  final ifd = tiff + data.getUint32(tiff + 4, endian);
  if (ifd + 2 > end) return null;
  final count = data.getUint16(ifd, endian);
  for (var i = 0; i < count; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > end) return null;
    if (data.getUint16(entry, endian) == 0x0112) {
      final value = data.getUint16(entry + 8, endian);
      return value >= 1 && value <= 8 ? value : null;
    }
  }
  return null;
}

ImageDimensions? _webp(ByteData data, Uint8List bytes) {
  final chunk = String.fromCharCodes(bytes, 12, 16);
  switch (chunk) {
    case 'VP8 ':
      // Frame tag (3 bytes) then the start code 9D 01 2A.
      if (bytes[23] != 0x9D || bytes[24] != 0x01 || bytes[25] != 0x2A) {
        return null;
      }
      return _valid(
        data.getUint16(26, Endian.little) & 0x3FFF,
        data.getUint16(28, Endian.little) & 0x3FFF,
      );
    case 'VP8L':
      if (bytes[20] != 0x2F) return null;
      final bits = data.getUint32(21, Endian.little);
      return _valid((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
    case 'VP8X':
      return _valid(_uint24(bytes, 24) + 1, _uint24(bytes, 27) + 1);
    default:
      return null;
  }
}

int _uint24(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
