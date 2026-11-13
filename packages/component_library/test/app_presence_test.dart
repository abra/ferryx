import 'package:component_library/component_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    ValueNotifier<bool> shown, {
    Widget child = const SizedBox(
      key: ValueKey('content'),
      width: 100,
      height: 80,
    ),
    bool reduced = false,
    bool maintainState = false,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(AppPlatformStyle.macos),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: shown,
            builder: (context, visible, _) => AppPresence(
              key: const ValueKey('presence'),
              visible: visible,
              resize: true,
              maintainState: maintainState,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('reveals and collapses, releasing closed content', (
    tester,
  ) async {
    final shown = ValueNotifier(false);
    addTearDown(shown.dispose);
    await pump(tester, shown);
    final surface = find.byKey(const ValueKey('presence'));
    expect(tester.getSize(surface).height, 0);
    shown.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getSize(surface).height, inExclusiveRange(0, 80));
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).height, 80);
    shown.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(tester.getSize(surface).height, inExclusiveRange(0, 80));
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).height, 0);
    expect(find.byKey(const ValueKey('content')), findsNothing);
  });

  testWidgets('closing blocks focus and pointer input before the fade ends', (
    tester,
  ) async {
    final shown = ValueNotifier(true);
    final focus = FocusNode();
    addTearDown(shown.dispose);
    addTearDown(focus.dispose);
    var taps = 0;
    await pump(
      tester,
      shown,
      child: SizedBox(
        width: 160,
        height: 80,
        child: TextButton(
          focusNode: focus,
          autofocus: true,
          onPressed: () => taps++,
          child: const Text('action'),
        ),
      ),
    );
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    shown.value = false;
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    await tester.tap(find.text('action'), warnIfMissed: false);
    expect(taps, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('reversing an entrance does not jump to a completed state', (
    tester,
  ) async {
    final shown = ValueNotifier(false);
    addTearDown(shown.dispose);
    await pump(tester, shown);
    shown.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final surface = find.byKey(const ValueKey('presence'));
    final before = tester.getSize(surface).height;
    shown.value = false;
    await tester.pump();
    expect(tester.getSize(surface).height, before);
    await tester.pump(const Duration(milliseconds: 15));
    expect(tester.getSize(surface).height, lessThan(before));
    shown.value = true;
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).height, 80);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion settles immediately, including a running reveal',
    (
      tester,
    ) async {
      final shown = ValueNotifier(false);
      addTearDown(shown.dispose);
      await pump(tester, shown);
      shown.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await pump(tester, shown, reduced: true);
      final surface = find.byKey(const ValueKey('presence'));
      expect(tester.getSize(surface).height, 80);
      shown.value = false;
      await tester.pump();
      expect(tester.getSize(surface).height, 0);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('maintained content survives hiding with its state', (
    tester,
  ) async {
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await pump(tester, shown, child: const _Counter(), maintainState: true);
    await tester.tap(find.text('0'));
    await tester.pump();
    shown.value = false;
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNothing);
    expect(find.text('1', skipOffstage: false), findsOneWidget);
    shown.value = true;
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a moved GlobalKey is released before the other host mounts it', (
    tester,
  ) async {
    final onRight = ValueNotifier(false);
    final key = GlobalKey();
    addTearDown(onRight.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: onRight,
          builder: (context, right, _) => Row(
            children: [
              for (final side in [false, true])
                Expanded(
                  child: AppPresence(
                    retainOnExit: false,
                    child: side == right ? _Counter(key: key) : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('0'));
    await tester.pump();
    onRight.value = true;
    await tester.pump();
    onRight.value = false;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int value = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => value++),
    child: Text('$value'),
  );
}
