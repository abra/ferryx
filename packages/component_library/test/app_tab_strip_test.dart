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
    MacGeneration generation = MacGeneration.sequoia,
    double width = 600,
  }) => MaterialApp(
    theme: AppTheme.of(style, Brightness.light, generation: generation),
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

  Rect tabRect(WidgetTester tester, String label) => tester.getRect(
    find.ancestor(of: find.text(label), matching: find.byType(HintTarget)),
  );

  testWidgets('on macOS 15 the tabs fill the bar edge to edge, as Finder\'s '
      'window tabs: they touch, + stands in a cell of its own at the end, '
      'and the strip joins the bar above', (tester) async {
    await tester.pumpWidget(strip(named(['Работа', 'Загрузки']), active: 1));
    final bar = tester.getRect(find.byType(AppTabStrip));
    final first = tabRect(tester, 'Работа');
    final second = tabRect(tester, 'Загрузки');
    final plus = tester.getRect(
      find.ancestor(
        of: find.byIcon(AppIcons.add),
        matching: find.byType(AppIconButton),
      ),
    );
    final metrics = AppTheme.of(
      AppPlatformStyle.macos,
      Brightness.light,
    ).extension<AppMetrics>()!;
    expect(first.left, bar.left);
    expect(first.right, second.left);
    // The + cell: a line, then the button's width, to the end.
    expect(bar.right - second.right, metrics.iconButtonSize.width);
    expect(plus.right, lessThanOrEqualTo(bar.right));
    expect(first.height, 28);
    expect(bar.height, 29, reason: '28 and the line under them');
    expect(
      AppTabStrip.joinsBarAbove(tester.element(find.byType(AppTabStrip))),
      isTrue,
    );
  });

  for (final ratio in [1.0, 1.5, 2.0]) {
    for (final count in [2, 3, 4]) {
      for (final extraPixel in [1.0, 2.0]) {
        testWidgets('flat tabs meet the + cell without a gap: $count tabs, '
            '$ratio DPR, $extraPixel extra physical pixels', (tester) async {
          final physicalWidth = 600 * ratio + extraPixel;
          tester.view.devicePixelRatio = ratio;
          tester.view.physicalSize = Size(physicalWidth, 200 * ratio);
          addTearDown(tester.view.reset);
          final labels = [for (var i = 0; i < count; i++) 'Folder $i'];
          await tester.pumpWidget(
            strip(
              named(labels),
              active: count - 1,
              width: physicalWidth / ratio,
            ),
          );
          await tester.pumpAndSettle();

          final bar = tester.getRect(find.byType(AppTabStrip));
          final tabs = [for (final label in labels) tabRect(tester, label)];
          final context = tester.element(find.byType(AppTabStrip));
          final cellWidth = context.metrics.iconButtonSize.width;
          expect(tabs.first.left, closeTo(bar.left, 1e-6));
          for (var i = 1; i < tabs.length; i++) {
            expect(tabs[i].left, closeTo(tabs[i - 1].right, 1e-6));
          }
          expect(
            tabs.last.right,
            closeTo(bar.right - cellWidth, 1e-6),
            reason: 'the last tab must touch the new-tab cell',
          );
          for (final tab in tabs) {
            expect(tab.left * ratio, closeTo((tab.left * ratio).round(), 1e-6));
            expect(
              tab.right * ratio,
              closeTo((tab.right * ratio).round(), 1e-6),
            );
          }
          expect(find.byIcon(AppIcons.chevronDown), findsNothing);
        });
      }
    }
  }

  testWidgets('fractional available width keeps fitted tabs unscrolled and '
      'on physical pixels', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 200);
    addTearDown(tester.view.reset);
    final labels = ['Work', 'Downloads', 'Documents'];
    // The 28 px new-tab cell leaves 570.6 px for three fitting tabs.
    await tester.pumpWidget(strip(named(labels), active: 2, width: 598.6));
    await tester.pumpAndSettle();

    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scroll.position.maxScrollExtent, closeTo(0, 1e-6));
    expect(scroll.position.pixels, closeTo(0, 1e-6));
    final viewport = tester.getRect(find.byType(ReorderableListView));
    for (final label in labels) {
      final tab = tabRect(tester, label);
      expect(tab.left, closeTo(tab.left.round(), 1e-6));
      expect(tab.right, closeTo(tab.right.round(), 1e-6));
      expect(tab.right, lessThanOrEqualTo(viewport.right + 1e-6));
    }
    expect(find.byIcon(AppIcons.chevronDown), findsNothing);
  });

  testWidgets('a pinned tab keeps its width while ordinary tabs fill the '
      'remaining room up to +', (tester) async {
    final labels = ['A pinned folder with a long name', 'Work', 'Downloads'];
    double? pinnedWidth;
    for (final width in [601.0, 702.0]) {
      await tester.pumpWidget(
        strip(named(labels, pinned: 1), active: 2, width: width),
      );
      await tester.pumpAndSettle();
      final pinned = tabRect(tester, labels.first);
      expect(pinned.width, lessThanOrEqualTo(AppTabStrip.maxPinnedWidth));
      if (pinnedWidth != null) expect(pinned.width, pinnedWidth);
      pinnedWidth = pinned.width;
      final bar = tester.getRect(find.byType(AppTabStrip));
      final cellWidth = tester
          .element(find.byType(AppTabStrip))
          .metrics
          .iconButtonSize
          .width;
      expect(tabRect(tester, 'Work').left, pinned.right);
      expect(tabRect(tester, 'Downloads').left, tabRect(tester, 'Work').right);
      expect(
        tabRect(tester, 'Downloads').right,
        closeTo(bar.right - cellWidth, 1e-6),
      );
    }
  });

  testWidgets('Windows tabs keep their width cap in a wide strip and '
      'scroll at their minimum width in a narrow one', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 300);
    addTearDown(tester.view.reset);
    final labels = ['Work', 'Downloads'];
    await tester.pumpWidget(
      strip(named(labels), style: AppPlatformStyle.windows, width: 900),
    );
    await tester.pumpAndSettle();
    for (final label in labels) {
      expect(tabRect(tester, label).width, 240);
    }
    expect(find.byIcon(AppIcons.chevronDown), findsNothing);

    await tester.pumpWidget(
      strip(
        named(labels),
        active: 1,
        style: AppPlatformStyle.windows,
        width: 240,
      ),
    );
    await tester.pumpAndSettle();
    expect(tabRect(tester, 'Downloads').width, 100);
    expect(find.byIcon(AppIcons.chevronDown), findsOneWidget);
    final viewport = tester.getRect(find.byType(ReorderableListView));
    final active = tabRect(tester, 'Downloads');
    expect(active.left, greaterThanOrEqualTo(viewport.left));
    expect(active.right, lessThanOrEqualTo(viewport.right));
  });

  for (final (style, generation) in [
    (AppPlatformStyle.macos, MacGeneration.tahoe),
    (AppPlatformStyle.windows, MacGeneration.sequoia),
    (AppPlatformStyle.gnome, MacGeneration.sequoia),
  ]) {
    testWidgets('${style.name} ${generation.name}: tabs stand apart on the '
        'bar, which keeps the line of the bar above', (tester) async {
      await tester.pumpWidget(
        strip(
          named(['Работа', 'Загрузки']),
          style: style,
          generation: generation,
        ),
      );
      final bar = tester.getRect(find.byType(AppTabStrip));
      expect(tabRect(tester, 'Работа').left, greaterThan(bar.left));
      expect(
        AppTabStrip.joinsBarAbove(tester.element(find.byType(AppTabStrip))),
        isFalse,
      );
    });
  }

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
