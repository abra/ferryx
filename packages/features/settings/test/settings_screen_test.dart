import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:settings_feature/settings_feature.dart';
import 'package:settings_feature/src/pages/terminal_page.dart';
import 'package:settings_feature/src/settings_rows.dart';

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
        SettingsSection.terminal => en.settingsTerminal,
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

  testWidgets('the sidebar\'s rows and search field stand a source list\'s '
      'margin from its edges', (tester) async {
    await open(tester);
    final metrics = tester.element(find.byType(AppNavItem).first).metrics;
    final sidebar = tester.getRect(
      find.ancestor(
        of: find.byType(AppSearchField),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == AppSizes.settingsNavWidth,
        ),
      ),
    );
    // Less the line at its right.
    final inner = sidebar.left + AppSizes.settingsNavWidth - 1;
    final search = tester.getRect(find.byType(AppSearchField));
    expect(search.left - sidebar.left, metrics.navRowMargin);
    expect(inner - search.right, metrics.navRowMargin);
    for (final row in find.byType(AppNavItem).evaluate()) {
      final rect = tester.getRect(find.byWidget(row.widget));
      expect(rect.left - sidebar.left, metrics.navRowMargin);
      expect(inner - rect.right, metrics.navRowMargin);
    }
    final icon = tester.getRect(
      find.descendant(
        of: find.byType(AppNavItem).first,
        matching: find.byType(Icon),
      ),
    );
    expect(icon.left - sidebar.left, 16);
  });

  testWidgets('the terminal page: the shell is written when the field is '
      'done, the size and the scrollback at once', (tester) async {
    final service = await testPreferences();
    await pumpScreen(
      tester,
      SettingsScreen(
        preferencesService: service,
        platform: TargetPlatform.macOS,
        version: '0.1.0',
        initialSection: SettingsSection.terminal,
        defaultShell: '/bin/zsh',
        onClose: () {},
      ),
    );
    expect(find.text(en.terminalShellDefault('/bin/zsh')), findsOneWidget);
    final field = find.byType(ShellField);
    await tester.enterText(
      find.descendant(of: field, matching: find.byType(TextField)),
      '  /opt/homebrew/bin/fish ',
    );
    await tester.pump();
    // Not at every key: the preferences are saved whole.
    expect(service.current.terminal.shell, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(service.current.terminal.shell, '/opt/homebrew/bin/fish');

    await tester.tap(find.text(en.terminalLineCount(10000)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.terminalLineCount(50000)).last);
    await tester.pumpAndSettle();
    expect(service.current.terminal.scrollback, 50000);

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
    // How the panels stand: by the window's shape until chosen.
    expect(
      service.current.panelArrangement,
      PanelArrangement.byWindowShape,
    );
    await tester.tap(find.text(en.panelsArrangementByWindowShape));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.panelsArrangementStacked).last);
    await tester.pumpAndSettle();
    expect(service.current.panelArrangement, PanelArrangement.stacked);
    expect(service.current.layouts, PanelLayout.defaults);
    // The view modes stand below the panels' options, out of view.
    await tester.scrollUntilVisible(
      find.text('1. Short'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('1. Short'), findsOneWidget);
  });

  testWidgets('the default view modes take the language\'s names, one the '
      'user named keeps it; a default saved as shown keeps its own', (
    tester,
  ) async {
    final service = await testPreferences();
    await service.update(
      (p) => p.copyWith(
        layouts: [
          ...PanelLayout.defaults,
          const PanelLayout(name: 'Photos', mode: ViewMode.brief),
        ],
      ),
    );
    await pumpScreen(
      tester,
      locale: const Locale('ru'),
      SettingsScreen(
        preferencesService: service,
        platform: TargetPlatform.macOS,
        version: '0.1.0',
        initialSection: SettingsSection.panels,
        onClose: () {},
      ),
    );
    await tester.scrollUntilVisible(
      find.text('6. Photos'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('1. ${ru.layoutShort}'), findsOneWidget);
    expect(find.text('5. ${ru.layoutDetails}'), findsOneWidget);
    expect(find.text('6. Photos'), findsOneWidget);
    expect(find.text('1. Short'), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('layout-0')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('layout-0')),
        matching: find.byTooltip(ru.hotkeysChange),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, ru.layoutShort),
      findsOneWidget,
      reason: 'the name as shown',
    );
    await tester.tap(find.widgetWithText(FilledButton, ru.actionSave));
    await tester.pumpAndSettle();
    expect(service.current.layouts.first.name, 'Short');
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
