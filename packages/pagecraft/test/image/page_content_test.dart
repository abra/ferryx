import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// A [width]×[height] RGBA sample of [paper] grey with [ink] pixels
/// painted black (or [inkValue]).
Uint8List sample(
  int width,
  int height, {
  int paper = 255,
  Iterable<(int, int)> ink = const [],
  int inkValue = 0,
}) {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    pixels[i * 4] = paper;
    pixels[i * 4 + 1] = paper;
    pixels[i * 4 + 2] = paper;
    pixels[i * 4 + 3] = 255;
  }
  for (final (x, y) in ink) {
    final offset = (y * width + x) * 4;
    pixels[offset] = inkValue;
    pixels[offset + 1] = inkValue;
    pixels[offset + 2] = inkValue;
  }
  return pixels;
}

Iterable<(int, int)> block(int left, int top, int right, int bottom) sync* {
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      yield (x, y);
    }
  }
}

void main() {
  group('detectContentBox', () {
    test('a blank page has no box', () {
      expect(detectContentBox(sample(100, 160), 100, 160), isNull);
      expect(detectContentBox(sample(100, 160, paper: 180), 100, 160), isNull);
    });

    test('finds a block of ink with one pixel of slack', () {
      final pixels = sample(100, 160, ink: block(20, 30, 80, 120));
      expect(
        detectContentBox(pixels, 100, 160),
        const ContentBox(left: 19, top: 29, right: 81, bottom: 121),
      );
    });

    test('reads BGRA samples by the right channels', () {
      // Red ink: luminance differs by channel order only if misread.
      final pixels = sample(100, 160, ink: block(20, 30, 80, 120), inkValue: 0);
      for (final (x, y) in block(20, 30, 80, 120)) {
        pixels[(y * 100 + x) * 4] = 0; // B
        pixels[(y * 100 + x) * 4 + 2] = 200; // R
      }
      expect(
        detectContentBox(pixels, 100, 160, order: PixelOrder.bgra),
        const ContentBox(left: 19, top: 29, right: 81, bottom: 121),
      );
    });

    test('ignores specks and the page edge', () {
      final pixels = sample(
        100,
        160,
        ink: [
          ...block(20, 30, 80, 120),
          (5, 5),
          (90, 150),
          ...block(0, 0, 100, 1),
        ],
      );
      expect(
        detectContentBox(pixels, 100, 160),
        const ContentBox(left: 19, top: 29, right: 81, bottom: 121),
      );
    });

    test('takes the paper tone from the margin, so grey scans work', () {
      final pixels = sample(100, 160, paper: 150, ink: block(20, 30, 80, 120));
      expect(
        detectContentBox(pixels, 100, 160),
        const ContentBox(left: 19, top: 29, right: 81, bottom: 121),
      );
      // Ink too close to the paper tone is paper.
      final faint = sample(
        100,
        160,
        paper: 150,
        ink: block(20, 30, 80, 120),
        inkValue: 130,
      );
      expect(detectContentBox(faint, 100, 160), isNull);
    });

    test('rejects samples that are too small or short of pixels', () {
      expect(detectContentBox(sample(2, 2), 2, 2), isNull);
      expect(detectContentBox(Uint8List(10), 10, 10), isNull);
    });
  });

  group('contentCrop', () {
    const page = (width: 612.0, height: 792.0);

    test('follows the ink horizontally with two percent of padding', () {
      final crop = contentCrop(
        content: const ContentBox(left: 72, top: 60, right: 540, bottom: 700),
        width: page.width,
        height: page.height,
        availableWidth: 390,
        availableHeight: 844,
      )!;
      expect(crop.left, closeTo(72 - 612 * 0.02, 1e-9));
      expect(crop.right, closeTo(540 + 612 * 0.02, 1e-9));
      // A phone box is taller than the cropped width allows: the crop
      // keeps the whole height, shifted to the top.
      expect(crop.top, 0);
      expect(crop.bottom, closeTo(792, 1e-9));
    });

    test('a full column keeps its ink top and bottom in a squarer box', () {
      final crop = contentCrop(
        content: const ContentBox(left: 72, top: 60, right: 540, bottom: 700),
        width: page.width,
        height: page.height,
        availableWidth: 390,
        availableHeight: 500,
      )!;
      expect(crop.top, closeTo(60 - 792 * 0.02, 1e-9));
      expect(crop.bottom, closeTo(700 + 792 * 0.02, 1e-9));
    });

    test('a short page grows to the box aspect, anchored at the ink', () {
      final crop = contentCrop(
        content: const ContentBox(left: 72, top: 60, right: 540, bottom: 200),
        width: page.width,
        height: page.height,
        availableWidth: 390,
        availableHeight: 500,
      )!;
      expect(crop.top, closeTo(60 - 792 * 0.02, 1e-9));
      expect(crop.height, closeTo(crop.width * 500 / 390, 1e-9));
    });

    test('shifts up rather than running past the bottom edge', () {
      final crop = contentCrop(
        content: const ContentBox(left: 72, top: 600, right: 540, bottom: 780),
        width: page.width,
        height: page.height,
        availableWidth: 390,
        availableHeight: 844,
      )!;
      expect(crop.bottom, closeTo(792, 1e-9));
      expect(crop.height, closeTo(792, 1e-9), reason: 'capped at the page');
    });

    test('keeps sparse pages whole', () {
      expect(
        contentCrop(
          content: const ContentBox(
            left: 200,
            top: 300,
            right: 400,
            bottom: 320,
          ),
          width: page.width,
          height: page.height,
          availableWidth: 390,
          availableHeight: 844,
        ),
        isNull,
      );
    });

    test('keeps a full page and a blank page whole', () {
      expect(
        contentCrop(
          content: const ContentBox(left: 0, top: 0, right: 612, bottom: 792),
          width: page.width,
          height: page.height,
          availableWidth: 390,
          availableHeight: 844,
        ),
        isNull,
      );
      expect(
        contentCrop(
          content: null,
          width: page.width,
          height: page.height,
          availableWidth: 390,
          availableHeight: 844,
        ),
        isNull,
      );
    });
  });
}
