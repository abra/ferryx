/// Palm database files: the container of MOBI books. Records are read
/// on demand from the file, so a 40 MB book costs the header and the
/// record offsets until a record is asked for.
library;

import 'dart:io';
import 'dart:typed_data';

import '../../pagecraft_exception.dart';
import 'mobi_headers.dart';

/// A PDB file open for random access to its records.
class PdbFile {
  PdbFile._(
    this.path,
    this._file,
    this.name,
    this.type,
    this.creator,
    this._offsets,
  );

  /// Opens [path] and reads the header and record offsets.
  static Future<PdbFile> open(String path) async {
    final file = await File(path).open();
    try {
      final head = await file.read(78);
      if (head.length < 78) {
        throw const PagecraftException('Not a PDB file');
      }
      final b = MobiBytes(head);
      final numRecords = b.u16(76);
      final table = await file.read(numRecords * 8);
      if (table.length < numRecords * 8) {
        throw const PagecraftException('Truncated PDB record list');
      }
      final t = MobiBytes(table);
      final fileLength = await file.length();
      final offsets = List<int>.generate(numRecords + 1, (i) {
        return i < numRecords ? t.u32(i * 8) : fileLength;
      });
      return PdbFile._(
        path,
        file,
        b.ascii(0, 32).replaceAll('\u0000', ''),
        b.ascii(60, 4),
        b.ascii(64, 4),
        offsets,
      );
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  final String path;
  final RandomAccessFile _file;
  final String name;
  final String type;
  final String creator;

  /// Record start offsets, with the file length as the last entry.
  final List<int> _offsets;
  Future<void> _pending = Future.value();

  int get numRecords => _offsets.length - 1;

  /// A snapshot for the native text reader; includes the final file boundary.
  Int64List get recordOffsets => Int64List.fromList(_offsets);

  bool get isMobi => type == 'BOOK' && creator == 'MOBI';

  /// Record [index] as bytes.
  Future<Uint8List> readRecord(int index) {
    if (index < 0 || index >= numRecords) {
      throw RangeError.range(index, 0, numRecords - 1, 'index');
    }
    final start = _offsets[index];
    final end = _offsets[index + 1];
    return _synchronized(() async {
      await _file.setPosition(start);
      return _file.read(end > start ? end - start : 0);
    });
  }

  /// The first four bytes of record [index], its magic.
  Future<String> readMagic(int index) async {
    if (index < 0 || index >= numRecords) {
      throw RangeError.range(index, 0, numRecords - 1, 'index');
    }
    final start = _offsets[index];
    final bytes = await _synchronized(() async {
      await _file.setPosition(start);
      return _file.read(4);
    });
    return String.fromCharCodes(bytes);
  }

  Future<void> close() => _synchronized(() => _file.close());

  /// Reads share one file position: calls run one after another.
  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// Whether the file at [path] is a MOBI book (`isMOBI`): a PDB whose
/// type and creator read `BOOKMOBI`.
Future<bool> isMobiFile(String path) async {
  final file = await File(path).open();
  try {
    await file.setPosition(60);
    final magic = await file.read(8);
    return String.fromCharCodes(magic) == 'BOOKMOBI';
  } finally {
    await file.close();
  }
}
