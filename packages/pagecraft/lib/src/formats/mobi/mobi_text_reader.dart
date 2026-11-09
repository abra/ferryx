import 'dart:io';
import 'dart:typed_data';

import '../../pagecraft_exception.dart';
import 'mobi_compression.dart';
import 'mobi_headers.dart';
import 'native/native_mobi_text_reader.dart';
import 'pdb.dart';

/// Internal text-byte boundary; format parsing and chapter assembly stay in Dart.
abstract interface class MobiTextReader {
  Future<Uint8List> readRecord(int index);
  Future<Uint8List> readAll();
  Future<void> close();

  static Future<MobiTextReader> open(
    PdbFile pdb,
    MobiHeaders headers,
    int start,
  ) async {
    final huff = headers.palmdoc.compression == 17480;
    final reader = await _native(
      () => NativeMobiTextReader.open(
        path: File(pdb.path).absolute.path,
        recordOffsets: pdb.recordOffsets,
        textStart: start + 1,
        textCount: headers.palmdoc.numTextRecords,
        dictionaryStart: huff ? start + headers.mobi.huffcdic : 0,
        dictionaryCount: huff ? headers.mobi.numHuffcdic : 0,
        compression: headers.palmdoc.compression,
        trailingFlags: headers.mobi.trailingFlags,
      ),
    );
    return _NativeMobiTextReader(reader);
  }

  /// Retains the current Dart implementation as the comparison reference.
  static Future<MobiTextReader> openDart(
    PdbFile pdb,
    MobiHeaders headers,
    int start,
  ) async {
    final Uint8List Function(Uint8List) decode;
    switch (headers.palmdoc.compression) {
      case 1:
        decode = (bytes) => bytes;
      case 2:
        decode = decompressPalmDoc;
      case 17480:
        final dictionary = await HuffCdicDecoder.load(
          headers.mobi,
          (index) => pdb.readRecord(start + index),
        );
        decode = dictionary.decompress;
      default:
        throw const PagecraftException('Unknown compression type');
    }
    return _DartMobiTextReader(pdb, headers, start, decode);
  }
}

class _NativeMobiTextReader implements MobiTextReader {
  _NativeMobiTextReader(this._reader);
  final NativeMobiTextReader _reader;

  @override
  Future<Uint8List> readRecord(int index) =>
      _native(() => _reader.readRecord(index));

  @override
  Future<Uint8List> readAll() =>
      _native(() => _reader.readRecords(0, _reader.recordCount));

  @override
  Future<void> close() => _reader.close();
}

Future<T> _native<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on MobiNativeException catch (error) {
    throw PagecraftException('MOBI text: ${error.message}');
  }
}

class _DartMobiTextReader implements MobiTextReader {
  _DartMobiTextReader(this._pdb, this._headers, this._start, this._decode);
  final PdbFile _pdb;
  final MobiHeaders _headers;
  final int _start;
  final Uint8List Function(Uint8List) _decode;
  Future<void> _pending = Future.value();
  Future<void>? _closing;

  Future<Uint8List> _read(int index) async {
    if (index < 0 || index >= _headers.palmdoc.numTextRecords) {
      throw RangeError.index(
        index,
        this,
        'index',
        null,
        _headers.palmdoc.numTextRecords,
      );
    }
    final record = await _pdb.readRecord(_start + index + 1);
    return _decode(removeTrailingEntries(record, _headers.mobi.trailingFlags));
  }

  @override
  Future<Uint8List> readRecord(int index) => _enqueue(() => _read(index));

  @override
  Future<Uint8List> readAll() => _enqueue(() async {
    final bytes = BytesBuilder(copy: false);
    for (var i = 0; i < _headers.palmdoc.numTextRecords; i++) {
      bytes.add(await _read(i));
    }
    return bytes.takeBytes();
  });

  @override
  Future<void> close() => _closing ??= _pending;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    if (_closing != null) throw StateError('MOBI text reader is closed');
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
