import 'package:component_library/component_library.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> picked;

  Future<void> pump(WidgetTester tester, {bool enabled = true}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          home: Scaffold(
            body: Center(
              child: AppMenuButton<String>(
                label: 'Practise',
                enabled: enabled,
                entries: const [
                  AppMenuAction(value: 'shuffled', label: 'Shuffled'),
                  AppMenuSeparator(),
                  AppMenuAction(value: 'inOrder', label: 'In order'),
                ],
                onSelected: picked.add,
              ),
            ),
          ),
        ),
      );

  setUp(() => picked = []);

  testWidgets('a click opens the menu under the button; a pick is passed '
      'on', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Practise'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final button = tester.getRect(find.byType(OutlinedButton));
    final item = tester.getRect(find.widgetWithText(AppMenuItem, 'Shuffled'));
    expect(item.top, greaterThanOrEqualTo(button.bottom), reason: 'under it');
    await tester.tap(find.text('In order'));
    await tester.pumpAndSettle();
    expect(picked, ['inOrder']);
    expect(find.byType(AppMenuItem), findsNothing);
  });

  testWidgets('the keys open it too; Esc picks nothing', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppMenuItem, 'Shuffled'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    expect(find.byType(AppMenuItem), findsNothing);
  });

  testWidgets('disabled, it opens nothing', (tester) async {
    await pump(tester, enabled: false);
    await tester.tap(find.text('Practise'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byType(AppMenuItem), findsNothing);
  });
}
