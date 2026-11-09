import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import 'column_scroller.dart';
import 'inline_styler.dart';

/// A block's background and borders, at its border box.
class ColumnDecoration {
  const ColumnDecoration({
    required this.rect,
    required this.background,
    required this.borderWidth,
    required this.borderStyle,
    required this.borderColor,
    this.radius = const CssCorners.all(CssRadius.zero),
    this.backgroundImage,
    this.scroller,
  });

  final Rect rect;

  /// `0xAARRGGBB`; transparent when none.
  final int background;
  final CssEdges<double> borderWidth;
  final CssEdges<CssBorderStyle> borderStyle;
  final CssEdges<int> borderColor;

  /// The corners' radii; percentages are of [rect]'s width and height.
  final CssCorners<CssRadius> radius;

  /// Drawn over [background] inside the borders ([backgroundTiles]).
  final CssBackgroundImage? backgroundImage;

  /// The part of the column that scrolls it sideways, if any: [rect] is
  /// where it is with the scroll at 0.
  final ColumnScroller? scroller;

  /// The padding box, where a background image is placed and drawn.
  Rect get paddingBox => Rect.fromLTRB(
    rect.left + borderWidth.left,
    rect.top + borderWidth.top,
    rect.right - borderWidth.right,
    rect.bottom - borderWidth.bottom,
  );

  /// The same decoration over [rect].
  ColumnDecoration at(Rect rect) => ColumnDecoration(
    rect: rect,
    background: background,
    borderWidth: borderWidth,
    borderStyle: borderStyle,
    borderColor: borderColor,
    radius: radius,
    backgroundImage: backgroundImage,
    scroller: scroller,
  );

  /// The same decoration, scrolled by [scroller].
  ColumnDecoration inScroller(ColumnScroller scroller) => ColumnDecoration(
    rect: rect,
    background: background,
    borderWidth: borderWidth,
    borderStyle: borderStyle,
    borderColor: borderColor,
    radius: radius,
    backgroundImage: backgroundImage,
    scroller: scroller,
  );
}

/// Where [image] is drawn in [area], the padding box, for an image of
/// [intrinsic] size (CSS Backgrounds 3 §3.6–§3.9): sized by its fit or
/// its set width and height (one of them keeping the ratio), placed by
/// its position (a percentage puts that point of the image at that point
/// of the box), repeated across and down where it repeats; only the
/// tiles that reach [visible], at most [limit] of them.
List<Rect> backgroundTiles(
  CssBackgroundImage image,
  Size intrinsic,
  Rect area, {
  Rect? visible,
  int limit = 400,
}) {
  if (area.isEmpty || intrinsic.isEmpty) return const [];
  final ratio = intrinsic.width / intrinsic.height;
  final Size size;
  switch (image.fit) {
    case CssBackgroundFit.cover || CssBackgroundFit.contain:
      final sx = area.width / intrinsic.width;
      final sy = area.height / intrinsic.height;
      final scale = image.fit == CssBackgroundFit.cover
          ? (sx > sy ? sx : sy)
          : (sx < sy ? sx : sy);
      size = intrinsic * scale;
    case CssBackgroundFit.auto:
      final w = image.width == null
          ? null
          : InlineStyler.px(image.width!, area.width);
      final h = image.height == null
          ? null
          : InlineStyler.px(image.height!, area.height);
      size = switch ((w, h)) {
        (final w?, final h?) => Size(w, h),
        (final w?, null) => Size(w, w / ratio),
        (null, final h?) => Size(h * ratio, h),
        (null, null) => intrinsic,
      };
  }
  if (size.width <= 0.5 || size.height <= 0.5) return const [];
  final origin = Offset(
    area.left + InlineStyler.px(image.x, area.width - size.width),
    area.top + InlineStyler.px(image.y, area.height - size.height),
  );
  final bounds = visible == null ? area : area.intersect(visible);
  if (bounds.isEmpty) return const [];
  List<double> starts(
    double at,
    double step,
    double from,
    double to,
    bool repeat,
  ) {
    if (!repeat) return [at];
    var start = at - ((at - from) / step).ceil() * step;
    final out = <double>[];
    for (; start < to && out.length <= limit; start += step) {
      out.add(start);
    }
    return out;
  }

  final xs = starts(
    origin.dx,
    size.width,
    bounds.left,
    bounds.right,
    image.repeatX,
  );
  final ys = starts(
    origin.dy,
    size.height,
    bounds.top,
    bounds.bottom,
    image.repeatY,
  );
  return [
    for (final y in ys)
      for (final x in xs)
        if (Rect.fromLTWH(x, y, size.width, size.height).overlaps(bounds))
          Rect.fromLTWH(x, y, size.width, size.height),
  ].take(limit).toList();
}
