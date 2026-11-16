import 'package:component_library/component_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _labels = AppGuidanceLabels(
  navigate: 'Navigate',
  choose: 'Choose',
  dismiss: 'Close',
  clear: 'Clear',
  nextControl: 'Next control',
  previousControl: 'Previous control',
  toggle: 'Toggle',
  adjust: 'Adjust',
  activate: 'Activate',
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required WidgetBuilder opener,
    bool enabled = true,
    AppPlatformStyle style = AppPlatformStyle.macos,
    double scale = 1,
    Size size = const Size(700, 480),
    String openerLabel = 'Open',
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(style),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: Scaffold(
          // Below the navigator: popup theme capture must carry this scope.
          body: AppGuidanceScope(
            labels: _labels,
            enabled: enabled,
            child: Builder(builder: opener),
          ),
        ),
      ),
    );
    await tester.tap(find.text(openerLabel));
    await tester.pumpAndSettle();
  }

  testWidgets('menu guidance follows actual enabled keyboard selection', (
    tester,
  ) async {
    int? result;
    await pump(
      tester,
      opener: (context) => TextButton(
        onPressed: () async {
          result = await showAppMenu<int>(
            context: context,
            anchor: const Rect.fromLTWH(40, 40, 50, 24),
            entries: const [
              AppMenuAction(value: 0, label: 'Disabled', enabled: false),
              AppMenuAction(value: 1, label: 'First'),
              AppMenuAction(value: 2, label: 'Second'),
            ],
          );
        },
        child: const Text('Open'),
      ),
    );
    final footer = find.byType(AppMenuNavigationHints);
    expect(tester.widget<AppMenuNavigationHints>(footer).canNavigate, isTrue);
    expect(tester.widget<AppMenuNavigationHints>(footer).canChoose, isFalse);
    final choose = find.byWidgetPredicate(
      (widget) => widget is AppTooltip && widget.message == _labels.choose,
    );
    expect(choose.hitTestable(), findsNothing);
    final before = tester.getRect(find.byType(AppMenuPanel));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.widget<AppMenuNavigationHints>(footer).canChoose, isTrue);
    expect(choose.hitTestable(), findsOneWidget);
    expect(tester.getRect(find.byType(AppMenuPanel)), before);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-disabled menu only offers dismissal', (tester) async {
    await pump(
      tester,
      opener: (context) => TextButton(
        onPressed: () => showAppMenu<int>(
          context: context,
          anchor: const Rect.fromLTWH(40, 40, 50, 24),
          entries: const [
            AppMenuAction(value: 0, label: 'Disabled', enabled: false),
          ],
        ),
        child: const Text('Open'),
      ),
    );
    final hints = tester.widget<AppMenuNavigationHints>(
      find.byType(AppMenuNavigationHints),
    );
    expect(hints.canNavigate, isFalse);
    expect(hints.canChoose, isFalse);
    expect(find.byType(AppMenuFooter), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Choose'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AppMenuPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final custom in [false, true]) {
    testWidgets('scope disabled; custom footer=$custom is preserved', (
      tester,
    ) async {
      await pump(
        tester,
        enabled: false,
        opener: (context) => TextButton(
          onPressed: () => showAppMenu<int>(
            context: context,
            anchor: const Rect.fromLTWH(40, 40, 50, 24),
            footer: custom
                ? const AppMenuFooter(hints: [('X', 'Specific action')])
                : null,
            entries: const [AppMenuAction(value: 1, label: 'First')],
          ),
          child: const Text('Open'),
        ),
      );
      expect(
        find.text('Specific action'),
        custom ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(AppMenuFooter),
        custom ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final style in AppPlatformStyle.values) {
    testWidgets('$style narrow 200% menu keeps items reachable', (
      tester,
    ) async {
      await pump(
        tester,
        style: style,
        scale: 2,
        size: const Size(320, 360),
        opener: (context) => TextButton(
          onPressed: () => showAppMenu<int>(
            context: context,
            width: 160,
            anchor: const Rect.fromLTWH(40, 40, 50, 24),
            entries: [
              for (var i = 0; i < 20; i++)
                AppMenuAction(value: i, label: 'Item $i'),
            ],
          ),
          child: const Text('Open'),
        ),
      );
      expect(find.byType(AppMenuFooter), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      final item = tester.getRect(find.widgetWithText(AppMenuItem, 'Item 19'));
      final footer = tester.getRect(find.byType(AppMenuFooter));
      expect(item.bottom, lessThanOrEqualTo(footer.top));
      final menu = tester.getRect(find.byType(AppMenuPanel));
      expect(menu.left, greaterThanOrEqualTo(AppSpacing.sm));
      expect(menu.right, lessThanOrEqualTo(320 - AppSpacing.sm));
      expect(menu.bottom, lessThanOrEqualTo(360 - AppSpacing.sm));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'popup button inherits guidance and keeps native current choice',
    (
      tester,
    ) async {
      int? picked;
      await pump(
        tester,
        opener: (_) => AppPopupButton<int>(
          value: 1,
          items: const [(1, 'Open'), (2, 'Second')],
          onChanged: (value) => picked = value,
        ),
      );
      expect(
        tester
            .widget<AppMenuNavigationHints>(
              find.byType(AppMenuNavigationHints),
            )
            .canChoose,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(picked, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nullable popup highlights System and can choose it again', (
    tester,
  ) async {
    String? current;
    final picked = <String?>[];
    await pump(
      tester,
      openerLabel: 'System',
      opener: (_) => StatefulBuilder(
        builder: (context, setState) => AppPopupButton<String?>(
          value: current,
          items: const [(null, 'System'), ('en', 'English')],
          onChanged: (value) {
            picked.add(value);
            setState(() => current = value);
          },
        ),
      ),
    );
    AppMenuItem selected() => tester
        .widgetList<AppMenuItem>(
          find.byType(AppMenuItem),
        )
        .singleWhere((item) => item.selected);
    expect(selected().label, 'System');
    expect(
      tester
          .widget<AppMenuNavigationHints>(
            find.byType(AppMenuNavigationHints),
          )
          .canChoose,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, ['en']);
    expect(current, 'en');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(selected().label, 'English');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, ['en', null]);
    expect(current, isNull);
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(picked, ['en', null]);
    expect(tester.takeException(), isNull);
  });

  for (final (items, custom) in [(0, false), (3, false), (3, true)]) {
    testWidgets(
      'picker with $items items, custom=$custom guides true actions',
      (
        tester,
      ) async {
        await pump(
          tester,
          opener: (context) => TextButton(
            onPressed: () => showAppQuickPicker<void>(
              context,
              builder: (_) => AppQuickPicker<int>(
                entries: [
                  for (var i = 0; i < items; i++)
                    AppQuickPickerItem(value: i, label: 'Result $i'),
                ],
                hintText: 'Search',
                noResultsText: 'No results',
                hints: custom ? const [('X', 'Specific action')] : const [],
                onQueryChanged: (_) {},
                onPick: (_) {},
              ),
            ),
            child: const Text('Open'),
          ),
        );
        expect(find.byType(AppMenuFooter), findsOneWidget);
        if (custom) {
          expect(find.byType(AppMenuNavigationHints), findsNothing);
          expect(find.text('Specific action'), findsOneWidget);
        } else {
          final hints = tester.widget<AppMenuNavigationHints>(
            find.byType(AppMenuNavigationHints),
          );
          expect(hints.canNavigate, items > 0);
          expect(hints.canChoose, items > 0);
          expect(hints.canDismiss, isTrue);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AppQuickPicker<int>), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
