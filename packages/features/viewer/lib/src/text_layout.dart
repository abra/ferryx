import 'dart:math' as math;

import 'line_layout.dart';

/// Longer lines use viewport-sized slices instead of one native paragraph.
const maxTextParagraphLength = 2048;

/// A rendered fragment, still addressed within its original logical line.
class TextSlice {
  const TextSlice(this.line, this.start, this.end);

  final int line;
  final int start;
  final int end;
}

/// Logical line positions and lazy paragraph fragments share one index.
/// Splitting for display never changes the source or its search coordinates.
class TextLayout extends LineLayout {
  factory TextLayout({
    required List<String> sourceLines,
    required double lineHeight,
    required int columns,
    required bool wrap,
  }) {
    columns = math.max(1, columns);
    var longest = 0;
    if (!wrap) {
      for (final line in sourceLines) {
        longest = math.max(longest, line.length);
      }
      return TextLayout._unwrapped(sourceLines, lineHeight, columns, longest);
    }
    final longLines = <int, List<int>>{};
    final prefix = List<int>.filled(sourceLines.length + 1, 0);
    final rows = <int>[];
    var uniformFragments = true;
    for (var line = 0; line < sourceLines.length; line++) {
      final text = sourceLines[line];
      longest = math.max(longest, text.length);
      var fragments = 1;
      if (text.length > maxTextParagraphLength) {
        final ends = <int>[];
        var start = 0;
        while (start < text.length) {
          var end = scalarBoundaryBefore(
            text,
            math.min(start + columns, text.length),
          );
          if (end == start) end = math.min(start + 2, text.length);
          ends.add(end);
          start = end;
        }
        longLines[line] = ends;
        fragments = ends.length;
        rows.add(ends.length);
      } else {
        final count = _rowsFor(text.length, columns);
        rows.add(count);
        if (count != 1) uniformFragments = false;
      }
      prefix[line + 1] = prefix[line] + fragments;
    }
    return TextLayout._wrapped(
      sourceLines,
      lineHeight,
      columns,
      longest,
      rows,
      prefix,
      longLines,
      uniformFragments,
    );
  }

  TextLayout._unwrapped(
    this.sourceLines,
    double lineHeight,
    this.columns,
    this.maxLineLength,
  ) : wrap = false,
      uniformFragments = true,
      _prefix = const [],
      _longLines = const {},
      super.uniform(lineHeight: lineHeight, lines: sourceLines.length);

  TextLayout._wrapped(
    this.sourceLines,
    double lineHeight,
    this.columns,
    this.maxLineLength,
    List<int> rows,
    this._prefix,
    this._longLines,
    this.uniformFragments,
  ) : wrap = true,
      super(lineHeight: lineHeight, rowsPerLine: rows);

  final List<String> sourceLines;
  final int columns;
  final bool wrap;
  final int maxLineLength;
  final bool uniformFragments;
  final List<int> _prefix;
  final Map<int, List<int>> _longLines;

  int get fragmentCount => wrap ? _prefix.last : sourceLines.length;

  TextSlice fragmentAt(int index) {
    if (!wrap) return TextSlice(index, 0, sourceLines[index].length);
    var low = 0;
    var high = sourceLines.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_prefix[mid] <= index) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    final fragments = _longLines[low];
    if (fragments == null) return TextSlice(low, 0, sourceLines[low].length);
    final part = index - _prefix[low];
    return TextSlice(
      low,
      part == 0 ? 0 : fragments[part - 1],
      fragments[part],
    );
  }

  double heightOfFragment(int index) {
    final slice = fragmentAt(index);
    return _longLines.containsKey(slice.line)
        ? lineHeight
        : _rowsFor(slice.end - slice.start, columns) * lineHeight;
  }

  @override
  double offsetOfPosition(int line, int column) {
    if (!wrap || sourceLines.isEmpty) return offsetOfLine(line);
    line = line.clamp(0, sourceLines.length - 1);
    column = column.clamp(0, math.max(0, sourceLines[line].length - 1));
    final fragments = _longLines[line];
    if (fragments != null) {
      var low = 0;
      var high = fragments.length - 1;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (fragments[mid] <= column) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      return offsetOfLine(line) + low * lineHeight;
    }
    return offsetOfLine(line) + column ~/ columns * lineHeight;
  }
}

int _rowsFor(int length, int columns) =>
    math.max(1, (length + columns - 1) ~/ columns);

/// UTF-16 slice boundaries must not bisect a supplementary Unicode scalar.
int scalarBoundaryBefore(String text, int offset) {
  if (_splitsScalar(text, offset)) return offset - 1;
  return offset;
}

int scalarBoundaryAfter(String text, int offset) {
  if (_splitsScalar(text, offset)) return offset + 1;
  return offset;
}

bool _splitsScalar(String text, int offset) =>
    offset > 0 &&
    offset < text.length &&
    text.codeUnitAt(offset - 1) >= 0xD800 &&
    text.codeUnitAt(offset - 1) <= 0xDBFF &&
    text.codeUnitAt(offset) >= 0xDC00 &&
    text.codeUnitAt(offset) <= 0xDFFF;
