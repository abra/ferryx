import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  // A phone in portrait: 390×844 CSS px at 3x.
  const phone = CssMediaEnvironment(
    viewportWidth: 390,
    viewportHeight: 760,
    deviceWidth: 390,
    deviceHeight: 844,
  );

  bool matches(
    String query, [
    CssMediaEnvironment environment = phone,
  ]) => cssMediaTextMatches(query, environment);

  group('media types', () {
    test('all and screen match; print and unknown types do not', () {
      expect(matches(''), isTrue);
      expect(matches('all'), isTrue);
      expect(matches('screen'), isTrue);
      expect(matches('SCREEN'), isTrue);
      expect(matches('only screen'), isTrue);
      expect(matches('print'), isFalse);
      // Kindle's and the retired types are not the reader's.
      expect(matches('amzn-kf8'), isFalse);
      expect(matches('amzn-mobi'), isFalse);
      expect(matches('handheld'), isFalse);
      expect(matches('tv'), isFalse);
    });

    test('not negates the whole query; lists match if any query does', () {
      expect(matches('not print'), isTrue);
      expect(matches('not screen'), isFalse);
      expect(matches('not amzn-mobi'), isTrue);
      expect(matches('print, screen'), isTrue);
      expect(matches('print, amzn-kf8'), isFalse);
    });

    test('malformed queries are not all', () {
      expect(matches('screen and'), isFalse);
      expect(matches('and screen'), isFalse);
      expect(matches('screen (color)'), isFalse);
      expect(matches('only'), isFalse);
      // One bad query does not spoil the list.
      expect(matches('screen and, screen'), isTrue);
    });
  });

  group('width as the paginated WebView saw it', () {
    test('wider than any breakpoint', () {
      expect(matches('(min-width: 1200px)'), isTrue);
      expect(matches('screen and (min-width: 40em)'), isTrue);
      expect(matches('(max-width: 600px)'), isFalse);
      expect(matches('(width > 10000px)'), isTrue);
      expect(matches('(orientation: landscape)'), isTrue);
      expect(matches('(orientation: portrait)'), isFalse);
      expect(matches('(min-aspect-ratio: 16/9)'), isTrue);
    });

    test('height and the device are the window and the screen', () {
      expect(matches('(min-height: 700px)'), isTrue);
      expect(matches('(max-height: 700px)'), isFalse);
      expect(matches('(max-device-width: 480px)'), isTrue);
      expect(matches('(min-device-width: 768px)'), isFalse);
      expect(
        matches(
          'only screen and (min-device-width: 768px) and '
          '(max-device-width: 1024px) and (orientation: landscape)',
        ),
        isFalse,
      );
      expect(
        matches(
          '(min-device-width: 768px)',
          const CssMediaEnvironment(deviceWidth: 820, deviceHeight: 1180),
        ),
        isTrue,
      );
      expect(matches('(device-aspect-ratio: 390/844)'), isTrue);
    });
  });

  group('features', () {
    test('lengths in em are 16px', () {
      expect(matches('(max-device-width: 24.375em)'), isTrue);
      expect(matches('(max-device-width: 24em)'), isFalse);
    });

    test('resolution and pixel ratio', () {
      expect(matches('(min-resolution: 2dppx)'), isTrue);
      expect(matches('(min-resolution: 192dpi)'), isTrue);
      expect(matches('(-webkit-min-device-pixel-ratio: 2)'), isTrue);
      expect(matches('(-webkit-max-device-pixel-ratio: 2)'), isFalse);
      expect(matches('(resolution: 3x)'), isTrue);
    });

    test('booleans: true unless zero or none', () {
      expect(matches('(color)'), isTrue);
      expect(matches('(monochrome)'), isFalse);
      expect(matches('(grid)'), isFalse);
      expect(matches('(hover)'), isFalse);
      expect(matches('(pointer: coarse)'), isTrue);
      expect(matches('(prefers-reduced-motion)'), isFalse);
    });

    test('preferences follow the environment', () {
      expect(matches('(prefers-color-scheme: light)'), isTrue);
      expect(matches('(prefers-color-scheme: dark)'), isFalse);
      const dark = CssMediaEnvironment(darkColorScheme: true);
      expect(matches('(prefers-color-scheme: dark)', dark), isTrue);
      const calm = CssMediaEnvironment(reducedMotion: true);
      expect(matches('(prefers-reduced-motion: reduce)', calm), isTrue);
    });

    test('unknown features make the query not all, even negated', () {
      expect(matches('(min-banana: 2)'), isFalse);
      expect(matches('not all and (min-banana: 2)'), isFalse);
      expect(matches('(banana)'), isFalse);
      expect(matches('(banana), screen'), isTrue);
    });
  });

  group('conditions', () {
    test('range syntax, both ways round and with two bounds', () {
      expect(matches('(height >= 700px)'), isTrue);
      expect(matches('(700px <= height)'), isTrue);
      expect(matches('(height < 700px)'), isFalse);
      expect(matches('(700px < height <= 800px)'), isTrue);
      expect(matches('(800px < height < 900px)'), isFalse);
      expect(matches('(height = 760px)'), isTrue);
    });

    test('and, or, not and nesting', () {
      expect(matches('(color) and (min-height: 700px)'), isTrue);
      expect(matches('(monochrome) or (min-height: 700px)'), isTrue);
      expect(matches('not (monochrome)'), isTrue);
      expect(matches('((color) and (monochrome)) or (hover: none)'), isTrue);
      // `and` and `or` do not mix without parentheses.
      expect(matches('(color) and (hover: none) or (monochrome)'), isFalse);
      // A media type takes `and` only.
      expect(matches('screen and (monochrome) or (color)'), isFalse);
    });
  });

  group('@supports', () {
    bool holds(String condition) =>
        cssSupportsConditionHolds(parseCssComponentValues(condition));

    test('a declaration holds when pagecraft parses it', () {
      expect(holds('(display: flex)'), isTrue);
      expect(holds('(border-radius: 4px)'), isTrue);
      expect(holds('(-webkit-hyphens: auto)'), isTrue);
      expect(holds('(display: banana)'), isFalse);
      expect(holds('(transform: rotate(4deg))'), isFalse);
    });

    test('not, and, or, selector()', () {
      expect(holds('not (transform: none)'), isTrue);
      expect(holds('(display: flex) and (position: relative)'), isTrue);
      expect(holds('(transform: none) or (display: grid)'), isTrue);
      expect(holds('(transform: none) and (display: grid)'), isFalse);
      expect(holds('selector(p > a)'), isTrue);
      expect(holds('selector(p >)'), isFalse);
      expect(holds('((display: flex) or (x: y)) and (not (z: w))'), isTrue);
      // `not` after `and` needs its own parentheses.
      expect(holds('(display: flex) and not (z: w)'), isFalse);
      expect(holds('banana'), isFalse);
    });
  });
}
