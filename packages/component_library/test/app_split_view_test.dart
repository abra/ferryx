import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final axis in Axis.values) {
    testWidgets('$axis: expanding panes preserves state and releases focus', (
      tester,
    ) async {
      final expanded = ValueNotifier<AppSplitPane?>(null);
      final fraction = ValueNotifier(.5);
      final focus = FocusNode();
      addTearDown(expanded.dispose);
      addTearDown(fraction.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          home: Center(
            child: SizedBox(
              width: 600,
              height: 400,
              child: ListenableBuilder(
                listenable: Listenable.merge([expanded, fraction]),
                builder: (context, _) => AppSplitView(
                  axis: axis,
                  fraction: fraction.value,
                  expandedPane: expanded.value,
                  handle: const SizedBox(),
                  first: const SizedBox.expand(key: ValueKey('first')),
                  second: _Counter(focus: focus),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('0'));
      focus.requestFocus();
      await tester.pump();
      final extent = axis == Axis.horizontal ? 600.0 : 400.0;
      double firstExtent() {
        final size = tester.getSize(find.byKey(const ValueKey('first')));
        return axis == Axis.horizontal ? size.width : size.height;
      }

      final initial = firstExtent();
      expanded.value = AppSplitPane.first;
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await tester.pump(const Duration(milliseconds: 40));
      expect(firstExtent(), inExclusiveRange(initial, extent));
      await tester.pumpAndSettle();
      expect(firstExtent(), extent);
      expect(find.text('1'), findsNothing);
      expect(find.text('1', skipOffstage: false), findsOneWidget);
      expanded.value = null;
      await tester.pumpAndSettle();
      expect(firstExtent(), initial);
      expect(find.text('1'), findsOneWidget);
      fraction.value = .25;
      await tester.pump();
      expect(firstExtent(), ((extent - 1) * .25).roundToDouble());
      expanded.value = AppSplitPane.second;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expanded.value = AppSplitPane.first;
      await tester.pumpAndSettle();
      expect(firstExtent(), extent);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Counter extends StatefulWidget {
  const _Counter({required this.focus});
  final FocusNode focus;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int value = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    focusNode: widget.focus,
    onPressed: () => setState(() => value++),
    child: Text('$value'),
  );
}
