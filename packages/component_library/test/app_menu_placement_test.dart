import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Where [showAppMenu] puts its panel: at a pointer's point, or by a box
/// (a button, the row the menu key opened it for) and never over it.
void main() {
  const window = Size(480, 320);
  const rowHeight = 28.0;
  final row = GlobalKey();

  /// A window with one row at [rowTop] and [rowLeft].
  Future<void> pump(
    WidgetTester tester, {
    required double rowTop,
    double rowLeft = 40,
    double rowWidth = 200,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(AppPlatformStyle.macos, Brightness.light),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: rowTop,
                left: rowLeft,
                width: rowWidth,
                height: rowHeight,
                child: SizedBox(key: row),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> open(
    WidgetTester tester, {
    required Rect anchor,
    int items = 4,
  }) async {
    unawaited(
      showAppMenu<int>(
        context: row.currentContext!,
        anchor: anchor,
        entries: [
          for (var i = 0; i < items; i++)
            AppMenuAction(value: i, label: 'Item $i'),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect panel(WidgetTester tester) => tester.getRect(find.byType(AppMenuPanel));
  Rect rowRect(WidgetTester tester) => tester.getRect(find.byKey(row));

  testWidgets('the menu key opens it under the row, a little in from its '
      'start', (tester) async {
    await pump(tester, rowTop: 40);
    final anchor = keyboardMenuAnchor(row.currentContext!);
    expect(anchor.top, rowRect(tester).top);
    expect(anchor.bottom, rowRect(tester).bottom);
    expect(anchor.left, rowRect(tester).left + AppSpacing.lg);
    await open(tester, anchor: anchor);
    expect(panel(tester).top, rowRect(tester).bottom + AppSpacing.xs);
    expect(panel(tester).left, anchor.left);
  });

  testWidgets('by the bottom edge it opens above the row, never over it', (
    tester,
  ) async {
    await pump(tester, rowTop: window.height - rowHeight - 20);
    await open(tester, anchor: keyboardMenuAnchor(row.currentContext!));
    expect(panel(tester).bottom, rowRect(tester).top - AppSpacing.xs);
    expect(panel(tester).overlaps(rowRect(tester)), isFalse);
  });

  testWidgets('a menu taller than either side takes the larger one and '
      'scrolls; the row stays in sight and End still reaches the last item', (
    tester,
  ) async {
    await pump(tester, rowTop: 130);
    await open(
      tester,
      anchor: keyboardMenuAnchor(row.currentContext!),
      items: 30,
    );
    final menu = panel(tester);
    expect(menu.overlaps(rowRect(tester)), isFalse);
    // 130 above the row, 162 below it: the menu goes under.
    expect(menu.top, rowRect(tester).bottom + AppSpacing.xs);
    expect(menu.bottom, lessThanOrEqualTo(window.height - AppSpacing.sm));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    final last = tester.getRect(find.widgetWithText(AppMenuItem, 'Item 29'));
    expect(last.bottom, lessThanOrEqualTo(menu.bottom));
  });

  testWidgets('by the right edge it ends at the row\'s end', (tester) async {
    // A narrow row by the edge: the menu would not fit from its start.
    await pump(tester, rowTop: 40, rowLeft: 300, rowWidth: 150);
    await open(tester, anchor: keyboardMenuAnchor(row.currentContext!));
    expect(panel(tester).right, moreOrLessEquals(rowRect(tester).right));
  });

  testWidgets('a right click opens it at the point, flipped up by the '
      'bottom edge and left by the right edge', (tester) async {
    await pump(tester, rowTop: 40);
    const point = Offset(60, 60);
    await open(tester, anchor: point & Size.zero);
    expect(panel(tester).topLeft, point);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final corner = Offset(window.width - 20, window.height - 20);
    await open(tester, anchor: corner & Size.zero);
    expect(panel(tester).bottomRight, corner);
  });

  testWidgets('a check mark on one item keeps every label in one column, '
      'as a native menu does', (tester) async {
    await pump(tester, rowTop: 40);
    unawaited(
      showAppMenu<int>(
        context: row.currentContext!,
        anchor: const Rect.fromLTWH(40, 40, 200, rowHeight),
        entries: const [
          AppMenuAction(value: 0, label: 'Plain'),
          AppMenuAction(value: 1, label: 'Switch', checked: false),
          AppMenuAction(value: 2, label: 'On', checked: true),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final lefts = {
      for (final label in ['Plain', 'Switch', 'On'])
        tester.getTopLeft(find.text(label)).dx,
    };
    expect(lefts, hasLength(1), reason: 'the labels line up');
  });
}
