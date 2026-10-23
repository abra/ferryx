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

/// [RoundedRectangleBorder] with its edge on the screen's pixels: the
/// shape of buttons, dialogs, menus and cards.
class AppRoundedRectangleBorder extends RoundedRectangleBorder
    with SnapsToPixels {
  const AppRoundedRectangleBorder({super.side, super.borderRadius});

  @override
  AppRoundedRectangleBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => AppRoundedRectangleBorder(
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  AppRoundedRectangleBorder scale(double t) => AppRoundedRectangleBorder(
    side: side.scale(t),
    borderRadius: borderRadius * t,
  );

  // Buttons blend their shapes between states: the blend keeps the snap.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is RoundedRectangleBorder
      ? AppRoundedRectangleBorder(
          side: BorderSide.lerp(a.side, side, t),
          borderRadius: BorderRadiusGeometry.lerp(
            a.borderRadius,
            borderRadius,
            t,
          )!,
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is RoundedRectangleBorder
      ? AppRoundedRectangleBorder(
          side: BorderSide.lerp(side, b.side, t),
          borderRadius: BorderRadiusGeometry.lerp(
            borderRadius,
            b.borderRadius,
            t,
          )!,
        )
      : super.lerpTo(b, t);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      super.paint(
        canvas,
        snapToPixels(canvas, rect),
        textDirection: textDirection,
      );
}

/// A bezel: [AppRoundedRectangleBorder] with [shade] laid over its bottom
/// edge, as an AppKit push button or text field is drawn on macOS 15 (a
/// light hairline above and at the sides, a darker one below, a shadow).
class AppBezelBorder extends AppRoundedRectangleBorder {
  const AppBezelBorder({
    required this.shade,
    super.side,
    super.borderRadius,
  });

  final Color shade;

  @override
  AppBezelBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => AppBezelBorder(
    shade: shade,
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  AppBezelBorder scale(double t) => AppBezelBorder(
    shade: shade,
    side: side.scale(t),
    borderRadius: borderRadius * t,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is RoundedRectangleBorder
      ? AppBezelBorder(
          shade: shade,
          side: BorderSide.lerp(a.side, side, t),
          borderRadius: BorderRadiusGeometry.lerp(
            a.borderRadius,
            borderRadius,
            t,
          )!,
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is RoundedRectangleBorder
      ? AppBezelBorder(
          shade: shade,
          side: BorderSide.lerp(side, b.side, t),
          borderRadius: BorderRadiusGeometry.lerp(
            borderRadius,
            b.borderRadius,
            t,
          )!,
        )
      : super.lerpTo(b, t);

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

/// [StadiumBorder] with its edge on the screen's pixels: a capsule.
class AppStadiumBorder extends StadiumBorder with SnapsToPixels {
  const AppStadiumBorder({super.side});

  @override
  AppStadiumBorder copyWith({BorderSide? side}) =>
      AppStadiumBorder(side: side ?? this.side);

  @override
  AppStadiumBorder scale(double t) => AppStadiumBorder(side: side.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is StadiumBorder
      ? AppStadiumBorder(side: BorderSide.lerp(a.side, side, t))
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is StadiumBorder
      ? AppStadiumBorder(side: BorderSide.lerp(side, b.side, t))
      : super.lerpTo(b, t);

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
