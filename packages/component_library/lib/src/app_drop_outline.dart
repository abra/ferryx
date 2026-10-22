import 'package:flutter/widgets.dart';

import 'theme/extensions/build_context_ext.dart';

/// The outline a list or a pane takes while files hang over it to be
/// dropped in, as Finder rings a window's list: the focus ring's colour
/// and width, drawn inside the edge so a neighbour never covers it, with a
/// row's rounding.
///
/// Painted over [child] without taking layout space or rebuilding it: the
/// same widget either way, only the painter changes.
class AppDropOutline extends StatelessWidget {
  const AppDropOutline({required this.active, required this.child, super.key});

  /// Files hang over the area and a drop would take them in.
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    return CustomPaint(
      foregroundPainter: active
          ? _DropOutlinePainter(
              color: context.appColors.focusRing,
              width: metrics.focusRingWidth,
              radius: metrics.radius.row,
            )
          : null,
      child: child,
    );
  }
}

class _DropOutlinePainter extends CustomPainter {
  _DropOutlinePainter({
    required this.color,
    required this.width,
    required this.radius,
  });

  final Color color;
  final double width;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final box = (Offset.zero & size).deflate(width / 2);
    if (box.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_DropOutlinePainter old) =>
      old.color != color || old.width != width || old.radius != radius;
}
