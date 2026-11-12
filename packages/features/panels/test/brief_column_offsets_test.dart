import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/panel/brief_column_offsets.dart';

void main() {
  test('variable widths resolve exact boundaries, partial columns and out-of-range offsets', () {
    final columns = BriefColumnOffsets([120, 210, 150]);
    expect(columns.startOf(0), 0);
    expect(columns.endOf(0), 120);
    expect(columns.startOf(2), 330);
    expect(columns.endOf(2), 480);
    for (final (offset, column) in [
      (-1.0, 0),
      (0.0, 0),
      (119.9, 0),
      (120.0, 1),
      (329.9, 1),
      (330.0, 2),
      (480.0, 2),
      (9999.0, 2),
    ]) {
      expect(columns.columnAt(offset), column, reason: '$offset');
    }
    expect(BriefColumnOffsets([]).columnAt(0), 0);
  });

  test('large column sets support direct far-end lookups', () {
    final columns = BriefColumnOffsets(List.filled(100000, 200));
    expect(columns.startOf(99999), 19999800);
    expect(columns.endOf(99999), 20000000);
    expect(columns.columnAt(19999800), 99999);
    expect(columns.columnAt(12345678), 61728);
  });
}
