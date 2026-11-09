import 'package:flutter/widgets.dart';

import 'page_turn_frame.dart';

/// Stable rendering seam for a page in either viewer.
///
/// [nativeOffset] compensates a scrolling viewport's existing translation.
/// Slide and cover keep the live page and reuse its layout and paint layer.
/// A deforming effect can own its transient rendering resources here without
/// changing gesture recognition, pagination or the page's selection tree.
class PageTurnLayer extends StatelessWidget {
  const PageTurnLayer({
    required this.frame,
    required this.role,
    required this.viewportSize,
    required this.backgroundColor,
    required this.child,
    this.nativeOffset = 0,
    super.key,
  });

  final PageTurnFrame frame;
  final PageTurnRole? role;
  final Size viewportSize;
  final Color backgroundColor;
  final double nativeOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final role = this.role;
    final shift = frame.isActive && role != null
        ? frame.offsetFor(role) - nativeOffset
        : 0.0;
    return Transform.translate(
      offset: frame.axis == Axis.horizontal
          ? Offset(shift * viewportSize.width, 0)
          : Offset(0, shift * viewportSize.height),
      child: ClipRect(
        clipper: _PageTurnClipper(frame, role),
        child: RepaintBoundary(
          child: ColoredBox(color: backgroundColor, child: child),
        ),
      ),
    );
  }
}

class _PageTurnClipper extends CustomClipper<Rect> {
  const _PageTurnClipper(this.frame, this.role);

  final PageTurnFrame frame;
  final PageTurnRole? role;

  @override
  Rect getClip(Size size) => frame.clipFor(role, size);

  @override
  bool shouldReclip(_PageTurnClipper oldClipper) =>
      role != oldClipper.role ||
      frame.animation != oldClipper.frame.animation ||
      frame.axis != oldClipper.frame.axis ||
      frame.incomingOffset != oldClipper.frame.incomingOffset ||
      frame.entrySide != oldClipper.frame.entrySide;
}
