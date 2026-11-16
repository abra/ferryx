import 'dart:io';
import 'dart:ui' as ui;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support/workspace_harness.dart';

enum _Selection {
  ordinaryKeys,
  mouse,
  vimNormal,
  vimVisual,
  quickSearch,
  vimSearch,
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    WorkspaceHarness.registerFallbacks();
    for (final (family, asset) in [
      ('Inter', 'packages/component_library/fonts/Inter-Variable.ttf'),
      ('Geist Mono', 'packages/component_library/fonts/GeistMono-Variable.ttf'),
      (
        '.AppleSystemUIFont',
        'packages/component_library/fonts/Inter-Variable.ttf',
      ),
      (
        '.AppleSystemUIFontMonospaced',
        'packages/component_library/fonts/GeistMono-Variable.ttf',
      ),
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });
  late WorkspaceHarness h;
  late List<String> clipboard;
  setUp(() async {
    clipboard = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    h = WorkspaceHarness();
    await h.setUp();
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    await h.tearDown();
  });

  PanelCubit panel(WidgetTester tester) =>
      tester.element(find.byType(PanelView).first).read<PanelCubit>();

  Future<void> select(WidgetTester tester, _Selection mode) async {
    final left = panel(tester);
    left.moveCursorTo(left.state.active!.firstItemIndex);
    await h.settle(tester);
    if (mode == _Selection.mouse) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      for (final name in ['a.txt', 'b.txt']) {
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is AppMiddleEllipsis && widget.text == name,
          ),
        );
        await h.settle(tester);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await h.settle(tester);
    } else if (mode == _Selection.vimVisual) {
      await h.type(tester, 'vj');
    } else {
      for (var i = 0; i < 2; i++) {
        await h.press(
          tester,
          LogicalKeyboardKey.space,
          alt: mode != _Selection.vimNormal && mode != _Selection.vimSearch,
          character: ' ',
        );
      }
      if (mode == _Selection.quickSearch) await h.type(tester, 'c');
      if (mode == _Selection.vimSearch) {
        await h.press(tester, LogicalKeyboardKey.slash, character: '/');
        await h.type(tester, 'c');
        expect(left.state.active!.searching, isTrue);
        expect(left.state.active!.quickSearch, 'c');
      }
    }
    expect(left.state.active!.selected, {'a.txt', 'b.txt'});
  }

  Future<void> openActions(
    WidgetTester tester,
    FerryxLocalizations l10n,
  ) async {
    final label = find.descendant(
      of: find.byType(KeyHintStrip),
      matching: find.text(l10n.contextActions),
    );
    expect(label.hitTestable(), findsOneWidget);
    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(find.byType(AppQuickPicker<AppCommand>), findsOneWidget);
  }

  List<AppQuickPickerItem<AppCommand>> actions(WidgetTester tester) => tester
      .widget<AppQuickPicker<AppCommand>>(
        find.byType(AppQuickPicker<AppCommand>),
      )
      .entries
      .whereType<AppQuickPickerItem<AppCommand>>()
      .toList();

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(AppQuickPicker<AppCommand>),
        matching: find.byType(AppTextField),
      ),
      text,
    );
    await tester.pumpAndSettle();
  }

  Finder actionLabel(String label) => find.descendant(
    of: find.byType(AppQuickPicker<AppCommand>),
    matching: find.byWidgetPredicate(
      (widget) => widget is AppMiddleEllipsis && widget.text == label,
    ),
  );

  for (final mode in _Selection.values) {
    testWidgets('${mode.name} selection discovers the full action inventory', (
      tester,
    ) async {
      final vim = {
        _Selection.vimNormal,
        _Selection.vimVisual,
        _Selection.vimSearch,
      }.contains(mode);
      final language = mode == _Selection.mouse || mode == _Selection.vimVisual
          ? 'ru'
          : 'en';
      await tester.runAsync(
        () => h.preferences.update((prefs) => prefs.copyWith(vimMode: vim)),
      );
      final l10n = lookupFerryxLocalizations(Locale(language));
      await h.pump(
        tester,
        size: const Size(900, 650),
        locale: Locale(language),
        brightness: language == 'ru' ? Brightness.dark : Brightness.light,
        textScale: language == 'ru' ? 1.2 : 1,
      );
      await select(tester, mode);
      final before = panel(tester).state.active!;
      await _capture(tester, h, '${mode.name}-selected');
      await openActions(tester, l10n);

      // Independent representative capabilities, not a copy of the model's
      // complete list or of the short hints that happen to fit in the footer.
      expect(
        actions(tester).map((item) => item.value),
        containsAll([
          AppCommand.copyItemName,
          AppCommand.copyItemPath,
          AppCommand.addToShelf,
          AppCommand.copyTo,
          AppCommand.moveTo,
          AppCommand.batchRename,
          AppCommand.renameInEditor,
          AppCommand.compress,
          AppCommand.fileAttributes,
          AppCommand.checksums,
          AppCommand.duplicate,
          AppCommand.newFolderWithSelection,
          AppCommand.moveToTrash,
          AppCommand.deletePermanently,
        ]),
      );
      String? groupOf(AppCommand command) {
        String? group;
        final entries = tester
            .widget<AppQuickPicker<AppCommand>>(
              find.byType(AppQuickPicker<AppCommand>),
            )
            .entries;
        for (final entry in entries) {
          if (entry is AppQuickPickerHeader<AppCommand>) group = entry.title;
          if (entry is AppQuickPickerItem<AppCommand> &&
              entry.value == command) {
            return group;
          }
        }
        return null;
      }

      expect(
        groupOf(AppCommand.batchRename),
        l10n.contextActionsSelection(2),
      );
      expect(
        groupOf(AppCommand.renameInPlace),
        l10n.contextActionsFocused(before.focused!.name),
      );
      await _capture(tester, h, '${mode.name}-actions');
      if (mode == _Selection.ordinaryKeys) {
        final last = actions(tester).last;
        await h.press(tester, LogicalKeyboardKey.end);
        expect(actionLabel(last.label).hitTestable(), findsOneWidget);
        await h.press(tester, LogicalKeyboardKey.home);
        final folderGroup = find.descendant(
          of: find.byType(AppQuickPicker<AppCommand>),
          matching: find.text(l10n.contextActionsFolder),
        );
        await tester.scrollUntilVisible(
          folderGroup,
          240,
          scrollable: find
              .descendant(
                of: find.byType(AppQuickPicker<AppCommand>),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(folderGroup.hitTestable(), findsOneWidget);
        await _capture(tester, h, '${mode.name}-folder-actions');
      }
      for (final command in [
        AppCommand.batchRename,
        AppCommand.compress,
        AppCommand.fileAttributes,
        AppCommand.deletePermanently,
      ]) {
        final label = actions(tester)
            .firstWhere((item) => item.value == command)
            .label;
        await search(tester, label);
        expect(actionLabel(label).hitTestable(), findsOneWidget);
        expect(actions(tester).map((item) => item.value), contains(command));
        if (command == AppCommand.batchRename) {
          await _capture(tester, h, '${mode.name}-filtered');
        }
        await search(tester, '');
      }

      await h.press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(AppQuickPicker<AppCommand>), findsNothing);
      final after = panel(tester).state.active!;
      expect(after.selected, before.selected);
      expect(after.cursor, before.cursor);
      expect(after.visual, before.visual);
      expect(after.quickSearch, before.quickSearch);
      expect(after.searching, before.searching);
      expect(
        tester
            .widget<PanelView>(find.byType(PanelView).first)
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(clipboard, isEmpty);
      expect(h.started, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final command in [AppCommand.copyItemName, AppCommand.copyItemPath]) {
    testWidgets('unbound ${command.name} runs on marks through Actions', (
      tester,
    ) async {
      await tester.runAsync(
        () => h.preferences.update(
          (prefs) => prefs.copyWith(shortcutOverrides: {command.name: []}),
        ),
      );
      final l10n = lookupFerryxLocalizations(const Locale('en'));
      await h.pump(tester, size: const Size(900, 600));
      await select(tester, _Selection.ordinaryKeys);
      final before = panel(tester).state.active!;
      expect(before.focused!.name, 'c.md');
      await openActions(tester, l10n);
      final item = actions(tester).firstWhere((item) => item.value == command);
      expect(item.keys, isEmpty);
      await search(tester, item.label);
      if (command == AppCommand.copyItemName) {
        await tester.tap(actionLabel(item.label));
        await tester.pumpAndSettle();
      } else {
        await h.press(tester, LogicalKeyboardKey.enter);
      }
      expect(find.byType(AppQuickPicker<AppCommand>), findsNothing);
      expect(clipboard, [
        command == AppCommand.copyItemName
            ? 'a.txt\nb.txt'
            : '/home/docs/a.txt\n/home/docs/b.txt',
      ]);
      expect(panel(tester).state.active!.selected, before.selected);
      expect(panel(tester).state.active!.cursor, before.cursor);
      expect(
        tester
            .widget<PanelView>(find.byType(PanelView).first)
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(h.started, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final command in [AppCommand.vimYank, AppCommand.vimCut]) {
    testWidgets('${command.name} from Actions replaces shelf and ends Visual', (
      tester,
    ) async {
      await tester.runAsync(
        () => h.preferences.update((prefs) => prefs.copyWith(vimMode: true)),
      );
      final l10n = lookupFerryxLocalizations(const Locale('en'));
      await h.pump(tester, size: const Size(900, 650));
      final left = panel(tester);
      left.moveCursorTo(left.state.active!.rows.length - 1);
      await h.settle(tester);
      await h.type(tester, 'ys');
      final workspace = tester
          .element(find.byType(KeyHintStrip))
          .read<WorkspaceCubit>();
      expect(workspace.state.shelf.items.map((item) => item.name), ['c.md']);
      await select(tester, _Selection.vimVisual);
      expect(left.state.active!.visual, isTrue);
      await openActions(tester, l10n);
      final item = actions(tester).firstWhere((item) => item.value == command);
      expect(item.keys, isNotEmpty);
      await search(tester, item.label);
      await h.press(tester, LogicalKeyboardKey.enter);

      expect(find.byType(AppQuickPicker<AppCommand>), findsNothing);
      expect(workspace.state.shelf.items.map((item) => item.name), [
        'a.txt',
        'b.txt',
      ]);
      final cut = command == AppCommand.vimCut;
      expect(
        workspace.state.shelf.items.every((item) => item.cut == cut),
        isTrue,
      );
      expect(left.state.active!.visual, isFalse);
      expect(h.started, isEmpty);
      expect(
        tester
            .widget<PanelView>(find.byType(PanelView).first)
            .focusNode
            .hasFocus,
        isTrue,
      );

      // The picker dispatches Paste through the same register-aware handler;
      // its copy/move behavior differs from the ordinary clipboard paste.
      await h.press(tester, LogicalKeyboardKey.tab);
      await openActions(tester, l10n);
      final paste = actions(tester)
          .firstWhere((item) => item.value == AppCommand.vimPaste);
      await search(tester, paste.label);
      await h.press(tester, LogicalKeyboardKey.enter);
      expect(h.started.single.kind, cut ? OpKind.move : OpKind.copy);
      expect(h.started.single.sources, [
        '/home/docs/a.txt',
        '/home/docs/b.txt',
      ]);
      expect(h.started.single.destination, '/tmp');
      expect(workspace.state.shelf.isEmpty, cut);
      expect(clipboard, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an open action list never retargets a changed selection', (
    tester,
  ) async {
    final l10n = lookupFerryxLocalizations(const Locale('en'));
    await h.pump(tester);
    await select(tester, _Selection.ordinaryKeys);
    await openActions(tester, l10n);
    final label = actions(tester)
        .firstWhere((item) => item.value == AppCommand.copyItemName)
        .label;
    await search(tester, label);
    final left = panel(tester);
    left.toggleSelectionAt(left.state.active!.firstItemIndex);
    await tester.pump();
    await tester.tap(actionLabel(label));
    await tester.pumpAndSettle();

    expect(clipboard, isEmpty);
    expect(left.state.active!.selected, {'b.txt'});
    expect(find.text(l10n.contextActionsChanged), findsOneWidget);
    expect(h.started, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _capture(
  WidgetTester tester,
  WorkspaceHarness harness,
  String name,
) async {
  final directory = Platform.environment['FERRYX_GUIDANCE_SHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        harness.shotKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
