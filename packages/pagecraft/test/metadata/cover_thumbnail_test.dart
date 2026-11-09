import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  group('CoverThumbnailSpec.fit', () {
    const spec = CoverThumbnailSpec(maxWidth: 480, maxHeight: 720);

    test('scales a tall page down to the box, keeping its ratio', () {
      expect(spec.fit(1200, 1800), (width: 480, height: 720));
      expect(spec.fit(1000, 3000), (width: 240, height: 720));
    });

    test('a wide image is bounded by the width', () {
      expect(spec.fit(2000, 1000), (width: 480, height: 240));
    });

    test('never upscales', () {
      expect(spec.fit(100, 150), (width: 100, height: 150));
      expect(spec.fit(480, 720), (width: 480, height: 720));
    });

    test('keeps at least one pixel on each side', () {
      expect(spec.fit(100000, 1), (width: 480, height: 1));
    });
  });

  group('encodeCoverThumbnail', () {
    test('encodes a page scan as a JPEG that fits the box', () async {
      final cover = await encodeCoverThumbnail(encodeSolidPng(1200, 1800));
      expect(cover, isNotNull);
      expect(cover!.mimeType, 'image/jpeg');
      expect(cover.width, 480);
      expect(cover.height, 720);
      expect(cover.bytes.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
      expect(
        probeImageDimensions(cover.bytes),
        const ImageDimensions(480, 720),
      );
      expect(cover.bytes.length, lessThan(64 * 1024));
    });

    test('keeps a small image at its own size', () async {
      final cover = await encodeCoverThumbnail(encodeSolidPng(100, 150));
      expect(cover!.width, 100);
      expect(cover.height, 150);
    });

    test('keeps the colours and channel order', () async {
      final cover = await encodeCoverThumbnail(
        encodeSolidPng(600, 900, rgba: 0xC04020FF),
      );
      final pixel = await _centrePixel(cover!.bytes);
      expect(pixel.r, closeTo(0xC0, 6));
      expect(pixel.g, closeTo(0x40, 6));
      expect(pixel.b, closeTo(0x20, 6));
    });

    test('honours the quality setting', () async {
      final source = encodeSolidPng(600, 900, rgba: 0x7F7F7FFF);
      final fine = await encodeCoverThumbnail(
        source,
        spec: const CoverThumbnailSpec(quality: 95),
      );
      final coarse = await encodeCoverThumbnail(
        source,
        spec: const CoverThumbnailSpec(quality: 30),
      );
      // A solid colour encodes to the same size at any quality; the
      // quantization table shows what the encoder was asked for.
      expect(
        _firstQuantizer(coarse!.bytes),
        greaterThan(_firstQuantizer(fine!.bytes)),
      );
    });

    test('answers null for bytes that are not an image', () async {
      expect(
        await encodeCoverThumbnail(Uint8List.fromList(List.filled(64, 0x41))),
        isNull,
      );
      expect(await encodeCoverThumbnail(Uint8List(0)), isNull);
    });

    test('answers null for a truncated image', () async {
      final png = encodeSolidPng(300, 300);
      expect(
        await encodeCoverThumbnail(png.sublist(0, png.length ~/ 2)),
        isNull,
      );
    });
  });
}

/// The first entry of the first DQT table: coarser quality, larger step.
int _firstQuantizer(Uint8List jpeg) {
  for (var i = 2; i + 5 < jpeg.length; i++) {
    if (jpeg[i] == 0xFF && jpeg[i + 1] == 0xDB) return jpeg[i + 5];
  }
  throw StateError('no DQT marker');
}

Future<({int r, int g, int b})> _centrePixel(Uint8List jpeg) async {
  final codec = await ui.instantiateImageCodec(jpeg);
  final image = (await codec.getNextFrame()).image;
  final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  image.dispose();
  codec.dispose();
  return (
    r: pixels.getUint8(offset),
    g: pixels.getUint8(offset + 1),
    b: pixels.getUint8(offset + 2),
  );
}
