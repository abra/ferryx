import 'package:flutter/animation.dart';

/// Motion durations. Resolve through `context.motion(...)`, which collapses
/// them to zero when the platform asks to reduce motion.
abstract final class AppMotion {
  /// Hover and press feedback, focus rings.
  static const Duration quick = Duration(milliseconds: 100);

  /// Menus, popovers and small layout changes.
  static const Duration short = Duration(milliseconds: 160);

  /// Panels sliding, page changes.
  static const Duration medium = Duration(milliseconds: 240);

  static const Curve curve = Curves.easeOutCubic;

  /// A small vertical settling distance for floating surfaces, in logical px.
  static const double surfaceOffset = 6;
}
