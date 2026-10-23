// Hairlines on the screen's pixels.
//
// A line one pixel wide drawn between two pixels spreads over both at half
// strength: on a screen of one pixel per point (a monitor without Retina)
// a field's outline then seems to be missing on that side. Layout puts
// boxes at fractions of a pixel all the time (a text's width, a width that
// flex shares out, a box centred in an odd width), so the borders snap as
// they paint: the stroke's rect grows outward to the device pixels it
// touches, over the fill's soft edge. The canvas maps a rect to its layer;
// the layers that can land between pixels (a dialog's, a menu's) are put
// on whole pixels by `PixelSnap`.

import 'package:flutter/material.dart';

import 'tokens/app_radius.dart';

/// A border that draws its lines on the screen's pixels ([snapToPixels]).
mixin SnapsToPixels on ShapeBorder {}

/// [rect] grown outward to the device pixels it touches, as [canvas] maps
/// it. Left as it is under a rotation or a skew.
Rect snapToPixels(Canvas canvas, Rect rect) {
  final ratio =
      WidgetsBinding
          .instance
          .platformDispatcher
          .implicitView
          ?.devicePixelRatio ??
      1;
  // Column-major: the scale on the diagonal, the translation last.
  final m = canvas.getTransform();
  if (m[1] != 0 || m[4] != 0 || m[0] <= 0 || m[5] <= 0) return rect;
  final sx = m[0] * ratio;
  final sy = m[5] * ratio;
  final tx = m[12] * ratio;
  final ty = m[13] * ratio;
  // A coordinate a rounding error off a pixel is on it.
  double down(double v, double s, double t) {
    final device = v * s + t;
    final near = device.roundToDouble();
    return ((device - near).abs() < 0.01 ? near : device.floorToDouble()) / s -
        t / s;
  }

  double up(double v, double s, double t) {
    final device = v * s + t;
    final near = device.roundToDouble();
    return ((device - near).abs() < 0.01 ? near : device.ceilToDouble()) / s -
        t / s;
  }

  return Rect.fromLTRB(
    down(rect.left, sx, tx),
    down(rect.top, sy, ty),
    up(rect.right, sx, tx),
    up(rect.bottom, sy, ty),
  );
}

/// Whether [side] is drawn inside a shape's edge, so the fill stops where
/// it starts (see [AppRoundedRectangleBorder.getOuterPath]).
bool _edgeInside(BorderSide side) =>
    side.style != BorderStyle.none &&
    side.width > 0 &&
    side.strokeAlign == BorderSide.strokeAlignInside;

/// [Border] with its lines on the screen's pixels: what a [BoxDecoration]
/// draws round a box.
class AppBorder extends Border with SnapsToPixels {
  const AppBorder({super.top, super.right, super.bottom, super.left});

  const AppBorder.fromBorderSide(super.side) : super.fromBorderSide();

  const AppBorder.symmetric({super.vertical, super.horizontal})
    : super.symmetric();

  /// The same line on every side.
  factory AppBorder.all({
    Color color = const Color(0xFF000000),
    double width = 1.0,
    BorderStyle style = BorderStyle.solid,
    double strokeAlign = BorderSide.strokeAlignInside,
  }) => AppBorder.fromBorderSide(
    BorderSide(
      color: color,
      width: width,
      style: style,
      strokeAlign: strokeAlign,
    ),
  );

  @override
  AppBorder scale(double t) => AppBorder(
    top: top.scale(t),
    right: right.scale(t),
    bottom: bottom.scale(t),
    left: left.scale(t),
  );

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) => super.paint(
    canvas,
    snapToPixels(canvas, rect),
    textDirection: textDirection,
    shape: shape,
    borderRadius: borderRadius,
  );
}

/// [BorderDirectional] with its lines on the screen's pixels.
class AppBorderDirectional extends BorderDirectional with SnapsToPixels {
  const AppBorderDirectional({
    super.top,
    super.start,
    super.end,
    super.bottom,
  });

  @override
  AppBorderDirectional scale(double t) => AppBorderDirectional(
    top: top.scale(t),
    start: start.scale(t),
    end: end.scale(t),
    bottom: bottom.scale(t),
  );

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) => super.paint(
    canvas,
    snapToPixels(canvas, rect),
    textDirection: textDirection,
    shape: shape,
    borderRadius: borderRadius,
  );
}

/// A keyboard focus ring a shape draws round itself
/// ([AppRoundedRectangleBorder.ring]): [width] of [color], [gap] off the
/// edge, and Fluent's 1-px [inner] line in that gap.
@immutable
class AppRing {
  const AppRing({
    required this.color,
    required this.width,
    this.gap = 0,
    this.inner,
  });

