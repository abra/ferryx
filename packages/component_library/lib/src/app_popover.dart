import 'package:flutter/material.dart';

import 'popup_focus.dart';
import 'app_transitions.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_motion.dart';
import 'theme/tokens/app_spacing.dart';

/// Shows [builder]'s widget under [anchor] (right edges aligned, flipped
/// above when there is no room), with no scrim; a click outside or Escape
/// closes it and gives the focus back to what held it. The date picker and
/// similar pickers use it.
Future<T?> showAppPopover<T>({
  required BuildContext context,
  required Rect anchor,
  required WidgetBuilder builder,
}) => pushReturningFocus(
  context,
  _PopoverRoute<T>(
    anchor: anchor,
    builder: builder,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    duration: context.motion(AppMotion.quick),
  ),
);

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({
    required this.anchor,
    required this.builder,
    required this.barrierLabel,
    required this.duration,
  });

  final Rect anchor;
  final WidgetBuilder builder;

  @override
  final String barrierLabel;
  final Duration duration;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => CustomSingleChildLayout(
    delegate: _PopoverLayout(anchor),
    child: FocusScope(autofocus: true, child: Builder(builder: builder)),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => AppSurfaceTransition(animation: animation, slide: false, child: child);
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout(this.anchor);

  final Rect anchor;
  static const _gap = AppSpacing.xs;
  static const _margin = AppSpacing.sm;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = size.width - childSize.width - _margin;
    final x = (anchor.right - childSize.width).clamp(_margin, maxX);
    final below = anchor.bottom + _gap;
    final fits = below + childSize.height + _margin <= size.height;
    final y = fits ? below : anchor.top - _gap - childSize.height;
    return Offset(x.toDouble(), y.clamp(_margin, double.infinity).toDouble());
  }

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}
