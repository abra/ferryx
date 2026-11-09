import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;

import 'native_library.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' as frb;
import 'rust/api.dart' as rust;

/// A decoding or file error reported by the native MOBI reader.
class MobiNativeException implements Exception {
  const MobiNativeException(this.message);
  final String message;

  @override
  String toString() => 'MobiNativeException: $message';
}

/// Owns one file and one dictionary cache; all work runs on the FRB pool.
/// Header parsing, chapter reconstruction and rendering belong to Pagecraft.
class NativeMobiTextReader {
  NativeMobiTextReader._(this._reader, this.recordCount);

  final rust.MobiTextReader _reader;
  final int recordCount;
  Future<void> _pending = Future.value();
  Future<void>? _closing;

  static Future<NativeMobiTextReader> open({
    required String path,
    required Int64List recordOffsets,
    required int textStart,
    required int textCount,
    required int dictionaryStart,
    required int dictionaryCount,
    required int compression,
    required int trailingFlags,
  }) async {
    for (final value in [
      textStart,
      textCount,
      dictionaryStart,
      dictionaryCount,
      trailingFlags,
    ]) {
      RangeError.checkValueInInterval(value, 0, 0xffffffff);
    }
    RangeError.checkValueInInterval(compression, 0, 0xffff, 'compression');
    await initializeMobiNative();
    final reader = await _nativeCall(
      () => rust.MobiTextReader.open(
        path: path,
        config: rust.MobiTextConfig(
          recordOffsets: frb.Int64List.raw(recordOffsets),
          textStart: textStart,
          textCount: textCount,
          dictionaryStart: dictionaryStart,
          dictionaryCount: dictionaryCount,
          compression: compression,
          trailingFlags: trailingFlags,
        ),
      ),
    );
    return NativeMobiTextReader._(reader, textCount);
  }

  Future<Uint8List> readRecord(int index) {
    if (index < 0 || index >= recordCount) {
      throw RangeError.index(index, this, 'index', null, recordCount);
    }
    _checkOpen();
    return _enqueue(() => _nativeCall(() => _reader.readRecord(index: index)));
  }

  Future<Uint8List> readRecords(int start, int count) {
    RangeError.checkValueInInterval(start, 0, recordCount, 'start');
    RangeError.checkValueInInterval(count, 0, recordCount - start, 'count');
    _checkOpen();
    return _enqueue(
      () => _nativeCall(
        () => _reader.readRecords(start: start, count: count),
      ),
    );
  }

  /// Drains accepted reads and releases the file and native handle once.
  Future<void> close() => _closing ??= _enqueue(() async {
    try {
      await _reader.close();
    } finally {
      _reader.dispose();
    }
  });

  void _checkOpen() {
    if (_closing != null) throw StateError('MOBI text reader is closed');
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

Future<T> _nativeCall<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on AnyhowException catch (error) {
    throw MobiNativeException(error.message);
  }
}
