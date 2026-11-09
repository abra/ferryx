/// The reader's contrast guard (`readflex_contrast_guard.js`): text whose
/// colour is unreadable on its background (a contrast under 4.5:1, WCAG's
/// AA) takes the reader's text colour, or black or white where even that
/// fails. Colours are `0xAARRGGBB`. Pure Dart.
library;

import 'dart:math' as math;

/// The contrast below which text is repaired.
const minimumTextContrast = 4.5;

/// [color] if it reads on [background] (opaque), else [textColor], else
/// black or white, whichever reads better. A translucent [color] is
/// judged as it shows over [background].
int readableTextColor(
  int color, {
  required int background,
  required int textColor,
}) {
  final visible = (color >>> 24) < 0xFF ? composite(color, background) : color;
  if (contrastRatio(visible, background) >= minimumTextContrast) return color;
  if (contrastRatio(textColor, background) >= minimumTextContrast) {
    return textColor;
  }
  return contrastRatio(0xFFFFFFFF, background) >=
          contrastRatio(0xFF000000, background)
      ? 0xFFFFFFFF
      : 0xFF000000;
}

/// [foreground] painted over [background] (source-over).
int composite(int foreground, int background) {
  final fa = (foreground >>> 24) / 255;
  if (fa >= 1) return foreground;
  final ba = (background >>> 24) / 255;
  final alpha = fa + ba * (1 - fa);
  if (alpha <= 0) return 0;
  int channel(int shift) {
    final f = (foreground >>> shift) & 0xFF;
    final b = (background >>> shift) & 0xFF;
    return ((f * fa + b * ba * (1 - fa)) / alpha).round().clamp(0, 255);
  }

  return ((alpha * 255).round() << 24) |
      (channel(16) << 16) |
      (channel(8) << 8) |
      channel(0);
}

/// WCAG 2's contrast ratio of two opaque colours, 1 to 21.
double contrastRatio(int a, int b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// WCAG 2's relative luminance of an sRGB colour.
double relativeLuminance(int color) {
  double linear(int shift) {
    final value = ((color >>> shift) & 0xFF) / 255;
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0);
}
