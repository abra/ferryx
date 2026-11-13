import 'package:component_library/component_library.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('AppRowListController', () {
    test('moves, extends a run from the anchor, flips rows', () {
      final rows = AppRowListController(10);
      expect(rows.targets, isEmpty);
      // From no lead, the first move picks the first row.
      rows.moveBy(1);
      expect(rows.lead, 0);
      expect(rows.targets, [0]);
      rows.moveBy(3);
      expect(rows.targets, [3]);
      rows.moveBy(2, extend: true);
      expect(rows.targets, [3, 4, 5]);
      rows.moveBy(-4, extend: true);
      expect(rows.targets, [1, 2, 3]);
      rows.toggle(7);
      expect(rows.targets, [1, 2, 3, 7]);
      expect(rows.lead, 7);
      rows.toggle(7);
      expect(rows.targets, [1, 2, 3]);
      rows.moveTo(99);
      expect(rows.lead, 9);
      rows.selectAll();
      expect(rows.targets, hasLength(10));
      rows.clear();
      // Nothing selected: the lead is the target.
      expect(rows.targets, [9]);
    });

    test('fewer rows drop what is gone; reset starts over', () {
      final rows = AppRowListController(10)..moveTo(8);
      rows.count = 5;
      // The lead past the end comes back to the last row.
      expect(rows.lead, 4);
      expect(rows.targets, [4]);
      rows
        ..count = 10
        ..moveTo(8)
        ..toggle(2);
      rows.count = 5;
      // A flipped row leads; what is past the end leaves the selection.
      expect(rows.lead, 2);
      expect(rows.targets, [2]);
      rows.reset(3);
      expect(rows.lead, -1);
      expect(rows.targets, isEmpty);
    });
  });

  group('AppRowList', () {
    late AppRowListController rows;
    late List<String> events;

    setUp(() {
      rows = AppRowListController(100);
      events = [];
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: AppRowList(
                controller: rows,
                itemExtent: 24,
                autofocus: true,
                header: const Text('Header'),
                onActivate: (i) => events.add('open $i'),
                onMenu: (i, _) => events.add('menu $i'),
                onKey: (event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.space) {
                    events.add('space ${rows.targets}');
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                itemBuilder: (context, index, look) => Text(
                  'row $index${look.selected ? ' *' : ''}',
                  style: TextStyle(color: look.ink(context)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the keys walk and select; the lead stays in view', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Header'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(rows.lead, 1);
      expect(find.text('row 1 *'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(rows.targets, [1, 2]);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(events, ['space [1, 2]']);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(rows.lead, 99);
      expect(find.text('row 99 *'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(rows.lead, lessThan(99));
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(find.text('row 0 *'), findsOneWidget);
    });

    testWidgets('clicks select, ⌘ flips, ⇧ extends; a double click opens', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('row 3'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(rows.targets, [3]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.tap(find.text('row 5'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump(const Duration(milliseconds: 500));
      expect(rows.targets, [3, 5]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('row 7'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(milliseconds: 500));
      expect(rows.targets, [5, 6, 7]);
      await tester.tap(find.text('row 2'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('row 2 *'));
      await tester.pump();
      expect(events, ['open 2']);
      await tester.tap(find.text('row 4'), buttons: kSecondaryButton);
      await tester.pump();
      expect(events.last, 'menu 4');
      expect(rows.targets, [4]);
    });

    testWidgets('an empty list shows its placeholder', (tester) async {
      rows = AppRowListController();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppPlatformStyle.gnome),
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: AppRowList(
                controller: rows,
                itemExtent: 24,
                empty: const Text('Nothing'),
                itemBuilder: (context, index, look) => const SizedBox(),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Nothing'), findsOneWidget);
    });
  });
}
