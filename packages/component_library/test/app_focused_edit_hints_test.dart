import 'package:component_library/component_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('field-only rebuilds update the available submit action', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var submitted = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: Scaffold(
          body: Column(
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => AppTextField(
                  controller: controller,
                  autofocus: true,
                  submitLabel: value.text.isEmpty ? null : 'Connect',
                  onSubmitted: value.text.isEmpty ? null : (_) => submitted++,
                ),
              ),
              const AppFocusedEditHints(fallback: Text('Screen actions')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connect'), findsNothing);
    await tester.enterText(find.byType(AppTextField), 'password');
    await tester.pumpAndSettle();
    expect(find.text('Connect'), findsOneWidget);
    // Native text input reports Return as the field's submit action.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(submitted, 1);
    controller.clear();
    await tester.pumpAndSettle();
    expect(find.text('Connect'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final style in AppPlatformStyle.values) {
    testWidgets('$style follows text, selection and field focus', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var hints = <AppKeyHint>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(style),
          home: Scaffold(
            body: Column(
              children: [
                AppTextField(controller: controller, focusNode: focus),
                AppFocusedEditHints(
                  fallback: const Text('Screen actions'),
                  builder: (value) {
                    hints = value;
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Screen actions'), findsOneWidget);
      focus.requestFocus();
      await tester.pumpAndSettle();
      final primary = style == AppPlatformStyle.macos ? '⌘' : 'Ctrl+';
      expect(hints.map((h) => h.keys.single), ['${primary}V']);

      controller.text = 'A filename';
      await tester.pump();
      expect(hints.map((h) => h.keys.single), ['${primary}A', '${primary}V']);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 1,
      );
      await tester.pump();
      expect(hints.map((h) => h.keys.single), [
        '${primary}A',
        '${primary}C',
        '${primary}X',
        '${primary}V',
      ]);
      focus.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('Screen actions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (readOnly, obscure, expected) in [
    (true, false, ['⌘A', '⌘C']),
    (false, true, ['⌘A', '⌘V']),
    (true, true, ['⌘A']),
  ]) {
    testWidgets('readOnly=$readOnly obscure=$obscure gives honest actions', (
      tester,
    ) async {
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'Private',
          selection: TextSelection(baseOffset: 0, extentOffset: 7),
        ),
      );
      addTearDown(controller.dispose);
      var hints = <AppKeyHint>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          home: Scaffold(
            body: Column(
              children: [
                AppTextField(
                  controller: controller,
                  autofocus: true,
                  readOnly: readOnly,
                  obscureText: obscure,
                  onSubmitted: (_) {},
                  submitLabel: 'Save',
                  selectAllOnFocus: false,
                ),
                AppFocusedEditHints(
                  fallback: const SizedBox(),
                  builder: (value) {
                    hints = value;
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(hints.map((h) => h.keys.single), [
        if (!readOnly) '↩',
        ...expected,
      ]);
      expect(hints.any((h) => h.label.contains('Private')), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Return needs an explicit label and single-line submit owner', (
    tester,
  ) async {
    var hints = <AppKeyHint>[];
    for (final (label, hasSubmit, maxLines, enter) in [
      (null, true, 1, false),
      ('Save', false, 1, false),
      ('Save', true, 2, false),
      ('Save', true, 1, true),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey((label, hasSubmit, maxLines)),
          theme: AppTheme.light(AppPlatformStyle.macos),
          home: Scaffold(
            body: Column(
              children: [
                AppTextField(
                  autofocus: true,
                  submitLabel: label,
                  maxLines: maxLines,
                  onSubmitted: hasSubmit ? (_) {} : null,
                ),
                AppFocusedEditHints(
                  fallback: const SizedBox(),
                  builder: (value) {
                    hints = value;
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(hints.any((h) => h.keys.single == '↩'), enter);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('fields in another focus scope keep this screen fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: Scaffold(
          body: Column(
            children: [
              FocusScope(
                child: AppFocusedEditHints(
                  fallback: const Text('Screen actions'),
                  builder: (_) => const Text('Editing'),
                ),
              ),
              const AppTextField(autofocus: true),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Screen actions'), findsOneWidget);
    expect(find.text('Editing'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dialog field cannot replace a covered screen footer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                AppFocusedEditHints(
                  fallback: const Text('Screen actions'),
                  builder: (_) => const Text('Screen editing'),
                ),
                TextButton(
                  onPressed: () => showAppDialog<void>(
                    context,
                    (_) => const AppDialog(
                      title: 'Dialog',
                      body: AppTextField(autofocus: true),
                      actions: [],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Screen actions'), findsOneWidget);
    expect(find.text('Screen editing'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing a focused form subtree retires its editing hints', (
    tester,
  ) async {
    var editing = true;
    FocusNode? retiredFocus;
    var ignoredWhileStillMounted = false;
    late StateSetter change;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return AppDialog(
                title: 'Connection',
                body: editing
                    ? _RetirementProbe(
                        onDeactivate: () {
                          ignoredWhileStillMounted =
                              retiredFocus?.context?.mounted == true &&
                              attachedFocusContext(retiredFocus) == null;
                        },
                        child: const AppTextField(autofocus: true),
                      )
                    : const Text('Read-only connection'),
                actions: [
                  FilledButton(onPressed: () {}, child: const Text('Save')),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    retiredFocus = FocusManager.instance.primaryFocus!;
    expect(attachedFocusContext(retiredFocus), isNotNull);
    final paste = find.byWidgetPredicate(
      (widget) => widget is AppKeyCap && widget.label == '⌘V',
    );
    expect(paste, findsOneWidget);

    // A form may replace fields while their focus transition is still pending.
    change(() => editing = false);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(ignoredWhileStillMounted, isTrue);
    expect(attachedFocusContext(retiredFocus), isNull);
    expect(paste, findsNothing);

    change(() => editing = true);
    await tester.pumpAndSettle();
    expect(paste, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RetirementProbe extends StatefulWidget {
  const _RetirementProbe({required this.child, required this.onDeactivate});

  final Widget child;
  final VoidCallback onDeactivate;

  @override
  State<_RetirementProbe> createState() => _RetirementProbeState();
}

class _RetirementProbeState extends State<_RetirementProbe> {
  @override
  void deactivate() {
    super.deactivate();
    widget.onDeactivate();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
