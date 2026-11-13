import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/panel/panel_header.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);

  late WorkspaceHarness h;

  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
  });

  tearDown(() => h.tearDown());

  Rect panel(WidgetTester tester, int index) =>
      tester.getRect(find.byType(PanelView).at(index));

  bool stacked(WidgetTester tester) =>
      panel(tester, 0).bottom <= panel(tester, 1).top;

  PanelCubit cubit(WidgetTester tester, int index) =>
      tester.element(find.byType(PanelView).at(index)).read<PanelCubit>();

  AppSplitter splitter(WidgetTester tester) =>
      tester.widget<AppSplitter>(find.byType(AppSplitter));

  Future<void> turn(WidgetTester tester) =>
      h.press(tester, LogicalKeyboardKey.keyP, meta: true, alt: true);

  for (final vertical in [false, true]) {
    testWidgets(
      '${vertical ? 'stacked' : 'side-by-side'}: dragging shows both shares, reset restores equal sizes and persists it',
      (tester) async {
        final snapshots = <WorkspaceSnapshot>[];
        await h.pump(
          tester,
          size: vertical ? const Size(800, 1101) : const Size(1101, 800),
          onSnapshot: snapshots.add,
        );
        final en = lookupFerryxLocalizations(const Locale('en'));
        final before = cubit(tester, 0).state.active!.cursor;
        final edge = find.byType(AppSplitter);
        final gesture = await tester.startGesture(
          tester.getCenter(edge),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(
          vertical ? const Offset(0, 100) : const Offset(100, 0),
        );
        await tester.pump();
        final value = splitter(tester).value;
        final shares = RegExp(r'(\d+)%')
            .allMatches(value)
            .map((m) => int.parse(m[1]!))
            .toList();
        expect(shares, hasLength(2));
        expect(shares.first, greaterThan(50));
        expect(shares.first + shares.last, 100);
        expect(find.text(value), findsOneWidget);
        expect(splitter(tester).focusNode.hasFocus, isFalse);
        await gesture.up();
        await gesture.removePointer();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 450));
        expect(snapshots.last.splitFraction, greaterThan(0.5));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(edge));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        await mouse.moveTo(tester.getCenter(find.text(en.splitterReset)));
        await tester.pumpAndSettle();
        await tester.tap(find.text(en.splitterReset));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 450));
        expect(h.preferences.current.splitFraction, 0.5);
        expect(snapshots.last.splitFraction, 0.5);
        final difference = vertical
            ? panel(tester, 0).height - panel(tester, 1).height
            : panel(tester, 0).width - panel(tester, 1).width;
        expect(difference.abs(), lessThanOrEqualTo(1));
        expect(cubit(tester, 0).state.active!.cursor, before);
        await mouse.removePointer();
      },
    );
  }

  testWidgets(
    'the equal-panels command and keyboard zero reset the same split',
    (tester) async {
      await h.pump(tester);
      await h.press(
        tester,
        LogicalKeyboardKey.arrowRight,
        control: true,
        alt: true,
      );
      final target = tester.element(find.byType(PanelView).first);
      invokeCommand(target, AppCommand.equalizePanels);
      await tester.pumpAndSettle();
      expect(h.preferences.current.splitFraction, 0.5);
      await h.press(
        tester,
        LogicalKeyboardKey.arrowRight,
        control: true,
        alt: true,
      );
      await h.press(
        tester,
        LogicalKeyboardKey.backslash,
        meta: true,
        alt: true,
      );
      await h.press(tester, LogicalKeyboardKey.digit0);
      expect(splitter(tester).value, contains('50%'));
      await h.press(tester, LogicalKeyboardKey.enter);
      expect(splitter(tester).focusNode.hasFocus, isFalse);
    },
  );

  testWidgets('by the window\'s shape: one above the other in a window '
      'taller than wide, as on a monitor turned upright, side by side in a '
      'wide one', (tester) async {
    await h.pump(tester, size: const Size(900, 1500));
    expect(stacked(tester), isTrue);
    expect(panel(tester, 0).width, 900);
    expect(panel(tester, 1).width, 900);
    expect(
      panel(tester, 0).height + panel(tester, 1).height,
      closeTo(
        panel(tester, 1).bottom - panel(tester, 0).top - 1,
        0.5,
      ),
    );
    // The edge between them moves up and down.
    expect(splitter(tester).axis, Axis.vertical);

    tester.view.physicalSize = const Size(1500, 900);
    await tester.pumpAndSettle();
    expect(stacked(tester), isFalse);
    expect(panel(tester, 0).right, lessThanOrEqualTo(panel(tester, 1).left));
    expect(splitter(tester).axis, Axis.horizontal);
  });

  testWidgets('⌥⌘P turns them the other way and keeps it whatever the '
      'window\'s shape; the panels keep their cursor and the keys', (
    tester,
  ) async {
    await h.pump(tester);
    expect(stacked(tester), isFalse);
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    final cursor = cubit(tester, 0).state.active!.cursor;
    expect(cursor, 2);

    await turn(tester);
    expect(stacked(tester), isTrue);
    expect(h.preferences.current.panelArrangement, PanelArrangement.stacked);
    expect(cubit(tester, 0).state.active!.cursor, cursor);
    // The keys stayed in the panel: ↓ still moves its cursor.
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    expect(cubit(tester, 0).state.active!.cursor, cursor + 1);

    await turn(tester);
    expect(stacked(tester), isFalse);
    expect(
      h.preferences.current.panelArrangement,
      PanelArrangement.sideBySide,
    );
    // Chosen, it holds in a tall window too.
    tester.view.physicalSize = const Size(900, 1500);
    await h.settle(tester);
    expect(stacked(tester), isFalse);
  });

  testWidgets('one above the other, the upper bar keeps clear of the '
      'window\'s buttons at both ends, the lower bar of none', (tester) async {
    const decor = WindowDecor(leadingInset: 70, trailingInset: 40);
    await h.pump(tester, size: const Size(900, 1500), decor: decor);
    final upper = tester.widget<PanelHeader>(find.byType(PanelHeader).at(0));
    final lower = tester.widget<PanelHeader>(find.byType(PanelHeader).at(1));
    expect(upper.leftInset, 70 + AppSpacing.md);
    expect(upper.rightInset, 40 + AppSpacing.sm);
    expect(lower.leftInset, AppSpacing.md);
    expect(lower.rightInset, AppSpacing.sm);
    // Nor does the lower one move the window.
    expect(lower.decor.integrated, isFalse);

    tester.view.physicalSize = const Size(1500, 900);
    await tester.pumpAndSettle();
    final left = tester.widget<PanelHeader>(find.byType(PanelHeader).at(0));
    final right = tester.widget<PanelHeader>(find.byType(PanelHeader).at(1));
    expect(left.leftInset, 70 + AppSpacing.md);
    expect(left.rightInset, AppSpacing.sm);
    expect(right.leftInset, AppSpacing.md);
    expect(right.rightInset, 40 + AppSpacing.sm);
  });
}
