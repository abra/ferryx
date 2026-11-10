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
    super.key,
  });

  final Widget child;

  /// Only corners meeting a rounded window edge need rounding.
  final BorderRadiusGeometry borderRadius;

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
    // Foreground paint keeps the outline over opaque content without
    // changing its layout, hit testing or mounted state as focus moves.
    return _ActiveArea(
      active: active,
      child: Focus(
        focusNode: _node,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ShapeDecoration(
            shape: AppRoundedRectangleBorder(
              borderRadius: widget.borderRadius,
              side: BorderSide(
                color: active
                    ? context.appColors.accent
                    : const Color(0x00000000),
                width: AppSizes.focusFrameWidth,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _ActiveArea extends InheritedWidget {
  const _ActiveArea({required this.active, required super.child});

  final bool active;

  @override
  bool updateShouldNotify(_ActiveArea oldWidget) => active != oldWidget.active;
}
