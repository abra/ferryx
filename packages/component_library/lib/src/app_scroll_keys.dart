import 'package:flutter/widgets.dart';

/// Lets the scroll keys (PageUp/PageDown, and ⌘/Ctrl with an arrow) move
/// [child]'s main scroll view while the focus sits above every scroll view
/// in it: on a pane's own node, where Flutter's `ScrollAction` finds no
/// `Scrollable` to move and the keys would do nothing. A page with nothing
/// focusable in it (the Stats tab) scrolls like any other.
///
/// Focus inside a scroll view scrolls that one, as before.
class AppScrollKeys extends StatelessWidget {
  const AppScrollKeys({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: {ScrollIntent: _ScrollKeysAction(context)},
    child: child,
  );
}

class _ScrollKeysAction extends ContextAction<ScrollIntent> {
  _ScrollKeysAction(this._root);

  /// Where the search for the main scroll view starts.
  final BuildContext _root;
  final _nearest = ScrollAction();

  @override
  bool isEnabled(ScrollIntent intent, [BuildContext? context]) =>
      (context != null && _nearest.isEnabled(intent, context)) ||
      _main(intent) != null;

  @override
  void invoke(ScrollIntent intent, [BuildContext? context]) {
    if (context != null && _nearest.isEnabled(intent, context)) {
      _nearest.invoke(intent, context);
      return;
    }
    final state = _main(intent);
    if (state == null) return;
    final position = state.position;
    final increment = ScrollAction.getDirectionalIncrement(state, intent);
    if (increment == 0) return;
    position.moveTo(
      (position.pixels + increment).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
    );
  }

  /// The scroll view under [_root] with the most room on [intent]'s axis
  /// that can move: the page itself, not a list or a field inside it.
  /// Walked only when a scroll key finds nothing nearer.
  ScrollableState? _main(ScrollIntent intent) {
    if (!_root.mounted) return null;
    final axis = axisDirectionToAxis(intent.direction);
    ScrollableState? best;
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        final position = state.position;
        if (axisDirectionToAxis(state.axisDirection) == axis &&
            position.hasContentDimensions &&
            position.hasViewportDimension &&
            position.maxScrollExtent > position.minScrollExtent &&
            (state.resolvedPhysics?.shouldAcceptUserOffset(position) ?? true) &&
            (best == null ||
                position.viewportDimension >
                    best!.position.viewportDimension)) {
          best = state;
        }
      }
      element.visitChildElements(visit);
    }

    _root.visitChildElements(visit);
    return best;
  }
}
