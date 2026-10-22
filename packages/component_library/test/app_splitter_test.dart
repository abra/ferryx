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

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
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
    await drag.up();
    await tester.pumpAndSettle();
    expect(log.first, 'start');
    expect(log.last, 'end');
    final moved = log.whereType<double>().fold<double>(0, (a, b) => a + b);
    expect(moved, greaterThan(0));
    expect(node.hasFocus, isFalse, reason: 'dragging does not take the keys');
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
