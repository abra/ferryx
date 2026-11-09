import 'package:meta/meta.dart';

/// How an entry's bytes are stored inside the archive.
enum ZipCompression {
  /// Method 0: the bytes are stored as they are.
  stored,

  /// Method 8: raw deflate.
  deflate,

  /// Any other method; [ZipArchive.read] refuses it.
  unsupported,
}

/// One file or directory listed in an archive's central directory.
///
/// Plain data, so it can be sent to another isolate together with the
/// archive's path (see [ZipArchive.readDetached]).
@immutable
class ZipEntry {
  const ZipEntry({
    required this.name,
    required this.compression,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.crc32,
    required this.isEncrypted,
  });

  /// Path inside the archive with `/` separators, as the archive spells it.
  final String name;

  final ZipCompression compression;

  /// Byte count on disk, before inflating.
  final int compressedSize;

  /// Byte count [ZipArchive.read] returns.
  final int uncompressedSize;

  /// Where the entry's local header starts in the file.
  final int localHeaderOffset;

  final int crc32;

  /// Traditional PKWARE or AES encryption; [ZipArchive.read] refuses it.
  final bool isEncrypted;

  bool get isDirectory => name.endsWith('/');

  @override
  bool operator ==(Object other) =>
      other is ZipEntry &&
      other.name == name &&
      other.compression == compression &&
      other.compressedSize == compressedSize &&
      other.uncompressedSize == uncompressedSize &&
      other.localHeaderOffset == localHeaderOffset &&
      other.crc32 == crc32 &&
      other.isEncrypted == isEncrypted;

  @override
  int get hashCode => Object.hash(
    name,
    compression,
    compressedSize,
    uncompressedSize,
    localHeaderOffset,
    crc32,
    isEncrypted,
  );

  @override
  String toString() =>
      'ZipEntry($name, ${compression.name}, $uncompressedSize bytes)';
}
