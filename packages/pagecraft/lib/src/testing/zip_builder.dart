import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One file to put in a test archive, with every header field under the
/// test's control.
class ZipBuilderEntry {
  ZipBuilderEntry(
    this.name,
    this.data, {
    this.deflate = false,
    this.method,
    this.utf8Flag = false,
    this.encrypted = false,
    this.zip64 = false,
    this.declaredUncompressedSize,
    this.corruptLocalSignature = false,
  });

  final String name;
  final List<int> data;
  final bool deflate;

  /// Overrides the method written to the headers (for unsupported ones).
  final int? method;
  final bool utf8Flag;
  final bool encrypted;

  /// Writes sizes and offset as ZIP64 extra fields with `0xFFFFFFFF`
  /// placeholders in the central directory.
  final bool zip64;

  /// Lies about the uncompressed size in the directory.
  final int? declaredUncompressedSize;
  final bool corruptLocalSignature;
}

/// Writes a ZIP file byte by byte, the way the specification lays it out.
///
/// Used instead of `package:archive` so tests can produce flags, methods,
/// ZIP64 records and damage that a well-behaved writer never would.
class ZipBuilder {
  ZipBuilder({this.comment = '', this.zip64Eocd = false});

  /// Trailing archive comment, which moves the EOCD record away from the
  /// end of the file.
  final String comment;

  /// Writes a ZIP64 end-of-central-directory record and locator, with
  /// `0xFFFF`/`0xFFFFFFFF` placeholders in the classic record.
  final bool zip64Eocd;

  final _entries = <ZipBuilderEntry>[];

  ZipBuilder add(
    String name,
    List<int> data, {
    bool deflate = false,
    bool utf8Flag = false,
  }) {
    _entries.add(
      ZipBuilderEntry(name, data, deflate: deflate, utf8Flag: utf8Flag),
    );
    return this;
  }

  ZipBuilder addEntry(ZipBuilderEntry entry) {
    _entries.add(entry);
    return this;
  }

  Uint8List build() {
    final out = BytesBuilder(copy: false);
    final central = BytesBuilder(copy: false);
    for (final entry in _entries) {
      final nameBytes = entry.utf8Flag
          ? utf8.encode(entry.name)
          : latin1.encode(entry.name);
      final stored = entry.deflate
          ? ZLibEncoder(raw: true).convert(entry.data)
          : entry.data;
      final method = entry.method ?? (entry.deflate ? 8 : 0);
      final flags = (entry.utf8Flag ? 1 << 11 : 0) | (entry.encrypted ? 1 : 0);
      final uncompressedSize =
          entry.declaredUncompressedSize ?? entry.data.length;
      final localOffset = out.length;

      final local = _Writer()
        ..u32(entry.corruptLocalSignature ? 0x11111111 : 0x04034b50)
        ..u16(20)
        ..u16(flags)
        ..u16(method)
        ..u16(0)
        ..u16(0)
        ..u32(0)
        ..u32(stored.length)
        ..u32(uncompressedSize)
        ..u16(nameBytes.length)
        ..u16(0)
        ..bytes(nameBytes);
      out.add(local.toBytes());
      out.add(stored);

      final extra = _Writer();
      if (entry.zip64) {
        extra
          ..u16(0x0001)
          ..u16(24)
          ..u64(uncompressedSize)
          ..u64(stored.length)
          ..u64(localOffset);
      }
      final extraBytes = extra.toBytes();
      final cd = _Writer()
        ..u32(0x02014b50)
        ..u16(20)
        ..u16(20)
        ..u16(flags)
        ..u16(method)
        ..u16(0)
        ..u16(0)
        ..u32(0)
        ..u32(entry.zip64 ? 0xFFFFFFFF : stored.length)
        ..u32(entry.zip64 ? 0xFFFFFFFF : uncompressedSize)
        ..u16(nameBytes.length)
        ..u16(extraBytes.length)
        ..u16(0)
        ..u16(0)
        ..u16(0)
        ..u32(0)
        ..u32(entry.zip64 ? 0xFFFFFFFF : localOffset)
        ..bytes(nameBytes)
        ..bytes(extraBytes);
      central.add(cd.toBytes());
    }

    final centralOffset = out.length;
    final centralBytes = central.toBytes();
    out.add(centralBytes);
    final commentBytes = utf8.encode(comment);

    if (zip64Eocd) {
      final zip64Offset = out.length;
      final record = _Writer()
        ..u32(0x06064b50)
        ..u64(44)
        ..u16(45)
        ..u16(45)
        ..u32(0)
        ..u32(0)
        ..u64(_entries.length)
        ..u64(_entries.length)
        ..u64(centralBytes.length)
        ..u64(centralOffset);
      out.add(record.toBytes());
      final locator = _Writer()
        ..u32(0x07064b50)
        ..u32(0)
        ..u64(zip64Offset)
        ..u32(1);
      out.add(locator.toBytes());
    }

    final eocd = _Writer()
      ..u32(0x06054b50)
      ..u16(0)
      ..u16(0)
      ..u16(zip64Eocd ? 0xFFFF : _entries.length)
      ..u16(zip64Eocd ? 0xFFFF : _entries.length)
      ..u32(zip64Eocd ? 0xFFFFFFFF : centralBytes.length)
      ..u32(zip64Eocd ? 0xFFFFFFFF : centralOffset)
      ..u16(commentBytes.length)
      ..bytes(commentBytes);
    out.add(eocd.toBytes());
    return out.toBytes();
  }
}

class _Writer {
  final _builder = BytesBuilder(copy: false);

  void u16(int value) => _builder.add([value & 0xFF, (value >> 8) & 0xFF]);

  void u32(int value) {
    u16(value & 0xFFFF);
    u16((value >> 16) & 0xFFFF);
  }

  void u64(int value) {
    u32(value & 0xFFFFFFFF);
    u32((value >> 32) & 0xFFFFFFFF);
  }

  void bytes(List<int> value) => _builder.add(value);

  Uint8List toBytes() => _builder.toBytes();
}
