import 'dart:ui' as ui;

import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// What [snapToPixels] makes of [rect] on a canvas [setUp] transformed.
Rect _snapped(void Function(Canvas canvas) setUp, Rect rect) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  setUp(canvas);
  final out = snapToPixels(canvas, rect);
  recorder.endRecording().dispose();
  return out;
}

void _pixelRatio(WidgetTester tester, double ratio) {
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
}

const _width = 60;

/// The red channel along row [y] from [from] to [to], of [child] drawn
/// black on white with its top left at (10.5, 8): half a pixel across.
Future<List<int>> _rowAcross(
  WidgetTester tester,
  Widget child, {
  required int y,
  required int from,
  required int to,
}) async {
  tester.view.physicalSize = const Size(60, 40);
  _pixelRatio(tester, 1);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 10.5, top: 8),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final data = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!;
  }))!;
  return [for (var x = from; x <= to; x++) data.getUint8((y * _width + x) * 4)];
}

const _black = BorderSide(color: Color(0xFF000000));
const _box = SizedBox(width: 20, height: 20);

void main() {
  group('snapToPixels', () {
    testWidgets('grows a rect between pixels outward to the pixels', (
      tester,
    ) async {
      _pixelRatio(tester, 1);
      expect(
        _snapped(
          (canvas) => canvas.translate(10.5, 3.25),
          const Rect.fromLTWH(0, 0, 20, 10),
        ),
        const Rect.fromLTRB(-0.5, -0.25, 20.5, 10.75),
      );
      expect(
        _snapped((_) {}, const Rect.fromLTWH(4, 5, 6, 7)),
        const Rect.fromLTWH(4, 5, 6, 7),
        reason: 'on pixels already',
      );
      expect(
        _snapped((_) {}, const Rect.fromLTRB(4.004, 5, 9.997, 7)),
        const Rect.fromLTRB(4, 5, 10, 7),
        reason: 'a rounding error off a pixel is on it',
      );
      expect(
        _snapped(
          (canvas) => canvas.rotate(0.3),
          const Rect.fromLTWH(0.5, 0.5, 4, 4),
        ),
        const Rect.fromLTWH(0.5, 0.5, 4, 4),
        reason: 'turned, there are no pixels to snap to',
      );
    });

    testWidgets('at two pixels per point, a half point is a pixel', (
      tester,
    ) async {
      _pixelRatio(tester, 2);
      expect(
        _snapped(
          (canvas) => canvas.translate(10.25, 0),
          const Rect.fromLTWH(0, 0, 10.5, 4),
        ),
        const Rect.fromLTRB(-0.25, 0, 10.75, 4),
      );
      expect(
        _snapped((_) {}, const Rect.fromLTWH(0.5, 1.5, 3, 2)),
        const Rect.fromLTWH(0.5, 1.5, 3, 2),
      );
    });
  });

  group('the borders keep snapping', () {
    test('through copyWith, scale and a blend', () {
      const shape = AppRoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      );
      expect(
        shape.copyWith(side: _black),
        isA<AppRoundedRectangleBorder>(),
        reason: 'a button gives its shape the side so',
      );
      expect(shape.scale(2), isA<AppRoundedRectangleBorder>());
      expect(
        OutlinedBorder.lerp(shape, shape.copyWith(side: _black), 0.5),
        isA<AppRoundedRectangleBorder>(),
      );
      expect(
        OutlinedBorder.lerp(const RoundedRectangleBorder(), shape, 0.5),
        isA<AppRoundedRectangleBorder>(),
      );
      const field = AppOutlineInputBorder();
      expect(
        field.copyWith(borderRadius: BorderRadius.circular(9)),
        isA<AppOutlineInputBorder>(),
        reason: 'a search field rounds it so',
      );
      expect(
        ShapeBorder.lerp(field, field.copyWith(borderSide: _black), 0.5),
        isA<AppOutlineInputBorder>(),
        reason: 'the decorator blends into the focused border',
      );
      expect(
        const AppStadiumBorder().copyWith(side: _black),
        isA<AppStadiumBorder>(),
      );
      expect(AppBorder.all().scale(2), isA<AppBorder>());
    });

    test('the theme\'s fields, buttons, dialogs and menus snap', () {
      for (final style in AppPlatformStyle.values) {
        for (final theme in [AppTheme.light(style), AppTheme.dark(style)]) {
          final fields = theme.inputDecorationTheme;
          for (final border in [
            fields.border,
            fields.enabledBorder,
            fields.focusedBorder,
            fields.errorBorder,
          ]) {
            expect(border, isA<SnapsToPixels>(), reason: '$style');
          }
          expect(theme.dialogTheme.shape, isA<SnapsToPixels>());
          expect(theme.popupMenuTheme.shape, isA<SnapsToPixels>());
          for (final buttons in [
            theme.filledButtonTheme.style,
            theme.outlinedButtonTheme.style,
            theme.textButtonTheme.style,
          ]) {
            expect(
              buttons!.shape!.resolve(const {}),
              isA<SnapsToPixels>(),
              reason: '$style',
            );
          }
        }
      }
    });
  });

  group('half a pixel across, on a screen of one pixel per point', () {
    // Unsnapped, the edge at 10.5 would grey two columns at half strength.
    testWidgets('a box\'s border lands whole on one column', (tester) async {
      expect(
        await _rowAcross(
          tester,
          DecoratedBox(
            decoration: BoxDecoration(border: AppBorder.all()),
            child: _box,
          ),
          y: 18,
          from: 9,
          to: 12,
        ),
        [0xFF, 0x00, 0xFF, 0xFF],
      );
    });

    testWidgets('so does a material\'s edge: a button, a dialog', (
      tester,
    ) async {
      expect(
        await _rowAcross(
          tester,
          const Material(
            color: Color(0xFFFFFFFF),
            shape: AppRoundedRectangleBorder(side: _black),
            child: _box,
          ),
          y: 18,
          from: 9,
          to: 12,
        ),
        [0xFF, 0x00, 0xFF, 0xFF],
      );
    });

    testWidgets('and a field\'s outline', (tester) async {
      expect(
        await _rowAcross(
          tester,
          const InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              contentPadding: EdgeInsets.zero,
              // The theme's own is the enabled one.
              enabledBorder: AppOutlineInputBorder(
                borderSide: _black,
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: _box,
          ),
          y: 18,
          from: 9,
          to: 12,
        ),
        [0xFF, 0x00, 0xFF, 0xFF],
      );
    });
  });

  group('PixelSnap', () {
    testWidgets('paints its child on the nearest pixel, and is hit there', (
      tester,
    ) async {
      _pixelRatio(tester, 1);
      final child = GlobalKey();
      var taps = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 10.5, top: 4.25),
              child: PixelSnap(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: SizedBox(key: child, width: 20, height: 10),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byType(PixelSnap)),
        const Offset(10.5, 4.25),
      );
      expect(
        tester.getTopLeft(find.byKey(child)),
        const Offset(11, 4),
        reason: 'what is anchored to the child sees where it is drawn',
      );
      await tester.tapAt(const Offset(10.8, 9));
      expect(taps, 0, reason: 'left of the child as drawn');
      await tester.tapAt(const Offset(20, 9));
      expect(taps, 1);
    });
  });

  group('PixelRow', () {
    testWidgets('rows of text heights land on pixels and keep touching, '
        'scrolled by a fraction too', (tester) async {
      _pixelRatio(tester, 1);
      tester.view.physicalSize = const Size(200, 300);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const heights = [17.3, 20.6, 18.94, 33.5];
      final keys = [for (var i = 0; i < heights.length; i++) GlobalKey()];
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ListView.builder(
              controller: controller,
              addRepaintBoundaries: false,
              padding: const EdgeInsets.only(top: 3.25),
              itemCount: heights.length + 20,
              itemBuilder: pixelRows(
                (context, index) => SizedBox(
                  key: index < heights.length ? keys[index] : null,
                  height: index < heights.length ? heights[index] : 30,
                ),
              ),
            ),
          ),
        ),
      );
      void expectOnPixels(String when) {
        for (var i = 0; i < heights.length; i++) {
          final row = tester.getRect(find.byKey(keys[i]));
          expect(row.top, row.top.roundToDouble(), reason: '$when: row $i');
          if (i > 0) {
            final above = tester.getRect(find.byKey(keys[i - 1]));
            expect(
              row.top - above.top,
              heights[i - 1].ceilToDouble(),
              reason: '$when: row $i follows a whole-pixel row',
            );
          }
        }
      }

      expectOnPixels('at rest');
      controller.jumpTo(3.4);
      await tester.pump();
      expectOnPixels('scrolled by a fraction');
    });
  });

  group('CentredOnPixels', () {
    testWidgets('a centred surface lands on whole pixels, and follows its '
        'content as it grows and shrinks', (tester) async {
      _pixelRatio(tester, 1);
      tester.view.physicalSize = const Size(301, 201);
      var rows = 2;
      late StateSetter setRows;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Center(
            child: CentredOnPixels(
              key: const Key('surface'),
              child: StatefulBuilder(
                builder: (context, setState) {
                  setRows = setState;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < rows; i++)
                        const SizedBox(width: 100.4, height: 20.3),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      void expectWhole(String when, double content) {
        final surface = tester.getRect(find.byKey(const Key('surface')));
        expect(surface.left, surface.left.roundToDouble(), reason: when);
        expect(surface.top, surface.top.roundToDouble(), reason: when);
        expect(surface.height - content, inInclusiveRange(0, 2), reason: when);
      }

      expectWhole('two rows', 40.6);
      setRows(() => rows = 5);
      await tester.pump();
      expectWhole('grown to five', 101.5);
      setRows(() => rows = 1);
      await tester.pump();
      expectWhole('shrunk to one', 20.3);
    });
  });
}
