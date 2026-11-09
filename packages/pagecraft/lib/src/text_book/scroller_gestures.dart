import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../layout/column_scroller.dart';

/// The part of a text view that scrolls sideways at a global position,
/// or null.
typedef ScrollerAt = ColumnScroller? Function(Offset global);

/// A horizontal drag that only begins on a part of the page that scrolls
/// sideways (a wide table): elsewhere it never enters the gesture arena,
/// so the selection area and page turns keep every other drag.
class ScrollerDragRecognizer extends HorizontalDragGestureRecognizer {
  ScrollerDragRecognizer({required this.scrollerAt, super.debugOwner});

  final ScrollerAt scrollerAt;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      super.isPointerAllowed(event) && scrollerAt(event.position) != null;
}

/// Moves a [ColumnScroller] with a finger and on after it lets go, the
/// platform's scroll friction slowing it down.
class ScrollerDrag {
  ScrollerDrag(this._vsync);

  final TickerProvider _vsync;

  /// Made for the first fling.
  AnimationController? _flingController;
  AnimationController get _fling =>
      _flingController ??= AnimationController.unbounded(vsync: _vsync)
        ..addListener(_onFling);
  ColumnScroller? _scroller;

  /// The scroller a drag moves, while one does.
  ColumnScroller? get scroller => _scroller;

  /// Starts moving [scroller]: a fling still going stops.
  void start(ColumnScroller scroller) {
    _flingController?.stop();
    _scroller = scroller;
  }

  /// The finger moved by [dx]: the content follows it.
  void update(double dx) {
    final scroller = _scroller;
    if (scroller == null || scroller.isDisposed) return;
    scroller.scrollTo(scroller.offset.value - dx);
  }

  /// The finger left at [velocity] (pixels per second, along x).
  void end(double velocity) {
    final scroller = _scroller;
    if (scroller == null || scroller.isDisposed) {
      _scroller = null;
      return;
    }
    if (velocity.abs() < kMinFlingVelocity) {
      _scroller = null;
      return;
    }
    _fling.animateWith(
      ClampingScrollSimulation(
        position: scroller.offset.value,
        velocity: -velocity,
      ),
    );
  }

  void _onFling() {
    final scroller = _scroller;
    if (scroller == null || scroller.isDisposed) {
      _fling.stop();
      return;
    }
    scroller.scrollTo(_fling.value);
    // At an edge: nothing more to move.
    if (scroller.offset.value != _fling.value) _fling.stop();
  }

  void stop() {
    _flingController?.stop();
    _scroller = null;
  }

  void dispose() => _flingController?.dispose();
}
