import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:component_library/component_library.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:viewer_feature/src/rich_text_preview.dart';
import 'package:viewer_feature/src/viewer_source.dart';

class _Source extends Mock implements ViewerSource {}

Future<void> _open(
  WidgetTester tester,
  String html, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  double fontSize = 15,
  double width = 600,
  double dpr = 1,
  GlobalKey? paintKey,
  ViewerSource? source,
}) async {
  tester.view.physicalSize = Size(width * dpr, 900 * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.of(AppPlatformStyle.macos, brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: paintKey,
          child: RichTextPreview(
            html: html,
            source: source ?? _Source(),
            generation: 1,
            fontSize: fontSize,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _text(String value) => find.text(value, findRichText: true);

ScrollableState _horizontal(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find
          .byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
          )
          .first,
    );

Future<(Uint8List, int)> _pixels(
  WidgetTester tester,
  GlobalKey key,
  double dpr,
) async => (await tester.runAsync(() async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: dpr);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (data!.buffer.asUint8List(), image.width);
  } finally {
    image.dispose();
  }
}))!;

void _expectGrid(
  (Uint8List, int) raster,
  Offset point,
  double dpr,
  Color color, {
  required Color background,
  bool present = true,
}) {
  final (pixels, width) = raster;
  final bg = [
    background.r,
    background.g,
    background.b,
  ].map((v) => v * 255).toList();
  final delta = [
    color.r,
    color.g,
    color.b,
  ].indexed.map((c) => c.$2 * 255 - bg[c.$1]).toList();
  final magnitude = delta.fold(0.0, (sum, v) => sum + v * v);
  var found = false;
  for (
    var y = (point.dy * dpr).floor() - 2;
    y <= (point.dy * dpr).ceil() + 2;
    y++
  ) {
    for (
      var x = (point.dx * dpr).floor() - 2;
      x <= (point.dx * dpr).ceil() + 2;
      x++
    ) {
      final i = (y * width + x) * 4;
      final actual = List.generate(
        3,
        (c) => pixels[i + c] + bg[c] * (1 - pixels[i + 3] / 255),
      );
      // CSS borders may fall between physical pixels. Require visible coverage
      // of the theme's grid color rather than a particular antialiasing phase.
      final coverage =
          List.generate(
            3,
            (c) => (actual[c] - bg[c]) * delta[c],
          ).reduce((a, b) => a + b) /
          magnitude;
      if (coverage >= 0.35 &&
          coverage <= 1.05 &&
          List.generate(
            3,
            (c) => (actual[c] - bg[c] - delta[c] * coverage).abs(),
          ).every((error) => error <= 2)) {
        found = true;
      }
    }
  }
  expect(found, present, reason: 'table grid at $point, DPR $dpr');
}

