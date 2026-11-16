import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/panels_feature.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(() async {
    WorkspaceHarness.registerFallbacks();
    for (final (family, file) in [
      ('Inter', 'Inter-Variable.ttf'),
      ('Geist Mono', 'GeistMono-Variable.ttf'),
    ]) {
      await (FontLoader(family)..addFont(
            rootBundle.load('packages/component_library/fonts/$file'),
          ))
          .load();
    }
  });
  late WorkspaceHarness h;
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp(vim: true);
  });
  tearDown(() => h.tearDown());

  PanelCubit panel(WidgetTester tester) =>
      tester.element(find.byType(PanelView).first).read<PanelCubit>();

  List<AppKeyHint> entries(WidgetTester tester) => tester
      .widget<AppKeyHints>(
        find.descendant(
          of: find.byType(KeyHintStrip),
          matching: find.byType(AppKeyHints),
        ),
      )
      .hints;

  for (final language in ['en', 'ru']) {
    testWidgets(
      '$language command input replaces file hints and Esc restores them',
      (
        tester,
      ) async {
        final locale = Locale(language);
        final l10n = lookupFerryxLocalizations(locale);
        await h.pump(tester, locale: locale, size: const Size(900, 600));
        final left = panel(tester);
        left.moveCursorTo(left.state.active!.firstItemIndex);
        await h.press(tester, LogicalKeyboardKey.space, character: ' ');
        final selected = left.state.active!.selected;
        expect(
          entries(tester).map((hint) => hint.label),
          contains(l10n.cmdCopyItemName),
        );

        await h.press(
          tester,
          LogicalKeyboardKey.semicolon,
          shift: true,
          character: ':',
        );
        await tester.enterText(find.byType(EditableText), 'cd /tmp');
        await h.settle(tester);

        final hints = entries(tester);
        expect(
          hints.map((hint) => hint.label),
          containsAll([
            l10n.paletteKeyRun,
            l10n.hintComplete,
            l10n.hintPreviousCommand,
            l10n.hintNextCommand,
            l10n.actionCancel,
          ]),
        );
        expect(hints.expand((hint) => hint.keys), isNot(contains('yn')));
        expect(hints.expand((hint) => hint.keys), isNot(contains('yp')));
        // Modal help would steal focus and discard this unfinished command.
        expect(find.text(l10n.contextActions), findsNothing);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          'cd /tmp',
        );
        expect(
          find.descendant(
            of: find.byType(KeyHintStrip),
            matching: find.text(l10n.hintComplete),
          ),
          findsOneWidget,
        );

        await h.press(tester, LogicalKeyboardKey.escape);

        expect(find.byType(EditableText), findsNothing);
        expect(left.state.active!.location.path, '/home/docs');
        expect(left.state.active!.selected, selected);
        expect(
          entries(tester).map((hint) => hint.label),
          contains(l10n.cmdCopyItemName),
        );
        expect(
          tester
              .widget<PanelView>(find.byType(PanelView).first)
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(h.started, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('inline rename keeps its draft until Enter or Escape', (
    tester,
  ) async {
    final l10n = lookupFerryxLocalizations(const Locale('en'));
    await h.pump(tester);
    final left = panel(tester);
    left.moveCursorTo(left.state.active!.firstItemIndex);
    final originalName = left.state.active!.focused!.name;
    await h.type(tester, 'cw');
    expect(left.state.active!.renaming, isNotNull);
    await tester.enterText(find.byType(EditableText), 'unfinished-name.txt');
    await h.settle(tester);

    expect(
      entries(tester).map((hint) => hint.label),
      [l10n.actionDone, l10n.actionCancel],
    );
    // Opening a modal here would commit the rename through focus loss.
    expect(find.text(l10n.contextActions), findsNothing);
    expect(left.state.active!.focused!.name, originalName);

    await h.press(tester, LogicalKeyboardKey.escape);

    expect(find.byType(EditableText), findsNothing);
    expect(left.state.active!.renaming, isNull);
    expect(left.state.active!.focused!.name, originalName);
    expect(h.started, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ordinary quick search retains next steps and marked-file hints',
    (
      tester,
    ) async {
      await tester.runAsync(
        () => h.preferences.update((prefs) => prefs.copyWith(vimMode: false)),
      );
      final l10n = lookupFerryxLocalizations(const Locale('en'));
      await h.pump(tester);
      await h.type(tester, 'a');
      final left = panel(tester);
      expect(left.state.active!.focused?.name, 'a.txt');
      expect(left.state.active!.quickSearch, 'a');
      expect(
        entries(tester).map((hint) => hint.label),
        containsAll([
          l10n.cmdClearQuickSearch,
          l10n.cmdOpenItem,
          l10n.cmdShowPreview,
          l10n.cmdToggleSelectionMoveDown,
        ]),
      );

      await h.press(tester, LogicalKeyboardKey.space, alt: true);

      expect(left.state.active!.selected, {'a.txt'});
      expect(
        entries(tester).map((hint) => hint.label),
        containsAll([
          l10n.cmdCopyItemName,
          l10n.cmdCopyItemPath,
        ]),
      );
      await h.press(tester, LogicalKeyboardKey.escape);
      expect(left.state.active!.quickSearch, isEmpty);
      expect(left.state.active!.selected, {'a.txt'});
      expect(
        entries(tester).map((hint) => hint.label),
        contains(l10n.cmdCopyItemName),
      );
      expect(h.started, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
