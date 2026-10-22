import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    AppPlatformStyle style = AppPlatformStyle.macos,
    double width = 400,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(style),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('AppCheckbox', () {
    testWidgets('the label is part of the target and Space flips it', (
      tester,
    ) async {
      var value = false;
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => AppCheckbox(
            value: value,
            label: 'Match case',
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      );
      await tester.tap(find.text('Match case'));
      await tester.pump();
      expect(value, isTrue);
      // Tab lands on the box, the only focusable thing; Space flips it.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(value, isFalse);
      // Return belongs to the window's default button, not the box.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(value, isFalse);
    });

    testWidgets('a disabled box ignores taps', (tester) async {
      await pump(
        tester,
        const AppCheckbox(value: true, label: 'Fixed', onChanged: null),
      );
      await tester.tap(find.text('Fixed'));
      await tester.pump();
      expect(find.byIcon(AppIcons.check), findsOneWidget);
    });
  });

  group('AppControlRow', () {
    testWidgets('a long label wraps and the control keeps its size', (
      tester,
    ) async {
      await pump(
        tester,
        AppControlRow(
          label:
              'Показывать скрытые файлы и папки, а также системные элементы '
              'и файлы, начинающиеся с точки',
          control: AppToggle(value: true, onChanged: (_) {}),
        ),
        width: 300,
      );
      final toggle = tester.getSize(find.byType(AppToggle));
      final metrics = AppMetrics.of(AppPlatformStyle.macos);
      expect(toggle.width, metrics.toggleSize.width);
      final label = tester.widget<Text>(find.textContaining('скрытые'));
      expect(label.maxLines, 2);
    });

    testWidgets('a note sits under the label', (tester) async {
      await pump(
        tester,
        AppControlRow(
          label: 'Vim keys',
          note: 'h j k l move',
          control: AppToggle(value: false, onChanged: (_) {}),
        ),
      );
      final label = tester.getTopLeft(find.text('Vim keys'));
      final note = tester.getTopLeft(find.text('h j k l move'));
      expect(note.dx, label.dx);
      expect(note.dy, greaterThan(label.dy));
    });
  });

  group('AppWindowActivity', () {
    testWidgets('the focus area greys while the window is not active', (
      tester,
    ) async {
      late BuildContext inside;
      await pump(
        tester,
        AppWindowActivity(
          child: AppFocusArea(
            child: Builder(
              builder: (context) {
                inside = context;
                return const Text('rows');
              },
            ),
          ),
        ),
      );
      Future<void> lifecycle(String state) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/lifecycle',
          const StringCodec().encodeMessage('AppLifecycleState.$state'),
          (_) {},
        );
        await tester.pump();
      }

      // The area holds no focus, so it is not the active one either way;
      // the window's state is what changes.
      expect(AppWindowActivity.of(inside), isTrue);
      await lifecycle('inactive');
      expect(AppWindowActivity.of(inside), isFalse);
      expect(AppFocusArea.activeOf(inside), isFalse);
      await lifecycle('resumed');
      expect(AppWindowActivity.of(inside), isTrue);
    });
  });

  group('AppSearchField', () {
    testWidgets('a clear button appears with text; Esc empties the field', (
      tester,
    ) async {
      final changes = <String>[];
      await pump(
        tester,
        AppSearchField(hintText: 'Search', onChanged: changes.add),
      );
      expect(find.byIcon(AppIcons.cancel), findsNothing);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(find.byIcon(AppIcons.cancel), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byIcon(AppIcons.cancel), findsNothing);
      expect(changes.last, '');
      await tester.enterText(find.byType(TextField), 'de');
      await tester.pump();
      await tester.tap(find.byIcon(AppIcons.cancel));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });
  });

  group('AppDialog', () {
    testWidgets('Return runs the default action when nothing has the focus; '
        'a field keeps Return', (tester) async {
      String? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showAppDialog<String>(
                context,
                (context) => AppDialog(
                  title: 'Name',
                  body: const SizedBox.shrink(),
                  actions: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop('cancel'),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop('ok'),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, 'ok');
      // ⌘. leaves, as Esc does.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(result, isNull);
      // A click beside the dialog leaves it open.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsNothing);
    });

    testWidgets('a focused field keeps Return for its submit', (
      tester,
    ) async {
      String? submitted;
      String? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showAppDialog<String>(
                context,
                (context) => AppDialog(
                  title: 'Name',
                  body: TextField(
                    autofocus: true,
                    onSubmitted: (v) {
                      submitted = v;
                      Navigator.of(context).pop('field');
                    },
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop('button'),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(submitted, 'x');
      expect(result, 'field');
    });
  });
}
