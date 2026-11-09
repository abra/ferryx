import 'package:component_library/component_library.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Object> log;
  late FocusNode node;

  setUp(() {
    log = [];
    node = FocusNode(debugLabel: 'edge');
  });
  tearDown(() => node.dispose());

  Future<void> pump(WidgetTester tester, {bool reset = false}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.of(AppPlatformStyle.macos, Brightness.light),
          home: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(width: 200),
                AppSplitter(
                  focusNode: node,
                  title: 'Sidebar width',
                  value: '240 pt',
                  hints: const [
                    AppKeyHint(['←', '→'], 'width'),
                  ],
                  onAction: log.add,
                  onDragStart: () => log.add('start'),
                  onDragUpdate: (dx) => log.add(dx),
                  onDragEnd: () => log.add('end'),
                  onReset: reset ? () => log.add('reset') : null,
                  resetLabel: reset ? 'Equal panels' : null,
                  resetHint: reset ? 'Double-click to reset' : null,
                ),
              ],
            ),
          ),
        ),
      );

  double lineOpacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('focused, it lights its line and shows the card; the keys '
      'become actions', (tester) async {
    await pump(tester);
    expect(find.text('Sidebar width'), findsNothing);
    expect(lineOpacity(tester), 0);
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('Sidebar width'), findsOneWidget);
    expect(find.text('240 pt'), findsOneWidget);
    expect(find.text('width'), findsOneWidget);
    expect(lineOpacity(tester), 1);

    Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }

    await press(LogicalKeyboardKey.arrowLeft);
    await press(LogicalKeyboardKey.arrowRight);
    await press(LogicalKeyboardKey.arrowLeft, shift: true);
    await press(LogicalKeyboardKey.arrowRight, shift: true);
    await press(LogicalKeyboardKey.home);
    await press(LogicalKeyboardKey.end);
    await press(LogicalKeyboardKey.digit0);
    await press(LogicalKeyboardKey.tab);
    await press(LogicalKeyboardKey.tab, shift: true);
    await press(LogicalKeyboardKey.enter);
    await press(LogicalKeyboardKey.escape);
    expect(log, [
      AppSplitterAction.left,
      AppSplitterAction.right,
      AppSplitterAction.farLeft,
      AppSplitterAction.farRight,
      AppSplitterAction.narrowest,
      AppSplitterAction.widest,
      AppSplitterAction.reset,
      AppSplitterAction.next,
      AppSplitterAction.previous,
      AppSplitterAction.done,
      AppSplitterAction.cancel,
    ]);
    expect(node.hasFocus, isTrue, reason: 'the owner decides where it goes');

    node.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Sidebar width'), findsNothing);
  });

  testWidgets('a held arrow repeats; ↑ and ↓ are kept, so the focus never '
      'slips out; a held Enter does not repeat', (tester) async {
    await pump(tester);
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown), isTrue);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyK), isFalse);
    expect(log, [
      AppSplitterAction.right,
      AppSplitterAction.right,
      AppSplitterAction.done,
    ]);
    expect(node.hasFocus, isTrue);
  });

  testWidgets('the pointer drags it and lights the line meanwhile', (
    tester,
  ) async {
    await pump(tester);
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(AppSplitter)),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(lineOpacity(tester), 1);
    expect(
      find.text('240 pt'),
      findsOneWidget,
      reason: 'dragging shows the size without taking keyboard focus',
    );
    await drag.up();
    await tester.pumpAndSettle();
    expect(log.first, 'start');
    expect(log.last, 'end');
    final moved = log.whereType<double>().fold<double>(0, (a, b) => a + b);
    expect(moved, greaterThan(0));
    expect(node.hasFocus, isFalse, reason: 'dragging does not take the keys');
  });

  testWidgets(
    'hover shows the value and a reset button that can be reached across the gap',
    (tester) async {
      await pump(tester, reset: true);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getBottomLeft(find.byType(AppSplitter)) + const Offset(2, -20),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('240 pt'), findsOneWidget);
      expect(
        tester.getCenter(find.text('240 pt')).dy,
        greaterThan(400),
        reason:
            'the card stays near the pointer even at the end of the divider',
      );
      expect(find.text('Double-click to reset'), findsOneWidget);
      expect(node.hasFocus, isFalse);
      await mouse.moveTo(tester.getCenter(find.text('Equal panels')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Equal panels'));
      expect(log, ['reset']);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'double-click resets; Tab from the focused edge reaches the reset button',
    (tester) async {
      await pump(tester, reset: true);
      final edge = find.byType(AppSplitter);
      await tester.tap(edge);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(edge);
      await tester.pumpAndSettle();
      expect(log, ['reset']);
      log.clear();
      node.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(log, ['reset']);
    },
  );

  testWidgets('the size card stays within a small overlay near the far edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 350,
                top: 0,
                bottom: 0,
                child: AppSplitter(
                  focusNode: node,
                  title: 'Panel sizes',
                  value: 'Left 80% · Right 20%',
                  hints: const [],
                  onAction: log.add,
                  onDragStart: () {},
                  onDragUpdate: (_) {},
                  onDragEnd: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    final card = tester.getRect(
      find
          .ancestor(
            of: find.text('Panel sizes'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(card.left, greaterThanOrEqualTo(0));
    expect(card.right, lessThanOrEqualTo(400));
    expect(card.top, greaterThanOrEqualTo(0));
    expect(card.bottom, lessThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an edge between stacked panes moves with ↑ and ↓, keeps ← '
      'and →, and drags up and down', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(AppPlatformStyle.macos, Brightness.light),
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 300),
              AppSplitter(
                focusNode: node,
                title: 'Terminal height',
                value: '12 lines',
                hints: const [],
                axis: Axis.vertical,
                line: AppSplitterLine.center,
                onAction: log.add,
                onDragStart: () => log.add('start'),
                onDragUpdate: (delta) => log.add(delta),
                onDragEnd: () => log.add('end'),
              ),
            ],
          ),
        ),
      ),
    );
    final edge = tester.getSize(find.byType(AppSplitter));
    expect(edge.height, AppSizes.resizeHandleWidth);
    expect(edge.width, 800);
    node.requestFocus();
    await tester.pumpAndSettle();
    // The card sits above the line.
    expect(
      tester.getBottomLeft(find.text('Terminal height')).dy,
      lessThan(tester.getTopLeft(find.byType(AppSplitter)).dy),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft), isTrue);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight), isTrue);
    expect(log, [
      AppSplitterAction.left,
      AppSplitterAction.right,
      AppSplitterAction.farLeft,
    ]);
    log.clear();
    node.unfocus();
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(AppSplitter)),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(0, -40));
    await drag.up();
    await tester.pumpAndSettle();
    expect(log.first, 'start');
    expect(log.last, 'end');
    final moved = log.whereType<double>().fold<double>(0, (a, b) => a + b);
    expect(moved, lessThan(0));
  });

  testWidgets('hint mode labels it; the label gives it the focus', (
    tester,
  ) async {
    final registry = HintRegistry();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(AppPlatformStyle.macos, Brightness.light),
        home: Scaffold(
          body: HintScope(
            registry: registry,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(width: 200),
                AppSplitter(
                  focusNode: node,
                  title: 'Sidebar width',
                  value: '240 pt',
                  hints: const [],
                  onAction: log.add,
                  onDragStart: () {},
                  onDragUpdate: (_) {},
                  onDragEnd: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final overlay = tester.renderObject<RenderBox>(find.byType(Scaffold));
    final anchors = registry.collect(overlay);
    expect(anchors, hasLength(1));
    anchors.single.onActivate();
    await tester.pump();
    expect(node.hasFocus, isTrue);
  });
}
