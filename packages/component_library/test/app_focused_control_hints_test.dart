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
  testWidgets('focused controls describe keys that change the actual control', (
    tester,
  ) async {
    var checked = false;
    var toggled = false;
    var option = 0;
    var segment = 0;
    var slider = 0.5;
    var activated = 0;
    var hints = <AppKeyHint>[];
    final editor = TextEditingController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: AppGuidanceScope(
          labels: _labels,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  AppCheckbox(
                    value: checked,
                    onChanged: (value) => setState(() => checked = value),
                    label: 'Check',
                  ),
                  AppToggle(
                    value: toggled,
                    onChanged: (value) => setState(() => toggled = value),
                  ),
                  AppPopupButton<int>(
                    value: option,
                    items: const [(0, 'First'), (1, 'Second')],
                    onChanged: (value) => setState(() => option = value),
                  ),
                  AppSegmentedControl<int>(
                    value: segment,
                    options: const [(0, 'Left'), (1, 'Right')],
                    onChanged: (value) => setState(() => segment = value),
                  ),
                  Slider(
                    value: slider,
                    divisions: 10,
                    onChanged: (value) => setState(() => slider = value),
                  ),
                  TextButton(
                    onPressed: () => activated++,
                    child: const Text('Apply'),
                  ),
                  AppTextField(controller: editor),
                  AppFocusedControlHints(
                    fallback: const Text('Screen actions'),
                    builder: (value) {
                      hints = value;
                      return AppKeyHints(value);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> key(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    await key(LogicalKeyboardKey.tab);
    expect(hints.single.label, 'Toggle');
    expect(hints.single.keys, ['Space']);
    await key(LogicalKeyboardKey.space);
    expect(checked, isTrue);

    await key(LogicalKeyboardKey.tab);
    expect(hints.single.label, 'Toggle');
    await key(LogicalKeyboardKey.space);
    expect(toggled, isTrue);

    await key(LogicalKeyboardKey.tab);
    expect(hints.single.label, 'Choose');
    expect(hints.single.keys, ['Space']);
    await key(LogicalKeyboardKey.space);
    await key(LogicalKeyboardKey.arrowDown);
    await key(LogicalKeyboardKey.enter);
    expect(option, 1);

    await key(LogicalKeyboardKey.tab);
    expect(hints.single.label, 'Choose');
    expect(hints.single.keys, ['←', '→']);
    await key(LogicalKeyboardKey.arrowRight);
    expect(segment, 1);

    await key(LogicalKeyboardKey.tab);
    expect(hints.single.label, 'Adjust');
    expect(hints.single.keys, ['←', '→']);
    await key(LogicalKeyboardKey.arrowRight);
    expect(slider, greaterThan(0.5));

    await key(LogicalKeyboardKey.tab);
    expect(hints.single.label, 'Activate');
    await key(LogicalKeyboardKey.space);
    expect(activated, 1);

    await key(LogicalKeyboardKey.tab);
    expect(find.text('Screen actions'), findsOneWidget);
    await tester.enterText(find.byType(AppTextField), 'Space is text');
    expect(editor.text, 'Space is text');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('scope disabling and modal focus do not leak control hints', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var enabled = true;
    late StateSetter change;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: StatefulBuilder(
          builder: (context, setState) {
            change = setState;
            return AppGuidanceScope(
              labels: _labels,
              enabled: enabled,
              child: Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      focusNode: focus,
                      onPressed: () => showAppDialog<void>(
                        context,
                        (_) => AppDialog(
                          title: 'Modal',
                          actions: const [],
                          body: AppCheckbox(value: true, onChanged: (_) {}),
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                    const AppFocusedControlHints(
                      fallback: Text('Screen actions'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('Activate'), findsOneWidget);
    change(() => enabled = false);
    await tester.pumpAndSettle();
    expect(find.text('Activate'), findsNothing);
    expect(find.text('Screen actions'), findsOneWidget);
    change(() => enabled = true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Activate'), findsNothing);
    expect(find.text('Screen actions', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
