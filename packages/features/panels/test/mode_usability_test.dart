import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/operations/pending_deletion_card.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
    h.addFolder('/home/audit', [
      'alpha.txt',
      'beta.txt',
      'gamma.txt',
      'notes.md',
      'other.txt',
      'zeta.txt',
    ]);
    await h.preferences.update((p) => p.copyWith(vimMode: true));
  });
  tearDown(() {
    CommandDispatcherAction.debugReached = null;
    return h.tearDown();
  });
  PanelCubit left(WidgetTester t) =>
      t.element(find.byType(PanelView).first).read<PanelCubit>();
  Future<void> key(
    WidgetTester t,
    LogicalKeyboardKey key, [
    String? character,
  ]) async {
    await t.sendKeyEvent(key, platform: 'macos', character: character);
    await t.pump();
  }

  testWidgets('Vim search leaves modified shortcuts to the workspace', (
    tester,
  ) async {
    await h.pump(tester, left: '/home/audit');
    await key(tester, LogicalKeyboardKey.slash, '/');
    await key(tester, LogicalKeyboardKey.keyA, 'a');
    final reached = <AppCommand>[];
    CommandDispatcherAction.debugReached = (command) {
      reached.add(command);
      return true;
    };
    await h.press(tester, LogicalKeyboardKey.keyA, meta: true, character: 'a');
    expect(left(tester).state.active!.quickSearch, 'a');
    expect(reached, contains(AppCommand.selectAll));
  });
  testWidgets('a pending find never consumes Tab or arrows', (tester) async {
    await h.pump(tester, left: '/home/audit');
    final panel = left(tester);
    await key(tester, LogicalKeyboardKey.keyF, 'f');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(panel.state.active!.cursor, 1);
    await key(tester, LogicalKeyboardKey.keyF, 'f');
    await key(tester, LogicalKeyboardKey.tab);
    expect(
      tester.widget<PanelView>(find.byType(PanelView).last).focusNode.hasFocus,
      isTrue,
    );
  });
  testWidgets(
    'pending counts and prefixes end when another panel takes focus',
    (tester) async {
      await h.pump(tester, left: '/home/audit');
      final panel = left(tester);
      await key(tester, LogicalKeyboardKey.digit3, '3');
      await key(tester, LogicalKeyboardKey.keyD, 'd');
      tester
          .widget<PanelView>(find.byType(PanelView).last)
          .focusNode
          .requestFocus();
      await tester.pump();
      expect(KeySequenceState.pending, isNull);
      tester
          .widget<PanelView>(find.byType(PanelView).first)
          .focusNode
          .requestFocus();
      await tester.pump();
      await key(tester, LogicalKeyboardKey.keyJ, 'j');
      expect(panel.state.active!.cursor, 1);
    },
  );
  testWidgets('a count is spent by a command that does not accept it', (
    tester,
  ) async {
    await h.pump(tester, left: '/home/audit');
    final panel = left(tester);
    panel.moveCursorTo(1);
    await tester.pump();
    await key(tester, LogicalKeyboardKey.digit3, '3');
    await key(tester, LogicalKeyboardKey.keyX, 'x');
    await key(tester, LogicalKeyboardKey.keyJ, 'j');
    expect(panel.state.active!.cursor, 2);
  });
  testWidgets('clicking a different tab retires an unfinished Vim find', (
    tester,
  ) async {
    await h.pump(tester, left: '/home/audit');
    final panel = left(tester);
    await panel.newTab();
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.keyF, 'f');
    panel.previousTab();
    await tester.pump();
    await key(tester, LogicalKeyboardKey.keyJ, 'j');
    expect(panel.state.active!.cursor, 1);
  });
  testWidgets(
    'leaving a command field does not pull focus back from the other panel',
    (tester) async {
      await h.pump(tester, left: '/home/audit');
      await h.press(
        tester,
        LogicalKeyboardKey.semicolon,
        shift: true,
        character: ':',
      );
      expect(find.byType(AppTextField), findsOneWidget);
      final right = tester
          .widget<PanelView>(find.byType(PanelView).last)
          .focusNode;
      right.requestFocus();
      await tester.pumpAndSettle();
      expect(right.hasFocus, isTrue);
      expect(find.byType(AppTextField), findsNothing);
    },
  );
  testWidgets('a window command spends a count before the next motion', (
    tester,
  ) async {
    await h.pump(tester, left: '/home/audit');
    await key(tester, LogicalKeyboardKey.digit3, '3');
    await h.press(
      tester,
      LogicalKeyboardKey.slash,
      shift: true,
      character: '?',
    );
    await key(tester, LogicalKeyboardKey.keyJ, 'j');
    expect(left(tester).state.active!.cursor, 1);
  });

  for (final vim in [false, true]) {
    testWidgets(
      'Vim=$vim: a slow rename never steals focus after leaving the field',
      (tester) async {
        await tester.runAsync(
          () => h.preferences.update((p) => p.copyWith(vimMode: vim)),
        );
        final done = Completer<String>();
        when(() => h.files.rename(any(), any())).thenAnswer((_) => done.future);
        await h.pump(tester, left: '/home/audit');
        final panel = left(tester);
        panel.moveCursorTo(1);
        panel.startRenaming();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(AppTextField), 'renamed.txt');
        final right = tester
            .widget<PanelView>(find.byType(PanelView).last)
            .focusNode;
        right.requestFocus();
        await tester.pump();
        expect(right.hasFocus, isTrue);
        h.folders['/home/audit']!.removeWhere((e) => e.name == 'alpha.txt');
        h.folders['/home/audit']!.add(h.file('/home/audit', 'renamed.txt'));
        done.complete('/home/audit/renamed.txt');
        await tester.pumpAndSettle();
        expect(right.hasFocus, isTrue);
        expect(panel.state.active!.renaming, isNull);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'Vim=$vim: deletion countdown can be cancelled without filesystem changes',
      (tester) async {
        await tester.runAsync(
          () => h.preferences.update((p) => p.copyWith(vimMode: vim)),
        );
        await h.pump(tester, left: '/home/audit');
        final panel = left(tester);
        panel.selectWhere((row) => row.name == 'alpha.txt', select: true);
        await tester.pump();
        if (vim) {
          await h.press(
            tester,
            LogicalKeyboardKey.keyD,
            shift: true,
            character: 'D',
          );
        } else {
          await h.press(tester, LogicalKeyboardKey.backspace, meta: true);
        }
        expect(find.byType(PendingDeletionCard), findsOneWidget);
        expect(h.started, isEmpty);
        await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(find.byType(PendingDeletionCard), findsNothing);
        expect(h.started, isEmpty);
        expect(panel.state.active!.selected, {'alpha.txt'});
        expect(tester.takeException(), isNull);
      },
    );
    for (final layout in [0, 2, PanelLayout.thumbnailIndex]) {
      testWidgets(
        'Vim=$vim, layout=$layout: browse, mark, search, Escape and tabs',
        (tester) async {
          await tester.runAsync(
            () => h.preferences.update((p) => p.copyWith(vimMode: vim)),
          );
          await h.pump(tester, left: '/home/audit');
          final panel = left(tester);
          panel.setLayout(layout);
          await tester.pumpAndSettle();
          panel.moveCursorTo(1);
          await tester.pump();
          await key(tester, LogicalKeyboardKey.arrowDown);
          expect(panel.state.active!.cursor, 1 + panel.geometry.columnsPerRow);
          if (vim) {
            await key(tester, LogicalKeyboardKey.space, ' ');
          } else {
            await h.press(
              tester,
              LogicalKeyboardKey.space,
              alt: true,
              character: ' ',
            );
          }
          expect(panel.state.active!.selected, hasLength(1));
          if (vim) await key(tester, LogicalKeyboardKey.slash, '/');
          await key(tester, LogicalKeyboardKey.keyA, 'a');
          expect(panel.state.active!.quickSearch, 'a');
          await key(tester, LogicalKeyboardKey.escape);
          expect(panel.state.active!.quickSearch, isEmpty);
          expect(panel.state.active!.selected, hasLength(1));
          await key(tester, LogicalKeyboardKey.escape);
          expect(panel.state.active!.selected, isEmpty);
          await h.press(tester, LogicalKeyboardKey.keyT, meta: true);
          expect(panel.state.tabs, hasLength(2));
          await h.press(tester, LogicalKeyboardKey.keyW, meta: true);
          expect(panel.state.tabs, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('an unrelated window command retires a pending find', (
    tester,
  ) async {
    await h.pump(tester, left: '/home/audit');
    await key(tester, LogicalKeyboardKey.keyF, 'f');
    await h.press(tester, LogicalKeyboardKey.keyR, meta: true, character: 'r');
    await key(tester, LogicalKeyboardKey.keyJ, 'j');
    expect(left(tester).state.active!.cursor, 1);
  });

  testWidgets(
    'changing modes clears a prefix without disturbing either panel',
    (
      tester,
    ) async {
      await h.pump(tester, left: '/home/audit');
      await key(tester, LogicalKeyboardKey.keyG, 'g');
      expect(KeySequenceState.pending, LogicalKeyboardKey.keyG);
      await tester.runAsync(
        () => h.preferences.update((p) => p.copyWith(vimMode: false)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(KeySequenceState.pending, isNull);
      await key(tester, LogicalKeyboardKey.keyJ, 'j');
      expect(left(tester).state.active!.quickSearch, 'j');
      await tester.runAsync(
        () => h.preferences.update((p) => p.copyWith(vimMode: true)),
      );
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      await key(tester, LogicalKeyboardKey.keyJ, 'j');
      expect(left(tester).state.active!.quickSearch, isEmpty);
      expect(left(tester).state.active!.cursor, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
