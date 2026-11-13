import 'package:component_library/component_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final (style, generation) in [
    (AppPlatformStyle.macos, MacGeneration.sequoia),
    (AppPlatformStyle.macos, MacGeneration.tahoe),
    (AppPlatformStyle.windows, MacGeneration.sequoia),
    (AppPlatformStyle.gnome, MacGeneration.sequoia),
  ]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.75]) {
        testWidgets(
          '$style $generation $brightness at $scale: plain, path, password, numeric and search fields align',
          (tester) async {
            tester.view.physicalSize = const Size(1800, 600);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final search = TextEditingController(text: 'query');
            addTearDown(search.dispose);
            final theme = AppTheme.of(
              style,
              brightness,
              generation: generation,
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Row(
                    children: [
                      const SizedBox(
                        width: 180,
                        child: AppTextField(hintText: 'Name'),
                      ),
                      const SizedBox(
                        width: 180,
                        child: AppTextField(
                          monospace: true,
                          hintText: '/folder/file',
                        ),
                      ),
                      const SizedBox(
                        width: 180,
                        child: AppTextField(
                          obscureText: true,
                          hintText: 'Password',
                        ),
                      ),
                      const SizedBox(
                        width: 180,
                        child: AppTextField(
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.end,
                        ),
                      ),
                      const SizedBox(
                        width: 180,
                        child: AppTextField(
                          readOnly: true,
                          hintText: 'Waiting',
                        ),
                      ),
                      const SizedBox(
                        width: 180,
                        child: AppTextField(
                          enabled: false,
                          monospace: true,
                          hintText: 'Disabled',
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: AppSearchField(
                          controller: search,
                          hintText: 'Search',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            final fields = find.byType(AppTextField);
            expect(fields, findsNWidgets(7));
            final height = tester.getSize(fields.first).height;
            final metrics = AppMetrics.of(style, generation: generation);
            expect(height, greaterThanOrEqualTo(metrics.controlHeight));
            if (scale == 1) expect(height, closeTo(metrics.controlHeight, 0.5));
            for (final element in fields.evaluate()) {
              final host = find.byWidget(element.widget);
              final field = tester.widget<EditableText>(
                find.descendant(of: host, matching: find.byType(EditableText)),
              );
              final decoration = tester
                  .widget<InputDecorator>(
                    find.descendant(
                      of: host,
                      matching: find.byType(InputDecorator),
                    ),
                  )
                  .decoration;
              expect(
                tester.getSize(host).height,
                closeTo(height, 0.5),
              );
              expect(
                field.style.fontSize,
                theme.textTheme.bodyLarge!.fontSize,
              );
              expect(
                decoration.hintStyle!.fontSize,
                field.style.fontSize,
              );
              expect(field.onEditingComplete, isNotNull);
            }
            final path = tester.widget<EditableText>(
              find.descendant(
                of: fields.at(1),
                matching: find.byType(EditableText),
              ),
            );
            final pathDecoration = tester
                .widget<InputDecorator>(
                  find.descendant(
                    of: fields.at(1),
                    matching: find.byType(InputDecorator),
                  ),
                )
                .decoration;
            expect(path.style.fontFamily, metrics.typeScale.monoFamily);
            expect(
              pathDecoration.hintStyle!.fontFamily,
              path.style.fontFamily,
            );
            final disabled = tester.widget<EditableText>(
              find.descendant(
                of: fields.at(5),
                matching: find.byType(EditableText),
              ),
            );
            expect(disabled.style.color, theme.disabledColor);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'Return submits repeatedly while keeping focus and the supplied selection',
    (tester) async {
      final controller = TextEditingController(text: 'report.txt')
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      final node = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(node.dispose);
      final submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          home: Scaffold(
            body: AppTextField(
              controller: controller,
              focusNode: node,
              autofocus: true,
              selectAllOnFocus: false,
              onSubmitted: submitted.add,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      for (var i = 0; i < 2; i++) {
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(node.hasPrimaryFocus, isTrue);
      }
      expect(submitted, ['report.txt', 'report.txt']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'number fields filter input and multiline fields retain newlines',
    (tester) async {
      final number = TextEditingController();
      final arguments = TextEditingController();
      addTearDown(number.dispose);
      addTearDown(arguments.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          home: Scaffold(
            body: Column(
              children: [
                AppTextField(
                  controller: number,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                AppTextField(
                  controller: arguments,
                  monospace: true,
                  minLines: 3,
                  maxLines: 5,
                ),
              ],
            ),
          ),
        ),
      );
      final fields = find.byType(AppTextField);
      await tester.enterText(fields.first, 'a12b3');
      expect(number.text, '123');
      await tester.enterText(fields.last, '--first\n--second');
      await tester.pump();
      expect(arguments.text, '--first\n--second');
      expect(
        tester.getSize(fields.last).height,
        greaterThan(tester.getSize(fields.first).height * 2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a read-only field keeps keyboard focus; a disabled one does not take it',
    (tester) async {
      final busy = FocusNode();
      final disabled = FocusNode();
      addTearDown(busy.dispose);
      addTearDown(disabled.dispose);
      var escaped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          home: Scaffold(
            body: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  escaped = true;
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Column(
                children: [
                  AppTextField(focusNode: busy, readOnly: true),
                  AppTextField(focusNode: disabled, enabled: false),
                ],
              ),
            ),
          ),
        ),
      );
      busy.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(busy.hasPrimaryFocus, isTrue);
      expect(escaped, isTrue);
      disabled.requestFocus();
      await tester.pump();
      expect(disabled.hasFocus, isFalse);
      expect(busy.hasPrimaryFocus, isTrue);
    },
  );

  testWidgets(
    'form labels and help wrap while the input and trailing action align',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 260,
                child: AppFormField(
                  label: 'Длинная подпись поля для пути к исполняемому файлу',
                  helpText: 'Подсказка остаётся под полем и переносится по доступной ширине.',
                  trailing: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Выбрать'),
                  ),
                  child: const AppTextField(monospace: true),
                ),
              ),
            ),
          ),
        ),
      );
      final field = tester.getRect(find.byType(AppTextField));
      final button = tester.getRect(find.byType(OutlinedButton));
      final label = tester.getRect(find.textContaining('Длинная'));
      final help = tester.getRect(find.textContaining('Подсказка'));
      expect(field.left, label.left);
      expect(help.left, label.left);
      expect(field.center.dy, closeTo(button.center.dy, 0.5));
      expect(help.top, greaterThan(field.bottom));
      expect(tester.takeException(), isNull);
    },
  );
}
