import 'package:component_library/component_library.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.of(AppPlatformStyle.macos, Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 240, child: child),
        ),
      ),
    ),
  );

  testWidgets('a row\'s action shows while the row is hovered or open, takes '
      'no room while hidden, and a click on it does not open the row', (
    tester,
  ) async {
    Rect? anchor;
    var opened = 0;
    Widget row({bool selected = false}) => AppNavItem(
      label: 'Linux',
      icon: AppIcons.folder,
      selected: selected,
      onTap: () => opened++,
      action: AppNavAction(
        icon: AppIcons.add,
        tooltip: 'Create inside',
        onPressed: (rect) => anchor = rect,
      ),
    );
    final plus = find.byIcon(AppIcons.add).hitTestable();

    await pump(tester, row());
    expect(plus, findsNothing, reason: 'idle');
    final label = tester.getSize(find.text('Linux')).width;

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('Linux')));
    addTearDown(mouse.removePointer);
    await tester.pump();
    expect(plus, findsOneWidget, reason: 'hovered');
    final button = tester.getRect(plus);
    final rowRect = tester.getRect(find.byType(AppNavItem));
    expect(button.right, lessThanOrEqualTo(rowRect.right));
    expect(button.center.dy, moreOrLessEquals(rowRect.center.dy, epsilon: 1));

    await tester.tap(plus, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(anchor, isNotNull);
    expect(anchor!.contains(button.center), isTrue, reason: 'its own frame');
    expect(opened, 0, reason: 'the row stays as it was');

    await mouse.moveTo(const Offset(600, 400));
    await tester.pump();
    expect(plus, findsNothing);
    expect(
      tester.getSize(find.text('Linux')).width,
      label,
      reason: 'hidden, it takes nothing from the label',
    );
    await pump(tester, row(selected: true));
    expect(plus, findsOneWidget, reason: 'the open row');
  });

  const long =
      'Chapter 12. Synaptic transmission at the neuromuscular junction';

  testWidgets('a value always shows whole; the label ends in an ellipsis '
      'before it', (tester) async {
    await pump(
      tester,
      AppNavItem(label: long, value: '1284', onTap: () {}),
    );
    final value = tester.renderObject<RenderParagraph>(find.text('1284'));
    expect(value.didExceedMaxLines, isFalse);
    expect(
      tester.getRect(find.text('1284')).right,
      lessThanOrEqualTo(tester.getRect(find.byType(AppNavItem)).right),
    );
    expect(
      tester.renderObject<RenderParagraph>(find.text(long)).didExceedMaxLines,
      isTrue,
    );
  });

  group('a cut label', () {
    Future<TestGesture> hover(WidgetTester tester, Finder at) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(at));
      addTearDown(mouse.removePointer);
      await tester.pump();
      return mouse;
    }

    Future<void> waitTip(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Finder tip(String text) => find.descendant(
      of: find.byType(Overlay),
      matching: find.text(text),
    );

    testWidgets('shows whole in a tooltip while the pointer rests on its '
        'row; a label that fits shows none', (tester) async {
      await pump(
        tester,
        Column(
          children: [
            AppNavItem(label: long, onTap: () {}),
            AppNavItem(label: 'Synapse', onTap: () {}),
          ],
        ),
      );
      expect(
        find.byType(Tooltip),
        findsNothing,
        reason: 'no row holds a tooltip until one is needed',
      );
      final mouse = await hover(tester, find.text(long));
      await waitTip(tester);
      expect(tip(long), findsNWidgets(2), reason: 'the row and the tooltip');

      await mouse.moveTo(tester.getCenter(find.text('Synapse')));
      await waitTip(tester);
      expect(tip(long), findsOneWidget, reason: 'gone with the pointer');
      expect(find.byType(Tooltip), findsNothing, reason: 'Synapse fits');
    });

    testWidgets('shows whole when the keyboard reaches its row, and goes '
        'with the focus', (tester) async {
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await pump(
        tester,
        Column(
          children: [
            AppNavItem(label: 'Synapse', focusNode: first, onTap: () {}),
            AppNavItem(label: long, focusNode: second, onTap: () {}),
          ],
        ),
      );
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      first.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await waitTip(tester);
      expect(second.hasFocus, isTrue);
      expect(tip(long), findsNWidgets(2));

      first.requestFocus();
      await waitTip(tester);
      expect(tip(long), findsOneWidget);
    });
  });
}
