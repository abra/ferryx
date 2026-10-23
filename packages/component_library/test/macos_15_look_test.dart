import 'dart:convert';
import 'dart:ui' as ui;

import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What macOS 15 draws, measured beside AppKit at one pixel per point:
/// Finder's list, NSTextField, NSPopUpButton, NSMenu, NSAlert and a sheet.
/// macOS 26 keeps its own look where it differs.
void main() {
  final sequoia = AppMetrics.of(AppPlatformStyle.macos);
  final tahoe = AppMetrics.of(
    AppPlatformStyle.macos,
    generation: MacGeneration.tahoe,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    MacGeneration generation = MacGeneration.sequoia,
    AppPlatformStyle style = AppPlatformStyle.macos,
    Brightness brightness = Brightness.light,
  }) => tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: AppTheme.of(style, brightness, generation: generation),
      builder: (context, child) => AppIdentity(icon: _icon, child: child!),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  test('a table\'s highlight spans the row, square; elsewhere and on macOS '
      '26 it is a list row\'s, inset and rounded', () {
    expect(sequoia.tableRowInset, 0);
    expect(sequoia.radius.tableRow, 0);
    expect(sequoia.radius.tableFrame, 0);
    // A sidebar, a menu and a picker keep the inset, rounded highlight.
    expect(sequoia.rowInset, greaterThan(0));
    expect(sequoia.radius.row, greaterThan(0));
    expect(tahoe.tableRowInset, tahoe.rowInset);
    expect(tahoe.radius.tableRow, tahoe.radius.row);
    final windows = AppMetrics.of(AppPlatformStyle.windows);
    expect(windows.tableRowInset, windows.rowInset);
  });

  testWidgets('a text field is square, its text 4 from the edge, its lower '
      'edge shaded; a search field stays rounded', (tester) async {
    await pump(
      tester,
      const SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(),
            AppSearchField(hintText: 'Search'),
          ],
        ),
      ),
    );
    final theme = Theme.of(tester.element(find.byType(TextField).first));
    final border =
        theme.inputDecorationTheme.enabledBorder! as AppOutlineInputBorder;
    expect(border.borderRadius, BorderRadius.zero);
    expect(border.shade, isNotNull);
    final field = tester.getRect(find.byType(TextField).first);
    final text = tester.getRect(find.byType(EditableText).first);
    expect(text.left - field.left, 4);
    final search = tester.widget<TextField>(
      find.descendant(
        of: find.byType(AppSearchField),
        matching: find.byType(TextField),
      ),
    );
    final searchBorder =
        search.decoration!.enabledBorder! as OutlineInputBorder;
    expect(searchBorder.borderRadius, BorderRadius.circular(6));
  });

  testWidgets('a focused text field takes the accent halo outside its '
      'bezel, as an NSTextField', (tester) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(
      tester,
      const SizedBox(width: 300, child: TextField(autofocus: true)),
    );
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byType(TextField));
    final above = await tester.runAsync(() async {
      final image = await captureImage(
        find.byType(Scaffold).evaluate().single,
      );
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final i =
          ((field.top.round() - 2) * image.width + field.center.dx.round()) * 4;
      return Color.fromARGB(
        255,
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      );
    });
    // The page is white; two points above the bezel the ring is blue.
    expect(above!.b, greaterThan(above.r + 0.2));
  });

  testWidgets('a push button\'s bezel is shaded below on macOS 15 only', (
    tester,
  ) async {
    OutlinedBorder shapeOf(ThemeData theme) =>
        theme.outlinedButtonTheme.style!.shape!.resolve(const {})!;
    expect(
      shapeOf(AppTheme.of(AppPlatformStyle.macos, Brightness.light)),
      isA<AppBezelBorder>(),
    );
    expect(
      shapeOf(
        AppTheme.of(
          AppPlatformStyle.macos,
          Brightness.light,
          generation: MacGeneration.tahoe,
        ),
      ),
      isNot(isA<AppBezelBorder>()),
    );
  });

  test('a sheet darkens the window behind it as macOS does', () {
    Color barrier(Brightness b) =>
        AppTheme.of(AppPlatformStyle.macos, b).dialogTheme.barrierColor!;
    expect(barrier(Brightness.light).a, closeTo(0.19, 0.005));
    expect(barrier(Brightness.dark).a, closeTo(0.28, 0.005));
  });

  testWidgets('a pop-up button ends in the accent\'s cap with white '
      'chevrons; on macOS 26 in bare chevrons', (tester) async {
    Future<Color?> chevrons(MacGeneration generation) async {
      await pump(
        tester,
        AppPopupButton<int>(
          value: 1,
          items: const [(1, 'Ask'), (2, 'Overwrite')],
          onChanged: (_) {},
        ),
        generation: generation,
      );
      return tester
          .widget<Icon>(
            find.byWidgetPredicate(
              (w) => w is Icon && w.icon == AppIcons.chevronsUpDown,
            ),
          )
          .color;
    }

    final colors = AppTheme.of(
      AppPlatformStyle.macos,
      Brightness.light,
    ).extension<AppColorsExt>()!;
    expect(await chevrons(MacGeneration.sequoia), colors.onAccent);
    expect(await chevrons(MacGeneration.tahoe), colors.textMuted);
  });

  group('a menu', () {
    Future<void> open(
      WidgetTester tester,
      List<AppMenuEntry<String>> entries, {
      MacGeneration generation = MacGeneration.sequoia,
    }) async {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppMenu<String>(
              context: context,
              anchor: const Offset(100, 100) & Size.zero,
              entries: entries,
            ),
            child: const Text('menu'),
          ),
        ),
        generation: generation,
      );
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
    }

    double labelLeft(WidgetTester tester, String label) =>
        tester.getTopLeft(find.text(label)).dx;

    testWidgets('keeps a check column only while an item is checked, its '
        'labels 11 further in', (tester) async {
      await open(tester, const [
        AppMenuAction(value: 'a', label: 'Short', checked: false),
        AppMenuAction(value: 'b', label: 'Wide', checked: false),
      ]);
      final bare = labelLeft(tester, 'Short');
      expect(
        tester
            .widget<AppMenuItem>(find.widgetWithText(AppMenuItem, 'Short'))
            .checked,
        isNull,
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await open(tester, const [
        AppMenuAction(value: 'a', label: 'Short', checked: false),
        AppMenuAction(value: 'b', label: 'Wide', checked: true),
      ]);
      expect(
        labelLeft(tester, 'Short') - bare,
        sequoia.menuCheckWidth - sequoia.menuCheckPull,
      );
    });

    testWidgets('shows no symbols on macOS 15, and them on macOS 26', (
      tester,
    ) async {
      const entries = [
        AppMenuAction(value: 'a', label: 'Copy', icon: AppIcons.copy),
        AppMenuAction(value: 'b', label: 'Rename'),
      ];
      await open(tester, entries);
      expect(find.byIcon(AppIcons.copy), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await open(tester, entries, generation: MacGeneration.tahoe);
      expect(find.byIcon(AppIcons.copy), findsOneWidget);
    });
  });

  group('an alert', () {
    Widget dialog({bool alert = true}) => AppDialog(
      title: 'Delete?',
      alert: alert,
      actions: [
        OutlinedButton(onPressed: () {}, child: const Text('No')),
        FilledButton(onPressed: () {}, child: const Text('Yes')),
      ],
    );

    final icon = find.byWidgetPredicate((w) => w is Image && w.image == _icon);

    testWidgets('carries the app\'s icon, 64 square, 20 above its title', (
      tester,
    ) async {
      await pump(tester, dialog());
      expect(tester.getSize(icon), const Size(64, 64));
      expect(
        tester.getRect(find.text('Delete?')).top - tester.getRect(icon).bottom,
        20,
      );
    });

    testWidgets('a sheet does not, nor an alert on another desktop', (
      tester,
    ) async {
      await pump(tester, dialog(alert: false));
      expect(icon, findsNothing);
      await pump(tester, dialog(), style: AppPlatformStyle.gnome);
      expect(icon, findsNothing);
    });
  });
}

/// One transparent pixel.
final _icon = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  ),
);
