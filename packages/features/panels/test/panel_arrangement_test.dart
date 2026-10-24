import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/panel/panel_header.dart';

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
