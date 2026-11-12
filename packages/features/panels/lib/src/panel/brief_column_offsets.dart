/// Prefix offsets built once for a set of column widths. Cursor targets
/// use O(1) lookup; animation frames find their column in O(log n).
class BriefColumnOffsets {
  BriefColumnOffsets(List<double> widths)
    : _offsets = List.filled(widths.length + 1, 0) {
    for (var i = 0; i < widths.length; i++) {
      _offsets[i + 1] = _offsets[i] + widths[i];
    }
  }

  final List<double> _offsets;

  int get length => _offsets.length - 1;
  double startOf(int column) => _offsets[column];
  double endOf(int column) => _offsets[column + 1];

  int columnAt(double offset) {
    if (length == 0) return 0;
    var low = 0, high = length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_offsets[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}
