/// Font files as the engine takes them: TrueType and OpenType (`sfnt`)
/// and collections as they are, WOFF 1.0 unpacked to `sfnt`. WOFF2
/// needs Brotli and is not read.
library;

import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

const _trueType = 0x00010000;
const _otto = 0x4F54544F; // 'OTTO'
const _true = 0x74727565; // 'true'
const _ttcf = 0x74746366; // 'ttcf'
const _woff = 0x774F4646; // 'wOFF'

/// [bytes] as a font the engine loads, or null when they are not one it
/// can (WOFF2, damage, something else).
Uint8List? sfntOf(Uint8List bytes) {
  if (bytes.length < 12) return null;
  final data = ByteData.sublistView(bytes);
  return switch (data.getUint32(0)) {
    _trueType || _otto || _true || _ttcf => bytes,
    _woff => _unwoff(data),
    _ => null,
  };
}

/// WOFF 1.0: a header, a table directory, then each table, zlib
/// compressed when that made it smaller. The `sfnt` gets the flavor,
/// the same tables in the same order, each padded to four bytes.
Uint8List? _unwoff(ByteData woff) {
  try {
    final flavor = woff.getUint32(4);
    final count = woff.getUint16(12);
    final sfntSize = woff.getUint32(16);
    if (count == 0 || sfntSize > 64 << 20) return null;
    final out = ByteData(sfntSize);
    var power = 1;
    var log = 0;
    while (power * 2 <= count) {
      power *= 2;
      log++;
    }
    out
      ..setUint32(0, flavor)
      ..setUint16(4, count)
      ..setUint16(6, power * 16)
      ..setUint16(8, log)
      ..setUint16(10, count * 16 - power * 16);
    var offset = 12 + 16 * count;
    final bytes = woff.buffer.asUint8List(
      woff.offsetInBytes,
      woff.lengthInBytes,
    );
    for (var i = 0; i < count; i++) {
      final entry = 44 + 20 * i;
      final tag = woff.getUint32(entry);
      final at = woff.getUint32(entry + 4);
      final compressed = woff.getUint32(entry + 8);
      final length = woff.getUint32(entry + 12);
      final checksum = woff.getUint32(entry + 16);
      final raw = bytes.sublist(at, at + compressed);
      final table = compressed < length
          ? Uint8List.fromList(ZLibDecoder().convert(raw))
          : raw;
      if (table.length != length || offset + length > sfntSize) return null;
      out
        ..setUint32(12 + 16 * i, tag)
        ..setUint32(16 + 16 * i, checksum)
        ..setUint32(20 + 16 * i, offset)
        ..setUint32(24 + 16 * i, length);
      out.buffer.asUint8List().setRange(offset, offset + length, table);
      offset += (length + 3) & ~3;
    }
    return out.buffer.asUint8List();
  } on Object {
    // A damaged file: as if it were not there.
    return null;
  }
}
