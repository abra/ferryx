import 'package:component_library/component_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Pumps [child] under the macOS theme of [generation].
Future<void> pumpMac(
  WidgetTester tester,
  MacGeneration generation,
  Widget child, {
  double? width,
}) => tester.pumpWidget(
  MaterialApp(
    themeAnimationDuration: Duration.zero,
    theme: AppTheme.of(
      AppPlatformStyle.macos,
      Brightness.light,
      generation: generation,
    ),
    home: Scaffold(
      body: Center(
        child: width == null ? child : SizedBox(width: width, child: child),
      ),
    ),
  ),
);

void main() {
  test('the generation follows the system\'s version', () {
    expect(
      MacGeneration.fromVersion('Version 15.7.9 (Build 24G231)'),
      MacGeneration.sequoia,
    );
    expect(
      MacGeneration.fromVersion('Version 26.0 (Build 25A354)'),
      MacGeneration.tahoe,
    );
    expect(MacGeneration.fromVersion('Version 27.1'), MacGeneration.tahoe);
    expect(MacGeneration.fromVersion(''), MacGeneration.sequoia);
    MacGeneration.debugOverride = MacGeneration.tahoe;
    addTearDown(() => MacGeneration.debugOverride = null);
    expect(MacGeneration.current, MacGeneration.tahoe);
  });

  test('macOS 26 has its own metrics and theme; the others have one', () {
    final sequoia = AppMetrics.of(AppPlatformStyle.macos);
    final tahoe = AppMetrics.of(
      AppPlatformStyle.macos,
      generation: MacGeneration.tahoe,
    );
    expect((sequoia.controlHeight, tahoe.controlHeight), (22, 24));
    expect((sequoia.navItemHeight, tahoe.navItemHeight), (28, 32));
    expect(tahoe.toggleSize, const Size(44, 20));
    expect((tahoe.toggleKnob, tahoe.toggleKnobWidth), (16, 26));
    expect(sequoia.toggleKnobWidth, sequoia.toggleKnob, reason: 'a circle');
    // Both the regular NSSwitch, as System Settings draws a pane's switch:
    // drawn by AppKit on macOS 15, 38 × 22 with a 20 pt knob 1 pt in.
    expect(sequoia.toggleSize, const Size(38, 22));
    expect(sequoia.toggleKnob, 20);
    expect(tahoe.radius.search, AppRadius.full);
    expect(sequoia.radius.search, sequoia.radius.control);
    expect(tahoe.generation, MacGeneration.tahoe);

    final light = AppTheme.of(AppPlatformStyle.macos, Brightness.light);
    final glass = AppTheme.of(
      AppPlatformStyle.macos,
      Brightness.light,
      generation: MacGeneration.tahoe,
    );
    expect(glass, isNot(same(light)));
    expect(glass.extension<AppMetrics>(), same(tahoe));
    expect(
      AppTheme.of(
        AppPlatformStyle.macos,
        Brightness.light,
        generation: MacGeneration.tahoe,
      ),
      same(glass),
      reason: 'built once',
    );
    for (final style in [AppPlatformStyle.windows, AppPlatformStyle.gnome]) {
      expect(
        AppTheme.of(style, Brightness.dark, generation: MacGeneration.tahoe),
        same(AppTheme.of(style, Brightness.dark)),
        reason: '$style has no generations',
      );
    }
  });

  for (final generation in MacGeneration.values) {
    testWidgets('$generation: the switch is the generation\'s, its knob a '
        'circle or a pill', (tester) async {
      await pumpMac(
        tester,
        generation,
        AppToggle(value: true, onChanged: (_) {}),
      );
      final metrics = AppMetrics.of(
        AppPlatformStyle.macos,
        generation: generation,
      );
      expect(tester.getSize(find.byType(AppToggle)), metrics.toggleSize);
      final knob = tester.getSize(
        find
            .descendant(
              of: find.byType(AnimatedAlign),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(knob, Size(metrics.toggleKnobWidth, metrics.toggleKnob));
    });

    for (final brightness in Brightness.values) {
      testWidgets('$generation $brightness: the switch\'s knob stays visible '
          'on the accent and neutral tracks', (tester) async {
        Color fillOf(Finder container) {
          return switch (tester
              .widget<AnimatedContainer>(container)
              .decoration) {
            final BoxDecoration box => box.color!,
            final ShapeDecoration shape => shape.color!,
            final other => throw StateError('$other'),
          };
        }

        for (final value in [true, false]) {
          await tester.pumpWidget(
            MaterialApp(
              themeAnimationDuration: Duration.zero,
              theme: AppTheme.of(
                AppPlatformStyle.macos,
                brightness,
                generation: generation,
              ),
              home: Scaffold(
                body: Center(
                  child: AppToggle(value: value, onChanged: (_) {}),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final containers = find.descendant(
            of: find.byType(AppToggle),
            matching: find.byType(AnimatedContainer),
          );
          final colors = AppTheme.of(
            AppPlatformStyle.macos,
            brightness,
            generation: generation,
          ).extension<AppColorsExt>()!;
          final knob = fillOf(containers.last);
          final track = fillOf(containers.first);
          expect(
            knob,
            value ? colors.onAccent : colors.switchKnob,
            reason: 'the knob, ${value ? 'on' : 'off'}',
          );
          expect(track, value ? colors.switchTrack : colors.pressedFill);
          if (value || brightness == Brightness.dark) {
            final luminances = [
              knob.computeLuminance(),
              track.computeLuminance(),
            ]..sort();
            expect(
              (luminances.last + 0.05) / (luminances.first + 0.05),
              greaterThanOrEqualTo(3),
              reason: 'the knob must remain visible against its track',
            );
          }
        }
      });
    }

    testWidgets('$generation: the switch keeps its size in larger text, as '
        'AppKit\'s does', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.of(
            AppPlatformStyle.macos,
            Brightness.light,
            generation: generation,
          ),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: Center(child: AppToggle(value: true, onChanged: (_) {})),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(AppToggle)),
        AppMetrics.of(
          AppPlatformStyle.macos,
          generation: generation,
        ).toggleSize,
      );
    });

    testWidgets('$generation: a search field is the generation\'s shape, '
        'a text field\'s height', (tester) async {
      await pumpMac(
        tester,
        generation,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSearchField(hintText: 'Search'),
            AppTextField(),
          ],
        ),
        width: 300,
      );
      final metrics = AppMetrics.of(
        AppPlatformStyle.macos,
        generation: generation,
      );
      final search = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byType(AppSearchField),
          matching: find.byType(InputDecorator),
        ),
      );
      final border = search.decoration.enabledBorder;
      final radius = border is OutlineInputBorder
          ? border.borderRadius.topLeft.x
          : metrics.radius.control;
      expect(radius, metrics.radius.search);
      final fields = find.byType(InputDecorator);
      expect(
        tester.getSize(fields.first).height,
        tester.getSize(fields.last).height,
        reason: 'beside a field or a button it keeps their line',
      );
      expect(
        tester.getSize(fields.last).height,
        closeTo(metrics.controlHeight, 1),
      );
    });
  }
}
