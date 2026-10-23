import 'package:flutter/material.dart';

import 'theme/app_platform_style.dart';
import 'theme/extensions/app_colors_ext.dart';
import 'theme/extensions/app_metrics.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/hairlines.dart';

/// Draws the platform's keyboard focus ring around [child] while it has
/// focus: the accent halo of macOS, Fluent's high-contrast 2 px stroke,
/// libadwaita's accent outline.
///
/// The ring is painted outside the child and takes no layout space, so a
/// focused control never shifts. It shows only while the keyboard is in
/// use (Flutter's focus highlight mode, which `FocusHighlightTracker`
/// switches off on a pointer press and back on with a key, as the
/// platforms do); the switch repaints the focused ring alone, without a
/// rebuild.
class FocusRing extends StatelessWidget {
  const FocusRing({
    required this.child,
    this.focused,
    this.radius,
    this.decorate = true,
    super.key,
  });

  final Widget child;

  /// Explicit focus state; when `null`, the nearest [Focus] is consulted.
  final bool? focused;

  /// Corner radius of the child; the platform's control radius by default.
  final double? radius;

  /// When false, nothing is drawn (handy to opt out in composed widgets).
  final bool decorate;

  static bool showsHighlight() =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  /// The platform's ring: the accent halo of [metrics]' width and gap,
  /// with Fluent's inner line in [surface].
  static AppRing ringOf(
    AppMetrics metrics,
    AppColorsExt colors,
    Color surface,
  ) => AppRing(
    color: colors.focusRing,
    width: metrics.focusRingWidth,
    gap: metrics.focusRingGap,
    inner: metrics.style == AppPlatformStyle.windows ? surface : null,
  );

  /// A button's [shape], with [ring] round it while the button has the
  /// keyboard's focus. A [Material] clips whatever its children paint, so
  /// a button's ring is its shape's to draw.
  static WidgetStateProperty<OutlinedBorder> ringedShape(
    OutlinedBorder shape,
    AppRing ring,
  ) => WidgetStateProperty.resolveWith(
    (states) =>
        shape is AppRoundedRectangleBorder &&
            states.contains(WidgetState.focused) &&
            showsHighlight()
        ? shape.withRing(ring)
        : shape,
  );

  @override
  Widget build(BuildContext context) {
    final hasFocus = decorate && (focused ?? Focus.of(context).hasFocus);
    // The same widget whatever the state, only the painter changes:
    // wrapping the child on focus (or on [decorate]) would remount it and
    // drop the focus it just gained.
    return CustomPaint(
      foregroundPainter: hasFocus
          ? FocusRingPainter.of(context, radius: radius)
          : null,
      child: child,
    );
  }
}

/// Paints the platform's focus ring around the painted box; for widgets that
/// draw their own focus state (`CustomPaint(foregroundPainter: ...)`).
///
/// Draws only in Flutter's traditional (keyboard) highlight mode, and
/// repaints when that mode changes, so a click or a key shows or hides
/// the ring without rebuilding the widget that owns it.
class FocusRingPainter extends CustomPainter {
  FocusRingPainter({
    required this.color,
    required this.width,
    required this.gap,
    required this.radius,
    this.inner,
  }) : super(repaint: _HighlightMode.instance);

  /// The ring of the theme's platform style around a box with [radius]
  /// corners (the control radius by default). Fluent pairs the outer
  /// stroke with a 1 px inner one in the background colour, so the ring
  /// reads on any fill.
  factory FocusRingPainter.of(BuildContext context, {double? radius}) {
    final metrics = context.metrics;
    final ring = FocusRing.ringOf(
      metrics,
      context.appColors,
      context.colors.surface,
    );
    return FocusRingPainter(
      color: ring.color,
      width: ring.width,
      gap: ring.gap,
      radius: radius ?? metrics.radius.control,
      inner: ring.inner,
    );
  }

  final Color color;
  final double width;
  final double gap;
  final double radius;
  final Color? inner;

  @override
  void paint(Canvas canvas, Size size) {
    if (!FocusRing.showsHighlight()) return;
    paintRing(
      canvas,
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      AppRing(color: color, width: width, gap: gap, inner: inner),
    );
  }

  @override
  bool shouldRepaint(FocusRingPainter old) =>
      old.color != color ||
      old.width != width ||
      old.gap != gap ||
      old.radius != radius ||
      old.inner != inner;
}

/// Flutter's focus highlight mode as a [Listenable], for painters to
/// repaint on: one listener on the focus manager for the whole app.
final class _HighlightMode extends ChangeNotifier {
  _HighlightMode._() {
    FocusManager.instance.addHighlightModeListener((_) => notifyListeners());
  }

  static final instance = _HighlightMode._();
}
