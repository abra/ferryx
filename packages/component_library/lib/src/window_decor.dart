import 'package:flutter/widgets.dart';

/// How the window's top row is woven into the content when the app draws
/// the title bar itself: on macOS the traffic lights sit over the top-left
/// of the content ([leadingInset]); on GNOME the app's header bar carries
/// the window buttons, usually at the right ([trailingInset]). [dragArea]
/// turns a strip into a handle that moves the window.
///
/// [none] is the plain layout under a system title bar: Windows keeps its
/// own (Snap Layouts, the window menu), as do Linux desktops that decorate
/// windows themselves.
@immutable
class WindowDecor {
  const WindowDecor({
    this.integrated = true,
    this.leadingInset = 0,
    this.trailingInset = 0,
    this.cornerRadius = 0,
    this.dragArea = _same,
  });

  static const none = WindowDecor(integrated: false);

  /// The decor of the window [context] is in, for a layer over the whole
  /// window that no screen hands one (the image viewer); [none] outside a
  /// [WindowDecorScope].
  static WindowDecor of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WindowDecorScope>()?.decor ??
      none;

  /// Whether the content draws the window's top row.
  final bool integrated;

  /// Width kept free at the start of the top row for window buttons.
  final double leadingInset;

  /// Width kept free at the end of the top row for window buttons.
  final double trailingInset;

  /// Native window corner radius; zero when full screen or system-decorated.
  final double cornerRadius;
  final Widget Function(Widget child) dragArea;

  static Widget _same(Widget child) => child;
}

/// Puts the window's [decor] above the routes, for [WindowDecor.of].
class WindowDecorScope extends InheritedWidget {
  const WindowDecorScope({
    required this.decor,
    required super.child,
    super.key,
  });

  final WindowDecor decor;

  @override
  bool updateShouldNotify(WindowDecorScope oldWidget) =>
      oldWidget.decor.integrated != decor.integrated ||
      oldWidget.decor.leadingInset != decor.leadingInset ||
      oldWidget.decor.trailingInset != decor.trailingInset ||
      oldWidget.decor.cornerRadius != decor.cornerRadius;
}
