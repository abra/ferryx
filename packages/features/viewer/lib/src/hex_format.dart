import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Bytes to a hex row.
const int hexRowLength = 16;

/// One row of the hex mode: the offset, two groups of eight bytes and the
/// bytes as text. Missing bytes at the file's end leave their columns
/// blank, so the rows stay aligned.
@immutable
class HexRow {
  const HexRow({
    required this.offset,
    required this.left,
    required this.right,
    required this.ascii,
  });

  final int offset;
  final String left;
  final String right;
  final String ascii;

  /// `00000010  48 65 6C 6C 6F 20 57 6F  72 6C 64 0A 00 00 00 00  |Hello World.....|`
  String get text => '${hexOffsetText(offset)}  $left  $right  |$ascii|';
}

int hexRowCount(int length) => (length + hexRowLength - 1) ~/ hexRowLength;

String hexOffsetText(int offset) =>
    offset.toRadixString(16).toUpperCase().padLeft(8, '0');

/// The [row]th row of [bytes]; [baseOffset] is where the bytes start in
/// the file.
HexRow hexRow(Uint8List bytes, int row, {int baseOffset = 0}) {
  final start = row * hexRowLength;
  String group(int from, int to) {
    final cells = <String>[];
    for (var i = from; i < to; i++) {
      final at = start + i;
      cells.add(at < bytes.length ? _hexByte(bytes[at]) : '  ');
    }
    return cells.join(' ');
  }

  final ascii = StringBuffer();
  for (var i = 0; i < hexRowLength; i++) {
    final at = start + i;
    if (at >= bytes.length) {
      ascii.write(' ');
    } else {
      final byte = bytes[at];
      ascii.write(
        byte >= 0x20 && byte <= 0x7E ? String.fromCharCode(byte) : '.',
      );
    }
  }
  return HexRow(
    offset: baseOffset + start,
    left: group(0, hexRowLength ~/ 2),
    right: group(hexRowLength ~/ 2, hexRowLength),
    ascii: ascii.toString(),
  );
}

String _hexByte(int byte) =>
    byte.toRadixString(16).toUpperCase().padLeft(2, '0');

/// Where the [column]th byte's two hex digits start in a row's hex text
/// (`left + "  " + right`), for highlighting.
int hexCellStart(int column) {
  final inGroup = column % (hexRowLength ~/ 2);
  final group = column ~/ (hexRowLength ~/ 2);
  return group * (hexRowLength ~/ 2 * 3 + 1) + inGroup * 3;
}
