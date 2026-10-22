import 'package:flutter/widgets.dart';

import 'hint_overlay.dart';
import 'hint_registry.dart';

/// Hint mode (⌘J) for the whole app: one [HintScope] over every route and
/// the overlay on top of them all, so the labels reach dialogs, the
/// settings and the review screen as well as the main window. The app maps
/// its chord to [HintModeHostState.toggle].
class HintModeHost extends StatefulWidget {
  const HintModeHost({required this.message, required this.child, super.key});

  /// The footer of the overlay, explaining the keys.
  final String message;
  final Widget child;

  static HintModeHostState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<HintModeHostState>();

  @override
  State<HintModeHost> createState() => HintModeHostState();
}

class HintModeHostState extends State<HintModeHost> {
  final _registry = HintRegistry();
  bool _shown = false;

  bool get shown => _shown;

  void toggle() => setState(() => _shown = !_shown);

  void dismiss() {
    if (_shown) setState(() => _shown = false);
  }

  @override
  Widget build(BuildContext context) => HintScope(
    registry: _registry,
    // The same subtree whether or not the overlay shows: a new parent would
    // remount the app under it.
    child: Stack(
      children: [
        widget.child,
        if (_shown)
          Positioned.fill(
            child: HintOverlay(
              registry: _registry,
              message: widget.message,
              onDismiss: dismiss,
            ),
          ),
      ],
    ),
  );
}
