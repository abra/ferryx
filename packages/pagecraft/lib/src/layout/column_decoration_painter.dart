import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import 'column_decoration.dart';
import 'inline_styler.dart';

/// Paints [decoration]'s background and borders as CSS draws them: the
/// background under the border (to the border box, rounded by the
/// corners' radii), then each edge in its own colour and style, meeting
/// its neighbours on the diagonal of the corner.
void paintColumnDecoration(Canvas canvas, ColumnDecoration decoration) {
  final rect = decoration.rect;
  if (rect.width <= 0 || rect.height < 0) return;
  final outer = _outerRRect(rect, decoration.radius);
  if ((decoration.background >>> 24) != 0) {
    final paint = Paint()..color = Color(decoration.background);
    if (outer.isRect) {
      canvas.drawRect(rect, paint);
    } else {
      canvas.drawRRect(outer, paint);
    }
  }
  final w = decoration.borderWidth;
  final edges = [
    for (final side in _Side.values)
      if (_isDrawn(decoration, side)) side,
  ];
  if (edges.isEmpty) return;
  final inner = _innerRect(rect, w);
  final innerRRect = _innerRRect(outer, inner, w);
  final c = decoration.borderColor;
  final s = decoration.borderStyle;
  // One solid colour all round: a ring.
  if (edges.length == 4 &&
      c.top == c.right &&
      c.top == c.bottom &&
      c.top == c.left &&
      [
        s.top,
        s.right,
        s.bottom,
        s.left,
      ].every((x) => x == CssBorderStyle.solid)) {
    canvas.drawDRRect(outer, innerRRect, Paint()..color = Color(c.top));
    return;
  }
  final ring = outer.isRect
      ? null
      : (Path()
          ..fillType = PathFillType.evenOdd
          ..addRRect(outer)
          ..addRRect(innerRRect));
  for (final side in edges) {
    final trapezoid = _trapezoid(side, rect, inner);
    final style = side.of(s);
    final color = side.of(c);
    final width = side.of(w);
    if (style == CssBorderStyle.solid ||
        (style == CssBorderStyle.double && width < 3)) {
      if (ring == null) {
        canvas.drawPath(trapezoid, Paint()..color = Color(color));
        continue;
      }
    }
    canvas.save();
    if (ring != null) canvas.clipPath(ring);
    canvas.clipPath(trapezoid);
    _paintEdge(canvas, side, style, color, width, rect, inner);
    canvas.restore();
  }
}

enum _Side {
  top,
  right,
  bottom,
  left;

  T of<T>(CssEdges<T> edges) => switch (this) {
    top => edges.top,
    right => edges.right,
    bottom => edges.bottom,
    left => edges.left,
  };

  bool get isHorizontal => this == top || this == bottom;

  /// Whether a 3D style shades this edge as the light, lower right one.
  bool get isLowerRight => this == bottom || this == right;
}

bool _isDrawn(ColumnDecoration d, _Side side) {
  final style = side.of(d.borderStyle);
  return side.of(d.borderWidth) > 0 &&
      style != CssBorderStyle.none &&
      style != CssBorderStyle.hidden &&
      (side.of(d.borderColor) >>> 24) != 0;
}

/// The padding box: [rect] less the border widths, never inside out.
Rect _innerRect(Rect rect, CssEdges<double> w) {
  var left = rect.left + w.left;
  var right = rect.right - w.right;
  var top = rect.top + w.top;
  var bottom = rect.bottom - w.bottom;
  if (left > right) left = right = (left + right) / 2;
  if (top > bottom) top = bottom = (top + bottom) / 2;
  return Rect.fromLTRB(left, top, right, bottom);
}

