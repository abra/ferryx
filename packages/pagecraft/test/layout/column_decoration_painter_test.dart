import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pagecraft/all_formats.dart';
import 'package:pagecraft/src/layout/column_decoration_painter.dart';

const _red = 0xFFFF0000;
const _blue = 0xFF0000FF;

ColumnDecoration _decoration({
  Rect rect = const Rect.fromLTWH(10, 10, 80, 40),
  int background = 0,
  double width = 4,
  CssBorderStyle style = CssBorderStyle.solid,
  CssEdges<int> color = const CssEdges.all(_red),
  CssCorners<CssRadius> radius = const CssCorners.all(CssRadius.zero),
  CssEdges<double>? widths,
  CssEdges<CssBorderStyle>? styles,
}) => ColumnDecoration(
  rect: rect,
  background: background,
  borderWidth: widths ?? CssEdges.all(width),
  borderStyle: styles ?? CssEdges.all(style),
  borderColor: color,
  radius: radius,
);

/// The decoration painted on a 100×60 transparent canvas, as RGBA bytes.
Future<_Pixels> _paint(WidgetTester tester, ColumnDecoration d) async {
  final recorder = ui.PictureRecorder();
  paintColumnDecoration(Canvas(recorder), d);
  final picture = recorder.endRecording();
  final bytes = await tester.runAsync(() async {
    final image = await picture.toImage(100, 60);
    final data = await image.toByteData();
    image.dispose();
    return data!;
  });
  picture.dispose();
  return _Pixels(bytes!);
}

class _Pixels {
  _Pixels(this._data);

  final ByteData _data;

  /// `0xAARRGGBB` at ([x], [y]).
  int at(int x, int y) {
    final i = (y * 100 + x) * 4;
    final r = _data.getUint8(i);
    final g = _data.getUint8(i + 1);
    final b = _data.getUint8(i + 2);
    final a = _data.getUint8(i + 3);
    return a << 24 | r << 16 | g << 8 | b;
  }
}

void main() {
  testWidgets('a solid border all round and the background under it', (
    tester,
  ) async {
    final p = await _paint(
      tester,
      _decoration(background: 0xFF00FF00),
    );
    expect(p.at(11, 30), _red, reason: 'left border');
    expect(p.at(50, 12), _red, reason: 'top border');
    expect(p.at(50, 30), 0xFF00FF00, reason: 'background inside');
    expect(p.at(5, 5), 0, reason: 'outside');
  });

  testWidgets('edges of different colours meet on the corner diagonal', (
    tester,
  ) async {
    final p = await _paint(
      tester,
      _decoration(
        width: 8,
        color: const CssEdges(_red, _blue, _red, _blue),
      ),
    );
    // Top left corner square 10..18: above the diagonal is the top's.
    expect(p.at(16, 11), _red);
    expect(p.at(11, 16), _blue);
  });

  testWidgets('rounded corners leave the corner empty', (tester) async {
    final p = await _paint(
      tester,
      _decoration(
        background: 0xFF00FF00,
        radius: const CssCorners.all(
          CssRadius(CssLength.px(12), CssLength.px(12)),
        ),
      ),
    );
    expect(p.at(10, 10), 0, reason: 'cut off by the radius');
    expect(p.at(50, 11), _red, reason: 'straight top border');
    expect(p.at(50, 30), 0xFF00FF00);
  });

  testWidgets('dashed and dotted edges have gaps; double has two lines', (
    tester,
  ) async {
    final dashed = await _paint(
      tester,
      _decoration(width: 2, style: CssBorderStyle.dashed),
    );
    final top = [for (var x = 10; x < 90; x++) dashed.at(x, 11)];
    expect(top, contains(_red));
    expect(top, contains(0), reason: 'gaps between dashes');
    expect(dashed.at(10, 11), _red, reason: 'a dash at the start');
    expect(dashed.at(89, 11), _red, reason: 'and at the end');

    final dotted = await _paint(
      tester,
      _decoration(width: 4, style: CssBorderStyle.dotted),
    );
    final dots = [for (var x = 10; x < 90; x++) dotted.at(x, 12)];
    expect(dots, contains(0));
    expect(dots.where((c) => c == _red).length, greaterThan(10));

    final double = await _paint(
      tester,
      _decoration(width: 6, style: CssBorderStyle.double),
    );
    expect(double.at(50, 10), _red, reason: 'outer line');
    expect(double.at(50, 13), 0, reason: 'the gap between');
    expect(double.at(50, 15), _red, reason: 'inner line');
  });

  testWidgets('inset darkens the top and left, outset the bottom and right', (
    tester,
  ) async {
    final inset = await _paint(
      tester,
      _decoration(style: CssBorderStyle.inset),
    );
    expect(inset.at(50, 11), isNot(_red), reason: 'top darker');
    expect(inset.at(50, 48), _red, reason: 'bottom as is');
    final outset = await _paint(
      tester,
      _decoration(style: CssBorderStyle.outset),
    );
    expect(outset.at(50, 11), _red);
    expect(outset.at(50, 48), isNot(_red));
  });

  testWidgets('only drawn edges paint: none, hidden and zero widths skip', (
    tester,
  ) async {
    final p = await _paint(
      tester,
      _decoration(
        widths: const CssEdges(4, 0, 4, 4),
        styles: const CssEdges(
          CssBorderStyle.solid,
          CssBorderStyle.solid,
          CssBorderStyle.none,
          CssBorderStyle.hidden,
        ),
      ),
    );
    expect(p.at(50, 11), _red);
    expect(p.at(50, 48), 0, reason: 'bottom: none');
    expect(p.at(11, 30), 0, reason: 'left: hidden');
    expect(p.at(88, 30), 0, reason: 'right: zero wide');
  });

  testWidgets('every border style, for review', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const styles = [
      CssBorderStyle.solid,
      CssBorderStyle.dashed,
      CssBorderStyle.dotted,
      CssBorderStyle.double,
      CssBorderStyle.groove,
      CssBorderStyle.ridge,
      CssBorderStyle.inset,
      CssBorderStyle.outset,
    ];
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          child: CustomPaint(
            size: const Size(420, 260),
            painter: _Gallery([
              for (final (i, style) in styles.indexed)
                _decoration(
                  rect: Rect.fromLTWH(
                    10 + (i % 4) * 100,
                    10 + (i ~/ 4) * 80,
                    90,
                    60,
                  ),
                  width: 6,
                  style: style,
                  background: 0xFFFFFFFF,
                  color: const CssEdges.all(0xFF3366AA),
                  radius: i.isOdd
                      ? const CssCorners.all(
                          CssRadius(CssLength.px(14), CssLength.px(14)),
                        )
                      : const CssCorners.all(CssRadius.zero),
                ),
              _decoration(
                rect: const Rect.fromLTWH(10, 170, 190, 70),
                width: 10,
                color: const CssEdges(_red, _blue, 0xFF00AA00, 0xFFAA00AA),
                radius: const CssCorners(
                  CssRadius(CssLength.percent(50), CssLength.percent(50)),
                  CssRadius.zero,
                  CssRadius(CssLength.px(20), CssLength.px(10)),
                  CssRadius.zero,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/decoration_styles.png'),
    );
  });
}

class _Gallery extends CustomPainter {
  const _Gallery(this.decorations);

  final List<ColumnDecoration> decorations;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (final d in decorations) {
      paintColumnDecoration(canvas, d);
    }
  }

  @override
  bool shouldRepaint(_Gallery oldDelegate) => false;
}
