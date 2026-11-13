import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/operations/operations_cards.dart';
import 'package:panels_feature/src/operations/pending_deletion_card.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  final en = lookupFerryxLocalizations(const Locale('en'));
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp(vim: true);
    h.addFolder('/tmp', ['right.txt']);
  });
  tearDown(() => h.tearDown());

  Finder view(PanelSide side) => find.byKey(ValueKey(side));
  PanelCubit panel(WidgetTester tester, PanelSide side) =>
      tester.element(view(side)).read<PanelCubit>();
  void select(PanelCubit panel, Set<String> names) =>
      panel.selectWhere((row) => names.contains(row.name), select: true);

  // No settle: advancing an entire countdown here would hide timing bugs.
  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
    String? character,
  }) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key, character: character);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  Future<void> trash(WidgetTester tester) =>
      press(tester, LogicalKeyboardKey.keyD, shift: true, character: 'D');

  void expectInside(WidgetTester tester, Finder card, PanelSide side) {
    final bounds = tester.getRect(view(side));
    final rect = tester.getRect(card);
    expect(rect.left, greaterThanOrEqualTo(bounds.left));
    expect(rect.right, lessThanOrEqualTo(bounds.right));
    expect(rect.top, greaterThanOrEqualTo(bounds.top));
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
  }

  testWidgets('D keeps files and marks in place; Cancel prevents any request', (
    tester,
  ) async {
    await h.pump(tester);
    final left = panel(tester, PanelSide.left);
    select(left, {'a.txt', 'b.txt'});
    final rows = left.state.active!.rows;
    await trash(tester);
    expect(h.started, isEmpty);
    expect(left.state.active!.rows, same(rows));
    expect(left.state.active!.selected, {'a.txt', 'b.txt'});
    expectInside(tester, find.byType(PendingDeletionCard), PanelSide.left);
    await tester.pump(const Duration(seconds: 3));
    expect(h.started, isEmpty);
    await tester.tap(find.widgetWithText(OutlinedButton, en.actionCancel));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byType(PendingDeletionCard), findsNothing);
    expect(h.started, isEmpty);
    expect(left.state.active!.selected, {'a.txt', 'b.txt'});
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'left panel');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Tab keeps the card at its source and Esc cancels from the other panel',
    (
      tester,
    ) async {
      await h.pump(tester);
      select(panel(tester, PanelSide.left), {'a.txt'});
      await trash(tester);
      await press(tester, LogicalKeyboardKey.tab);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'right panel');
      expectInside(tester, find.byType(PendingDeletionCard), PanelSide.left);
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 6));
      expect(h.started, isEmpty);
      expect(find.byType(PendingDeletionCard), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'right panel');
    },
  );

  testWidgets(
    'deadline uses captured paths despite navigation and new selections',
    (
      tester,
    ) async {
      await h.pump(tester);
      final left = panel(tester, PanelSide.left);
      select(left, {'a.txt', 'b.txt'});
      await trash(tester);
      left.deselectAll();
      select(left, {'c.md'});
      await trash(tester); // Must not replace or extend the batch.
      await left.open(const Location.native('/home/projects/ferryx'));
      await press(tester, LogicalKeyboardKey.tab);
      final right = panel(tester, PanelSide.right);
      select(right, {'right.txt'});
      await tester.pump(const Duration(milliseconds: 4999));
      expect(h.started, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.started, hasLength(1));
      expect(h.started.single.kind, OpKind.trash);
      expect(h.started.single.sources, [
        '/home/docs/a.txt',
        '/home/docs/b.txt',
      ]);
      expect(right.state.active!.selected, {'right.txt'});
      await tester.pump(const Duration(seconds: 2));
      expect(h.started, hasLength(1));
    },
  );

  testWidgets(
    'started deletion progress and completion stay in the source panel',
    (
      tester,
    ) async {
      await h.pump(tester);
      select(panel(tester, PanelSide.left), {'a.txt'});
      await trash(tester);
      await tester.pump(const Duration(seconds: 5));
      final id = h.started.length;
      h.progress.add(
        OperationProgress(id: id, kind: OpKind.trash, state: OpState.running),
      );
      await tester.pump();
      await tester.pump(); // The service stream delivers between frames.
      Finder visibleCards() => find.byWidgetPredicate(
        (widget) => widget is OperationsCards && widget.operations.isNotEmpty,
      );
      expect(visibleCards(), findsOneWidget);
      expectInside(tester, visibleCards(), PanelSide.left);
      h.progress.add(
        OperationProgress(id: id, kind: OpKind.trash, state: OpState.done),
      );
      await tester.pump();
      await tester.pump();
      expectInside(tester, visibleCards(), PanelSide.left);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(visibleCards(), findsNothing);
    },
  );

  testWidgets(
    'pending Cancel stays visible when ordinary operation cards are hidden',
    (
      tester,
    ) async {
      unawaited(
        h.preferences.update((p) => p.copyWith(operationsVisible: false)),
      );
      await h.pump(tester);
      select(panel(tester, PanelSide.left), {'a.txt'});
      await trash(tester);
      expect(
        find.widgetWithText(OutlinedButton, en.actionCancel),
        findsOneWidget,
      );
      await press(tester, LogicalKeyboardKey.escape);
      expect(h.started, isEmpty);
    },
  );

  testWidgets('reduced motion keeps the full delay and an accurate countdown', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await h.pump(tester);
    select(panel(tester, PanelSide.left), {'a.txt'});
    await trash(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(h.started, isEmpty);
    expect(
      find.text(
        en.joinedDetails(
          en.pendingDeleteRemaining(4),
          en.pendingDeleteNotStarted,
        ),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 3999));
    expect(h.started, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(h.started, hasLength(1));
  });

  testWidgets('closing the window cancels waiting work', (tester) async {
    await h.pump(tester);
    select(panel(tester, PanelSide.left), {'a.txt'});
    await trash(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(h.started, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'each panel owns its own pending batch; Esc cancels only the active one',
    (
      tester,
    ) async {
      await h.pump(tester);
      select(panel(tester, PanelSide.left), {'a.txt'});
      await trash(tester);
      await press(tester, LogicalKeyboardKey.tab);
      select(panel(tester, PanelSide.right), {'right.txt'});
      await trash(tester);
      expect(find.byType(PendingDeletionCard), findsNWidgets(2));
      for (final side in PanelSide.values) {
        expectInside(
          tester,
          find.byWidgetPredicate(
            (widget) =>
                widget is PendingDeletionCard && widget.deletion.side == side,
          ),
          side,
        );
      }
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(AppMotion.quick);
      expect(find.byType(PendingDeletionCard), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(h.started.single.sources, ['/home/docs/a.txt']);
    },
  );

  testWidgets(
    'permanent deletion still requires confirmation before the grace period',
    (
      tester,
    ) async {
      await h.pump(tester);
      select(panel(tester, PanelSide.left), {'a.txt'});
      expect(
        invokeCommand(
          FocusManager.instance.primaryFocus!.context!,
          AppCommand.deletePermanently,
        ),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.byType(PendingDeletionCard), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      expect(h.started, isEmpty);
      await tester.tap(
        find.widgetWithText(OutlinedButton, en.deletePermanently),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PendingDeletionCard), findsOneWidget);
      expect(h.started, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      expect(h.started.single.kind, OpKind.delete);
      expect(h.started.single.sources, ['/home/docs/a.txt']);
    },
  );

  testWidgets(
    'the Trash confirmation preference is honored; cancelling it schedules nothing',
    (
      tester,
    ) async {
      unawaited(h.preferences.update((p) => p.copyWith(confirmTrash: true)));
      await h.pump(tester);
      select(panel(tester, PanelSide.left), {'a.txt'});
      await trash(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.byType(PendingDeletionCard), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, en.actionCancel));
      await tester.pump(const Duration(seconds: 6));
      expect(h.started, isEmpty);
      expect(find.byType(PendingDeletionCard), findsNothing);
    },
  );

  testWidgets(
    'an editing field keeps Esc; it does not cancel a pending deletion',
    (
      tester,
    ) async {
      await h.pump(tester);
      final left = panel(tester, PanelSide.left);
      select(left, {'a.txt'});
      await trash(tester);
      await press(
        tester,
        LogicalKeyboardKey.semicolon,
        shift: true,
        character: ':',
      );
      expect(find.byType(EditableText), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(PendingDeletionCard), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(AppMotion.quick);
      expect(find.byType(PendingDeletionCard), findsNothing);
      expect(h.started, isEmpty);
    },
  );

  testWidgets(
    'a failed start reports the normal error after the grace period',
    (
      tester,
    ) async {
      when(() => h.operations.start(any())).thenThrow(
        const FerryxException(
          FerryxErrorKind.permissionDenied,
          '/home/docs/a.txt',
        ),
      );
      await h.pump(tester);
      select(panel(tester, PanelSide.left), {'a.txt'});
      await trash(tester);
      verifyNever(() => h.operations.start(any()));
      await tester.pump(const Duration(seconds: 5));
      verify(() => h.operations.start(any())).called(1);
      await tester.pumpAndSettle();
      expect(find.byType(PendingDeletionCard), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final style in AppPlatformStyle.values) {
    for (final large in [false, true]) {
      testWidgets(
        '${style.name}: card fits ${large ? 'stacked Russian large text' : 'side-by-side English'}',
        (
          tester,
        ) async {
          await h.pump(
            tester,
            style: style,
            locale: Locale(large ? 'ru' : 'en'),
            textScale: large ? 1.75 : 1,
            brightness: large ? Brightness.dark : Brightness.light,
            size: large ? const Size(800, 900) : const Size(1000, 700),
          );
          select(panel(tester, PanelSide.left), {'a.txt', 'b.txt', 'c.md'});
          await trash(tester);
          await tester.pump(AppMotion.short);
          expectInside(
            tester,
            find.byType(PendingDeletionCard),
            PanelSide.left,
          );
          final label = lookupFerryxLocalizations(Locale(large ? 'ru' : 'en'))
              .actionCancel;
          await tester.tap(find.widgetWithText(OutlinedButton, label));
          await tester.pump(const Duration(seconds: 6));
          expect(h.started, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
