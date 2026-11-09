/// Dart reference for MOBI text-record decoding: variable-length integers,
/// trailing entries, PalmDOC (LZ77) and Huffman/CDIC decompression, based on
/// `mobi.js`. Production text records use the internal Rust backend; the index
/// parser also uses the variable-length integer helpers here.
library;

import 'dart:math';
import 'dart:typed_data';

import 'mobi_headers.dart';

/// A variable-length quantity read forward: 7 bits per byte, the high bit
/// marks the last byte (`getVarLen`).
({int value, int length}) readVarLen(Uint8List bytes, [int offset = 0]) {
  var value = 0;
  var length = 0;
  final end = offset + 4 < bytes.length ? offset + 4 : bytes.length;
  for (var i = offset; i < end; i++) {
    final byte = bytes[i];
    value = (value << 7) | (byte & 0x7F);
    length++;
    if (byte & 0x80 != 0) break;
  }
  return (value: value, length: length);
}

/// A variable-length quantity read from the end of [bytes]: the high
/// bit marks the first byte (`getVarLenFromEnd`).
int readVarLenFromEnd(Uint8List bytes) {
  var value = 0;
  final start = bytes.length > 4 ? bytes.length - 4 : 0;
  for (var i = start; i < bytes.length; i++) {
    final byte = bytes[i];
    if (byte & 0x80 != 0) value = 0;
    value = (value << 7) | (byte & 0x7F);
  }
  return value;
}

int countBitsSet(int x) {
  var count = 0;
  for (; x > 0; x >>= 1) {
    if (x & 1 == 1) count++;
  }
  return count;
}

int countUnsetEnd(int x) {
  var count = 0;
  while (x & 1 == 0) {
    x >>= 1;
    count++;
  }
  return count;
}

/// Strips the trailing entries a text record carries after its text: one
/// variable-length entry per set flag bit, then the multibyte overlap
/// (`#removeTrailingEntries`).
Uint8List removeTrailingEntries(Uint8List record, int trailingFlags) {
  final multibyte = trailingFlags & 1 != 0;
  final entries = countBitsSet(trailingFlags >> 1);
  var bytes = record;
  // A size past the start leaves nothing, as `subarray` clamps it.
  Uint8List cut(int length) =>
      Uint8List.sublistView(bytes, 0, max(0, bytes.length - length));
  for (var i = 0; i < entries; i++) {
    bytes = cut(readVarLenFromEnd(bytes));
  }
  if (multibyte && bytes.isNotEmpty) {
    bytes = cut((bytes[bytes.length - 1] & 0x3) + 1);
  }
  return bytes;
}

/// PalmDOC decompression (`decompressPalmDOC`).
Uint8List decompressPalmDoc(Uint8List input) {
  final out = BytesBuilder(copy: false);
  // The output is needed for back references; keep a growable copy.
  final output = <int>[];
  for (var i = 0; i < input.length; i++) {
    final byte = input[i];
    if (byte == 0) {
      output.add(0);
    } else if (byte <= 8) {
      final end = i + byte + 1 > input.length ? input.length : i + byte + 1;
      for (var j = i + 1; j < end; j++) {
        output.add(input[j]);
      }
      i += byte;
    } else if (byte <= 0x7F) {
      output.add(byte);
    } else if (byte <= 0xBF) {
      if (i + 1 >= input.length) break;
      final pair = (byte << 8) | input[i + 1];
      i++;
      final distance = (pair & 0x3FFF) >> 3;
      final length = (pair & 0x7) + 3;
      for (var j = 0; j < length; j++) {
        final from = output.length - distance;
        output.add(from >= 0 && from < output.length ? output[from] : 0);
      }
    } else {
      output
        ..add(32)
        ..add(byte ^ 0x80);
    }
  }
  out.add(output);
  return out.toBytes();
}

/// Huffman/CDIC decompression (`huffcdic`): a HUFF record with the code
/// tables and CDIC records with the dictionary, loaded through
/// [loadRecord]; entries decompress lazily and are cached.
class HuffCdicDecoder {
  HuffCdicDecoder._(this._table1, this._table2, this._dictionary);

