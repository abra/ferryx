import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../pagecraft_exception.dart';
import 'zip_cp437.dart';
import 'zip_entry.dart';

/// A ZIP file read in place: the central directory is parsed once, entry
/// bytes are read from the file on demand.
///
/// This is the container under EPUB, CBZ and zipped FB2. Only stored and
/// deflated entries are supported, which is what every book archive uses;
/// encrypted entries and other methods are reported, not read. CRCs are not
/// verified: a damaged image fails to decode, a damaged chapter fails to
/// parse, and both are reported where they are used.
///
/// All reads on one archive are serialized because `RandomAccessFile` allows
/// one pending operation at a time. Call [close] when done.
class ZipArchive {
  ZipArchive._(this.path, this._file, this.entries)
    : _byName = {for (final entry in entries) entry.name: entry};

  /// The file the archive was opened from.
  final String path;

  /// Entries in central-directory order, directories included.
  final List<ZipEntry> entries;

  final RandomAccessFile _file;
  final Map<String, ZipEntry> _byName;
  Future<void> _pending = Future.value();
  bool _closed = false;

  /// Central directories above this size are refused: a book archive has
  /// thousands of entries at most, and the directory is held in memory.
  static const maxCentralDirectoryBytes = 64 * 1024 * 1024;

  /// Maximum compressed and uncompressed bytes held for a single entry.
  static const maxEntryBytes = 128 * 1024 * 1024;
  static const maxCompressedEntryBytes = 128 * 1024 * 1024;

