import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'theme/extensions/build_context_ext.dart';

/// Something the pointer can drag files out of (a row): a drag starts once
/// the primary button, held down on it, has moved past the desktop's drag
/// threshold (`context.metrics.dragThreshold`). A click, a ⇧-click or a
/// ⌘-click that wobbles a little stays a click, as in Finder.
///
/// It only listens to the pointer, never joins the gesture arena, so the
/// taps and double taps of the child keep working; the drag's own work
/// (what to drag, the system session) is [onDragStart]'s.
class FileDragSource extends StatefulWidget {
  const FileDragSource({
    required this.onDragStart,
    required this.child,
    this.enabled = true,
    super.key,
  });

  /// The pointer passed the threshold at this global position.
  final ValueChanged<Offset> onDragStart;

  /// Off while the child is being edited (a name renamed in place), so a
  /// text selection never turns into a drag.
  final bool enabled;

  final Widget child;

  @override
  State<FileDragSource> createState() => _FileDragSourceState();
}

class _FileDragSourceState extends State<FileDragSource> {
  int? _pointer;
  Offset _down = Offset.zero;
  bool _started = false;

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled || event.buttons != kPrimaryButton) {
      _pointer = null;
      return;
    }
    _pointer = event.pointer;
    _down = event.position;
    _started = false;
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _started || !widget.enabled) return;
    if (event.buttons != kPrimaryButton) {
      _pointer = null;
      return;
    }
    final threshold = context.metrics.dragThreshold;
    if ((event.position - _down).distance <= threshold) return;
    _started = true;
    widget.onDragStart(event.position);
  }

  void _onEnd(PointerEvent event) {
    if (event.pointer == _pointer) _pointer = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onEnd,
    onPointerCancel: _onEnd,
    child: widget.child,
  );
}