  final Color color;
  final double width;
  final double gap;
  final Color? inner;

  @override
  bool operator ==(Object other) =>
      other is AppRing &&
      other.color == color &&
      other.width == width &&
      other.gap == gap &&
      other.inner == inner;

  @override
  int get hashCode => Object.hash(color, width, gap, inner);
}

/// [ring] round [shape] (the control's own outline), outside it.
void paintRing(Canvas canvas, RRect shape, AppRing ring) {
  final outset = ring.gap + ring.width / 2;
  canvas.drawRRect(
    shape.inflate(outset),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ring.width
      ..color = ring.color,
  );
  final inner = ring.inner;
  if (inner != null && ring.gap > 0) {
    canvas.drawRRect(
      shape.inflate(ring.gap / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring.gap
        ..color = inner,
    );
  }
}

/// [RoundedRectangleBorder] with its edge on the screen's pixels: the
/// shape of buttons, dialogs, menus and cards.
///
/// With [insetFill] the fill stops where the edge starts, as AppKit draws
/// a bezel or a window: laid under a translucent edge it shows through
/// the rounded corners' half-covered pixels, and the edge seems to break
/// there. Not for a [Material] that clips its children, which would clip
/// the edge away with them (a button with a background builder, a dialog
/// with a clip): clip such content inside instead. [ring] is a focus ring
/// round the shape, for a button whose state draws it (a [Material]'s
/// children cannot paint outside it).
class AppRoundedRectangleBorder extends RoundedRectangleBorder
    with SnapsToPixels {
  const AppRoundedRectangleBorder({
    super.side,
    super.borderRadius,
    this.insetFill = false,
    this.ring,
  });

  final bool insetFill;
  final AppRing? ring;

  /// The same shape with another [side], [borderRadius] or [ring]: each
  /// kind keeps what is its own.
  AppRoundedRectangleBorder _with({
    required BorderSide side,
    required BorderRadiusGeometry borderRadius,
    required AppRing? ring,
  }) => AppRoundedRectangleBorder(
    side: side,
    borderRadius: borderRadius,
    insetFill: insetFill,
    ring: ring,
  );

  /// This shape with [ring] round it (none: without one).
  AppRoundedRectangleBorder withRing(AppRing? ring) =>
      _with(side: side, borderRadius: borderRadius, ring: ring);

  @override
  AppRoundedRectangleBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => _with(
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
    ring: ring,
  );

  @override
  AppRoundedRectangleBorder scale(double t) =>
      _with(side: side.scale(t), borderRadius: borderRadius * t, ring: ring);

  // Buttons blend their shapes between states: the blend keeps the snap.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is RoundedRectangleBorder
      ? _with(
          side: BorderSide.lerp(a.side, side, t),
          borderRadius: BorderRadiusGeometry.lerp(
            a.borderRadius,
            borderRadius,
            t,
          )!,
          ring: t < 0.5 && a is AppRoundedRectangleBorder ? a.ring : ring,
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is RoundedRectangleBorder
      ? _with(
          side: BorderSide.lerp(side, b.side, t),
          borderRadius: BorderRadiusGeometry.lerp(
            borderRadius,
            b.borderRadius,
            t,
          )!,
          ring: t < 0.5 || b is! AppRoundedRectangleBorder ? ring : b.ring,
        )
      : super.lerpTo(b, t);

  // A Material fills by the outer path, a ShapeDecoration through
  // [paintInterior]: both stop inside the edge.
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      insetFill && _edgeInside(side)
      ? getInnerPath(rect, textDirection: textDirection)
      : super.getOuterPath(rect, textDirection: textDirection);

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => insetFill && _edgeInside(side)
      ? canvas.drawRRect(
          borderRadius
              .resolve(textDirection)
              .toRRect(rect)
              .deflate(side.strokeInset),
          paint,
        )
      : super.paintInterior(canvas, rect, paint, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final snapped = snapToPixels(canvas, rect);
    super.paint(canvas, snapped, textDirection: textDirection);
    if (ring case final ring?) {
      paintRing(
        canvas,
        borderRadius.resolve(textDirection).toRRect(snapped),
        ring,
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AppRoundedRectangleBorder &&
      other.runtimeType == runtimeType &&
      other.insetFill == insetFill &&
      other.ring == ring &&
      super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, insetFill, ring);
}

/// The edge of a floating surface (a dialog, a menu, a picker): a line
/// round its plate, and [highlight] just inside it, over the fill. Its
/// fill stops inside the line ([insetFill]).
class AppWindowBorder extends AppRoundedRectangleBorder {
  const AppWindowBorder({
    this.highlight,
    super.side,
    super.borderRadius,
    super.ring,
  }) : super(insetFill: true);

  /// A macOS window's, sheet's or menu's edge, measured on macOS 15: a
  /// dark line round the plate (#A6 over a dimmed window), in the dark a
  /// black line with a light one inside it.
  factory AppWindowBorder.macos({required double radius, required bool dark}) =>
      AppWindowBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: Colors.black.withValues(alpha: dark ? 0.9 : 0.18),
        ),
        highlight: dark ? Colors.white.withValues(alpha: 0.2) : null,
      );

  final Color? highlight;

  @override
  AppWindowBorder _with({
    required BorderSide side,
    required BorderRadiusGeometry borderRadius,
    required AppRing? ring,
  }) => AppWindowBorder(
    highlight: highlight,
    side: side,
    borderRadius: borderRadius,
    ring: ring,
  );

  @override
  AppWindowBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => _with(
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
    ring: ring,
  );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    super.paint(canvas, rect, textDirection: textDirection);
    final light = highlight;
    if (light == null || !_edgeInside(side)) return;
    final inner = borderRadius
        .resolve(textDirection)
        .toRRect(snapToPixels(canvas, rect))
        .deflate(side.width);
    canvas.drawDRRect(inner, inner.deflate(1), Paint()..color = light);
  }

  @override
  bool operator ==(Object other) =>
      other is AppWindowBorder &&
      other.highlight == highlight &&
      super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, highlight);
}

