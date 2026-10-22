import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:settings_feature/settings_feature.dart';

import 'support.dart';

void main() {
  Future<PreferencesService> open(
    WidgetTester tester, {
    SettingsSection section = SettingsSection.general,
    VoidCallback? onClose,
  }) async {
    final service = await testPreferences();
    await pumpScreen(
      tester,
      SettingsScreen(
        preferencesService: service,
        platform: TargetPlatform.macOS,
        version: '0.1.0',
        initialSection: section,
        onClose: onClose ?? () {},
      ),
    );
    return service;
  }

  testWidgets('opens on its section and every section opens', (tester) async {
    await open(tester, section: SettingsSection.viewer);
    expect(find.text(en.viewerWrapLabel), findsOneWidget);
    for (final section in SettingsSection.values) {
      final label = switch (section) {
        SettingsSection.general => en.settingsGeneral,
        SettingsSection.panels => en.settingsPanels,
        SettingsSection.viewer => en.settingsViewer,
        SettingsSection.hotkeys => en.settingsHotkeys,
        SettingsSection.editors => en.settingsEditors,
        SettingsSection.tools => en.settingsTools,
        SettingsSection.about => en.settingsAbout,
      };
      await tester.tap(find.widgetWithText(AppNavItem, label));
      await tester.pumpAndSettle();
      expect(find.text(label), findsNWidgets(2), reason: '$section title');
    }
    expect(find.text(en.aboutVersion('0.1.0')), findsOneWidget);
  });

  testWidgets('a toggle writes the preference at once', (tester) async {
    final service = await open(tester);
    expect(service.current.confirmTrash, isFalse);
    final toggle = find.ancestor(
      of: find.text(en.confirmTrashLabel),
      matching: find.byType(AppControlRow),
    );
    await tester.tap(
      find.descendant(of: toggle, matching: find.byType(AppToggle)),
    );
    await tester.pumpAndSettle();
    expect(service.current.confirmTrash, isTrue);
  });

  testWidgets('the theme segments and the panels page write too', (
    tester,
  ) async {
    final service = await open(tester);
    await tester.tap(find.text(en.themeDark));
    await tester.pumpAndSettle();
    expect(service.current.themeMode, AppThemeMode.dark);
    await tester.tap(find.widgetWithText(AppNavItem, en.settingsPanels));
    await tester.pumpAndSettle();
    final hidden = find.ancestor(
      of: find.text(en.panelsShowHidden),
      matching: find.byType(AppControlRow),
    );
    await tester.tap(
      find.descendant(of: hidden, matching: find.byType(AppToggle)),
    );
    await tester.pumpAndSettle();
    expect(service.current.showHiddenFiles, isTrue);
    expect(service.current.layouts, PanelLayout.defaults);
    expect(find.text('1. Short'), findsOneWidget);
  });

  testWidgets('the search narrows the pages and Esc closes', (tester) async {
    var closed = false;
    await open(tester, onClose: () => closed = true);
    await tester.enterText(find.byType(AppSearchField), 'hot');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppNavItem, en.settingsHotkeys), findsOneWidget);
    expect(find.widgetWithText(AppNavItem, en.settingsPanels), findsNothing);
    // The open page was left out, so the page with the hit opened.
    expect(find.text(en.settingsHotkeys), findsNWidgets(2));
    // Esc empties the search first, as a search field's does; the pages
    // come back. The next Esc closes.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(find.widgetWithText(AppNavItem, en.settingsPanels), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('an editor is added through its dialog', (tester) async {
    final service = await open(tester, section: SettingsSection.editors);
    expect(find.text(en.editorsEmpty), findsOneWidget);
    await tester.tap(find.text(en.editorsAdd));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AppDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Vim');
    await tester.enterText(fields.at(1), '/usr/bin/vim');
    await tester.enterText(fields.at(2), '*.md;*.txt');
    await tester.tap(find.text(en.actionSave));
    await tester.pumpAndSettle();
    expect(service.current.editors, [
      const ExternalEditor(
        name: 'Vim',
        path: '/usr/bin/vim',
        mask: '*.md;*.txt',
      ),
    ]);
    expect(find.text('Vim'), findsOneWidget);
  });
}
