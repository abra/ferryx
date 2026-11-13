import 'package:component_library/component_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('an open page reflects updated declarative route content', (
    tester,
  ) async {
    final title = ValueNotifier('first document');
    addTearDown(title.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<String>(
          valueListenable: title,
          builder: (context, text, _) => Navigator(
            pages: [
              const MaterialPage<void>(child: Text('files')),
              AppPage<void>(
                key: const ValueKey('viewer'),
                child: Text(text),
              ),
            ],
            onDidRemovePage: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('first document'), findsOneWidget);
    title.value = 'second document';
    await tester.pumpAndSettle();
    expect(find.text('first document'), findsNothing);
    expect(find.text('second document'), findsOneWidget);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'reduced=$reduced: a dialog accepts input during its entrance',
      (
        tester,
      ) async {
        final opener = FocusNode();
        final text = TextEditingController();
        addTearDown(opener.dispose);
        addTearDown(text.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppPlatformStyle.macos),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  focusNode: opener,
                  autofocus: true,
                  onPressed: () => showAppDialog<void>(
                    context,
                    (context) => AppDialog(
                      title: 'Rename',
                      body: AppTextField(controller: text, autofocus: true),
                      actions: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        final field = tester.widget<EditableText>(find.byType(EditableText));
        expect(field.focusNode.hasFocus, isTrue);
        await tester.enterText(find.byType(AppTextField), 'report.txt');
        expect(text.text, 'report.txt');
        if (!reduced) {
          final fade = tester.widget<Opacity>(
            find
                .descendant(
                  of: find.byType(AppSurfaceTransition),
                  matching: find.byType(Opacity),
                )
                .first,
          );
          expect(fade.opacity, inExclusiveRange(0, 1));
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);
        expect(opener.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
