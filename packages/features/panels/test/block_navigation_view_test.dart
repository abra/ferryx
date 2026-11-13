import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/panel/panel_footer.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp(vim: true);
    h.folders['/home/docs'] = [
      for (var i = 1; i <= 300; i++)
        h.file('/home/docs', 'file-${i.toString().padLeft(3, '0')}.txt'),
    ];
  });
  tearDown(() => h.tearDown());

  Finder panel() => find.byType(PanelView).first;
  PanelCubit cubit(WidgetTester tester) =>
      tester.element(panel()).read<PanelCubit>();
  Future<void> brace(
    WidgetTester tester, {
    bool forward = true,
    bool glyph = false,
  }) async {
    final key = forward
        ? (glyph
              ? LogicalKeyboardKey.braceRight
              : LogicalKeyboardKey.bracketRight)
        : (glyph
              ? LogicalKeyboardKey.braceLeft
              : LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
    // macOS reports the typed brace; the simulator needs its physical bracket.
    await tester.sendKeyEvent(
      key,
      platform: 'macos',
      character: forward ? '}' : '{',
      physicalKey: forward
          ? PhysicalKeyboardKey.bracketRight
          : PhysicalKeyboardKey.bracketLeft,
    );
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
    await h.settle(tester);
  }

  for (final layout in [2, 0, PanelLayout.thumbnailIndex]) {
    for (final glyph in [false, true]) {
      testWidgets('layout=$layout, glyph=$glyph: braces use measured blocks, '
          'counts and Visual; position and hints stay visible', (tester) async {
        await h.pump(tester);
        final c = cubit(tester);
        c.setLayout(layout);
        await tester.pumpAndSettle();
        final size = c.geometry.rowsPerPage;
        expect(size, greaterThan(1));
        expect(size, lessThan(300));
        c.moveCursorTo(1 + math.min(5, size - 1));
        c.toggleSelection();
        await tester.pump();
        final marks = c.state.active!.selected;
        clearInteractions(h.files);
        await brace(tester, glyph: glyph);
        expect(c.state.active!.cursorPosition, size + 1);
        expect(c.state.active!.selected, same(marks));
        final footer = find.descendant(
          of: panel(),
          matching: find.byType(PanelFooter),
        );
        final l10n = tester.element(footer).l10n;
        expect(
          find.descendant(
            of: footer,
            matching: find.text(l10n.itemPosition(size + 1, 300)),
          ),
          findsOneWidget,
        );

        await h.press(tester, LogicalKeyboardKey.digit3, character: '3');
        await brace(tester, glyph: glyph);
        expect(c.state.active!.cursorPosition, math.min(4 * size + 1, 300));
        expect(find.text('3'), findsNothing, reason: 'the count was consumed');
        c.moveCursorTo(size + 1);
        await tester.pump();
        await brace(tester, forward: false, glyph: glyph);
        expect(c.state.active!.cursorPosition, 1);

        c.clearSelection();
        await h.press(tester, LogicalKeyboardKey.keyV, character: 'v');
        await brace(tester, glyph: glyph);
        expect(c.state.active!.selected.length, size + 1);
        expect(c.state.active!.selected, isNot(contains('..')));
        await h.press(tester, LogicalKeyboardKey.escape);
        c.clearSelection();
        expect(c.state.active!.selected, isEmpty);
        await h.settle(tester);
        for (final label in ['{', '}']) {
          expect(
            find.byWidgetPredicate(
              (widget) => widget is AppKeyCap && widget.label == label,
            ),
            findsOneWidget,
            reason:
                'visible keys: ${tester.widgetList<AppKeyCap>(find.byType(AppKeyCap)).map((cap) => cap.label).toList()}; hints: ${tester.widget<KeyHintStrip>(find.byType(KeyHintStrip)).hints.whereType<CommandHint>().map((hint) => hint.command).toList()}',
          );
        }
        final cursor = tester.widget<PanelView>(panel()).cursorRowKey!;
        final frame = find.descendant(
          of: panel(),
          matching: find.byWidgetPredicate(
            (widget) => widget is AppFocusFrame && widget.visible,
          ),
        );
        expect(
          tester
              .getRect(frame)
              .contains(tester.getRect(find.byKey(cursor)).center),
          isTrue,
        );
        verifyNever(() => h.files.openListing(any(), any(), any()));
        verifyNever(() => h.files.refreshListing(any()));
        expect(h.started, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('braces remain text in search, command and rename fields; '
      'ordinary mode does not jump', (tester) async {
    await h.pump(tester);
    final c = cubit(tester);
    c.moveCursorTo(7);
    await tester.pump();
    await h.press(tester, LogicalKeyboardKey.slash, character: '/');
    final beforeSearch = c.state.active!.cursor;
    await brace(tester, glyph: true);
    expect(c.state.active!.quickSearch, '}');
    expect(c.state.active!.cursor, beforeSearch);
    await h.press(tester, LogicalKeyboardKey.escape);
    await h.press(
      tester,
      LogicalKeyboardKey.semicolon,
      shift: true,
      character: ':',
    );
    final beforeCommand = c.state.active!.cursor;
    await brace(tester, glyph: true);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'vim command line');
    expect(c.state.active!.cursor, beforeCommand);
    await h.press(tester, LogicalKeyboardKey.escape);
    c.startRenaming();
    await tester.pumpAndSettle();
    await brace(tester, glyph: true);
    expect(c.state.active!.renaming, isNotNull);
    expect(c.state.active!.cursor, beforeCommand);
    await h.press(tester, LogicalKeyboardKey.escape);
    await tester.runAsync(
      () => h.preferences.update((p) => p.copyWith(vimMode: false)),
    );
    await tester.pumpAndSettle();
    final beforePlain = c.state.active!.cursor;
    await brace(tester, glyph: true);
    expect(c.state.active!.quickSearch, '}');
    expect(c.state.active!.cursor, beforePlain);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resizing updates block hints without moving the cursor or reading files',
    (tester) async {
      h.folders['/home/docs'] = h.folders['/home/docs']!.take(20).toList();
      await h.pump(tester);
      final c = cubit(tester);
      expect(c.geometry.rowsPerPage, greaterThanOrEqualTo(20));
      Finder hint() => find.byWidgetPredicate(
        (widget) => widget is AppKeyCap && widget.label == '}',
      );
      expect(hint(), findsNothing);
      final before = c.state;
      clearInteractions(h.files);
      tester.view.physicalSize = const Size(1200, 330);
      await h.settle(tester);
      expect(c.geometry.rowsPerPage, lessThan(20));
      expect(hint(), findsOneWidget);
      tester.view.physicalSize = const Size(1200, 800);
      await h.settle(tester);
      expect(hint(), findsNothing);
      expect(c.state, same(before));
      verifyNever(() => h.files.openListing(any(), any(), any()));
      verifyNever(() => h.files.refreshListing(any()));
      expect(tester.takeException(), isNull);
    },
  );
}