  static Future<HuffCdicDecoder> load(
    MobiHeader mobi,
    Future<Uint8List> Function(int index) loadRecord,
  ) async {
    final huff = MobiBytes(await loadRecord(mobi.huffcdic));
    if (huff.ascii(0, 4) != 'HUFF') {
      throw const FormatException('Invalid HUFF record');
    }
    final offset1 = huff.u32(8);
    final offset2 = huff.u32(12);
    final table1 = List<_Table1Entry>.generate(256, (i) {
      final x = huff.u32(offset1 + i * 4);
      return _Table1Entry(
        found: x & 0x80 != 0,
        codeLength: x & 0x1F,
        value: x >>> 8,
      );
    });
    final table2 = List<_Table2Entry?>.filled(33, null);
    for (var i = 0; i < 32; i++) {
      final offset = offset2 + i * 8;
      table2[i + 1] = _Table2Entry(
        min: huff.u32(offset),
        max: huff.u32(offset + 4),
      );
    }
    final dictionary = <_DictionaryEntry>[];
    for (var i = 1; i < mobi.numHuffcdic; i++) {
      final record = MobiBytes(await loadRecord(mobi.huffcdic + i));
      if (record.ascii(0, 4) != 'CDIC') {
        throw const FormatException('Invalid CDIC record');
      }
      final headerLength = record.u32(4);
      final numEntries = record.u32(8);
      final codeLength = record.u32(12);
      // `numEntries` counts entries across every CDIC record.
      final n = _min(1 << codeLength, numEntries - dictionary.length);
      final buffer = MobiBytes(record.slice(headerLength));
      for (var j = 0; j < n; j++) {
        final offset = buffer.u16(j * 2);
        final x = buffer.u16(offset);
        final length = x & 0x7FFF;
        final decompressed = x & 0x8000 != 0;
        dictionary.add(
          _DictionaryEntry(
            buffer.slice(offset + 2, offset + 2 + length),
            decompressed,
          ),
        );
      }
    }
    return HuffCdicDecoder._(table1, table2, dictionary);
  }

  final List<_Table1Entry> _table1;
  final List<_Table2Entry?> _table2;
  final List<_DictionaryEntry> _dictionary;

  Uint8List decompress(Uint8List bytes) {
    final out = BytesBuilder(copy: false);
    final bitLength = bytes.length * 8;
    var i = 0;
    while (i < bitLength) {
      final bits = _read32Bits(bytes, i);
      final entry = _table1[bits >>> 24];
      var codeLength = entry.codeLength;
      var value = entry.value;
      if (!entry.found) {
        while (bits >>> (32 - codeLength) < _table2[codeLength]!.min) {
          codeLength++;
        }
        value = _table2[codeLength]!.max;
      }
      i += codeLength;
      if (i > bitLength) break;
      final code = value - (bits >>> (32 - codeLength));
      if (code < 0 || code >= _dictionary.length) {
        throw const FormatException('Huffman code outside the dictionary');
      }
      var result = _dictionary[code];
      if (!result.decompressed) {
        result = _DictionaryEntry(decompress(result.bytes), true);
        _dictionary[code] = result;
      }
      out.add(result.bytes);
    }
    return out.toBytes();
  }

  /// 32 bits of [bytes] from bit [from], zero-padded past the end
  /// (`read32Bits`).
  static int _read32Bits(Uint8List bytes, int from) {
    final startByte = from >> 3;
    final end = from + 32;
    final endByte = end >> 3;
    var bits = 0;
    for (var i = startByte; i <= endByte; i++) {
      bits = (bits << 8) | (i < bytes.length ? bytes[i] : 0);
    }
    return (bits >> (8 - (end & 7))) & 0xFFFFFFFF;
  }
}

int _min(int a, int b) => a < b ? a : b;

class _Table1Entry {
  const _Table1Entry({
    required this.found,
    required this.codeLength,
    required this.value,
  });

  final bool found;
  final int codeLength;
  final int value;
}

class _Table2Entry {
  const _Table2Entry({required this.min, required this.max});

  final int min;
  final int max;
}

class _DictionaryEntry {
  const _DictionaryEntry(this.bytes, this.decompressed);

  final Uint8List bytes;
  final bool decompressed;
}
