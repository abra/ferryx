import 'dart:ui' as ui;

import 'package:component_library/component_library.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoButton;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  AppPlatformStyle style = AppPlatformStyle.macos,
}) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.of(style, brightness),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const options = [('system', 'System'), ('light', 'Light'), ('dark', 'Dark')];
  for (final brightness in Brightness.values) {
    testWidgets(
      '$brightness: the selected appearance is visible and announced',
      (
        tester,
      ) async {
        var selected = 'system';
        await _pump(
          tester,
          StatefulBuilder(
            builder: (context, setState) => AppSegmentedControl<String>(
              options: options,
              value: selected,
              onChanged: (next) => setState(() => selected = next),
            ),
          ),
          brightness: brightness,
        );
        expect(find.byType(CupertinoButton), findsNWidgets(3));
        final colors = AppPalette.of(brightness).colors;
        for (final (value, label) in options) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(selected, value);
          for (final (other, title) in options) {
            final finder = find.text(title);
            expect(
              tester.getSemantics(finder).flagsCollection.isSelected,
              other == selected ? ui.Tristate.isTrue : ui.Tristate.isFalse,
            );
            expect(
              tester.widget<Text>(finder).style!.color,
              other == selected ? colors.onSegmentedSelected : colors.textMuted,
            );
          }
        }
        expect(
          tester.getSize(find.byType(AppSegmentedControl<String>)).height,
          AppMetrics.of(AppPlatformStyle.macos).controlHeight,
        );
      },
    );
  }

  testWidgets('dark appearance paints the selected tile above its track', (
    tester,
  ) async {
    const key = ValueKey('appearance');
    await _pump(
      tester,
      RepaintBoundary(
        key: key,
        child: const AppSegmentedControl<String>(
          options: options,
          value: 'system',
          onChanged: _ignore,
        ),
      ),
      brightness: Brightness.dark,
    );
    final colors = AppPalette.of(Brightness.dark).colors;
    final tile = find.ancestor(
      of: find.text('System'),
      matching: find.byType(CupertinoButton),
    );
    final controlRect = tester.getRect(find.byKey(key));
    final tileRect = tester.getRect(tile).shift(-controlRect.topLeft);
    final image = await tester.runAsync(
      () => captureImage(find.byKey(key).evaluate().single),
    );
    try {
      final data = (await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      Color pixel(int x, int y) {
        final index = (y * image!.width + x) * 4;
        return Color.fromARGB(
          data.getUint8(index + 3),
          data.getUint8(index),
          data.getUint8(index + 1),
          data.getUint8(index + 2),
        );
      }

      expect(
        // Sample the tile's padding, away from label glyphs and rounded edges.
        pixel(tileRect.left.floor() + 4, tileRect.center.dy.floor()),
        colors.segmentedSelected,
      );
      expect(pixel(image!.width ~/ 2, 0), colors.segmentedBackground);
    } finally {
      image?.dispose();
    }
  });

  testWidgets('macOS segments share one Tab stop and keep arrow selection', (
    tester,
  ) async {
    final before = FocusNode();
    final after = FocusNode();
    addTearDown(before.dispose);
    addTearDown(after.dispose);
    var selected = 'system';
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              icon: AppIcons.close,
              tooltip: 'Before',
              focusNode: before,
              onPressed: () {},
            ),
            AppSegmentedControl<String>(
              options: options,
              value: selected,
              onChanged: (next) => setState(() => selected = next),
            ),
            AppIconButton(
              icon: AppIcons.close,
              tooltip: 'After',
              focusNode: after,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    before.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(before.hasFocus, isFalse);
    expect(after.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(selected, 'light');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(after.hasFocus, isTrue);
  });

  for (final style in AppPlatformStyle.values) {
    testWidgets('$style: icon buttons keep their compact platform size', (
      tester,
    ) async {
      await _pump(
        tester,
        AppIconButton(icon: AppIcons.close, tooltip: 'Close', onPressed: () {}),
        style: style,
      );
      expect(
        find.byType(CupertinoButton),
        style == AppPlatformStyle.macos ? findsOneWidget : findsNothing,
      );
      expect(
        tester.getSize(find.byType(AppIconButton)),
        AppMetrics.of(style).iconButtonSize,
      );
    });
  }

  testWidgets('a disabled macOS icon button keeps its announced state', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var calls = 0;
    var enabled = true;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AppIconButton(
          icon: AppIcons.split,
          tooltip: 'Preview',
          selected: true,
          focusNode: focus,
          onPressed: enabled
              ? () => setState(() {
                  calls++;
                  enabled = false;
                })
              : null,
        ),
      ),
    );
    final button = find.byType(AppIconButton);
    final announcedButton = find.bySemanticsLabel('Preview');
    expect(announcedButton, findsOneWidget);
    final enabledState = tester.getSemantics(announcedButton);
    expect(enabledState.label, 'Preview');
    expect(enabledState.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(enabledState.flagsCollection.isToggled, ui.Tristate.isTrue);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final disabledState = tester.getSemantics(announcedButton);
    expect(disabledState.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(disabledState.flagsCollection.isToggled, ui.Tristate.isTrue);
    await tester.tap(button);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets(
    'macOS icon button keeps hover, press, keyboard and cancellation',
    (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var calls = 0;
      await _pump(
        tester,
        AppIconButton(
          icon: AppIcons.close,
          tooltip: 'Close',
          focusNode: focus,
          onPressed: () => calls++,
        ),
      );
      final control = find.byType(AppIconButton);
      Color? fill() {
        final face = find.descendant(
          of: control,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is BoxDecoration,
          ),
        );
        final decoration =
            tester.widget<Container>(face).decoration! as BoxDecoration;
        return decoration.color;
      }

      final colors = AppPalette.of(Brightness.light).colors;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(control));
      await tester.pump();
      expect(fill(), colors.hoverFill);
      await mouse.down(tester.getCenter(control));
      await tester.pump();
      expect(fill(), colors.pressedFill);
      await mouse.moveTo(tester.getBottomRight(control) + const Offset(8, 8));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(calls, 0);
      await mouse.removePointer();
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

void _ignore(String _) {}
