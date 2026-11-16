import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support/workspace_harness.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  late List<String> writes;
  var failWrite = false;
  const folder = '/home/clipboard';
  const names = ['notes', 'zeta.txt', 'данные.csv'];
  const paths = [
    '$folder/notes',
    '$folder/zeta.txt',
    '$folder/данные.csv',
  ];

  setUp(() async {
    writes = [];
    failWrite = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          if (failWrite) {
            throw PlatformException(
              code: 'unavailable',
              message: 'Clipboard unavailable',
            );
          }
          writes.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    h = WorkspaceHarness();
    await h.setUp();
    h.addFolder(folder, ['zeta.txt', 'report draft.md', 'данные.csv']);
    h.addFolder('$folder/notes');
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    await h.tearDown();
  });

  PanelCubit left(WidgetTester tester) =>
      tester.element(find.byType(PanelView).first).read<PanelCubit>();

  void markInReverseOrder(PanelCubit panel) {
    for (final name in names.reversed) {
      panel.toggleSelectionAt(
        panel.state.active!.rows.indexWhere((row) => row.name == name),
      );
    }
    panel.moveCursorTo(
      panel.state.active!.rows.indexWhere(
        (row) => row.name == 'report draft.md',
      ),
    );
  }

  Future<void> dispatch(WidgetTester tester, AppCommand command) async {
    Actions.invoke(
      tester.element(find.byType(PanelView).first),
      CommandIntent(command),
    );
    await tester.pumpAndSettle();
  }

  for (final command in [
    AppCommand.copyItemName,
    AppCommand.copyItemPath,
    AppCommand.copyPaths,
  ]) {
    testWidgets('${command.name} copies marked rows in visible order', (
      tester,
    ) async {
      await h.pump(tester, left: folder);
      final panel = left(tester);
      markInReverseOrder(panel);
      final selected = panel.state.active!.selected;
      final cursor = panel.state.active!.cursor;
      await tester.pumpAndSettle();

      await h.press(
        tester,
        LogicalKeyboardKey.keyC,
        meta: true,
        shift: command == AppCommand.copyItemName,
        alt: command == AppCommand.copyItemPath,
      );

      expect(
        writes,
        [(command == AppCommand.copyItemName ? names : paths).join('\n')],
      );
      expect(panel.state.active!.selected, selected);
      expect(panel.state.active!.cursor, cursor);
      final l10n = lookupFerryxLocalizations(const Locale('en'));
      expect(
        find.text(
          command == AppCommand.copyItemName
              ? l10n.noticeNamesCopied(names.length)
              : l10n.noticePathsCopied(paths.length),
        ),
        findsOneWidget,
      );
      expect(h.started, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${command.name} falls back to the focused file', (
      tester,
    ) async {
      await h.pump(tester, left: folder);
      final panel = left(tester);
      panel.moveCursorTo(
        panel.state.active!.rows.indexWhere(
          (row) => row.name == 'report draft.md',
        ),
      );
      await tester.pumpAndSettle();

      await dispatch(tester, command);

      expect(writes, [
        command == AppCommand.copyItemName
            ? 'report draft.md'
            : '$folder/report draft.md',
      ]);
      expect(panel.state.active!.selected, isEmpty);
      expect(h.started, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${command.name} on parent row preserves the clipboard', (
      tester,
    ) async {
      await h.pump(tester, left: folder);
      final panel = left(tester);
      panel.moveCursorTo(
        panel.state.active!.rows.indexWhere((row) => row.isParent),
      );
      await tester.pumpAndSettle();

      await dispatch(tester, command);

      expect(writes, isEmpty);
      expect(h.started, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final command in [AppCommand.copyItemName, AppCommand.copyItemPath]) {
    testWidgets('Vim ${command.name} copies the selected list', (tester) async {
      await tester.runAsync(
        () => h.preferences.update((prefs) => prefs.copyWith(vimMode: true)),
      );
      await h.pump(tester, left: folder);
      final panel = left(tester);
      markInReverseOrder(panel);
      final selected = panel.state.active!.selected;
      await tester.pumpAndSettle();

      await h.press(tester, LogicalKeyboardKey.keyY, character: 'y');
      await h.press(
        tester,
        command == AppCommand.copyItemName
            ? LogicalKeyboardKey.keyN
            : LogicalKeyboardKey.keyP,
        character: command == AppCommand.copyItemName ? 'n' : 'p',
      );

      expect(
        writes,
        [(command == AppCommand.copyItemName ? names : paths).join('\n')],
      );
      expect(panel.state.active!.selected, selected);
      expect(h.started, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in [const Locale('en'), const Locale('ru')]) {
    for (final command in [AppCommand.copyItemName, AppCommand.copyItemPath]) {
      testWidgets(
        '${locale.languageCode} row menu copies ${command.name} list',
        (
          tester,
        ) async {
          await h.pump(tester, left: folder, locale: locale);
          final panel = left(tester);
          markInReverseOrder(panel);
          final selected = panel.state.active!.selected;
          await tester.pumpAndSettle();
          final row = find.byWidgetPredicate(
            (widget) =>
                widget is AppMiddleEllipsis && widget.text == 'zeta.txt',
          );

          await tester.tapAt(tester.getCenter(row), buttons: kSecondaryButton);
          await tester.pumpAndSettle();
          final l10n = lookupFerryxLocalizations(locale);
          await tester.tap(
            find.descendant(
              of: find.byType(AppMenuList<AppCommand>),
              matching: find.text(
                command == AppCommand.copyItemName
                    ? l10n.menuCopyNames
                    : l10n.menuCopyPaths,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            writes,
            [(command == AppCommand.copyItemName ? names : paths).join('\n')],
          );
          expect(panel.state.active!.selected, selected);
          expect(h.started, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('copying with an empty root listing preserves the clipboard', (
    tester,
  ) async {
    h.folders['/'] = <FileEntry>[];
    await h.pump(tester, left: '/');
    expect(left(tester).state.active!.rows, isEmpty);

    await dispatch(tester, AppCommand.copyItemName);
    await dispatch(tester, AppCommand.copyItemPath);

    expect(writes, isEmpty);
    expect(h.started, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clipboard failure reports an error without a success notice', (
    tester,
  ) async {
    await h.pump(tester, left: folder);
    final panel = left(tester);
    markInReverseOrder(panel);
    final selected = panel.state.active!.selected;
    await tester.pumpAndSettle();
    failWrite = true;

    await dispatch(tester, AppCommand.copyItemName);

    final l10n = lookupFerryxLocalizations(const Locale('en'));
    expect(writes, isEmpty);
    expect(find.textContaining('Clipboard unavailable'), findsOneWidget);
    expect(find.text(l10n.noticeNamesCopied(names.length)), findsNothing);
    expect(panel.state.active!.selected, selected);
    expect(h.started, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
