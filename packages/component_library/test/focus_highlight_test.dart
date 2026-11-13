// Focus rings show while the keyboard is in use and hide after a pointer
// press, as on macOS, Windows 11 and GNOME; a list row takes the focus when
// clicked, unless it opens a window. Clicks are a mouse's: Flutter itself
// hides rings after a touch, never after a mouse.

import 'package:component_library/component_library.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Counts what a painter draws; a painter that drew another way would
/// read as drawing nothing and fail the keyboard-mode test.
class _CountingCanvas implements Canvas {
  int draws = 0;

  @override
  void drawRRect(RRect rrect, Paint paint) => draws++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

FocusHighlightMode get mode => FocusManager.instance.highlightMode;

void main() {
  group('FocusHighlightTracker', () {
    testWidgets('starts hidden; a key shows the rings, a pointer press '
        'hides them; modifiers alone change nothing', (tester) async {
      final tracker = FocusHighlightTracker.attach();
      addTearDown(tracker.dispose);
      await tester.pumpWidget(
        const MaterialApp(home: Center(child: Text('surface'))),
      );
      expect(mode, FocusHighlightMode.touch, reason: 'hidden until a key');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(mode, FocusHighlightMode.traditional);
      await tester.tap(find.text('surface'), kind: PointerDeviceKind.mouse);
      expect(mode, FocusHighlightMode.touch);
      // ⌘ (or Shift) held for a ⌘-click is not keyboard use.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(mode, FocusHighlightMode.touch);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(mode, FocusHighlightMode.traditional);
    });

    testWidgets('only listens: keys still reach their handlers; detaching '
        'restores the strategy it found', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      final tracker = FocusHighlightTracker.attach();
      var heard = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            focusNode: node,
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent) heard++;
              return KeyEventResult.handled;
            },
            child: const SizedBox(),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      expect(heard, 1);
      tracker.dispose();
      expect(
        FocusManager.instance.highlightStrategy,
        FocusHighlightStrategy.alwaysTraditional,
      );
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    });
  });

  group('FocusRingPainter', () {
    FocusRingPainter painter() => FocusRingPainter(
      color: const Color(0xFF007AFF),
      width: 3,
      gap: 0,
      radius: 6,
    );

    test('draws in the keyboard mode only', () {
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final canvas = _CountingCanvas();
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      painter().paint(canvas, const Size(80, 22));
      expect(canvas.draws, 0);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      painter().paint(canvas, const Size(80, 22));
      expect(canvas.draws, 1);
    });

    testWidgets('a mode switch repaints the focused ring and rebuilds '
        'nothing', (tester) async {
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      var builds = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          home: Center(
            child: Focus(
              focusNode: node,
              child: Builder(
                builder: (context) => FocusRing(
                  child: Builder(
                    builder: (context) {
                      builds++;
                      return const SizedBox(width: 80, height: 22);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      final paint = tester.renderObject<RenderCustomPaint>(
        find.descendant(
          of: find.byType(FocusRing),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(paint.foregroundPainter, isA<FocusRingPainter>());
      final before = builds;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      expect(paint.debugNeedsPaint, isTrue, reason: 'repaints on the switch');
      await tester.pump();
      expect(builds, before, reason: 'no rebuild');
    });
  });

  group('AppNavItem', () {
    Future<void> pumpRows(WidgetTester tester, FocusNode elsewhere) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppPlatformStyle.macos),
            home: Material(
              child: Column(
                children: [
                  Focus(focusNode: elsewhere, child: const Text('editor')),
                  AppNavItem(label: 'Editor', onTap: () {}),
                  AppNavItem(label: 'Flashcards', onTap: () {}),
                  AppNavItem(
                    label: 'Settings',
                    focusOnTap: false,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );

    String? focusedLabel() {
      String? label;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
        final widget = e.widget;
        if (widget is! AppNavItem) return true;
        label = widget.label;
        return false;
      });
      return label;
    }

    testWidgets('a click takes the focus, so the arrows go on from the row '
        'picked; a row that opens a window leaves it where it was', (
      tester,
    ) async {
      final elsewhere = FocusNode();
      addTearDown(elsewhere.dispose);
      await pumpRows(tester, elsewhere);
      elsewhere.requestFocus();
      await tester.pump();
      await tester.tap(find.text('Settings'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(elsewhere.hasPrimaryFocus, isTrue, reason: 'like a button');
      await tester.tap(find.text('Editor'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(focusedLabel(), 'Editor');
    });

    testWidgets('with the tracker: no ring after the click, the ring on the '
        'next row after ↓', (tester) async {
      final tracker = FocusHighlightTracker.attach();
      addTearDown(tracker.dispose);
      final elsewhere = FocusNode();
      addTearDown(elsewhere.dispose);
      await pumpRows(tester, elsewhere);
      await tester.tap(find.text('Editor'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(focusedLabel(), 'Editor');
      expect(FocusRing.showsHighlight(), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedLabel(), 'Flashcards');
      expect(FocusRing.showsHighlight(), isTrue);
    });
  });
}
