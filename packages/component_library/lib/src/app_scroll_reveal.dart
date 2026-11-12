import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

import 'theme/tokens/app_motion.dart';

/// Reveals a cursor's range with short, interruptible scrolls. Distant
/// targets jump directly so a lazy list never builds the intervening items.
/// The view owns [controller] and calls [dispose] before disposing it.
class AppScrollReveal {
  AppScrollReveal(this.controller);

  final ScrollController controller;
  double? _destination;
  int _generation = 0;
  bool _disposed = false, _scheduled = false;
  VoidCallback? _pending;

  bool get isAnimating => !_disposed && _destination != null;

  /// Coalesces requests until layout has published the current extents.
  /// The callback reads the latest cursor, rather than a captured old index.
  void schedule(VoidCallback request) {
    if (_disposed) return;
    _pending = request;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final pending = _pending;
      _pending = null;
      if (!_disposed) pending?.call();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// [alignment] is null for minimal movement, or 0/0.5/1 for start/centre/end.
  void reveal({
    required double start,
    required double end,
    double? alignment,
    bool reduceMotion = false,
    bool immediate = false,
  }) {
    assert(alignment == null || alignment >= 0 && alignment <= 1);
    if (_disposed || !controller.hasClients) return;
    final position = controller.position;
    if (!position.hasContentDimensions || !position.hasViewportDimension) {
      return;
    }
    final viewport = position.viewportDimension;
    if (viewport <= 0) return;
    final current = position.pixels;
    final double wanted;
    if (alignment != null) {
      wanted = start - (viewport - (end - start)) * alignment;
    } else if (end - start >= viewport || start < current) {
      wanted = start;
    } else if (end > current + viewport) {
      wanted = end - viewport;
    } else {
      wanted = current;
    }
    final target = wanted.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final distance = (target - current).abs();
    if (immediate || reduceMotion || distance > viewport) {
      _jump(target);
      return;
    }
    if (distance <= precisionErrorTolerance) {
      // Reversing direction may reveal the new cursor already. Stop the
      // previous animation instead of letting it carry the viewport away.
      if (_destination != null) _jump(target);
      return;
    }
    final destination = _destination;
    if (destination != null) {
      final revealing =
          alignment == null &&
          start >= destination &&
          end <= destination + viewport;
      if (revealing ||
          (destination - target).abs() <= precisionErrorTolerance) {
        return;
      }
    }
    final duration = destination == null ? AppMotion.short : AppMotion.quick;
    final generation = ++_generation;
    _destination = target;
    unawaited(
      position
          .animateTo(target, duration: duration, curve: AppMotion.curve)
          .then((_) {
            if (!_disposed && generation == _generation) _destination = null;
          }),
    );
  }

  void _jump(double target) {
    final active = _destination != null;
    _generation++;
    _destination = null;
    if (active ||
        (controller.offset - target).abs() > precisionErrorTolerance) {
      controller.jumpTo(target);
    }
  }

  /// Native wheel/trackpad and drag input take over even if a keyboard
  /// request was waiting for this frame's layout.
  bool onUserScroll(UserScrollNotification notification) {
    if (notification.depth == 0 &&
        notification.direction != ScrollDirection.idle) {
      _pending = null;
      _generation++;
      _destination = null;
    }
    return false;
  }

  void dispose() {
    _disposed = true;
    _pending = null;
    _generation++;
  }
}
