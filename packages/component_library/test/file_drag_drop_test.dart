import 'package:component_library/component_library.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('FileDragSource', () {
    late List<Offset> started;
    late int taps;

    setUp(() {
      started = [];
      taps = 0;
    });

    Future<void> pump(
      WidgetTester tester, {
      AppPlatformStyle style = AppPlatformStyle.macos,
      bool enabled = true,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(style, Brightness.light),
        home: Center(
          child: FileDragSource(
            enabled: enabled,
            onDragStart: started.add,
            child: GestureDetector(
              onTap: () => taps++,
              child: const ColoredBox(
                color: Colors.white,
                child: SizedBox(width: 200, height: 40),
              ),
            ),
          ),
        ),
      ),
    );

    Future<TestGesture> press(
      WidgetTester tester, {
      int buttons = kPrimaryButton,
    }) => tester.startGesture(
      tester.getCenter(find.byType(FileDragSource)),
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );

    testWidgets('starts once past the threshold, where the pointer is', (
      tester,
    ) async {
      await pump(tester);
      final gesture = await press(tester);
      await gesture.moveBy(const Offset(3, 2));
      expect(started, isEmpty);
      await gesture.moveBy(const Offset(2, 0));
      expect(started, hasLength(1));
      expect(
        started.single,
        tester.getCenter(find.byType(FileDragSource)) + const Offset(5, 2),
      );
      await gesture.moveBy(const Offset(30, 0));
      expect(started, hasLength(1), reason: 'one drag per press');
      await gesture.up();
      // A new press may drag again.
      final again = await press(tester);
      await again.moveBy(const Offset(0, 10));
      await again.up();
      expect(started, hasLength(2));
    });

    testWidgets('GNOME waits longer (gtk-dnd-drag-threshold)', (tester) async {
      await pump(tester, style: AppPlatformStyle.gnome);
      final gesture = await press(tester);
      await gesture.moveBy(const Offset(7, 0));
      expect(started, isEmpty);
      await gesture.moveBy(const Offset(2, 0));
      expect(started, hasLength(1));
      await gesture.up();
    });

    testWidgets('a click that wobbles stays a click', (tester) async {
      await pump(tester);
      final gesture = await press(tester);
      await gesture.moveBy(const Offset(2, -2));
      await gesture.up();
      await tester.pump();
      expect(started, isEmpty);
      expect(taps, 1);
    });

    testWidgets('the secondary button and a disabled source never drag', (
      tester,
    ) async {
      await pump(tester);
      final secondary = await press(tester, buttons: kSecondaryButton);
      await secondary.moveBy(const Offset(40, 0));
      await secondary.up();
      await pump(tester, enabled: false);
      final primary = await press(tester);
      await primary.moveBy(const Offset(40, 0));
      await primary.up();
      expect(started, isEmpty);
    });
  });

  group('FileDropTarget', () {
    FileDropTarget target(String id, List<String> log) => FileDropTarget(
      id: id,
      onOver: (drag) {
        log.add('over $id');
        return FileDropOperation.copy;
      },
      onLeave: () => log.add('leave $id'),
      onDrop: (drag, operation) => log.add('drop $id'),
      child: const SizedBox.expand(),
    );

    testWidgets('the innermost target under the point wins', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FileDropTarget(
            id: 'panel',
            onOver: (_) => FileDropOperation.move,
            onLeave: () {},
            onDrop: (_, _) {},
            child: Stack(
              children: [
                const SizedBox.expand(),
                Positioned(
                  left: 0,
                  top: 0,
                  width: 100,
                  height: 20,
                  child: target('row', log),
                ),
              ],
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(Stack));
      final row = FileDropTarget.at(context, const Offset(10, 10))!;
      expect(row.id, 'row');
      row.onOver(const FileDragInfo(allowed: {}));
      expect(log, ['over row']);
      expect(FileDropTarget.at(context, const Offset(300, 300))?.id, 'panel');
    });

    testWidgets('outside every target there is none', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(),
        ),
      );
      expect(
        FileDropTarget.at(
          tester.element(find.byType(SizedBox)),
          const Offset(5, 5),
        ),
        isNull,
      );
    });

    test('FileDragInfo knows a drag of this window by its local data', () {
      expect(const FileDragInfo(allowed: {}).isLocal, isFalse);
      expect(const FileDragInfo(allowed: {}, local: {'a': 1}).isLocal, isTrue);
    });
  });

  group('AppDropOutline', () {
    CustomPaint paintOf(WidgetTester tester) => tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(AppDropOutline),
        matching: find.byType(CustomPaint),
      ),
    );

    testWidgets('rings its child only while active, without a new child', (
      tester,
    ) async {
      Future<void> pump(bool active) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.of(AppPlatformStyle.macos, Brightness.dark),
          home: AppDropOutline(
            active: active,
            child: const SizedBox(
              key: ValueKey('rows'),
              width: 200,
              height: 100,
            ),
          ),
        ),
      );
      await pump(false);
      final rows = tester.element(find.byKey(const ValueKey('rows')));
      expect(paintOf(tester).foregroundPainter, isNull);
      await pump(true);
      expect(paintOf(tester).foregroundPainter, isNotNull);
      expect(
        tester.element(find.byKey(const ValueKey('rows'))),
        same(rows),
        reason: 'the rows keep their state',
      );
      expect(find.byType(AppDropOutline), paints..rrect());
    });
  });
}