void main() {
  for (final scale in [1.0, 1.75]) {
    testWidgets('27 spreadsheet columns stay readable at text scale $scale', (
      tester,
    ) async {
      final headers = List.generate(27, (i) => 'Наименование устройства $i');
      await _open(
        tester,
        '<table><tr>${headers.map((h) => '<th><p>$h</p></th>').join()}</tr>'
        '<tr>${List.generate(27, (i) => '<td>Значение $i</td>').join()}</tr></table>',
        scale: scale,
      );
      final first = tester.getSize(_text(headers.first));
      expect(first.width, greaterThanOrEqualTo(100 * scale));
      expect(first.height, lessThan(200 * scale));
      final horizontal = _horizontal(tester);
      expect(horizontal.position.maxScrollExtent, greaterThan(2000 * scale));
      horizontal.position.jumpTo(horizontal.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(_text(headers.last).hitTestable(), findsOneWidget);
      expect(_text(headers.first).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final dpr in [1.0, 2.0]) {
      testWidgets('table grid paints in $brightness at DPR $dpr', (
        tester,
      ) async {
        final key = GlobalKey();
        await _open(
          tester,
          '<table><tr><td><p>A1</p></td><td><p>B1</p></td></tr>'
          '<tr><td><p>A2</p></td><td><p>B2</p></td></tr></table>',
          brightness: brightness,
          dpr: dpr,
          paintKey: key,
        );
        final a1 = tester.getRect(_text('A1'));
        final b1 = tester.getRect(_text('B1'));
        final a2 = tester.getRect(_text('A2'));
        final color = tester.element(_text('A1')).appColors.controlBorder;
        final background = Theme.of(tester.element(_text('A1')))
            .scaffoldBackgroundColor;
        final raster = await _pixels(tester, key, dpr);
        _expectGrid(
          raster,
          Offset((a1.right + b1.left) / 2, a1.center.dy),
          dpr,
          color,
          background: background,
        );
        _expectGrid(
          raster,
          Offset(a1.center.dx, (a1.bottom + a2.top) / 2),
          dpr,
          color,
          background: background,
        );
        _expectGrid(
          raster,
          Offset(a1.left - AppSpacing.sm - 1, a1.center.dy),
          dpr,
          color,
          background: background,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('row spans contribute occupied columns to the next row', (
    tester,
  ) async {
    await _open(
      tester,
      '<table><tr><td rowspan="2">Spanning</td><td>Top</td></tr>'
      '<tr><td>One</td><td>Two</td><td>Three</td><td>Four</td></tr></table>',
      width: 400,
    );
    final scroll = _horizontal(tester).position;
    expect(scroll.maxScrollExtent, greaterThan(200));
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_text('Four').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested tables keep independent horizontal scrolling', (
    tester,
  ) async {
    await _open(
      tester,
      '<table><tr><td>Outer<table><tr>'
      '${List.generate(6, (i) => '<td>Nested $i</td>').join()}'
      '</tr></table></td><td>Sibling</td></tr></table>',
    );
    final scrolls = tester
        .stateList<ScrollableState>(
          find.byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
          ),
        )
        .toList();
    expect(scrolls, hasLength(2));
    expect(scrolls.first.position.maxScrollExtent, 0);
    expect(scrolls.last.position.maxScrollExtent, greaterThan(300));
    scrolls.last.position.jumpTo(scrolls.last.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_text('Nested 5').hitTestable(), findsOneWidget);
    expect(_text('Sibling').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Word grid subdivisions do not inflate merged columns', (
    tester,
  ) async {
    await _open(
      tester,
      '<table><tr><td colspan="18">Title</td></tr><tr>'
      '<td colspan="6">First</td><td colspan="6">Second</td>'
      '<td colspan="6">Third</td></tr></table>',
      width: 400,
    );
    final scroll = _horizontal(tester).position;
    expect(scroll.maxScrollExtent, inExclusiveRange(100, 250));
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_text('Third').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('increasing preview font size also widens columns', (
    tester,
  ) async {
    final source = _Source();
    const html =
        '<table><tr><td>First</td><td>Second</td>'
        '<td>Third</td><td>Last</td></tr></table>';
    await _open(tester, html, source: source, width: 400);
    final initial = tester.getSize(_text('First')).width;
    await _open(tester, html, source: source, width: 400, fontSize: 30);
    expect(tester.getSize(_text('First')).width, greaterThan(initial * 1.8));
    final scroll = _horizontal(tester).position;
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_text('Last').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('column and row spans preserve the grid and readable width', (
    tester,
  ) async {
    final key = GlobalKey();
    await _open(
      tester,
      '<table><tr><td colspan="3"><p>Merged</p></td></tr>'
      '<tr><td rowspan="2"><p>Left</p></td><td><p>Middle</p></td>'
      '<td><p>Right</p></td></tr><tr><td><p>Bottom</p></td>'
      '<td><p>End</p></td></tr></table>',
      width: 320,
      paintKey: key,
    );
    final merged = tester.getRect(_text('Merged'));
    final left = tester.getRect(_text('Left'));
    final middle = tester.getRect(_text('Middle'));
    final bottom = tester.getRect(_text('Bottom'));
    expect(merged.width, greaterThanOrEqualTo(3 * 120 - 18));
    expect(middle.width, greaterThanOrEqualTo(100));
    expect(bottom.left, closeTo(middle.left, 1));
    final dividerX = (left.right + middle.left) / 2;
    final color = tester.element(_text('Left')).appColors.controlBorder;
    final background = Theme.of(tester.element(_text('Left')))
        .scaffoldBackgroundColor;
    final raster = await _pixels(tester, key, 1);
    _expectGrid(
      raster,
      Offset(dividerX, middle.center.dy),
      1,
      color,
      background: background,
    );
    _expectGrid(
      raster,
      Offset(dividerX, merged.center.dy),
      1,
      color,
      background: background,
      present: false,
    );
    _expectGrid(
      raster,
      Offset(left.center.dx, (middle.bottom + bottom.top) / 2),
      1,
      color,
      background: background,
      present: false,
    );
    expect(_horizontal(tester).position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached table grid follows a theme change', (tester) async {
    final key = GlobalKey();
    final source = _Source();
    const html = '<table><tr><td><p>Cell</p></td></tr></table>';
    for (final brightness in Brightness.values) {
      await _open(
        tester,
        html,
        brightness: brightness,
        paintKey: key,
        source: source,
      );
      final rect = tester.getRect(_text('Cell'));
      final color = tester.element(_text('Cell')).appColors.controlBorder;
      final background = Theme.of(tester.element(_text('Cell')))
          .scaffoldBackgroundColor;
      final raster = await _pixels(tester, key, 1);
      _expectGrid(
        raster,
        Offset(rect.left - AppSpacing.sm - 1, rect.center.dy),
        1,
        color,
        background: background,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
