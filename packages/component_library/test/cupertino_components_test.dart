import 'package:component_library/component_library.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  AppPlatformStyle style = AppPlatformStyle.macos,
  Brightness brightness = Brightness.light,
  ScrollBehavior? scrollBehavior,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.of(style, brightness),
      scrollBehavior:
          scrollBehavior ??
          const MaterialScrollBehavior().copyWith(scrollbars: false),
      home: Scaffold(
        body: Center(child: SizedBox(width: 300, height: 400, child: child)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final style in AppPlatformStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$style $brightness: shared controls choose their platform', (
        tester,
      ) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await _pump(
          tester,
          Column(
            children: [
              const AppTextField(hintText: 'Name'),
              const AppSearchField(hintText: 'Search'),
              const AppCheckbox(value: false, mixed: true, onChanged: null),
              const AppSpinner(),
              Expanded(
                child: AppScrollbar(
                  controller: controller,
                  child: ListView.builder(
                    controller: controller,
                    itemExtent: 40,
                    itemCount: 50,
                    itemBuilder: (_, index) => Text('$index'),
                  ),
                ),
              ),
            ],
          ),
          style: style,
          brightness: brightness,
        );
        final mac = style == AppPlatformStyle.macos;
        expect(
          find.byType(CupertinoTextField),
          mac ? findsNWidgets(2) : findsNothing,
        );
        expect(find.byType(TextField), mac ? findsNothing : findsNWidgets(2));
        expect(
          find.byType(CupertinoCheckbox),
          mac ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(CupertinoActivityIndicator),
          mac ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(CupertinoScrollbar),
          mac ? findsOneWidget : findsNothing,
        );
        expect(find.byType(Scrollbar), mac ? findsNothing : findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('a mixed checkbox clicks once and has only one keyboard stop', (
    tester,
  ) async {
    var value = false;
    var mixed = true;
    final changes = <bool>[];
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AppCheckbox(
          value: value,
          mixed: mixed,
          label: 'Option',
          onChanged: (next) => setState(() {
            changes.add(next);
            value = next;
            mixed = false;
          }),
        ),
      ),
    );
    expect(
      tester.widget<CupertinoCheckbox>(find.byType(CupertinoCheckbox)).value,
      isNull,
    );
    await tester.tap(find.byType(CupertinoCheckbox));
    await tester.pump();
    expect(changes, [true]);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(changes, [true, false]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(changes, [true, false], reason: 'Return belongs to the dialog');
  });

  testWidgets(
    'controller changes preserve text without disposing caller resources',
    (
      tester,
    ) async {
      final first = TextEditingController(text: 'report.txt');
      final second = TextEditingController(text: 'summary.txt');
      final focus = FocusNode();
      final current = ValueNotifier<TextEditingController?>(first);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(focus.dispose);
      addTearDown(current.dispose);
      await _pump(
        tester,
        ValueListenableBuilder<TextEditingController?>(
          valueListenable: current,
          builder: (context, controller, _) => AppTextField(
            controller: controller,
            focusNode: focus,
            selectAllOnFocus: false,
          ),
        ),
      );
      current.value = null;
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'report.txt',
      );
      await tester.enterText(find.byType(EditableText), 'draft.txt');
      current.value = second;
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller,
        same(second),
      );
      expect(first.text, 'report.txt');
      await tester.pumpWidget(const SizedBox.shrink());
      first.addListener(() {});
      second.addListener(() {});
      focus.addListener(() {});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search adornments keep keyboard focus', (tester) async {
    final controller = TextEditingController(text: 'query');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await _pump(
      tester,
      AppSearchField(
        hintText: 'Search',
        controller: controller,
        focusNode: focus,
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.tap(
      find.byIcon(AppIcons.cancel),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(focus.hasPrimaryFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('clicking the field bezel focuses its editor', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pump(tester, Center(child: AppTextField(focusNode: focus)));
    final bounds = tester.getRect(find.byType(AppTextField));
    await tester.tapAt(
      bounds.topCenter + const Offset(0, 2),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final axis in Axis.values) {
    testWidgets('the macOS scrollbar drags on $axis', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AppScrollbar(
          controller: controller,
          thumbVisibility: true,
          child: ListView.builder(
            controller: controller,
            scrollDirection: axis,
            itemExtent: 80,
            itemCount: 100,
            itemBuilder: (_, index) => Text('$index'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(AppScrollbar));
      final start = axis == Axis.vertical
          ? bounds.topRight + const Offset(-5, 12)
          : bounds.bottomLeft + const Offset(12, -5);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(
        axis == Axis.vertical ? const Offset(0, 60) : const Offset(60, 0),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(
        controller.offset,
        lessThanOrEqualTo(controller.position.maxScrollExtent),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('explicit scrollbars suppress the automatic duplicate', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      AppScrollbar(
        controller: controller,
        child: ListView.builder(
          controller: controller,
          itemExtent: 40,
          itemCount: 100,
          itemBuilder: (_, index) => Text('$index'),
        ),
      ),
      scrollBehavior: const AppScrollBehavior(),
    );
    expect(find.byType(CupertinoScrollbar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'automatic desktop scrollbars also use the shared Cupertino adapter',
    (
      tester,
    ) async {
      await _pump(
        tester,
        ListView.builder(
          itemExtent: 40,
          itemCount: 100,
          itemBuilder: (_, index) => Text('$index'),
        ),
        scrollBehavior: const AppScrollBehavior(),
      );
      expect(find.byType(CupertinoScrollbar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
