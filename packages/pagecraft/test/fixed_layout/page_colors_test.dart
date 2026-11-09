import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

const fixtures = 'test/fixtures/pdf';
const warm = ui.Color(0xFFF3E4CF);
const warmInk = ui.Color(0xFF33261B);
const night = ui.Color(0xFF0F1115);
const nightInk = ui.Color(0xFFBCC1CA);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(preparePdfEngineForTests);

  group('pageColorsFor', () {
    test('keeps the original colours when the setting is off', () {
      expect(
        pageColorsFor(themed: false, background: warm, foreground: warmInk),
        isNull,
      );
    });

    test('white paper is left alone', () {
      expect(
        pageColorsFor(
          themed: true,
          background: const ui.Color(0xFFFFFFFF),
          foreground: const ui.Color(0xFF000000),
        ),
        isNull,
      );
      expect(
        pageColorsFor(
          themed: true,
          background: const ui.Color(0xFFFEFEFE),
          foreground: const ui.Color(0xFF000000),
        ),
        isNull,
      );
    });

    test('light themes tint, dark themes invert', () {
      expect(
        pageColorsFor(themed: true, background: warm, foreground: warmInk),
        const PageColors(background: warm, foreground: warmInk, dark: false),
      );
      expect(
        pageColorsFor(themed: true, background: night, foreground: nightInk),
        const PageColors(background: night, foreground: nightInk, dark: true),
      );
    });

    test('the filter maps paper, ink and keeps a blue figure blue', () {
      ui.Color apply(PageColors colors, ui.Color source) {
        // ColorFilter.matrix has no Dart-side apply; mirror its arithmetic
        // on the 4×5 matrix the filter was built from.
        final matrix = debugPageColorMatrix(colors);
        final rgb = [source.r, source.g, source.b];
        double channel(int c) {
          var value = matrix[c * 5 + 4] / 255;
          for (var i = 0; i < 3; i++) {
            value += matrix[c * 5 + i] * rgb[i];
          }
          return value.clamp(0, 1);
        }

        return ui.Color.from(
          alpha: 1,
          red: channel(0),
          green: channel(1),
          blue: channel(2),
        );
      }

      const light = PageColors(
        background: warm,
        foreground: warmInk,
        dark: false,
      );
      expect(apply(light, const ui.Color(0xFFFFFFFF)), _near(warm));
      expect(apply(light, const ui.Color(0xFF000000)), _near(warmInk));

      const darkTheme = PageColors(
        background: night,
        foreground: nightInk,
        dark: true,
      );
      expect(apply(darkTheme, const ui.Color(0xFFFFFFFF)), _near(night));
      expect(apply(darkTheme, const ui.Color(0xFF000000)), _near(nightInk));
      final blue = apply(darkTheme, const ui.Color(0xFF0000FF));
      expect(blue.b, greaterThan(blue.r + 0.1));
      expect(blue.b, greaterThan(blue.g + 0.1));
      final grey = apply(darkTheme, const ui.Color(0xFF808080));
      expect(grey.r, closeTo((night.r + nightInk.r) / 2, 0.02));
      expect(pageColorFilter(darkTheme), same(pageColorFilter(darkTheme)));
    });

    test('relative luminance follows WCAG', () {
      expect(relativeLuminance(const ui.Color(0xFFFFFFFF)), closeTo(1, 1e-9));
      expect(relativeLuminance(const ui.Color(0xFF000000)), 0);
      expect(
        relativeLuminance(const ui.Color(0xFF808080)),
        closeTo(0.2159, 1e-3),
      );
    });
  });

  group('paintPageWithColors', () {
    late PdfBook book;
    late ui.Image page;

    setUpAll(() async {
      book = await PdfBook.open('$fixtures/figure.pdf');
      final info = await _resolve(
        PdfPageImage(book: book, pageIndex: 0, targetWidth: 306),
      );
      page = info.image;
    });

    tearDownAll(() async {
      page.dispose();
      await book.close();
    });

    Future<ui.Image> painted(PageColors? colors) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      paintPageWithColors(
        canvas,
        page,
        source: ui.Rect.fromLTWH(
          0,
          0,
          page.width.toDouble(),
          page.height.toDouble(),
        ),
        destination: ui.Rect.fromLTWH(
          0,
          0,
          page.width.toDouble(),
          page.height.toDouble(),
        ),
        colors: colors,
      );
      return recorder.endRecording().toImage(page.width, page.height);
    }

    // The margin, a glyph of the title and the blue figure, at half scale.
    const paperPoint = (10, 10);
    const figurePoint = (150, 210);

    test('keeps the page as published without colours', () async {
      final image = await painted(null);
      expect(
        await _pixel(image, paperPoint),
        _near(const ui.Color(0xFFFFFFFF)),
      );
      expect(
        await _pixel(image, figurePoint),
        _near(const ui.Color(0xFF0000FF)),
      );
    });

    test('a light theme tints the paper and keeps the ink dark', () async {
      final image = await painted(
        const PageColors(background: warm, foreground: warmInk, dark: false),
      );
      expect(await _pixel(image, paperPoint), _near(warm));
      final ink = await _darkest(
        image,
        left: 36,
        top: 36,
        right: 170,
        bottom: 56,
      );
      expect(_luminance(ink), lessThan(60));
    });

    test(
      'a dark theme inverts, maps ink to the text colour and keeps hues',
      () async {
        final image = await painted(
          const PageColors(background: night, foreground: nightInk, dark: true),
        );
        expect(await _pixel(image, paperPoint), _near(night));
        final ink = await _brightest(
          image,
          left: 36,
          top: 36,
          right: 170,
          bottom: 56,
        );
        expect(_luminance(ink), greaterThan(150));
        expect(_luminance(ink), lessThan(205));
        final figure = await _pixel(image, figurePoint);
        expect(figure.b, greaterThan(figure.r + 25 / 255));
        expect(figure.b, greaterThan(figure.g + 25 / 255));
      },
    );
  });
}

Future<ImageInfo> _resolve(ImageProvider provider) {
  final completer = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info);
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

Future<ui.Color> _pixel(ui.Image image, (int, int) point) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final offset = (point.$2 * image.width + point.$1) * 4;
  return ui.Color.fromARGB(
    255,
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

Future<ui.Color> _darkest(
  ui.Image image, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) => _extreme(
  image,
  left: left,
  top: top,
  right: right,
  bottom: bottom,
  darkest: true,
);

Future<ui.Color> _brightest(
  ui.Image image, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) => _extreme(
  image,
  left: left,
  top: top,
  right: right,
  bottom: bottom,
  darkest: false,
);

Future<ui.Color> _extreme(
  ui.Image image, {
  required int left,
  required int top,
  required int right,
  required int bottom,
  required bool darkest,
}) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  ui.Color? best;
  var bestLuminance = darkest ? 999.0 : -1.0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * image.width + x) * 4;
      final color = ui.Color.fromARGB(
        255,
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      );
      final luminance = _luminance(color);
      if (darkest ? luminance < bestLuminance : luminance > bestLuminance) {
        best = color;
        bestLuminance = luminance;
      }
    }
  }
  return best!;
}

double _luminance(ui.Color color) =>
    (color.r * 255 * 54 + color.g * 255 * 183 + color.b * 255 * 19) / 256;

Matcher _near(ui.Color expected) => predicate<ui.Color>(
  (color) =>
      ((color.r - expected.r) * 255).abs() <= 3 &&
      ((color.g - expected.g) * 255).abs() <= 3 &&
      ((color.b - expected.b) * 255).abs() <= 3,
  'within 3 of $expected',
);
