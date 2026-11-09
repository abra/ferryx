import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Theme colours for image pages (PDF): paper takes the reader background
/// and ink takes the reader text colour, as `readflex_page_colors.js` did.
///
/// Light themes tint the paper to the background and lift black to the
/// text colour. Dark themes invert luminance, keeping the hue so blue stays
/// blue, then map black to the background and white to the text colour.
/// Photos invert too; readers who mind keep the original colours.
class PageColors {
  const PageColors({
    required this.background,
    required this.foreground,
    required this.dark,
  });

  final ui.Color background;
  final ui.Color foreground;

  /// Whether the page is inverted (dark themes) or only tinted.
  final bool dark;

  @override
  bool operator ==(Object other) =>
      other is PageColors &&
      other.background == background &&
      other.foreground == foreground &&
      other.dark == dark;

  @override
  int get hashCode => Object.hash(background, foreground, dark);

  @override
  String toString() =>
      'PageColors(background: $background, foreground: $foreground, dark: $dark)';
}

/// Backgrounds this light are white paper already; recolouring would only
/// soften black text.
const _whitePaperLuminance = 0.98;

/// Reader themes darker than this invert pages instead of tinting them.
const _darkThemeLuminance = 0.4;

/// The page colours for a reader theme, or null to keep pages as published
/// (the setting is off, or the theme is white paper).
PageColors? pageColorsFor({
  required bool themed,
  required ui.Color background,
  required ui.Color foreground,
}) {
  if (!themed) return null;
  final paper = relativeLuminance(background);
  if (paper >= _whitePaperLuminance) return null;
  return PageColors(
    background: background,
    foreground: foreground,
    dark: paper < _darkThemeLuminance,
  );
}

/// WCAG relative luminance of [color], 0–1.
double relativeLuminance(ui.Color color) {
  double linear(double channel) => channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}

/// Draws [source] of [image] into [destination] with [colors] applied, as
/// the WebView recoloured its bitmaps with canvas composite operations:
/// the same blend modes, on the GPU, once per frame.
/// Draws [source] of [image] into [destination], recoloured by [colors].
///
/// Recolouring is one `ColorFilter.matrix` on the image paint: a single
/// draw that renders the same under Impeller and Skia. (Blend modes inside
/// a `saveLayer`, the WebView's canvas recipe, are a no-op on Impeller.)
void paintPageWithColors(
  ui.Canvas canvas,
  ui.Image image, {
  required ui.Rect source,
  required ui.Rect destination,
  required PageColors? colors,
  ui.FilterQuality filterQuality = ui.FilterQuality.medium,
}) {
  // Hard edges, as `RawImage` paints: a page bitmap ends where it ends.
  final paint = ui.Paint()
    ..filterQuality = filterQuality
    ..isAntiAlias = false;
  if (colors != null) paint.colorFilter = pageColorFilter(colors);
  canvas.drawImageRect(image, source, destination, paint);
}

/// The colour filter that recolours a page for [colors].
///
/// Light themes map white to the background and black to the text colour,
/// linearly in between. Dark themes first invert luminance in YIQ space,
/// which keeps the hue, so a blue figure stays blue, then map the inverted
/// white (now black) to the background and the inverted black to the text
/// colour. Each is one 4×5 matrix, so a page costs the same draw as an
/// unrecoloured one.
ui.ColorFilter pageColorFilter(PageColors colors) => _filters.putIfAbsent(
  colors,
  () => ui.ColorFilter.matrix(debugPageColorMatrix(colors)),
);

final _filters = <PageColors, ui.ColorFilter>{};

/// The 4×5 matrix behind [pageColorFilter], for tests.
@visibleForTesting
List<double> debugPageColorMatrix(PageColors colors) {
  final bg = [colors.background.r, colors.background.g, colors.background.b];
  final fg = [colors.foreground.r, colors.foreground.g, colors.foreground.b];
  final matrix = List<double>.filled(20, 0);
  for (var c = 0; c < 3; c++) {
    final span = bg[c] - fg[c];
    if (colors.dark) {
      // out = bg + (fg - bg) * inverted, inverted = M·src + 1, so
      // out = -span * M·src + fg.
      for (var i = 0; i < 3; i++) {
        matrix[c * 5 + i] = -span * _lumaInvert[c * 3 + i];
      }
      matrix[c * 5 + 4] = fg[c] * 255;
    } else {
      // out = fg + (bg - fg) * src.
      matrix[c * 5 + c] = span;
      matrix[c * 5 + 4] = fg[c] * 255;
    }
  }
  matrix[18] = 1;
  return matrix;
}

/// Luminance inversion in YIQ: Y becomes 1 − Y, I and Q stay, so colours
/// keep their hue. Applied as `M·rgb + (1, 1, 1)`.
const _lumaInvert = [
  0.402, -1.174, -0.228, //
  -0.598, -0.174, -0.228, //
  -0.598, -1.174, 0.772, //
];
