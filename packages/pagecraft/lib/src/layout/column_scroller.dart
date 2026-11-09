import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A part of a column wider than the column, which scrolls sideways
/// inside [viewport]: a table wider than its containing block whose CSS
/// lets it scroll (`overflow-x: auto` or `scroll`).
///
/// Its items and decorations keep the rects they were laid out at, with
/// the content from [contentLeft], [contentWidth] wide; [offset] moves
/// them left by that much (right while negative) under the viewport's
/// clip. Only `x` changes: pages, positions and anchors, which go by
/// `y`, never move with it. The offset is the reader's, shared by every
/// page that shows the column; it starts at 0, the content where the
/// layout put it (its start edge on the viewport's).
class ColumnScroller {
  ColumnScroller({
    required this.viewport,
    required this.contentLeft,
    required this.contentWidth,
  });

  /// Where the content is seen, in column coordinates.
  final Rect viewport;
  final double contentLeft;
  final double contentWidth;

  /// How far the content can move: [minOffset] shows its left edge,
  /// [maxOffset] its right edge.
  double get minOffset => math.min(0, contentLeft - viewport.left);
  double get maxOffset =>
      math.max(0, contentLeft + contentWidth - viewport.right);

  final ValueNotifier<double> offset = ValueNotifier(0);

  /// Whether its column was disposed: it scrolls no more.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  /// Scrolls to [value], within the content.
  void scrollTo(double value) {
    if (_disposed) return;
    offset.value = value.clamp(minOffset, maxOffset).toDouble();
  }

  /// Whether the content can move by [delta] (positive: left) at all.
  bool canScroll(double delta) => delta > 0
      ? offset.value < maxOffset - 0.5
      : delta < 0 && offset.value > minOffset + 0.5;

  /// Where a point of the content, in column coordinates, is shown.
  Offset toView(Offset content) => content - Offset(offset.value, 0);

  /// The point of the content shown at [view], in column coordinates.
  Offset toContent(Offset view) => view + Offset(offset.value, 0);

  void dispose() {
    _disposed = true;
    offset.dispose();
  }
}
