import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palette_feature/palette_feature.dart';
import 'package:panels_feature/src/panel/panel_header.dart';
import 'package:shortcuts/shortcuts.dart';

import '../../packages/features/panels/test/support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  testWidgets('the visible command button opens the palette for its panel', (
    tester,
  ) async {
    await h.pump(
      tester,
      commandHandlers: {
        AppCommand.commandPalette: () => unawaited(
          showCommandPalette(
            FocusManager.instance.primaryFocus!.context!,
            shortcutMap: h.shortcutMap,
            vim: false,
          ),
        ),
      },
    );
    final right = find.byType(PanelHeader).last;
    await tester.tap(
      find.descendant(of: right, matching: find.text('Commands')),
    );
    await h.settle(tester);
    expect(find.byType(PaletteView), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'New Tab');
    await h.settle(tester);
    await h.press(tester, LogicalKeyboardKey.enter);
    expect(find.byType(PaletteView), findsNothing);
    final tabs = tester.widget<AppTabStrip>(find.byType(AppTabStrip));
    expect(tabs.tabs, hasLength(2));
    expect(
      tabs.tabs.map((tab) => tab.label),
      everyElement('tmp'),
      reason: 'the clicked right panel owns the command',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'compact headers keep sort and command access at large text sizes',
    (tester) async {
      var palettes = 0;
      for (final style in AppPlatformStyle.values) {
        for (final brightness in Brightness.values) {
          await h.pump(
            tester,
            size: const Size(900, 600),
            locale: const Locale('ru'),
            textScale: 1.6,
            style: style,
            brightness: brightness,
            commandHandlers: {AppCommand.commandPalette: () => palettes++},
          );
          final headers = find.byType(PanelHeader);
          for (var i = 0; i < 2; i++) {
            final palette = find.descendant(
              of: headers.at(i),
              matching: find.byWidgetPredicate(
                (w) => w is AppTooltip && w.message == 'Палитра команд',
              ),
            );
            expect(palette, findsOneWidget);
            final header = tester.getRect(headers.at(i));
            final button = tester.getRect(palette);
            expect(header.contains(button.center), isTrue);
            await tester.tap(palette);
            await tester.pump();
          }
          expect(tester.takeException(), isNull);
        }
      }
      expect(
        palettes,
        AppPlatformStyle.values.length * Brightness.values.length * 2,
      );
    },
  );
}
