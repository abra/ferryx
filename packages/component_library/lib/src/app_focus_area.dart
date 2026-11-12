import 'package:flutter/widgets.dart';

import 'app_window_activity.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/hairlines.dart';
import 'theme/tokens/app_sizes.dart';

/// A part of the window the keys can be in: the sidebar, a pane, a PDF's
/// pages or its notes, a panel. The one holding the focus draws an inset
/// accent outline, and what it selects takes the accent
/// ([activeOf]); the others grey their selections, as macOS greys one
/// without focus. So it is plain where the next key goes.
///
/// Areas nest: the innermost one around the focus is the active one. A
/// focus outside every area (a menu, a dialog, a bar between areas) keeps
/// the last area active, so nothing flickers while a menu is open.
class AppFocusArea extends StatefulWidget {
  const AppFocusArea({
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.showOutline = true,
    super.key,
  });

  final Widget child;

  /// Only corners meeting a rounded window edge need rounding.
  final BorderRadiusGeometry borderRadius;

  /// Use a descendant [AppFocusFrame] to outline only part of this area.
  /// Focus tracking and selection colors still cover the whole area.
  final bool showOutline;

  /// Whether the area around [context] is the one the keys are in; true
  /// outside every area (a dialog's own content). False everywhere while
  /// the window is not the active one ([AppWindowActivity]), as macOS
  /// greys every selection of a window that is not key.
  static bool activeOf(BuildContext context) =>
      AppWindowActivity.of(context) &&
      (context.dependOnInheritedWidgetOfExactType<_ActiveArea>()?.active ??
          true);

  @override
  State<AppFocusArea> createState() => _AppFocusAreaState();
}

class _AppFocusAreaState extends State<AppFocusArea> {
  /// Holds the area's part of the focus tree; it takes no focus itself.
  final _node = FocusNode(
    debugLabel: 'AppFocusArea',
    canRequestFocus: false,
    skipTraversal: true,
  );

  static final _areas = <FocusNode, _AppFocusAreaState>{};
  static _AppFocusAreaState? _active;

  @override
  void initState() {
    super.initState();
    if (_areas.isEmpty) FocusManager.instance.addListener(_follow);
    _areas[_node] = this;
    // The focus may be inside already (a remount, an autofocus).
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  @override
  void dispose() {
    _areas.remove(_node);
    if (_active == this) _active = null;
    if (_areas.isEmpty) FocusManager.instance.removeListener(_follow);
    _node.dispose();
    super.dispose();
  }

  static void _follow() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return;
    _AppFocusAreaState? found = _areas[focus];
    for (final node in focus.ancestors) {
      if (found != null) break;
      found = _areas[node];
    }
    if (found == null || found == _active) return;
    final previous = _active;
    _active = found;
    if (previous != null && previous.mounted) previous._changed();
    found._changed();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final active = _active == this && AppWindowActivity.of(context);
    return _ActiveArea(
      active: active,
      child: Focus(
        focusNode: _node,
        child: AppFocusFrame(
          visible: widget.showOutline,
          borderRadius: widget.borderRadius,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Outlines part of the nearest [AppFocusArea] without adding a focus scope.
/// Insets affect only the foreground paint, keeping content and hit targets
/// in place when the active area or frame bounds change.
class AppFocusFrame extends StatelessWidget {
  const AppFocusFrame({
    required this.child,
    this.insets = EdgeInsets.zero,
    this.borderRadius = BorderRadius.zero,
    this.visible = true,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry insets;
  final BorderRadiusGeometry borderRadius;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final inset = insets.resolve(Directionality.of(context));
    final active = visible && AppFocusArea.activeOf(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          left: inset.left,
          top: inset.top,
          right: inset.right,
          bottom: inset.bottom,
          child: IgnorePointer(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: ShapeDecoration(
                shape: AppRoundedRectangleBorder(
                  borderRadius: borderRadius,
                  side: BorderSide(
                    color: active
                        ? context.appColors.accent
                        : const Color(0x00000000),
                    width: AppSizes.focusFrameWidth,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveArea extends InheritedWidget {
  const _ActiveArea({required this.active, required super.child});

  final bool active;

  @override
  bool updateShouldNotify(_ActiveArea oldWidget) => active != oldWidget.active;
}
