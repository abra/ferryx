import 'package:material_ui/material_ui.dart';

import 'hairlines.dart';

/// The edge of a Fluent control: a hairline that turns darker along the
/// bottom, which is what gives Windows 11 buttons their slight lift
/// (`ControlElevationBorderBrush`).
@immutable
class FluentElevationBorder extends OutlinedBorder with SnapsToPixels {
  const FluentElevationBorder({
    required this.borderRadius,
    required this.top,
    required this.bottom,
    super.side = BorderSide.none,
  });

  final BorderRadius borderRadius;

  /// The edge everywhere but along the bottom.
  final Color top;

  /// The bottom few pixels of the edge.
  final Color bottom;

  /// How far up the darker bottom reaches, as Fluent's brush does.
  static const double _bottomReach = 3;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(1);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect).deflate(1));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.height <= 0) return;
    rect = snapToPixels(canvas, rect);
    final edge = borderRadius.toRRect(rect).deflate(0.5);
    final turn = ((rect.height - _bottomReach) / rect.height).clamp(0.0, 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, top, bottom],
        stops: [0, turn, 1],
      ).createShader(rect);
    canvas.drawRRect(edge, paint);
  }

  @override
  ShapeBorder scale(double t) => FluentElevationBorder(
    borderRadius: borderRadius * t,
    top: top,
    bottom: bottom,
    side: side.scale(t),
  );

  @override
  FluentElevationBorder copyWith({BorderSide? side}) => FluentElevationBorder(
    borderRadius: borderRadius,
    top: top,
    bottom: bottom,
    side: side ?? this.side,
  );

  @override
  bool operator ==(Object other) =>
      other is FluentElevationBorder &&
      other.borderRadius == borderRadius &&
      other.top == top &&
      other.bottom == bottom &&
      other.side == side;

  @override
  int get hashCode => Object.hash(borderRadius, top, bottom, side);
}

/// A Fluent text box: a rounded hairline with a line along the bottom that
/// turns into a 2 px accent bar while the box has focus.
@immutable
class FluentInputBorder extends OutlineInputBorder with SnapsToPixels {
  const FluentInputBorder({
    required super.borderRadius,
    required super.borderSide,
    required this.bottom,
  }) : super(gapPadding: 0);

  /// The line along the bottom edge, inside the rounded box.
  final BorderSide bottom;

  @override
  FluentInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
    BorderSide? bottom,
  }) => FluentInputBorder(
    borderRadius: borderRadius ?? this.borderRadius,
    borderSide: borderSide ?? this.borderSide,
    bottom: bottom ?? this.bottom,
  );

  // The decorator animates between the enabled and focused borders; keep
  // the bottom line through the blend instead of falling back to a plain
  // outline.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is FluentInputBorder
      ? FluentInputBorder(
          borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
          borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
          bottom: BorderSide.lerp(a.bottom, bottom, t),
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is FluentInputBorder
      ? FluentInputBorder(
          borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
          borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
          bottom: BorderSide.lerp(bottom, b.bottom, t),
        )
      : super.lerpTo(b, t);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    rect = snapToPixels(canvas, rect);
    super.paint(canvas, rect, textDirection: textDirection);
    if (bottom.width <= 0 || bottom.style == BorderStyle.none) return;
    canvas
      ..save()
      ..clipRRect(borderRadius.toRRect(rect))
      ..drawRect(
        Rect.fromLTRB(
          rect.left,
          rect.bottom - bottom.width,
          rect.right,
          rect.bottom,
        ),
        Paint()..color = bottom.color,
      )
      ..restore();
  }

  @override
  bool operator ==(Object other) =>
      other is FluentInputBorder &&
      other.borderRadius == borderRadius &&
      other.borderSide == borderSide &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(borderRadius, borderSide, bottom);
}