  /// Opens the file and parses its central directory.
  ///
  /// Throws [PagecraftException] when the file is not a ZIP archive or its
  /// directory is damaged; `FileSystemException` when it cannot be read.
  static Future<ZipArchive> open(String path) async {
    final file = await File(path).open();
    try {
      final entries = await _readCentralDirectory(file);
      return ZipArchive._(path, file, entries);
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  ZipEntry? entry(String name) => _byName[name];

  /// Reads one entry's bytes, inflating when needed.
  ///
  /// [maxBytes] lowers the default output limit of [maxEntryBytes]. Both the
  /// declared and actual output sizes are checked. Compressed input is also
  /// limited to [maxCompressedEntryBytes].
  Future<Uint8List> read(ZipEntry entry, {int? maxBytes}) {
    if (_closed) throw StateError('ZipArchive is closed: $path');
    _checkReadable(entry, maxBytes);
    return _synchronized(() => _readEntry(_file, entry, maxBytes));
  }

  /// Reads [entry] from the archive at [path] in a fresh file handle.
  ///
  /// For isolates: both arguments are plain data, so a page can be read and
  /// decoded off the UI isolate without re-parsing the directory.
  static Future<Uint8List> readDetached(
    String path,
    ZipEntry entry, {
    int? maxBytes,
  }) async {
    _checkReadable(entry, maxBytes);
    final file = await File(path).open();
    try {
      return await _readEntry(file, entry, maxBytes);
    } finally {
      await file.close();
    }
  }

  Future<void> close() {
    if (_closed) return _pending;
    _closed = true;
    return _synchronized(_file.close);
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }

  static void _checkReadable(ZipEntry entry, int? maxBytes) {
    if (maxBytes != null && maxBytes < 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes');
    }
    if (entry.compressedSize > maxCompressedEntryBytes) {
      throw PagecraftException('Compressed entry too large: ${entry.name}');
    }
    maxBytes = maxBytes == null || maxBytes > maxEntryBytes
        ? maxEntryBytes
        : maxBytes;
    if (entry.compression == ZipCompression.stored &&
        entry.compressedSize > entry.uncompressedSize) {
      throw PagecraftException(
        'Stored entry exceeds size limit: ${entry.name}',
      );
    }
    if (entry.isEncrypted) {
      throw PagecraftException('Encrypted entry: ${entry.name}');
    }
    if (entry.compression == ZipCompression.unsupported) {
      throw PagecraftException('Unsupported compression: ${entry.name}');
    }
    if (entry.uncompressedSize > maxBytes) {
      throw PagecraftException(
        'Entry too large: ${entry.name} is ${entry.uncompressedSize} bytes, '
        'limit $maxBytes',
      );
    }
  }

  static Future<Uint8List> _readEntry(
    RandomAccessFile file,
    ZipEntry entry,
    int? maxBytes,
  ) async {
    await file.setPosition(entry.localHeaderOffset);
    final header = await file.read(_localHeaderLength);
    if (header.length < _localHeaderLength ||
        _u32(header, 0) != _localHeaderSignature) {
      throw PagecraftException('Damaged local header: ${entry.name}');
    }
    final nameLength = _u16(header, 26);
    final extraLength = _u16(header, 28);
    await file.setPosition(
      entry.localHeaderOffset + _localHeaderLength + nameLength + extraLength,
    );
    final compressed = await file.read(entry.compressedSize);
    if (compressed.length != entry.compressedSize) {
      throw PagecraftException('Truncated entry: ${entry.name}');
    }
    final bytes = switch (entry.compression) {
      ZipCompression.stored => compressed,
      ZipCompression.deflate => await Isolate.run(
        () => _inflate(compressed, entry, maxBytes),
      ),
      ZipCompression.unsupported => throw StateError('checked earlier'),
    };
    if (bytes.length != entry.uncompressedSize) {
      throw PagecraftException(
        'Entry size mismatch: ${entry.name} inflated to ${bytes.length} '
        'bytes, expected ${entry.uncompressedSize}',
      );
    }
    return bytes;
  }

  static Uint8List _inflate(
    Uint8List compressed,
    ZipEntry entry,
    int? maxBytes,
  ) {
    final limit = [
      entry.uncompressedSize,
      maxBytes ?? maxEntryBytes,
      maxEntryBytes,
    ].reduce((a, b) => a < b ? a : b);
    final output = _BoundedInflateSink(limit, entry.name);
    try {
      final decoder = ZLibDecoder(raw: true).startChunkedConversion(output);
      for (var offset = 0; offset < compressed.length; offset += 4096) {
        final end = (offset + 4096).clamp(0, compressed.length);
        decoder.add(Uint8List.sublistView(compressed, offset, end));
      }
      decoder.close();
      return output.bytes.takeBytes();
    } on FormatException catch (e) {
      throw PagecraftException('Damaged deflate stream: ${entry.name} ($e)');
    }
  }

  static Future<List<ZipEntry>> _readCentralDirectory(
    RandomAccessFile file,
  ) async {
    final length = await file.length();
    // The end-of-central-directory record is in the last 22 bytes plus a
    // comment of at most 65535.
    final tailLength = length < _maxTailLength ? length : _maxTailLength;
    await file.setPosition(length - tailLength);
    final tail = await file.read(tailLength);
    final eocd = _findEocd(tail);
    if (eocd < 0) throw const PagecraftException('Not a ZIP archive');

    var entryCount = _u16(tail, eocd + 10);
    var directorySize = _u32(tail, eocd + 12);
    var directoryOffset = _u32(tail, eocd + 16);
    final needsZip64 =
        entryCount == 0xFFFF ||
        directorySize == 0xFFFFFFFF ||
        directoryOffset == 0xFFFFFFFF;
    if (needsZip64) {
      final locator = eocd - _zip64LocatorLength;
      if (locator < 0 || _u32(tail, locator) != _zip64LocatorSignature) {
        throw const PagecraftException('Damaged ZIP64 directory locator');
      }
      final zip64EocdOffset = _u64(tail, locator + 8);
      await file.setPosition(zip64EocdOffset);
      final record = await file.read(_zip64EocdLength);
      if (record.length < _zip64EocdLength ||
          _u32(record, 0) != _zip64EocdSignature) {
        throw const PagecraftException('Damaged ZIP64 directory record');
      }
      entryCount = _u64(record, 32);
      directorySize = _u64(record, 40);
      directoryOffset = _u64(record, 48);
    }
    if (directorySize > maxCentralDirectoryBytes ||
        directoryOffset + directorySize > length) {
      throw const PagecraftException('Damaged central directory');
    }

    await file.setPosition(directoryOffset);
    final directory = await file.read(directorySize);
    if (directory.length != directorySize) {
      throw const PagecraftException('Truncated central directory');
    }
    return _parseEntries(directory, entryCount);
  }

  static int _findEocd(Uint8List tail) {
    for (var i = tail.length - _eocdLength; i >= 0; i--) {
      if (_u32(tail, i) == _eocdSignature &&
          i + _eocdLength + _u16(tail, i + 20) == tail.length) {
        return i;
      }
    }
    return -1;
  }

  static List<ZipEntry> _parseEntries(Uint8List directory, int entryCount) {
    final entries = <ZipEntry>[];
    var offset = 0;
    for (var i = 0; i < entryCount; i++) {
      if (offset + _centralHeaderLength > directory.length ||
          _u32(directory, offset) != _centralHeaderSignature) {
        throw const PagecraftException('Damaged central directory entry');
      }
      final flags = _u16(directory, offset + 8);
      final method = _u16(directory, offset + 10);
      final crc32 = _u32(directory, offset + 16);
      var compressedSize = _u32(directory, offset + 20);
      var uncompressedSize = _u32(directory, offset + 24);
      final nameLength = _u16(directory, offset + 28);
      final extraLength = _u16(directory, offset + 30);
      final commentLength = _u16(directory, offset + 32);
      var localHeaderOffset = _u32(directory, offset + 42);
      final nameStart = offset + _centralHeaderLength;
      final extraStart = nameStart + nameLength;
      final end = extraStart + extraLength + commentLength;
      if (end > directory.length) {
        throw const PagecraftException('Damaged central directory entry');
      }

      // ZIP64 extra field: only the fields that overflowed are present, in
      // this order.
      var extra = extraStart;
      while (extra + 4 <= extraStart + extraLength) {
        final id = _u16(directory, extra);
        final size = _u16(directory, extra + 2);
        if (id == _zip64ExtraId) {
          var field = extra + 4;
          if (uncompressedSize == 0xFFFFFFFF) {
            uncompressedSize = _u64(directory, field);
            field += 8;
          }
          if (compressedSize == 0xFFFFFFFF) {
            compressedSize = _u64(directory, field);
            field += 8;
          }
          if (localHeaderOffset == 0xFFFFFFFF) {
            localHeaderOffset = _u64(directory, field);
          }
          break;
        }
        extra += 4 + size;
      }

      final utf8Names = flags & _utf8Flag != 0;
      final nameBytes = Uint8List.sublistView(directory, nameStart, extraStart);
      entries.add(
        ZipEntry(
          name: utf8Names
              ? utf8.decode(nameBytes)
              : _decodeLegacyName(nameBytes),
          compression: switch (method) {
            0 => ZipCompression.stored,
            8 => ZipCompression.deflate,
            _ => ZipCompression.unsupported,
          },
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize,
          localHeaderOffset: localHeaderOffset,
          crc32: crc32,
          isEncrypted: flags & _encryptedFlag != 0,
        ),
      );
      offset = end;
    }
    return entries;
  }

  /// Names without the UTF-8 flag are CP437 by the specification, but most
  /// tools write UTF-8 anyway and leave the flag clear.
  static String _decodeLegacyName(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return decodeCp437(bytes);
    }
  }

  static int _u16(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _u32(Uint8List bytes, int offset) =>
      _u16(bytes, offset) | (_u16(bytes, offset + 2) << 16);

  static int _u64(Uint8List bytes, int offset) =>
      _u32(bytes, offset) | (_u32(bytes, offset + 4) << 32);

  static const _eocdSignature = 0x06054b50;
  static const _eocdLength = 22;
  static const _maxTailLength = _eocdLength + 0xFFFF;
  static const _zip64LocatorSignature = 0x07064b50;
  static const _zip64LocatorLength = 20;
  static const _zip64EocdSignature = 0x06064b50;
  static const _zip64EocdLength = 56;
  static const _zip64ExtraId = 0x0001;
  static const _centralHeaderSignature = 0x02014b50;
  static const _centralHeaderLength = 46;
  static const _localHeaderSignature = 0x04034b50;
  static const _localHeaderLength = 30;
  static const _encryptedFlag = 1 << 0;
  static const _utf8Flag = 1 << 11;
}

class _BoundedInflateSink implements Sink<List<int>> {
  _BoundedInflateSink(this.limit, this.name);
  final int limit;
  final String name;
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > limit) {
      throw PagecraftException('Inflated entry exceeds size limit: $name');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
