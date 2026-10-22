import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final style in AppPlatformStyle.values) {
    for (final brightness in Brightness.values) {
      test('$style $brightness: sixteen ANSI colours that read on the '
          'terminal\'s surface', () {
        final theme = AppTheme.of(style, brightness);
        final colors = theme.extension<AppTerminalColors>()!;
        expect(colors.ansi, hasLength(16));
        final surface = theme.colorScheme.surface;
        final dark = brightness == Brightness.dark;
        for (var i = 0; i < 16; i++) {
          // The background's own colour (black in dark, white in light)
          // and bright white in light are for backgrounds, not text.
          final own = dark ? i == 0 : (i == 7 || i == 15);
          final needed = own ? 2.0 : (i < 8 ? 4.4 : 4.0);
          expect(
            _contrast(colors.ansi[i], surface),
            greaterThanOrEqualTo(needed),
            reason: 'colour $i on $surface',
          );
        }
      });
    }
  }

  test('a theme change blends the palettes', () {
    final light = AppTerminalColors.forBrightness(Brightness.light);
    final dark = AppTerminalColors.forBrightness(Brightness.dark);
    expect(light.lerp(dark, 0).ansi, light.ansi);
    expect(light.lerp(dark, 1).ansi, dark.ansi);
    expect(light.lerp(null, 0.5), same(light));
    expect(light.red, light.ansi[1]);
    expect(dark.brightWhite, dark.ansi[15]);
  });
}
