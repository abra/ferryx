import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_feature/src/hex_format.dart';

void main() {
  test('a full row: offset, two groups, the bytes as text', () {
    final bytes = Uint8List.fromList(
      utf8.encode('Hello World\n') + [0, 1, 0x7F, 0xFF],
    );
    final row = hexRow(bytes, 0, baseOffset: 16);
    expect(row.offset, 16);
    expect(row.left, '48 65 6C 6C 6F 20 57 6F');
    expect(row.right, '72 6C 64 0A 00 01 7F FF');
    expect(row.ascii, 'Hello World.....');
    expect(
      row.text,
      '00000010  48 65 6C 6C 6F 20 57 6F  72 6C 64 0A 00 01 7F FF  |Hello World.....|',
    );
  });

  test('a short last row keeps its columns aligned', () {
    final bytes = Uint8List.fromList([0x41, 0x42, 0x43]);
    final row = hexRow(bytes, 0);
    expect(row.left, '41 42 43${' ' * 15}');
    expect(row.right, ' ' * 23);
    expect(row.ascii, 'ABC             ');
    expect(row.text.length, hexRow(Uint8List(16), 0).text.length);
  });

  test('rows and cells', () {
    expect(hexRowCount(0), 0);
    expect(hexRowCount(16), 1);
    expect(hexRowCount(17), 2);
    expect(hexOffsetText(0xABCDE), '000ABCDE');
    expect(hexCellStart(0), 0);
    expect(hexCellStart(1), 3);
    expect(hexCellStart(7), 21);
    // The second group starts after the first's 23 characters and two
    // spaces.
    expect(hexCellStart(8), 25);
    expect(hexCellStart(15), 46);
  });
}
