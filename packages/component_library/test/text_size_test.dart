import 'package:component_library/component_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Components at a text size: what grows with the text keeps the room
/// around it, and what lines up at one size lines up at every size.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
    double width = 800,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.of(AppPlatformStyle.macos, Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );

  for (final scale in [1.0, 1.6]) {
    testWidgets('at text $scale a cap of arrows stands as tall as a cap of '
        'letters', (tester) async {
      await pump(
        tester,
        scale: scale,
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppKeyCap('Esc', key: Key('letters')),
            AppKeyCap('↑↓', key: Key('arrows')),
            AppKeyCap('⌥⇧⌘⌫', key: Key('symbols')),
          ],
        ),
      );
      final letters = tester.getSize(find.byKey(const Key('letters'))).height;
      expect(tester.getSize(find.byKey(const Key('arrows'))).height, letters);
      expect(tester.getSize(find.byKey(const Key('symbols'))).height, letters);
    });
  }

  testWidgets('a nav row is the platform\'s height until its line would '
      'crowd it, then grows with the line', (tester) async {
    late double at1;
    late double at16;
    Widget probe(void Function(double) out) => Builder(
      builder: (context) {
        out(AppNavItem.extentOf(context));
        return AppNavItem(label: 'Today', key: const Key('row'), onTap: () {});
      },
    );
    await pump(tester, probe((v) => at1 = v));
    expect(at1, AppMetrics.of(AppPlatformStyle.macos).navItemHeight);
    expect(tester.getSize(find.byKey(const Key('row'))).height, at1);
    await pump(tester, probe((v) => at16 = v), scale: 1.6);
    expect(at16, greaterThan(at1));
    expect(tester.getSize(find.byKey(const Key('row'))).height, at16);
    expect(tester.takeException(), isNull);
  });
}
