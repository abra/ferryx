import 'package:component_library/component_library.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// What the strip was asked to do, as text, in order.
  late List<String> calls;

  Widget strip(
    List<AppTab> tabs, {
    int active = 0,
    AppPlatformStyle style = AppPlatformStyle.macos,
    double width = 600,
  }) => MaterialApp(
    theme: AppTheme.of(style, Brightness.light),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: AppTabStrip(
            tabs: tabs,
            active: active,
            onSelect: (i) => calls.add('select $i'),
            onClose: (i) => calls.add('close $i'),
            onReorder: (from, to) => calls.add('move $from $to'),
            onMenu: (i, _) => calls.add('menu $i'),
            onNewTab: () => calls.add('new'),
            onLeave: () => calls.add('leave'),
            closeTooltip: 'Close tab',
            newTabTooltip: 'New tab',
            listTooltip: 'All tabs',
          ),
        ),
      ),
    ),
  );

  List<AppTab> named(List<String> labels, {int pinned = 0}) => [
    for (final (i, label) in labels.indexed)
      AppTab(id: i, label: label, icon: AppIcons.document, pinned: i < pinned),
  ];

  setUp(() => calls = []);

  testWidgets('a click selects; ×, the middle button close; a right click '
      'asks for the menu; + asks for a new tab', (tester) async {
    await tester.pumpWidget(strip(named(['Сома', 'Аксон', 'Глия'])));
    await tester.tap(find.text('Аксон'), kind: PointerDeviceKind.mouse);
    await tester.tap(
      find.text('Глия'),
      buttons: kMiddleMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.tap(
      find.text('Сома'),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    // The active tab shows its close button under the pointer.
    // The taps' mouse is still known to the tracker: a hover moves it.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(tester.getCenter(find.text('Сома')));
    await tester.pump();
    await tester.tap(find.byIcon(AppIcons.close).first);
    await tester.tap(find.byIcon(AppIcons.add));
    expect(calls, ['select 1', 'close 2', 'menu 0', 'close 0', 'new']);
  });

  testWidgets('a pinned tab has no close button and keeps out of the middle '
      'button', (tester) async {
    await tester.pumpWidget(
      strip(named(['Сегодня', 'Аксон'], pinned: 1), active: 0),
    );
    expect(find.byIcon(AppIcons.pin), findsOneWidget);
    final pinnedTab = find.ancestor(
      of: find.text('Сегодня'),
      matching: find.byWidgetPredicate((w) => '${w.runtimeType}' == '_Tab'),
    );
    expect(
      find.descendant(of: pinnedTab, matching: find.byIcon(AppIcons.close)),
      findsNothing,
    );
    // The other tab holds its close button's room, hidden until a hover.
    expect(find.byIcon(AppIcons.close).hitTestable(), findsNothing);
    await tester.tap(
      find.text('Сегодня'),
      buttons: kMiddleMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    expect(calls, isEmpty);
  });

  testWidgets('a click takes no focus; once a tab has it, ←/→ stop at the '
      'ends, Home and End reach them, Enter selects, Esc leaves', (
    tester,
  ) async {
    await tester.pumpWidget(strip(named(['Сома', 'Аксон', 'Глия'])));
    final before = FocusManager.instance.primaryFocus;
    await tester.tap(find.text('Аксон'), kind: PointerDeviceKind.mouse);
    expect(FocusManager.instance.primaryFocus, same(before));

    String? focused() {
      String? label;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
        final widget = e.widget;
        if (widget is Semantics && widget.properties.label != null) {
          label = widget.properties.label;
          return false;
        }
        return true;
      });
      return label;
    }

    Focus.of(tester.element(find.text('Сома'))).requestFocus();
    await tester.pump();
    expect(focused(), 'Сома');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(focused(), 'Сома', reason: 'the start stops it');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focused(), 'Аксон');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(focused(), 'Глия');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focused(), 'Глия', reason: 'the end stops it');
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(focused(), 'Сома');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(calls, ['select 1', 'select 0', 'leave']);
  });

  testWidgets('more tabs than fit scroll, the active one in view, and ⌄ '
      'lists them', (tester) async {
    final labels = [for (var i = 1; i <= 12; i++) 'Документ $i'];
    await tester.pumpWidget(strip(named(labels), active: 11, width: 500));
    await tester.pumpAndSettle();
    expect(find.byIcon(AppIcons.chevronDown), findsOneWidget);
    expect(find.text('Документ 12'), findsOneWidget, reason: 'built: in view');
    final view = tester.getRect(find.byType(Scrollable));
    final active = tester.getRect(
      find.ancestor(
        of: find.text('Документ 12'),
        matching: find.byType(HintTarget),
      ),
    );
    expect(active.right, lessThanOrEqualTo(view.right + 0.5));
    expect(active.left, greaterThanOrEqualTo(view.left - 0.5));
    await tester.tap(find.byIcon(AppIcons.chevronDown));
    await tester.pumpAndSettle();
    expect(find.byType(AppMenuItem), findsNWidgets(12));
    await tester.tap(find.byType(AppMenuItem).first);
    await tester.pumpAndSettle();
    expect(calls, ['select 0']);
  });

  testWidgets('a strip made narrower, as a split makes a pane, keeps the '
      'active tab in view', (tester) async {
    final labels = [for (var i = 1; i <= 12; i++) 'Документ $i'];
    await tester.pumpWidget(strip(named(labels), active: 5, width: 500));
    await tester.pumpAndSettle();
    Rect active() => tester.getRect(
      find.ancestor(
        of: find.text('Документ 6'),
        matching: find.byType(HintTarget),
      ),
    );
    Rect view() => tester.getRect(find.byType(Scrollable));
    expect(active().right, lessThanOrEqualTo(view().right + 0.5));
    // Narrower: the scroll it keeps would leave the active tab past the
    // end, were it not brought back.
    await tester.pumpWidget(strip(named(labels), active: 5, width: 300));
    await tester.pumpAndSettle();
    expect(active().right, lessThanOrEqualTo(view().right + 0.5));
    expect(active().left, greaterThanOrEqualTo(view().left - 0.5));
  });

  testWidgets('a drag moves a tab', (tester) async {
    await tester.pumpWidget(strip(named(['Сома', 'Аксон', 'Глия'])));
    final from = tester.getCenter(find.text('Сома'));
    final to = tester.getCenter(find.text('Глия'));
    final mouse = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(kLongPressTimeout);
    for (var i = 1; i <= 10; i++) {
      await mouse.moveTo(Offset.lerp(from, to + const Offset(40, 0), i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await mouse.up();
    await tester.pumpAndSettle();
    expect(calls, ['move 0 2']);
  });

  testWidgets('the strip grows with the text', (tester) async {
    await tester.pumpWidget(strip(named(['Сома'])));
    final small = tester.getSize(find.byType(AppTabStrip)).height;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: strip(named(['Сома'])),
      ),
    );
    final big = tester.getSize(find.byType(AppTabStrip)).height;
    expect(big, greaterThan(small));
  });
}
