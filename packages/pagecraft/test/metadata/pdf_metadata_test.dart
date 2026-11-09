import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

const fixtures = 'test/fixtures/pdf';

void main() {
  setUpAll(preparePdfEngineForTests);

  test(
    'reads the Info dictionary and renders the first page as cover',
    () async {
      final metadata = await readPdfMetadata('$fixtures/text_outline.pdf');
      expect(metadata.title, 'Vellum Fixture');
      expect(metadata.author, 'Fixture Author');
      final cover = metadata.cover!;
      expect(cover.mimeType, 'image/jpeg');
      // 612×792 pt fitted into 480×720: the width binds.
      expect(cover.width, 480);
      expect(cover.height, 621);
      expect(
        probeImageDimensions(cover.bytes),
        const ImageDimensions(480, 621),
      );
      final centre = await _pixelAt(cover.bytes, 240, 310);
      expect(centre.r, greaterThan(245), reason: 'a white page');
      expect(centre.g, greaterThan(245));
      expect(centre.b, greaterThan(245));
    },
  );

  test('a PDF without a title is named after its file', () async {
    final metadata = await readPdfMetadata('$fixtures/plain.pdf');
    expect(metadata.title, 'plain');
    expect(metadata.author, isNull);
    expect(metadata.cover, isNotNull);
  });

  test('uses the given thumbnail spec', () async {
    final metadata = await readPdfMetadata(
      '$fixtures/plain.pdf',
      spec: const CoverThumbnailSpec(maxWidth: 100, maxHeight: 100),
    );
    expect(metadata.cover!.width, 77);
    expect(metadata.cover!.height, 100);
  });

  test('refuses encrypted and unreadable files', () async {
    await expectLater(
      readPdfMetadata('$fixtures/locked.pdf'),
      throwsA(isA<PdfPasswordRequiredException>()),
    );
    final tempDir = await Directory.systemTemp.createTemp('pdf_metadata_');
    addTearDown(() => tempDir.delete(recursive: true));
    final junk = File('${tempDir.path}/junk.pdf');
    await junk.writeAsString('nope');
    await expectLater(
      readPdfMetadata(junk.path),
      throwsA(isA<PagecraftException>()),
    );
  });

  group('encodeCoverFromPixels', () {
    test('keeps BGRA colours straight', () async {
      // One 4×4 block of pure blue in BGRA.
      final pixels = Uint8List(4 * 4 * 4);
      for (var i = 0; i < 16; i++) {
        pixels[i * 4] = 0xFF; // B
        pixels[i * 4 + 3] = 0xFF; // A
      }
      final cover = await encodeCoverFromPixels(
        pixels,
        width: 4,
        height: 4,
        order: CoverPixelOrder.bgra,
      );
      expect(cover.width, 4);
      expect(cover.height, 4);
      final pixel = await _pixelAt(cover.bytes, 2, 2);
      expect(pixel.b, greaterThan(200));
      expect(pixel.r, lessThan(60));
      expect(pixel.g, lessThan(60));
    });

    test('rejects a buffer of the wrong size', () {
      expect(
        () => encodeCoverFromPixels(
          Uint8List(10),
          width: 2,
          height: 2,
          order: CoverPixelOrder.rgba,
        ),
        throwsArgumentError,
      );
    });
  });
}

Future<({int r, int g, int b})> _pixelAt(Uint8List jpeg, int x, int y) async {
  final codec = await ui.instantiateImageCodec(jpeg);
  final image = (await codec.getNextFrame()).image;
  final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final offset = (y * image.width + x) * 4;
  image.dispose();
  codec.dispose();
  return (
    r: pixels.getUint8(offset),
    g: pixels.getUint8(offset + 1),
    b: pixels.getUint8(offset + 2),
  );
}