/// A bezel: [AppRoundedRectangleBorder] with [shade] laid over its bottom
/// edge, as an AppKit push button or text field is drawn on macOS 15 (a
/// light hairline above and at the sides, a darker one below, a shadow).
class AppBezelBorder extends AppRoundedRectangleBorder {
  const AppBezelBorder({
    required this.shade,
    super.side,
    super.borderRadius,
    super.insetFill,
    super.ring,
  });

  final Color shade;

  @override
  AppBezelBorder _with({
    required BorderSide side,
    required BorderRadiusGeometry borderRadius,
    required AppRing? ring,
  }) => AppBezelBorder(
    shade: shade,
    side: side,
    borderRadius: borderRadius,
    insetFill: insetFill,
    ring: ring,
  );

  @override
  AppBezelBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => _with(
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
    ring: ring,
  );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    super.paint(canvas, rect, textDirection: textDirection);
    paintShade(
      canvas,
      snapToPixels(canvas, rect),
      borderRadius.resolve(textDirection),
      side,
      shade,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppBezelBorder && other.shade == shade && super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, shade);
}

/// [side]'s stroke round [rect] again in [shade], over the edge already
/// drawn, along the bottom row only: a bezel's darker lower edge.
void paintShade(
  Canvas canvas,
  Rect rect,
  BorderRadius radius,
  BorderSide side,
  Color shade,
) {
  if (side.style == BorderStyle.none || side.width <= 0) return;
  canvas
    ..save()
    ..clipRect(
      Rect.fromLTRB(
        rect.left,
        rect.bottom - side.width,
        rect.right,
        rect.bottom,
      ),
    )
    ..drawRRect(
      radius.toRRect(rect).deflate(side.width / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side.width
        ..color = shade,
    )
    ..restore();
}

/// A box of [color] in a hairline [edge] (none: no line), rounded by
/// [radius]: a [ShapeDecoration], so the fill stops inside the edge. A
/// [BoxDecoration] lays the fill under its border, which then fades at the
/// rounded corners, as if the box had no edge there.
ShapeDecoration appEdgedBox({
  Color? color,
  Color? edge,
  double radius = 0,
  List<BoxShadow>? shadows,
}) => ShapeDecoration(
  color: color,
  shadows: shadows,
  shape: radius >= AppRadius.full
      ? AppStadiumBorder(
          side: edge == null ? BorderSide.none : BorderSide(color: edge),
          insetFill: true,
        )
      : AppRoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: edge == null ? BorderSide.none : BorderSide(color: edge),
          insetFill: true,
        ),
);

/// [StadiumBorder] with its edge on the screen's pixels: a capsule.
class AppStadiumBorder extends StadiumBorder with SnapsToPixels {
  const AppStadiumBorder({super.side, this.insetFill = false});

  /// See [AppRoundedRectangleBorder.insetFill].
  final bool insetFill;

  @override
  AppStadiumBorder copyWith({BorderSide? side}) =>
      AppStadiumBorder(side: side ?? this.side, insetFill: insetFill);

