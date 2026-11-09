import 'dart:ui' show Rect;

/// A float as the lines beside it see it: its margin box in a
/// paragraph's coordinates, on the paragraph's [left] or right side.
class FloatArea {
  const FloatArea(this.rect, {required this.left});

  final Rect rect;
  final bool left;

  @override
  String toString() => 'FloatArea(${left ? 'left' : 'right'} $rect)';
}

/// The floats beside a paragraph, in its coordinates (x from its left
/// edge, y from its top), and how far into its lines they reach: CSS 2.1
/// §9.5, a line box next to a float is shortened. A line is beside a
/// float when it starts between the float's top and bottom.
class LineExclusions {
  const LineExclusions(this.areas);

  final List<FloatArea> areas;

  bool get isEmpty => areas.isEmpty;

  /// The room the floats take from the left and the right of a line
  /// [width] wide that starts at [y].
  ({double left, double right}) insetsAt(double y, double width) {
    var left = 0.0;
    var right = 0.0;
    for (final area in areas) {
      final rect = area.rect;
      if (y < rect.top || y >= rect.bottom) continue;
      if (area.left) {
        if (rect.right > left) left = rect.right;
      } else if (width - rect.left > right) {
        right = width - rect.left;
      }
    }
    return (
      left: left.clamp(0, width).toDouble(),
      right: right.clamp(0, width).toDouble(),
    );
  }

  /// The first height below [y] where a float starts or ends, or null:
  /// the lines from there have other room.
  double? nextChange(double y) {
    double? next;
    for (final area in areas) {
      final top = area.rect.top;
      final bottom = area.rect.bottom;
      if (top > y && (next == null || top < next)) next = top;
      if (bottom > y && (next == null || bottom < next)) next = bottom;
    }
    return next;
  }
}
