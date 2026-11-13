import 'package:component_library/component_library.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final field = FocusNode(debugLabel: 'field');
  final other = FocusNode(debugLabel: 'other');
  tearDownAll(() {
    field.dispose();
    other.dispose();
  });

  /// A field, a second field, a button that takes no focus and blank
  /// space, as a pane's bar and text are.
  Future<void> pump(WidgetTester tester, {required bool keep}) async {
    Widget app = MaterialApp(
      theme: AppTheme.of(AppPlatformStyle.macos, Brightness.light),
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                focusNode: field,
                controller: TextEditingController(text: 'Синапс'),
              ),
            ),
            SizedBox(width: 240, child: TextField(focusNode: other)),
            AppIconButton(
              icon: AppIcons.today,
              tooltip: 'Calendar',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    if (keep) app = TapOutsideKeepsFocus(child: app);
    await tester.pumpWidget(app);
    field.requestFocus();
    await tester.pump();
  }

  Future<void> click(WidgetTester tester, Offset at, {int? buttons}) async {
    await tester.tapAt(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: buttons ?? kPrimaryButton,
    );
    await tester.pumpAndSettle();
  }

  final desktops = TargetPlatformVariant.desktop();

  testWidgets('Flutter alone drops the field\'s focus on a click on a '
      'button beside it', (tester) async {
    await pump(tester, keep: false);
    await click(tester, tester.getCenter(find.byType(AppIconButton)));
    expect(field.hasFocus, isFalse);
  }, variant: desktops);

  testWidgets('a click on a button or blank space keeps the caret in '
      'its field', (tester) async {
    await pump(tester, keep: true);
    await click(tester, tester.getCenter(find.byType(AppIconButton)));
    expect(field.hasPrimaryFocus, isTrue, reason: 'a button');
    await click(tester, const Offset(600, 500));
    expect(field.hasPrimaryFocus, isTrue, reason: 'blank space');
  }, variant: desktops);

  testWidgets('a click on another field moves the focus there', (
    tester,
  ) async {
    await pump(tester, keep: true);
    await click(tester, tester.getCenter(find.byType(TextField).last));
    expect(other.hasPrimaryFocus, isTrue);
  }, variant: desktops);

  testWidgets('a click outside closes the field\'s context menu and '
      'keeps the caret', (tester) async {
    await pump(tester, keep: true);
    await click(
      tester,
      tester.getCenter(find.byType(TextField).first),
      buttons: kSecondaryButton,
    );
    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    await click(tester, const Offset(600, 500));
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    expect(field.hasPrimaryFocus, isTrue);
  }, variant: desktops);
}
