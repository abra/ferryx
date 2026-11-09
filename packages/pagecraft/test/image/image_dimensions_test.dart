import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

import 'package:pagecraft/testing.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

/// A JPEG header: SOI, optional APP1 with an EXIF orientation, then SOF0
/// with the given size and a truncated scan.
Uint8List _jpeg({
  required int width,
  required int height,
  int? orientation,
  bool progressive = false,
  bool bigEndianExif = false,
}) {
  final out = <int>[0xFF, 0xD8];
  // APP0 JFIF, 16 bytes long, is what most encoders write first.
  out.addAll([0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00]);
  out.addAll(List.filled(16 - 7, 0));
  if (orientation != null) {
    final endian = bigEndianExif ? Endian.big : Endian.little;
    final tiff = ByteData(8 + 2 + 12 + 4)
      ..setUint16(0, bigEndianExif ? 0x4D4D : 0x4949)
      ..setUint16(2, 0x2A, endian)
      ..setUint32(4, 8, endian)
      ..setUint16(8, 1, endian)
      ..setUint16(10, 0x0112, endian)
      ..setUint16(12, 3, endian)
      ..setUint32(14, 1, endian)
      ..setUint16(18, orientation, endian);
    final payload = [
      0x45,
      0x78,
      0x69,
      0x66,
      0,
      0,
      ...tiff.buffer.asUint8List(),
    ];
    final length = payload.length + 2;
    out.addAll([0xFF, 0xE1, length >> 8, length & 0xFF, ...payload]);
  }
  final sof = ByteData(2 + 1 + 2 + 2 + 1)
    ..setUint16(0, 8 + 3)
    ..setUint8(2, 8)
    ..setUint16(3, height)
    ..setUint16(5, width)
    ..setUint8(7, 3);
  out.addAll([
    0xFF,
    progressive ? 0xC2 : 0xC0,
    ...sof.buffer.asUint8List(),
    1,
    0x22,
    0,
    2,
    0x11,
    1,
    3,
    0x11,
    1,
  ]);
  out.addAll([0xFF, 0xDA, 0, 8, 0, 0, 0, 0, 0, 0]);
  return _bytes(out);
}

Uint8List _webp(String chunk, List<int> payload) {
  final body = [
    ...'WEBP'.codeUnits,
    ...chunk.codeUnits,
    payload.length,
    0,
    0,
    0,
    ...payload,
  ];
  final size = ByteData(4)..setUint32(0, body.length, Endian.little);
  return _bytes(
    [
      'RIFF'.codeUnits,
      size.buffer.asUint8List(),
      body,
    ].expand((e) => e).toList(),
  );
}

