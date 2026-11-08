import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:settings_feature/settings_feature.dart';
import 'package:settings_feature/src/pages/terminal_font_picker.dart';
import 'package:settings_feature/src/settings_rows.dart';

import 'support.dart';

void main() {
  void disposeAfterTest(WidgetTester tester, PreferencesService service) {
    addTearDown(() async {
      final closed = service.dispose();
      // The stream was created in the widget test's fake async zone.
      await tester.pump();
      await closed;
    });
  }

  Finder pickerButton() => find.descendant(
    of: find.byType(TerminalFontPicker),
    matching: find.byType(OutlinedButton),
  );

  Text preview(WidgetTester tester) =>
      tester.widget<Text>(find.text(en.terminalFontSample));

  Future<void> choose(WidgetTester tester, String family) async {
    await tester.tap(pickerButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text(family).last);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    PreferencesService service, {
    required Future<List<String>> Function() loadFonts,
    SettingsSection section = SettingsSection.terminal,
  }) => pumpScreen(
    tester,
    SettingsScreen(
      preferencesService: service,
      platform: TargetPlatform.macOS,
      version: '0.1.0',
      initialSection: section,
      loadMonospaceFonts: loadFonts,
      onClose: () {},
    ),
  );

  testWidgets('font choices persist, update the preview and reset to the '
      'system face without reloading the catalog', (tester) async {
    final storage = InMemoryPreferencesStorage();
    final service = await PreferencesService.create(storage: storage);
    disposeAfterTest(tester, service);
    var loads = 0;
    await open(
      tester,
      service,
      section: SettingsSection.general,
      loadFonts: () async {
        loads++;
        return ['Menlo', 'Monaco'];
      },
    );
    expect(loads, 0, reason: 'only the terminal page needs a font catalog');
    await tester.tap(find.widgetWithText(AppNavItem, en.settingsTerminal));
    await tester.pumpAndSettle();
    expect(loads, 1);

    await tester.tap(pickerButton());
    await tester.pumpAndSettle();
    expect(find.text(AppTypography.bundledMono), findsOneWidget);
    expect(find.text('Menlo'), findsOneWidget);
    expect(find.text('Monaco'), findsOneWidget);
    await tester.tap(find.text('Menlo'));
    await tester.pumpAndSettle();
    expect(service.current.terminal.fontFamily, 'Menlo');
    expect((await storage.load())!.terminal.fontFamily, 'Menlo');
    expect(preview(tester).style!.fontFamily, 'Menlo');
    expect(preview(tester).style!.fontSize, 12);

    final slider = find.descendant(
      of: find.ancestor(
        of: find.text(en.terminalFontSizeLabel),
        matching: find.byType(SliderRow),
      ),
      matching: find.byType(Slider),
    );
    await tester.tap(slider);
    await tester.pumpAndSettle();
    expect(service.current.terminal.fontSize, isNot(12));
    expect(preview(tester).style!.fontSize, service.current.terminal.fontSize);
    expect(preview(tester).style!.fontFamily, 'Menlo');
    expect(loads, 1);

    await choose(tester, en.terminalFontSystem);
    expect(service.current.terminal.fontFamily, isEmpty);
    expect((await storage.load())!.terminal.fontFamily, isEmpty);
    final type = tester
        .element(find.byType(TerminalFontPicker))
        .metrics
        .typeScale;
    expect(preview(tester).style!.fontFamily, type.monoFamily);
    expect(loads, 1);
  });

  testWidgets('a missing saved family stays selected with a fallback notice '
      'until the user chooses another face', (tester) async {
    const missing = 'A font removed from this computer';
    final storage = InMemoryPreferencesStorage(
      const Preferences(terminal: TerminalPreferences(fontFamily: missing)),
    );
    final service = await PreferencesService.create(storage: storage);
    disposeAfterTest(tester, service);
    await open(tester, service, loadFonts: () async => ['Menlo']);

    expect(find.text(missing), findsOneWidget);
    expect(find.text(en.terminalFontUnavailable), findsOneWidget);
    expect(service.current.terminal.fontFamily, missing);
    expect(storage.saves, 0);
    expect(preview(tester).style!.fontFamily, missing);
    final system = tester
        .element(find.byType(TerminalFontPicker))
        .metrics
        .typeScale
        .monoFamily;
    expect(preview(tester).style!.fontFamilyFallback, contains(system));

    await choose(tester, AppTypography.bundledMono);
    expect(service.current.terminal.fontFamily, AppTypography.bundledMono);
    expect(find.text(en.terminalFontUnavailable), findsNothing);
    expect(preview(tester).style!.fontFamily, AppTypography.bundledMono);
  });

  testWidgets('a catalog failure preserves the saved choice and Retry loads '
      'installed families', (tester) async {
    final storage = InMemoryPreferencesStorage(
      const Preferences(terminal: TerminalPreferences(fontFamily: 'Menlo')),
    );
    final service = await PreferencesService.create(storage: storage);
    disposeAfterTest(tester, service);
    var loads = 0;
    await open(
      tester,
      service,
      loadFonts: () async {
        if (++loads == 1) throw PlatformException(code: 'font_catalog_failed');
        return ['Menlo', 'Monaco'];
      },
    );

    expect(find.text(en.terminalFontsLoadFailed), findsOneWidget);
    expect(find.text(en.terminalFontUnavailable), findsNothing);
    expect(find.text('Menlo'), findsOneWidget);
    expect(service.current.terminal.fontFamily, 'Menlo');
    expect(storage.saves, 0);
    await tester.tap(find.text(en.actionRetry));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text(en.terminalFontsLoadFailed), findsNothing);
    expect(find.text(en.terminalFontUnavailable), findsNothing);
    expect(find.text(en.actionRetry), findsNothing);
    expect(service.current.terminal.fontFamily, 'Menlo');

    await choose(tester, 'Monaco');
    expect(service.current.terminal.fontFamily, 'Monaco');
    expect(loads, 2);
  });

  testWidgets('leaving a page during catalog loading is safe and reopening '
      'it reads a fresh catalog', (tester) async {
    final pending = Completer<List<String>>();
    final service = await testPreferences();
    disposeAfterTest(tester, service);
    var loads = 0;
    await open(
      tester,
      service,
      loadFonts: () => ++loads == 1 ? pending.future : Future.value(['Menlo']),
    );
    expect(find.text(en.terminalFontsLoading), findsOneWidget);
    expect(loads, 1);
    await tester.tap(find.widgetWithText(AppNavItem, en.settingsGeneral));
    await tester.pumpAndSettle();
    pending.complete(['A catalog from the old page']);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TerminalFontPicker), findsNothing);

    await tester.tap(find.widgetWithText(AppNavItem, en.settingsTerminal));
    await tester.pumpAndSettle();
    expect(loads, 2);
    await tester.tap(pickerButton());
    await tester.pumpAndSettle();
    expect(find.text('Menlo'), findsOneWidget);
    expect(find.text('A catalog from the old page'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('the font popup opens and selects with the keyboard', (
    tester,
  ) async {
    final service = await testPreferences();
    disposeAfterTest(tester, service);
    await open(tester, service, loadFonts: () async => ['Menlo']);
    Focus.of(tester.element(find.text(en.terminalFontSystem))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(AppTypography.bundledMono), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(service.current.terminal.fontFamily, AppTypography.bundledMono);
    expect(preview(tester).style!.fontFamily, AppTypography.bundledMono);
  });
}
