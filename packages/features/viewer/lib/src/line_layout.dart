import 'dart:math' as math;

/// Where each line of a window lies in its scroll view: the height of a
/// line of text, and with wrapping on, how many lines each one takes.
class LineLayout {
  LineLayout({
    required this.lineHeight,
    required List<int> rowsPerLine,
  }) : _rows = rowsPerLine {
    var sum = 0;
    _prefix = List<int>.filled(_rows.length + 1, 0);
    for (var i = 0; i < _rows.length; i++) {
      sum += _rows[i];
      _prefix[i + 1] = sum;
    }
  }

  /// Every line one row tall.
  LineLayout.uniform({required this.lineHeight, required int lines})
    : _rows = const [],
      _uniformLines = lines {
    _prefix = const [];
  }

  final double lineHeight;
  final List<int> _rows;
  late final List<int> _prefix;
  int _uniformLines = 0;

  bool get _uniform => _rows.isEmpty;

  int get lines => _uniform ? _uniformLines : _rows.length;

  /// The whole height.
  double get extent => (_uniform ? _uniformLines : _prefix.last) * lineHeight;

  double offsetOfLine(int line) {
    final at = math.min(math.max(line, 0), lines);
    return (_uniform ? at : _prefix[at]) * lineHeight;
  }

  double heightOfLine(int line) =>
      (_uniform ? 1 : _rows[math.min(math.max(line, 0), _rows.length - 1)]) *
      lineHeight;

  /// The line at the scroll [offset].
  int lineAtOffset(double offset) {
    if (lines == 0) return 0;
    final row = (offset / lineHeight).floor();
    if (_uniform) return math.min(math.max(row, 0), _uniformLines - 1);
    // The last line whose first row is at or before `row`.
    var low = 0;
    var high = _rows.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_prefix[mid] <= row) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// Rows a line of [chars] characters takes at [charWidth] in [width].
  static int rowsFor(int chars, double charWidth, double width) {
    if (chars == 0 || charWidth <= 0 || width <= 0) return 1;
    final perRow = math.max(1, (width / charWidth).floor());
    return math.max(1, (chars / perRow).ceil());
  }
}
