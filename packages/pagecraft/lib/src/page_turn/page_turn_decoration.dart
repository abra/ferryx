import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'page_turn_frame.dart';

/// Decoration above both page layers, independent of their paint order.
class PageTurnDecoration extends StatelessWidget {
  const PageTurnDecoration({required this.frame, super.key});

  final PageTurnFrame frame;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(painter: _PageTurnShadowPainter(frame)),
  );
}

class _PageTurnShadowPainter extends CustomPainter {
  const _PageTurnShadowPainter(this.frame);

  final PageTurnFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    if (!frame.castsShadow || size.isEmpty) return;
    final offset = frame.incomingOffset!;
    final distance = offset.abs();
    if (distance <= 0 || distance >= 1) return;
    final horizontal = frame.axis == Axis.horizontal;
    final extent = horizontal ? size.width : size.height;
    final width = math.min(20.0, extent * 0.1);
    final edge = (offset > 0 ? offset : 1 + offset) * extent;
    final direction = offset > 0 ? -1 : 1;
    final strength = (math.min(distance, 1 - distance) * 8).clamp(0.0, 1.0);
    final start = horizontal ? Offset(edge, 0) : Offset(0, edge);
    final end =
        start +
        (horizontal
            ? Offset(width * direction, 0)
            : Offset(0, width * direction));
    final strip = horizontal
        ? Rect.fromLTRB(
            math.min(start.dx, end.dx),
            0,
            math.max(start.dx, end.dx),
            size.height,
          )
        : Rect.fromLTRB(
            0,
            math.min(start.dy, end.dy),
            size.width,
            math.max(start.dy, end.dy),
          );
    canvas.drawRect(
      strip,
      Paint()
        ..shader = ui.Gradient.linear(start, end, [
          const Color(0xFF000000).withValues(alpha: 0.18 * strength),
          const Color(0x00000000),
        ]),
    );
  }

  @override
  bool shouldRepaint(_PageTurnShadowPainter oldDelegate) =>
      frame.animation != oldDelegate.frame.animation ||
      frame.axis != oldDelegate.frame.axis ||
      frame.incomingOffset != oldDelegate.frame.incomingOffset;
}
