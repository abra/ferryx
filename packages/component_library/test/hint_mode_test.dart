import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('labels are single letters while they suffice, then pairs', () {
    expect(hintLabels(3), ['a', 's', 'd']);
    expect(hintLabels(26).toSet(), hasLength(26));
    final many = hintLabels(40);
    expect(many, hasLength(40));
    expect(many.every((l) => l.length == 2), isTrue);
    expect(many.toSet(), hasLength(40));
  });

  testWidgets('hint mode labels visible targets and runs the typed one', (
    tester,
  ) async {
    final registry = HintRegistry();
    final activated = <String>[];
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: HintScope(
          registry: registry,
          child: Stack(
            children: [
              Column(
                children: [
                  HintTarget(
                    onActivate: () => activated.add('first'),
                    onActivateAlt: () => activated.add('first-alt'),
                    child: const SizedBox(width: 100, height: 30),
                  ),
                  HintTarget(
                    onActivate: () => activated.add('second'),
                    child: const SizedBox(width: 100, height: 30),
                  ),
                  const HintTarget(
                    onActivate: null,
                    child: SizedBox(width: 100, height: 30),
                  ),
                ],
              ),
              Positioned.fill(
                child: HintOverlay(
                  registry: registry,
                  message: 'press a letter',
                  onDismiss: () => dismissed++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    // Reading order: the top target gets "a", the next "s"; the disabled one
    // is not labelled.
    expect(find.text('a'), findsOneWidget);
    expect(find.text('s'), findsOneWidget);
    expect(find.text('d'), findsNothing);
    expect(find.text('press a letter'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(activated, ['first-alt']);
    expect(dismissed, 1);
  });

  testWidgets('Esc cancels and a target outside its viewport is skipped', (
    tester,
  ) async {
    final registry = HintRegistry();
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: HintScope(
          registry: registry,
          child: Stack(
            children: [
              SizedBox(
                height: 50,
                child: ListView(
                  children: [
                    HintTarget(
                      onActivate: () {},
                      child: const SizedBox(height: 30),
                    ),
                    HintTarget(
                      onActivate: () {},
                      child: const SizedBox(height: 30),
                    ),
                    HintTarget(
                      onActivate: () {},
                      child: const SizedBox(height: 30),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: HintOverlay(
                  registry: registry,
                  message: '',
                  onDismiss: () => dismissed++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    // Only the rows that intersect the 50 px viewport are labelled.
    expect(find.text('a'), findsOneWidget);
    expect(find.text('s'), findsOneWidget);
    expect(find.text('d'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(dismissed, 1);
  });

  testWidgets('closing gives the focus back, unless the target took it', (
    tester,
  ) async {
    final registry = HintRegistry();
    final before = FocusNode(debugLabel: 'before');
    final edge = FocusNode(debugLabel: 'edge');
    addTearDown(() {
      before.dispose();
      edge.dispose();
    });
    var shown = false;
    late StateSetter setShown;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: HintScope(
          registry: registry,
          child: StatefulBuilder(
            builder: (context, setState) {
              setShown = setState;
              return Stack(
                children: [
                  Column(
                    children: [
                      Focus(
                        focusNode: before,
                        child: const SizedBox(height: 10),
                      ),
                      HintTarget(
                        onActivate: edge.requestFocus,
                        child: Focus(
                          focusNode: edge,
                          child: const SizedBox(width: 100, height: 30),
                        ),
                      ),
                    ],
                  ),
                  if (shown)
                    Positioned.fill(
                      child: HintOverlay(
                        registry: registry,
                        message: 'press a letter',
                        onDismiss: () => setShown(() => shown = false),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    Future<void> open() async {
      before.requestFocus();
      await tester.pump();
      setShown(() => shown = true);
      await tester.pump();
      await tester.pump();
    }

    await open();
    expect(before.hasFocus, isFalse, reason: 'the overlay takes the keys');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(before.hasFocus, isTrue, reason: 'Esc gives it back');

    await open();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(edge.hasFocus, isTrue, reason: 'the target keeps what it took');
  });

  testWidgets('every pressable control is labelled without registering; a '
      'label presses it; text fields get none; under a dialog only the '
      'dialog is labelled', (tester) async {
    final log = <String>[];
    var checked = false;
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        builder: (context, child) =>
            HintModeHost(message: 'keys', child: child!),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              pageContext = context;
              return Column(
                children: [
                  TextButton(
                    onPressed: () => log.add('button'),
                    child: const Text('Button'),
                  ),
                  Checkbox(
                    value: checked,
                    onChanged: (v) => setState(() => checked = v!),
                  ),
                  const TextField(),
                ],
              );
            },
          ),
        ),
      ),
    );
    Future<List<String>> labels() async {
      HintModeHost.maybeOf(pageContext)!.toggle();
      await tester.pump();
      await tester.pump();
      final overlay = find.byType(HintOverlay);
      return [
        for (final text in tester.widgetList<Text>(
          find.descendant(of: overlay, matching: find.byType(Text)),
        ))
          if (text.data != 'keys') text.data!,
      ];
    }

    // The button and the check box; not the field.
    expect(await labels(), ['a', 's']);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(checked, isTrue, reason: 's pressed the check box');
    expect(find.byType(HintOverlay), findsNothing);

    unawaited(
      showDialog<void>(
        context: pageContext,
        builder: (context) => Dialog(
          child: TextButton(
            onPressed: () => log.add('dialog'),
            child: const Text('In the dialog'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await labels(), ['a'], reason: 'the page under it has none');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(log, ['dialog']);
  });
}