  @override
  AppStadiumBorder scale(double t) =>
      AppStadiumBorder(side: side.scale(t), insetFill: insetFill);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is StadiumBorder
      ? AppStadiumBorder(
          side: BorderSide.lerp(a.side, side, t),
          insetFill: insetFill,
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is StadiumBorder
      ? AppStadiumBorder(
          side: BorderSide.lerp(side, b.side, t),
          insetFill: insetFill,
        )
      : super.lerpTo(b, t);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      insetFill && _edgeInside(side)
      ? getInnerPath(rect, textDirection: textDirection)
      : super.getOuterPath(rect, textDirection: textDirection);

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => insetFill && _edgeInside(side)
      ? canvas.drawPath(getInnerPath(rect, textDirection: textDirection), paint)
      : super.paintInterior(canvas, rect, paint, textDirection: textDirection);

  @override
  bool operator ==(Object other) =>
      other is AppStadiumBorder &&
      other.insetFill == insetFill &&
      super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, insetFill);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      super.paint(
        canvas,
        snapToPixels(canvas, rect),
        textDirection: textDirection,
      );
}

/// [OutlineInputBorder] with its outline on the screen's pixels: the
/// border of a text field.
class AppOutlineInputBorder extends OutlineInputBorder with SnapsToPixels {
  const AppOutlineInputBorder({
    super.borderSide,
    super.borderRadius,
    super.gapPadding,
    this.halo,
    this.shade,
  });

  /// A ring outside the border: the focus ring of a macOS field, which
  /// keeps its bezel and takes the accent halo around it.
  final BorderSide? halo;

  /// Laid over the bottom edge, darker than the rest as an NSTextField's
  /// bezel is on macOS 15 ([AppBezelBorder]); none paints it as the rest.
  final Color? shade;

  @override
  AppOutlineInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
    BorderSide? halo,
    Color? shade,
  }) => AppOutlineInputBorder(
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
    gapPadding: gapPadding ?? this.gapPadding,
    halo: halo ?? this.halo,
    shade: shade ?? this.shade,
  );

  @override
  AppOutlineInputBorder scale(double t) => AppOutlineInputBorder(
    borderSide: borderSide.scale(t),
    borderRadius: borderRadius * t,
    gapPadding: gapPadding * t,
    halo: halo?.scale(t),
    shade: shade,
  );

  // The decorator blends the enabled border into the focused one; the
  // halo fades in with it.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is OutlineInputBorder
      ? AppOutlineInputBorder(
          borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
          borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
          gapPadding: gapPadding,
          halo: _lerpHalo(a is AppOutlineInputBorder ? a.halo : null, halo, t),
          shade: shade,
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is OutlineInputBorder
      ? AppOutlineInputBorder(
          borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
          borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
          gapPadding: gapPadding,
          halo: _lerpHalo(halo, b is AppOutlineInputBorder ? b.halo : null, t),
          shade: shade,
        )
      : super.lerpTo(b, t);

  bool get _edged =>
      borderSide.style != BorderStyle.none && borderSide.width > 0;

  // The fill inside the outline, as a bezel's (see
  // [AppRoundedRectangleBorder.getOuterPath]).
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _edged
      ? getInnerPath(rect, textDirection: textDirection)
      : super.getOuterPath(rect, textDirection: textDirection);

  // The decorator fills through this one: inside the outline, on the
  // pixels the outline is snapped to, so no fill shows under the edge
  // and no ground between them.
  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => _edged
      ? canvas.drawRRect(
          borderRadius
              .resolve(textDirection)
              .toRRect(snapToPixels(canvas, rect))
              .deflate(borderSide.width),
          paint,
        )
      : super.paintInterior(canvas, rect, paint, textDirection: textDirection);

  // The decorator moves to a new border only when the two differ: the
  // focused one differs from the enabled one by its halo alone.
  @override
  bool operator ==(Object other) =>
      other is AppOutlineInputBorder &&
      other.halo == halo &&
      other.shade == shade &&
      super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, halo, shade);

  static BorderSide? _lerpHalo(BorderSide? a, BorderSide? b, double t) {
    if (a == null && b == null) return null;
    final from = a ?? b!.copyWith(color: b.color.withValues(alpha: 0));
    final to = b ?? a!.copyWith(color: a.color.withValues(alpha: 0));
    return BorderSide.lerp(from, to, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    final snapped = snapToPixels(canvas, rect);
    super.paint(
      canvas,
      snapped,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
    if (shade case final shade?) {
      paintShade(
        canvas,
        snapped,
        borderRadius.resolve(textDirection),
        borderSide,
        shade,
      );
    }
    final ring = halo;
    if (ring == null || ring.width <= 0 || ring.color.a == 0) return;
    final outset = ring.width / 2;
    canvas.drawRRect(
      borderRadius
          .resolve(textDirection)
          .toRRect(snapped.inflate(outset))
          .shift(Offset.zero),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring.width
        ..color = ring.color,
    );
  }
}
