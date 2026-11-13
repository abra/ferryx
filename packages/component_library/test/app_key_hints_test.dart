import 'package:component_library/component_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const hints = [
    AppKeyHint(['gT'], 'Previous tab', typed: true),
    AppKeyHint(['gt'], 'Next tab', typed: true),
    AppKeyHint(['F5'], 'Copy to the other panel'),
  ];

  Future<void> pump(
    WidgetTester tester,
    double width, {
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(AppPlatformStyle.macos),
      home: Material(
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: direction,
            child: Center(
              child: SizedBox(
                width: width,
                child: const AppKeyHints(hints, singleLine: true),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('keeps a prefix of complete hints and restores it on resize', (
    tester,
  ) async {
    await pump(tester, 700);
    final first = tester.getRect(find.text('Previous tab'));
    final second = tester.getRect(find.text('Next tab'));
    final line = tester.getRect(find.byType(AppKeyHints));
    final firstWidth = first.right - line.left;
    final secondWidth = second.right - line.left;

    for (final direction in TextDirection.values) {
      await pump(tester, secondWidth - 1, direction: direction);
      expect(find.text('Previous tab'), findsOneWidget);
      expect(find.text('Next tab'), findsNothing);
      expect(find.text('Copy to the other panel'), findsNothing);
      final visible = tester.getRect(find.text('Previous tab'));
      final bounds = tester.getRect(find.byType(AppKeyHints));
      expect(visible.left, greaterThanOrEqualTo(bounds.left));
      expect(visible.right, lessThanOrEqualTo(bounds.right));
      await pump(tester, firstWidth - 1, direction: direction);
      expect(find.text('Previous tab'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await pump(tester, 700);
    expect(find.text('Copy to the other panel'), findsOneWidget);
  });

  testWidgets('large text is measured and hidden hints leave semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, 700);
    final line = tester.getRect(find.byType(AppKeyHints));
    final width = tester.getRect(find.text('Next tab')).right - line.left + 1;
    await pump(tester, width);
    expect(find.bySemanticsLabel('Next tab'), findsOneWidget);
    await pump(tester, width, scale: 1.6);
    expect(find.text('Previous tab'), findsOneWidget);
    expect(find.text('Next tab'), findsNothing);
    expect(find.bySemanticsLabel('Next tab'), findsNothing);
    await pump(tester, 700);
    expect(find.bySemanticsLabel('Next tab'), findsOneWidget);
    semantics.dispose();
  });
}