void main() {
  group('svg', () {
    ImageDimensions? svg(String text) =>
        probeImageDimensions(Uint8List.fromList(text.codeUnits));

    test('width and height, in px or other units', () {
      expect(
        svg(
          '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80"/>',
        ),
        const ImageDimensions(120, 80),
      );
      expect(
        svg('<svg width="30pt" height="1in" viewBox="0 0 1 1"></svg>'),
        const ImageDimensions(40, 96),
      );
    });

    test('the viewBox gives the ratio, or the size', () {
      expect(
        svg('<svg viewBox="0 0 400 200" width="100"></svg>'),
        const ImageDimensions(100, 50),
      );
      expect(
        svg("<svg viewBox='0,0,64,48'></svg>"),
        const ImageDimensions(64, 48),
      );
      expect(
        svg('<svg width="100%" height="100%" viewBox="0 0 10 20"></svg>'),
        const ImageDimensions(10, 20),
      );
      expect(
        svg('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
        const ImageDimensions(300, 150),
      );
    });

    test('after a declaration, comments, a doctype and a BOM', () {
      final text =
          '\uFEFF<?xml version="1.0"?>\n<!-- made by hand -->\n'
          '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "x.dtd">\n'
          '<svg width="10" height="20"/>';
      expect(
        probeImageDimensions(
          Uint8List.fromList(const Utf8Encoder().convert(text)),
        ),
        const ImageDimensions(10, 20),
      );
      expect(
        isSvgImage(Uint8List.fromList('<html><svg/></html>'.codeUnits)),
        isFalse,
      );
      expect(
        svg('<html><body><svg width="1" height="1"/></body></html>'),
        isNull,
      );
    });
  });
  group('probeImageDimensions', () {
    test('reads PNG IHDR', () {
      expect(
        probeImageDimensions(encodeSolidPng(640, 480)),
        const ImageDimensions(640, 480),
      );
      expect(
        probeImageDimensions(encodeSolidPng(1, 1)),
        const ImageDimensions(1, 1),
      );
    });

    test('rejects a PNG whose first chunk is not IHDR', () {
      final png = encodeSolidPng(4, 4);
      png[12] = 0x49;
      png[13] = 0x44;
      png[14] = 0x41;
      png[15] = 0x54;
      expect(probeImageDimensions(png), isNull);
    });

    test('reads baseline and progressive JPEG frame headers', () {
      expect(
        probeImageDimensions(_jpeg(width: 1200, height: 1800)),
        const ImageDimensions(1200, 1800),
      );
      expect(
        probeImageDimensions(_jpeg(width: 300, height: 200, progressive: true)),
        const ImageDimensions(300, 200),
      );
    });

    test('swaps JPEG sides for rotated EXIF orientations', () {
      for (final orientation in [5, 6, 7, 8]) {
        expect(
          probeImageDimensions(
            _jpeg(width: 1200, height: 800, orientation: orientation),
          ),
          const ImageDimensions(800, 1200),
          reason: 'orientation $orientation',
        );
      }
      for (final orientation in [1, 2, 3, 4]) {
        expect(
          probeImageDimensions(
            _jpeg(width: 1200, height: 800, orientation: orientation),
          ),
          const ImageDimensions(1200, 800),
          reason: 'orientation $orientation',
        );
      }
      expect(
        probeImageDimensions(
          _jpeg(width: 1200, height: 800, orientation: 6, bigEndianExif: true),
        ),
        const ImageDimensions(800, 1200),
      );
    });

    test('ignores an EXIF orientation out of range', () {
      expect(
        probeImageDimensions(_jpeg(width: 1200, height: 800, orientation: 9)),
        const ImageDimensions(1200, 800),
      );
    });

    test('returns null for a JPEG cut before its frame header', () {
      final jpeg = _jpeg(width: 100, height: 100);
      expect(probeImageDimensions(jpeg.sublist(0, 20)), isNull);
      // A scan marker before any frame header.
      expect(
        probeImageDimensions(
          _bytes([0xFF, 0xD8, 0xFF, 0xDA, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
        isNull,
      );
      // A byte that is not a marker.
      expect(
        probeImageDimensions(
          _bytes([0xFF, 0xD8, 0x00, 0xC0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
        isNull,
      );
    });

    test('reads GIF and BMP headers, including bottom-up BMP heights', () {
      final gif = _bytes(
        [
          'GIF89a'.codeUnits,
          [0x20, 0x01, 0x40, 0x00],
          List.filled(8, 0),
        ].expand((e) => e).toList(),
      );
      expect(probeImageDimensions(gif), const ImageDimensions(288, 64));

      final bmp = ByteData(26)
        ..setUint8(0, 0x42)
        ..setUint8(1, 0x4D)
        ..setInt32(18, 500, Endian.little)
        ..setInt32(22, -300, Endian.little);
      expect(
        probeImageDimensions(bmp.buffer.asUint8List()),
        const ImageDimensions(500, 300),
      );
    });

    test('reads WebP VP8, VP8L and VP8X headers', () {
      final vp8 = _webp('VP8 ', [
        0, 0, 0, // frame tag
        0x9D, 0x01, 0x2A, // start code
        0xE8, 0x03, // 1000, scale bits clear
        0x2C, 0x01, // 300
        0, 0, 0, 0,
      ]);
      expect(probeImageDimensions(vp8), const ImageDimensions(1000, 300));

      final bits = (999) | ((299) << 14); // width-1, height-1
      final vp8l = _webp('VP8L', [
        0x2F,
        bits & 0xFF,
        (bits >> 8) & 0xFF,
        (bits >> 16) & 0xFF,
        (bits >> 24) & 0xFF,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(probeImageDimensions(vp8l), const ImageDimensions(1000, 300));

      final vp8x = _webp('VP8X', [
        0,
        0,
        0,
        0,
        0xE7,
        0x03,
        0x00,
        0x2B,
        0x01,
        0x00,
        0,
        0,
        0,
        0,
      ]);
      expect(probeImageDimensions(vp8x), const ImageDimensions(1000, 300));

      expect(
        probeImageDimensions(
          _webp('VP8 ', [0, 0, 0, 1, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
        isNull,
      );
      expect(probeImageDimensions(_webp('ALPH', List.filled(14, 0))), isNull);
    });

    test('returns null for unknown or too short input and zero sizes', () {
      expect(probeImageDimensions(_bytes(List.filled(64, 0x41))), isNull);
      expect(probeImageDimensions(_bytes([0x89, 0x50])), isNull);
      expect(probeImageDimensions(Uint8List(0)), isNull);
      final gif = _bytes(
        [
          'GIF89a'.codeUnits,
          [0, 0, 0, 0],
          List.filled(8, 0),
        ].expand((e) => e).toList(),
      );
      expect(probeImageDimensions(gif), isNull);
    });

    test('dimensions are value objects with orientation helpers', () {
      const wide = ImageDimensions(1800, 900);
      expect(wide.isLandscape, isTrue);
      expect(wide.aspectRatio, 2);
      expect(wide, const ImageDimensions(1800, 900));
      expect(wide.hashCode, const ImageDimensions(1800, 900).hashCode);
      expect(const ImageDimensions(600, 900).isLandscape, isFalse);
      expect(wide.toString(), 'ImageDimensions(1800×900)');
    });
  });
}