/// [rect] with the corners' radii, percentages of its width and height,
/// scaled down together when adjacent ones would overlap (CSS
/// Backgrounds 3 §5.5).
RRect _outerRRect(Rect rect, CssCorners<CssRadius> radius) {
  if (radius == const CssCorners.all(CssRadius.zero)) {
    return RRect.fromRectAndRadius(rect, Radius.zero);
  }
  Radius resolve(CssRadius r) => Radius.elliptical(
    InlineStyler.px(r.x, rect.width),
    InlineStyler.px(r.y, rect.height),
  );
  var tl = resolve(radius.topLeft);
  var tr = resolve(radius.topRight);
  var br = resolve(radius.bottomRight);
  var bl = resolve(radius.bottomLeft);
  double ratio(double side, double a, double b) =>
      a + b > side && a + b > 0 ? side / (a + b) : 1;
  final f = [
    ratio(rect.width, tl.x, tr.x),
    ratio(rect.width, bl.x, br.x),
    ratio(rect.height, tl.y, bl.y),
    ratio(rect.height, tr.y, br.y),
  ].reduce(math.min);
  if (f < 1) {
    tl *= f;
    tr *= f;
    br *= f;
    bl *= f;
  }
  return RRect.fromRectAndCorners(
    rect,
    topLeft: tl,
    topRight: tr,
    bottomRight: br,
    bottomLeft: bl,
  );
}

/// The padding edge: the outer corners less the borders they join.
RRect _innerRRect(RRect outer, Rect inner, CssEdges<double> w) {
  Radius less(Radius r, double x, double y) =>
      Radius.elliptical(math.max(0, r.x - x), math.max(0, r.y - y));
  return RRect.fromRectAndCorners(
    inner,
    topLeft: less(outer.tlRadius, w.left, w.top),
    topRight: less(outer.trRadius, w.right, w.top),
    bottomRight: less(outer.brRadius, w.right, w.bottom),
    bottomLeft: less(outer.blRadius, w.left, w.bottom),
  );
}

/// The region of [side]'s border: from the outer edge to the inner one,
/// cut at each corner along the line joining the two corners.
Path _trapezoid(_Side side, Rect outer, Rect inner) {
  final points = switch (side) {
    _Side.top => [
      outer.topLeft,
      outer.topRight,
      inner.topRight,
      inner.topLeft,
    ],
    _Side.right => [
      outer.topRight,
      outer.bottomRight,
      inner.bottomRight,
      inner.topRight,
    ],
    _Side.bottom => [
      outer.bottomRight,
      outer.bottomLeft,
      inner.bottomLeft,
      inner.bottomRight,
    ],
    _Side.left => [
      outer.bottomLeft,
      outer.topLeft,
      inner.topLeft,
      inner.bottomLeft,
    ],
  };
  return Path()..addPolygon(points, true);
}

/// The band of [side]: the strip between the outer and inner edges,
/// corner to corner.
Rect _band(_Side side, Rect outer, Rect inner) => switch (side) {
  _Side.top => Rect.fromLTRB(outer.left, outer.top, outer.right, inner.top),
  _Side.right => Rect.fromLTRB(
    inner.right,
    outer.top,
    outer.right,
    outer.bottom,
  ),
  _Side.bottom => Rect.fromLTRB(
    outer.left,
    inner.bottom,
    outer.right,
    outer.bottom,
  ),
  _Side.left => Rect.fromLTRB(outer.left, outer.top, inner.left, outer.bottom),
};

