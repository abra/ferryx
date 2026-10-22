import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var taps = <String>[];

  Future<void> pumpAt(WidgetTester tester, double width) async {
    taps = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        // Material gives the text the theme's style, not the 48 px
        // error style of text without one.
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: AppFitOrElse(
                fallback: GestureDetector(
                  onTap: () => taps.add('narrow'),
                  child: const Text('Short'),
                ),
                // Stretches once it fits: intrinsics measure it, not its
                // stretched size.
                child: GestureDetector(
                  onTap: () => taps.add('wide'),
                  child: const Row(
                    children: [
                      Text('A label that needs room'),
                      Spacer(),
                      Text('end'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  RenderFitOrElse fit(WidgetTester tester) =>
      tester.renderObject(find.byType(AppFitOrElse));

  testWidgets('the wide form where it fits, stretched to the width', (
    tester,
  ) async {
    await pumpAt(tester, 600);
    expect(fit(tester).fits, isTrue);
    expect(tester.getSize(find.byType(AppFitOrElse)).width, 600);
    expect(tester.getTopRight(find.text('end')).dx, 600);
    await tester.tap(find.text('end'));
    expect(taps, ['wide']);
    expect(find.text('Short'), findsNothing, reason: 'offstage');
    expect(find.text('Short', skipOffstage: false), findsOneWidget);
  });

  testWidgets('the fallback once the wide form would overflow; the hidden '
      'one is never hit or reported as overflowing', (tester) async {
    await pumpAt(tester, 120);
    expect(fit(tester).fits, isFalse);
    expect(tester.takeException(), isNull, reason: 'no overflow report');
    expect(find.text('A label that needs room'), findsNothing);
    expect(
      find.text('A label that needs room', skipOffstage: false).hitTestable(),
      findsNothing,
    );
    await tester.tap(find.text('Short'));
    expect(taps, ['narrow']);
  });

  testWidgets('switches back and forth as the width changes', (tester) async {
    await pumpAt(tester, 120);
    expect(fit(tester).fits, isFalse);
    await pumpAt(tester, 400);
    expect(fit(tester).fits, isTrue);
  });

  testWidgets('only the shown form reaches screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAt(tester, 120);
    expect(find.bySemanticsLabel('Short'), findsOneWidget);
    expect(find.bySemanticsLabel('A label that needs room'), findsNothing);
    semantics.dispose();
  });
}
