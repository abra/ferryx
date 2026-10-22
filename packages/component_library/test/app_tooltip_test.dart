import 'package:component_library/component_library.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.of(AppPlatformStyle.macos, Brightness.light),
      home: Scaffold(
        body: Row(
          children: [
            TextButton(onPressed: () {}, child: const Text('before')),
            AppIconButton(
              icon: AppIcons.split,
              tooltip: 'Split',
              shortcut: '⇧⌘\\',
              onPressed: () {},
            ),
            TextButton(onPressed: () {}, child: const Text('after')),
          ],
        ),
      ),
    ),
  );

  Finder tip() => find.textContaining('Split', findRichText: true);

  testWidgets('the keyboard\'s focus shows the tooltip after the hover\'s '
      'wait, and leaving hides it', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // before
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // the icon button
    await tester.pump(const Duration(milliseconds: 300));
    expect(tip(), findsNothing, reason: 'not before the wait');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(tip(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // after
    await tester.pumpAndSettle();
    expect(tip(), findsNothing);
  });

  testWidgets('a click that focuses it shows no more than the hover does', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppIconButton)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    // The pointer leaves at once, so the hover never fires its own tooltip.
    await gesture.moveTo(const Offset(1, 1));
    await tester.pump(const Duration(seconds: 2));
    expect(tip(), findsNothing);
  });
}
