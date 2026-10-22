/// Motion durations. Resolve through `context.motion(...)`, which collapses
/// them to zero when the platform asks to reduce motion.
abstract final class AppMotion {
  /// Hover and press feedback, focus rings.
  static const Duration quick = Duration(milliseconds: 100);

  /// Menus, popovers, collapse of a rem.
  static const Duration short = Duration(milliseconds: 160);

  /// Panels sliding, page changes.
  static const Duration medium = Duration(milliseconds: 240);
}
