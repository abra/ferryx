import 'package:component_library/component_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const labels = AppGuidanceLabels(
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
  Finder cap(String label) => find.byWidgetPredicate(
    (widget) => widget is AppKeyCap && widget.label == label,
  );

  Future<void> open(
    WidgetTester tester, {
    required WidgetBuilder dialog,
    AppPlatformStyle style = AppPlatformStyle.macos,
    double scale = 1,
    bool guidance = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(style),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: guidance
              ? AppGuidanceScope(labels: labels, child: child!)
              : child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppDialog<void>(context, dialog),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a focused option shows Space and keeps native tab order', (
    tester,
  ) async {
    var checked = false;
    var saved = false;
    await open(
      tester,
      guidance: true,
      dialog: (_) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: 'Options',
          body: AppCheckbox(
            value: checked,
            onChanged: (value) => setState(() => checked = value),
            label: 'Keep attributes',
          ),
          actions: [
            FilledButton(
              onPressed: () => saved = true,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(cap('Space'), findsOneWidget);
    expect(cap('↩'), findsOneWidget);
    expect(cap('Tab'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(checked, isTrue);
    expect(saved, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<FilledButton>(),
      isNotNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom guidance replaces the automatic editor guidance', (
    tester,
  ) async {
    await open(
      tester,
      guidance: true,
      dialog: (_) => const AppDialog(
        title: 'Search results',
        body: AppTextField(autofocus: true),
        guidance: AppKeyHints([
          AppKeyHint(['↓'], 'Go to results'),
        ]),
        actions: [],
      ),
    );
    expect(cap('↓'), findsOneWidget);
    expect(cap('⌘V'), findsNothing);
    expect(cap('Tab'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a field can own Tab completion without a traversal promise', (
    tester,
  ) async {
    final controller = TextEditingController(text: '/home/do');
    addTearDown(controller.dispose);
    await open(
      tester,
      guidance: true,
      dialog: (_) => AppDialog(
        title: 'Destination',
        body: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.tab) {
              controller.text = '/home/docs/';
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: AppTextField(controller: controller, autofocus: true),
        ),
        actions: [FilledButton(onPressed: () {}, child: const Text('Copy'))],
      ),
    );
    final fieldFocus = FocusManager.instance.primaryFocus;
    expect(cap('Tab'), findsNothing);
    expect(cap('⌘V'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, '/home/docs/');
    expect(FocusManager.instance.primaryFocus, same(fieldFocus));
    expect(cap('Tab'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a popup hides covered guidance without resizing the dialog', (
    tester,
  ) async {
    await open(
      tester,
      guidance: true,
      dialog: (_) => AppDialog(
        title: 'Find',
        body: AppPopupButton<int>(
          value: 0,
          items: const [(0, 'All files'), (1, 'Documents')],
          onChanged: (_) {},
        ),
        guidance: const AppKeyHints([
          AppKeyHint(['↓'], 'Browse matches'),
        ]),
        actions: const [],
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final dialog = find.byType(AppDialog);
    final before = tester.getRect(dialog);
    final guidance = find.descendant(of: dialog, matching: cap('↓'));
    expect(guidance, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(guidance, findsNothing);
    expect(tester.getRect(dialog), before);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(guidance, findsOneWidget);
    expect(tester.getRect(dialog), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom keyboard surfaces can omit generic guidance', (
    tester,
  ) async {
    await open(
      tester,
      guidance: true,
      dialog: (_) => AppDialog(
        title: 'Record shortcut',
        showGuidance: false,
        body: const Text('Press a shortcut'),
        actions: [FilledButton(onPressed: () {}, child: const Text('Save'))],
      ),
    );
    expect(find.byType(AppKeyCap), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a localized search describes clear before dismiss', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'query');
    addTearDown(controller.dispose);
    await open(
      tester,
      guidance: true,
      dialog: (_) => AppDialog(
        title: 'Find',
        body: AppSearchField(
          hintText: 'Search',
          controller: controller,
          autofocus: true,
        ),
        actions: const [],
      ),
    );
    expect(cap('Esc'), findsOneWidget);
    expect(find.text('Clear', findRichText: true), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Clear', findRichText: true), findsNothing);
    expect(cap('Esc'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the guidance preference hides automatic dialog hints', (
    tester,
  ) async {
    await open(
      tester,
      dialog: (_) => const AppGuidanceScope(
        labels: labels,
        enabled: false,
        child: AppDialog(
          title: 'Edit',
          body: AppTextField(autofocus: true),
          actions: [],
        ),
      ),
    );
    expect(find.byType(AppKeyCap), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final enabled in [true, false]) {
    testWidgets('Return guidance matches an enabled=$enabled default', (
      tester,
    ) async {
      var submitted = false;
      await open(
        tester,
        dialog: (_) => AppDialog(
          title: 'Create',
          body: const Text('Choose an action'),
          actions: [
            OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
            FilledButton(
              onPressed: enabled ? () => submitted = true : null,
              child: const Text('Create'),
            ),
          ],
        ),
      );
      expect(cap('↩'), enabled ? findsOneWidget : findsNothing);
      expect(cap('Esc'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submitted, enabled);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a destructive default describes and invokes cancellation', (
    tester,
  ) async {
    var cancelled = false;
    var deleted = false;
    await open(
      tester,
      dialog: (_) => AppDialog(
        title: 'Delete',
        destructive: true,
        body: const Text('Files'),
        actions: [
          OutlinedButton(
            onPressed: () => cancelled = true,
            child: const Text('Keep files'),
          ),
          AppDestructiveButton(
            label: 'Delete',
            onPressed: () => deleted = true,
          ),
        ],
      ),
    );
    expect(cap('↩'), findsOneWidget);
    final enterRow = find
        .ancestor(of: cap('↩'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(
        of: enterRow,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == 'Keep files',
        ),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(cancelled, isTrue);
    expect(deleted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unlabelled field owns Return without a default promise', (
    tester,
  ) async {
    await open(
      tester,
      dialog: (_) => AppDialog(
        title: 'Edit',
        body: AppTextField(autofocus: true, onSubmitted: (_) {}),
        actions: [FilledButton(onPressed: () {}, child: const Text('Save'))],
      ),
    );
    expect(cap('↩'), findsNothing);
    expect(cap('⌘V'), findsOneWidget);
    expect(cap('Esc'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<FilledButton>(),
      isNotNull,
    );
    expect(cap('↩'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search clears before Escape advertises dismissing the dialog', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'query');
    addTearDown(controller.dispose);
    await open(
      tester,
      dialog: (_) => AppDialog(
        title: 'Find',
        body: AppSearchField(
          hintText: 'Search',
          controller: controller,
          autofocus: true,
        ),
        actions: const [],
      ),
    );
    expect(cap('Esc'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(find.byType(AppDialog), findsOneWidget);
    expect(cap('Esc'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a guarded busy dialog does not promise Escape will close it', (
    tester,
  ) async {
    await open(
      tester,
      dialog: (_) => const PopScope<void>(
        canPop: false,
        child: AppDialog(
          title: 'Working',
          body: Text('Please wait'),
          actions: [],
        ),
      ),
    );
    expect(cap('Esc'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a newly mounted dialog ignores the outgoing field focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('outgoing'),
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: const Scaffold(body: AppTextField(autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('incoming'),
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: Scaffold(
          body: AppDialog(
            title: 'Next screen',
            body: const Text('Ready'),
            actions: [
              FilledButton(onPressed: () {}, child: const Text('Continue')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(cap('↩'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final style in AppPlatformStyle.values) {
    testWidgets('$style low form keeps its size across editing states', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(700, 480)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await open(
        tester,
        style: style,
        scale: 1.5,
        dialog: (_) => AppDialog(
          title: 'Create a folder',
          body: AppTextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (_) {},
            submitLabel: 'Create',
          ),
          actions: [
            FilledButton(onPressed: () {}, child: const Text('Create')),
          ],
        ),
      );
      final before = tester.getRect(find.byType(Dialog));
      controller.text = 'A folder';
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 8,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(Dialog)), before);
      expect(tester.getRect(find.byType(FilledButton)).bottom, lessThan(480));
      expect(find.text('Create').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
