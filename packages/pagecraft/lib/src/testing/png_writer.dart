import 'dart:io';
import 'dart:typed_data';

/// Encodes a solid-colour RGBA PNG of the given size. Deterministic: the
/// same arguments give the same bytes, so fixtures can be hashed.
Uint8List encodeSolidPng(int width, int height, {int rgba = 0x336699FF}) {
  final row = Uint8List(1 + width * 4);
  for (var x = 0; x < width; x++) {
    row[1 + x * 4] = (rgba >> 24) & 0xFF;
    row[2 + x * 4] = (rgba >> 16) & 0xFF;
    row[3 + x * 4] = (rgba >> 8) & 0xFF;
    row[4 + x * 4] = rgba & 0xFF;
  }
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    raw.add(row);
  }
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(
    out,
    'IDAT',
    Uint8List.fromList(ZLibEncoder(level: 6).convert(raw.toBytes())),
  );
  _chunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final typeBytes = type.codeUnits;
  final length = ByteData(4)..setUint32(0, data.length);
  out.add(length.buffer.asUint8List());
  out.add(typeBytes);
  out.add(data);
  final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
  out.add(crc.buffer.asUint8List());
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
