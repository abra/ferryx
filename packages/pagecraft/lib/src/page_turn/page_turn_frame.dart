import 'package:flutter/widgets.dart';

import 'page_turn_animation.dart';

enum PageTurnRole { outgoing, incoming }

/// Presentation of one turn, in viewport lengths along [axis].
///
/// Views own gestures and settling; strategies only determine how already laid
/// out pages appear. [entrySide] stays explicit because the incoming offset
/// reaches zero at the end of a turn.
class PageTurnFrame {
  const PageTurnFrame.idle({required this.animation, required this.axis})
    : incomingOffset = null,
      entrySide = 0;

  const PageTurnFrame.active({
    required this.animation,
    required this.axis,
    required double incomingOffset,
    required this.entrySide,
  }) : incomingOffset = incomingOffset,
       assert(incomingOffset >= -1 && incomingOffset <= 1),
       assert(entrySide == -1 || entrySide == 1);

  final PageTurnAnimation animation;
  final Axis axis;
  final double? incomingOffset;
  final double entrySide;

  bool get isActive => incomingOffset != null;
  bool get castsShadow => isActive && _strategy.castsShadow;

  _PageTurnStrategy get _strategy => switch (animation) {
    PageTurnAnimation.slide => const _SlideStrategy(),
    PageTurnAnimation.cover => const _CoverStrategy(),
  };

  double offsetFor(PageTurnRole role) {
    final incoming = incomingOffset;
    if (incoming == null) return 0;
    return role == PageTurnRole.incoming
        ? incoming
        : _strategy.outgoingOffset(incoming, entrySide);
  }

  /// Clip in the page's own coordinates, before its translation.
  Rect clipFor(PageTurnRole? role, Size size) {
    final incoming = incomingOffset;
    if (incoming == null || role != PageTurnRole.outgoing) {
      return Offset.zero & size;
    }
    return _strategy.outgoingClip(size, axis, incoming);
  }

  /// Visible region in the viewport, also used by highlight tracking.
  Rect visibleRect(PageTurnRole role, Size size) {
    final offset = offsetFor(role);
    final displacement = axis == Axis.horizontal
        ? Offset(offset * size.width, 0)
        : Offset(0, offset * size.height);
    return clipFor(
      role,
      size,
    ).shift(displacement).intersect(Offset.zero & size);
  }
}

abstract class _PageTurnStrategy {
  const _PageTurnStrategy();

  bool get castsShadow;
  double outgoingOffset(double incoming, double entrySide);
  Rect outgoingClip(Size size, Axis axis, double incoming);
}

class _SlideStrategy extends _PageTurnStrategy {
  const _SlideStrategy();

  @override
  bool get castsShadow => false;

  @override
  double outgoingOffset(double incoming, double entrySide) =>
      incoming - entrySide;

  @override
  Rect outgoingClip(Size size, Axis axis, double incoming) =>
      Offset.zero & size;
}

class _CoverStrategy extends _PageTurnStrategy {
  const _CoverStrategy();

  @override
  bool get castsShadow => true;

  @override
  double outgoingOffset(double incoming, double entrySide) => 0;

  @override
  Rect outgoingClip(Size size, Axis axis, double incoming) {
    if (axis == Axis.horizontal) {
      return incoming >= 0
          ? Rect.fromLTRB(0, 0, size.width * incoming, size.height)
          : Rect.fromLTRB(
              size.width * (1 + incoming),
              0,
              size.width,
              size.height,
            );
    }
    return incoming >= 0
        ? Rect.fromLTRB(0, 0, size.width, size.height * incoming)
        : Rect.fromLTRB(
            0,
            size.height * (1 + incoming),
            size.width,
            size.height,
          );
  }
}
