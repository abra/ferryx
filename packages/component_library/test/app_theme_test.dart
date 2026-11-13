import 'package:component_library/component_library.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// WCAG contrast of [fg] painted over [bg] (alpha composited first).
double contrast(Color fg, Color bg) {
  final top = Color.alphaBlend(fg, bg);
  final a = top.computeLuminance();
  final b = bg.computeLuminance();
  final (light, dark) = a > b ? (a, b) : (b, a);
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  const styles = AppPlatformStyle.values;
  const brightnesses = Brightness.values;

  group('AppPlatformStyle', () {
    test('maps every target platform to a desktop style', () {
      expect(AppPlatformStyle.of(TargetPlatform.macOS), AppPlatformStyle.macos);
      expect(AppPlatformStyle.of(TargetPlatform.iOS), AppPlatformStyle.macos);
      expect(
        AppPlatformStyle.of(TargetPlatform.windows),
        AppPlatformStyle.windows,
      );
      for (final other in [
        TargetPlatform.linux,
        TargetPlatform.android,
        TargetPlatform.fuchsia,
      ]) {
        expect(AppPlatformStyle.of(other), AppPlatformStyle.gnome);
      }
    });

    test('follows the platform override, as tests set it', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(AppPlatformStyle.current, AppPlatformStyle.windows);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('AppTheme', () {
    test('builds each style and brightness once and keeps it', () {
      for (final style in styles) {
        for (final brightness in brightnesses) {
          final theme = AppTheme.of(style, brightness);
          expect(AppTheme.of(style, brightness), same(theme));
          expect(theme.brightness, brightness);
          expect(theme.platform, style.targetPlatform);
          expect(theme.extension<AppMetrics>()!.style, style);
          expect(theme.extension<AppColorsExt>(), isNotNull);
        }
      }
    });

    test('no ink splashes and an arrow over buttons, as desktops have', () {
      for (final style in styles) {
        final theme = AppTheme.light(style);
        expect(theme.splashFactory, NoSplash.splashFactory);
        for (final button in [
          theme.filledButtonTheme.style!,
          theme.outlinedButtonTheme.style!,
          theme.textButtonTheme.style!,
        ]) {
          expect(
            button.mouseCursor!.resolve({}),
            SystemMouseCursors.basic,
            reason: '$style',
          );
          expect(
            button.minimumSize!.resolve({})!.height,
            AppMetrics.of(style).controlHeight,
          );
        }
      }
    });

    test('Windows buttons carry the Fluent elevation edge, text boxes the '
        'bottom line that turns accent on focus', () {
      final theme = AppTheme.light(AppPlatformStyle.windows);
      expect(
        theme.outlinedButtonTheme.style!.shape!.resolve({}),
        isA<FluentElevationBorder>(),
      );
      final input = theme.inputDecorationTheme;
      final focused = input.focusedBorder! as FluentInputBorder;
      expect(focused.bottom.width, 2);
      expect(focused.bottom.color, theme.colorScheme.primary);
      final blended = focused.lerpFrom(input.enabledBorder, 0.5);
      expect(blended, isA<FluentInputBorder>(), reason: 'kept while animating');
    });

    test('a text field is a control: body text on the control height, its '
        'border round all of it', () {
      for (final style in styles) {
        final theme = AppTheme.light(style);
        final input = theme.inputDecorationTheme;
        final field = theme.textTheme.bodyLarge!;
        final padding = input.contentPadding!.resolve(TextDirection.ltr);
        expect(field.fontSize, theme.textTheme.bodyMedium!.fontSize);
        expect(
          field.fontSize! * field.height! + padding.vertical,
          closeTo(AppMetrics.of(style).controlHeight, 1e-9),
          reason: '$style',
        );
        // A dense field draws its border round the content only and puts
        // any extra minimum height below it.
        expect(input.constraints, isNull);
        expect(input.visualDensity, VisualDensity.standard);
        final mono = AppTypography.of(style).mono;
        expect(
          mono.fontSize! * mono.height!,
          closeTo(field.fontSize! * field.height!, 1e-9),
          reason: 'a monospace field is as tall',
        );
      }
    });

    test('macOS dialogs and alerts sit on the window colour', () {
      final theme = AppTheme.light(AppPlatformStyle.macos);
      expect(
        theme.dialogTheme.backgroundColor,
        theme.extension<AppColorsExt>()!.window,
      );
    });
  });

  group('typography', () {
    test('the system face first, the bundled faces last in the fallback', () {
      final families = {
        AppPlatformStyle.macos: '.AppleSystemUIFont',
        AppPlatformStyle.windows: 'Segoe UI Variable Text',
        AppPlatformStyle.gnome: 'Adwaita Sans',
      };
      for (final style in styles) {
        final type = AppTypography.of(style);
        expect(type.sansFamily, families[style]);
        expect(type.sansFallback.last, AppTypography.bundledSans);
        expect(type.monoFallback.last, AppTypography.bundledMono);
        final body = AppTheme.light(style).textTheme.bodyMedium!;
        expect(body.fontFamily, families[style]);
        expect(body.fontFamilyFallback, type.sansFallback);
      }
    });

    test('body text on each platform\'s own ramp', () {
      final body = {
        AppPlatformStyle.macos: 13.0,
        AppPlatformStyle.windows: 14.0,
        AppPlatformStyle.gnome: 14.67,
      };
      for (final style in styles) {
        final text = AppTheme.light(style).textTheme;
        expect(text.bodyMedium!.fontSize, body[style], reason: '$style');
        expect(
          text.bodySmall!.fontSize,
          lessThan(text.bodyMedium!.fontSize!),
        );
      }
    });

    test('no web tracking leaks in from Material\'s own ramp', () {
      for (final style in styles) {
        final text = AppTheme.light(style).textTheme;
        for (final s in [
          text.bodyMedium!,
          text.bodySmall!,
          text.labelLarge!,
          text.labelSmall!,
        ]) {
          expect(s.letterSpacing, 0, reason: '$style $s');
        }
      }
    });

    test('every weight also sets the wght axis (no faked bold)', () {
      for (final style in styles) {
        final theme = AppTheme.light(style);
        final text = theme.textTheme;
        final all = {
          'bodyMedium': text.bodyMedium!,
          'titleMedium': text.titleMedium!,
          'labelSmall': text.labelSmall!,
          'displayLarge': text.displayLarge!,
          'mono': AppTypography.of(style).mono,
          'keyCap': AppTypography.of(style).keyCap,
        };
        all.forEach((name, s) {
          final axis = s.fontVariations!.singleWhere((v) => v.axis == 'wght');
          expect(axis.value, s.fontWeight!.value, reason: '$style $name');
        });
      }
    });
  });

  group('AppMetrics', () {
    test('the platforms\' own sizes', () {
      final mac = AppMetrics.of(AppPlatformStyle.macos);
      final win = AppMetrics.of(AppPlatformStyle.windows);
      final gnome = AppMetrics.of(AppPlatformStyle.gnome);
      expect(
        [mac.controlHeight, win.controlHeight, gnome.controlHeight],
        [22, 32, 34],
      );
      expect(
        [mac.topBarHeight, win.topBarHeight, gnome.topBarHeight],
        [52, 48, 47],
      );
      expect(
        [mac.radius.control, win.radius.control, gnome.radius.control],
        [6, 4, 9],
      );
      // A sidebar row and the room to the next one: a source list's rows
      // touch, NavigationView's stand 4 apart, a libadwaita sidebar's 2.
      expect(
        [
          for (final m in [mac, win, gnome]) (m.navItemHeight, m.navItemGap),
        ],
        [(28, 0), (36, 4), (36, 2)],
      );
      expect(
        [mac.menuItemHeight, win.menuItemHeight, gnome.menuItemHeight],
        [22, 28, 32],
      );
      // Only libadwaita rounds an alert and its buttons more than a dialog.
      expect([gnome.radius.alert, gnome.radius.alertAction], [18, 12]);
      for (final m in [mac, win]) {
        expect(m.radius.alert, m.radius.dialog, reason: '${m.style}');
        expect(m.radius.alertAction, m.radius.control, reason: '${m.style}');
      }
      expect(mac.navSelection, AppNavSelection.tint);
      expect(win.navSelection, AppNavSelection.indicator);
      expect(gnome.navSelection, AppNavSelection.fill);
      expect(mac.menuHighlightAccent, isTrue);
      expect(win.menuHighlightAccent || gnome.menuHighlightAccent, isFalse);
      expect(win.contentLayer, isTrue);
      expect(mac.navHover, isFalse, reason: 'source lists do not hover');
    });

    test('every radius grows from chip to dialog within a style', () {
      for (final style in styles) {
        final r = AppMetrics.of(style).radius;
        expect(r.chip, lessThanOrEqualTo(r.control));
        expect(r.menuItem, lessThan(r.menu));
        expect(r.control, lessThanOrEqualTo(r.dialog));
      }
    });

    test('snaps between styles instead of blending, and keys the theme', () {
      final mac = AppMetrics.of(AppPlatformStyle.macos);
      final win = AppMetrics.of(AppPlatformStyle.windows);
      expect(mac.lerp(win, 0.4), same(mac));
      expect(mac.lerp(win, 0.6), same(win));
      expect(mac.copyWith(), same(mac));
      // The extension map is keyed by `type`; a field of that name would
      // hide the metrics from `Theme.extension`.
      expect(mac.type, AppMetrics);
    });

    test('monospace swaps family and fallbacks together', () {
      final metrics = AppMetrics.of(AppPlatformStyle.gnome);
      final mono = metrics.monospace(const TextStyle(fontSize: 13));
      expect(mono.fontFamily, 'Adwaita Mono');
      expect(mono.fontFamilyFallback!.last, AppTypography.bundledMono);
      expect(mono.fontSize, 13);
    });
  });

  group('palettes', () {
    test('segmented selections remain distinct and their labels readable', () {
      for (final brightness in brightnesses) {
        final colors = AppPalette.of(brightness).colors;
        expect(
          contrast(colors.onSegmentedSelected, colors.segmentedSelected),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(colors.textMuted, colors.segmentedBackground),
          greaterThanOrEqualTo(4.5),
        );
        if (brightness == Brightness.dark) {
          expect(
            contrast(colors.segmentedSelected, colors.segmentedBackground),
            greaterThanOrEqualTo(3),
          );
        }
      }
    });

    test('selection text stays readable without borrowing button colours', () {
      for (final brightness in brightnesses) {
        final palette = AppPalette.of(brightness);
        final c = palette.colors;
        expect(AppPalette.of(brightness), same(palette));
        for (final background in [c.selectionAccent, c.accentSoft]) {
          expect(
            contrast(c.onSelection, background),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(c.onSelectionMuted, background),
            greaterThanOrEqualTo(4.5),
          );
          expect(contrast(c.accent, background), greaterThanOrEqualTo(3));
        }
        expect(contrast(c.onAccent, c.accent), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onCursor, c.cursorFill), greaterThanOrEqualTo(4.5));
        expect(
          contrast(c.onCursorMuted, c.cursorFill),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(c.accent, c.cursorFill), greaterThanOrEqualTo(3));
        expect(
          contrast(c.cursorFill, palette.surface),
          greaterThan(contrast(c.accentSoft, palette.surface)),
          reason: 'the current file must stand out more than marked files',
        );
        expect(
          contrast(c.textMuted, c.selectionMuted),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test(
      'text reads on its surfaces (WCAG AA for body and secondary text)',
      () {
        for (final style in styles) {
          for (final brightness in brightnesses) {
            final palette = AppPalette.of(brightness);
            final c = palette.colors;
            final label = '$style $brightness';
            expect(
              contrast(palette.onSurface, palette.surface),
              greaterThan(7),
              reason: label,
            );
            expect(
              contrast(c.textMuted, palette.surface),
              greaterThanOrEqualTo(4.5),
              reason: '$label textMuted',
            );
            expect(
              contrast(c.textFaint, palette.surface),
              greaterThanOrEqualTo(2.8),
              reason: '$label textFaint',
            );
            expect(
              contrast(c.link, palette.surface),
              greaterThanOrEqualTo(4.5),
              reason: '$label link',
            );
            expect(
              contrast(c.danger, palette.surface),
              greaterThanOrEqualTo(4.5),
              reason: '$label danger',
            );
            expect(
              contrast(c.onAccent, c.accent),
              greaterThanOrEqualTo(3),
              reason: '$label onAccent',
            );
            // A bookmark's star on the window's bars, where it stands.
            for (final bar in [palette.surface, c.windowChrome]) {
              expect(
                contrast(c.starEdge, bar),
                greaterThanOrEqualTo(3),
                reason: '$label star',
              );
            }
            for (final rating in [
              c.ratingAgain,
              c.ratingHard,
              c.ratingGood,
              c.ratingEasy,
            ]) {
              expect(
                contrast(rating, palette.surface),
                greaterThanOrEqualTo(3),
                reason: '$label rating',
              );
            }
          }
        }
      },
    );

    test('selected text on a page: a visible tint in both themes, under '
        'which the page\'s ink stays readable', () {
      for (final style in styles) {
        final light = AppPalette.of(Brightness.light).colors;
        final dark = AppPalette.of(Brightness.dark).colors;
        // The page is white in both themes, so the tint is too.
        expect(dark.pageSelection, light.pageSelection, reason: '$style');
        final tint = light.pageSelection;
        expect(tint.a, 1, reason: 'opaque, to multiply');
        const page = Color(0xFFFFFFFF);
        expect(contrast(tint, page), greaterThan(1.35), reason: '$style seen');
        // Book text (#333) multiplied by the tint stays dark on it.
        Color multiply(Color a, Color b) => Color.from(
          alpha: 1,
          red: a.r * b.r,
          green: a.g * b.g,
          blue: a.b * b.b,
        );
        const ink = Color(0xFF333333);
        expect(
          contrast(multiply(ink, tint), tint),
          greaterThan(7),
          reason: '$style ink',
        );
      }
    });

    test('six PDF markers, clamped by index', () {
      final c = AppPalette.of(Brightness.light).colors;
      expect(c.markers, hasLength(6));
      expect(c.marker(99), c.markers.last);
      expect(c.marker(-1), c.markers.first);
    });

    test('interpolates for the light/dark cross-fade, markers included', () {
      final a = AppPalette.of(Brightness.light).colors;
      final b = AppPalette.of(Brightness.dark).colors;
      expect(a.lerp(b, 0).sidebar, a.sidebar);
      expect(a.lerp(b, 1).sidebar, b.sidebar);
      expect(a.lerp(b, 0.5).markers, hasLength(6));
      expect(a.lerp(null, 0.5), same(a));
    });
  });

  testWidgets('the menu plate: fill, an edge that holds on a white page, a '
      'tight and a floating shadow on every style', (tester) async {
    for (final style in styles) {
      late ShapeDecoration plate;
      late ShapeDecoration onDark;
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: AppTheme.light(style),
          home: Builder(
            builder: (context) {
              plate = AppMenuPanel.plate(context);
              onDark = AppMenuPanel.plate(context, backdrop: Brightness.dark);
              return const SizedBox();
            },
          ),
        ),
      );
      final colors = AppTheme.light(style).extension<AppColorsExt>()!;
      final shape = plate.shape as AppRoundedRectangleBorder;
      final edge = shape.side.color;
      expect(
        contrast(edge, plate.color!),
        greaterThan(contrast(colors.line, plate.color!)),
        reason: '$style: the menu edge is stronger than a divider',
      );
      // The fill stops inside the edge, so its corners keep it.
      expect(shape.insetFill, isTrue);
      final shadows = plate.shadows!;
      expect(shadows, hasLength(2));
      expect(shadows.first.blurRadius, lessThan(8), reason: 'at the edge');
      expect(shadows.last.blurRadius, greaterThanOrEqualTo(16));
      // What lies under the plate sets the shadow: heavier on a dark one.
      expect(
        onDark.shadows!.last.color.a,
        greaterThan(shadows.last.color.a),
      );
      expect(onDark.shape, plate.shape, reason: 'the edge is the theme\'s');
      expect(
        shape.borderRadius,
        BorderRadius.circular(AppMetrics.of(style).radius.menu),
      );
    }
  });

  testWidgets('context accessors read the theme of the platform style', (
    tester,
  ) async {
    late AppMetrics metrics;
    late TextStyle mono;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.windows),
        home: Builder(
          builder: (context) {
            metrics = context.metrics;
            mono = context.mono;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(metrics.style, AppPlatformStyle.windows);
    expect(mono.fontFamily, 'Cascadia Mono');
    expect(
      mono.color,
      AppTheme.light(AppPlatformStyle.windows).colorScheme.onSurface,
    );
  });
}