/// Paints one edge's [style] into its band (the canvas is clipped to the
/// edge's region).
void _paintEdge(
  Canvas canvas,
  _Side side,
  CssBorderStyle style,
  int color,
  double width,
  Rect outer,
  Rect inner,
) {
  final band = _band(side, outer, inner);
  final paint = Paint()..color = Color(color);
  switch (style) {
    case CssBorderStyle.double when width >= 3:
      // Two lines a third of the width each, a third apart.
      final third = width / 3;
      canvas
        ..drawRect(_strip(side, band, 0, third), paint)
        ..drawRect(_strip(side, band, width - third, width), paint);
    case CssBorderStyle.dashed:
      _dashes(
        canvas,
        side,
        band,
        width,
        dash: width * 3,
        gap: width * 2,
        paint: paint,
      );
    case CssBorderStyle.dotted:
      _dots(canvas, side, band, width, paint);
    case CssBorderStyle.inset || CssBorderStyle.outset:
      final raised = style == CssBorderStyle.outset;
      paint.color = Color(
        side.isLowerRight != raised ? color : _darker(color),
      );
      canvas.drawRect(band, paint);
    case CssBorderStyle.groove || CssBorderStyle.ridge:
      // The outer half shaded as inset (groove) or outset (ridge), the
      // inner half the other way.
      final raised = style == CssBorderStyle.ridge;
      final outerColor = side.isLowerRight != raised ? color : _darker(color);
      final innerColor = side.isLowerRight != raised ? _darker(color) : color;
      canvas
        ..drawRect(
          _strip(side, band, 0, width / 2),
          Paint()..color = Color(outerColor),
        )
        ..drawRect(
          _strip(side, band, width / 2, width),
          Paint()..color = Color(innerColor),
        );
    default:
      canvas.drawRect(band, paint);
  }
}

/// The part of [band] from [from] to [to] px in from the outer edge.
Rect _strip(_Side side, Rect band, double from, double to) => switch (side) {
  _Side.top => Rect.fromLTRB(
    band.left,
    band.top + from,
    band.right,
    band.top + to,
  ),
  _Side.bottom => Rect.fromLTRB(
    band.left,
    band.bottom - to,
    band.right,
    band.bottom - from,
  ),
  _Side.left => Rect.fromLTRB(
    band.left + from,
    band.top,
    band.left + to,
    band.bottom,
  ),
  _Side.right => Rect.fromLTRB(
    band.right - to,
    band.top,
    band.right - from,
    band.bottom,
  ),
};

/// Dashes along [band], one at each end, the gaps evened out.
void _dashes(
  Canvas canvas,
  _Side side,
  Rect band,
  double width, {
  required double dash,
  required double gap,
  required Paint paint,
}) {
  final length = side.isHorizontal ? band.width : band.height;
  if (length <= 0) return;
  var count = ((length + gap) / (dash + gap)).round();
  while (count > 1 && count * dash > length) {
    count--;
  }
  if (count < 2) {
    canvas.drawRect(band, paint);
    return;
  }
  final spacing = (length - count * dash) / (count - 1);
  for (var i = 0; i < count; i++) {
    final start = i * (dash + spacing);
    canvas.drawRect(
      side.isHorizontal
          ? Rect.fromLTWH(band.left + start, band.top, dash, band.height)
          : Rect.fromLTWH(band.left, band.top + start, band.width, dash),
      paint,
    );
  }
}

/// Round dots as wide as the border along [band], two widths apart,
/// spread so one sits at each end; square below 2 px.
void _dots(Canvas canvas, _Side side, Rect band, double width, Paint paint) {
  final length = side.isHorizontal ? band.width : band.height;
  if (length <= 0) return;
  final count = math.max(1, (length / (width * 2)).round());
  final step = count > 1 ? (length - width) / (count - 1) : 0.0;
  for (var i = 0; i < count; i++) {
    final along = width / 2 + i * step;
    final center = side.isHorizontal
        ? Offset(band.left + along, band.center.dy)
        : Offset(band.center.dx, band.top + along);
    if (width < 2) {
      canvas.drawRect(
        Rect.fromCenter(center: center, width: width, height: width),
        paint,
      );
    } else {
      canvas.drawCircle(center, width / 2, paint);
    }
  }
}

/// The shaded side of a 3D border: two thirds of the colour, as
/// browsers darken it; black gets a dark grey so the shading shows.
int _darker(int argb) {
  final alpha = argb & 0xFF000000;
  int channel(int shift) => ((argb >> shift & 0xFF) * 2 / 3).round();
  if (argb & 0x00FFFFFF == 0) return alpha | 0x00404040;
  return alpha | channel(16) << 16 | channel(8) << 8 | channel(0);
}
