import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'exceptions.dart';

/// The hashes the Checksums dialog makes and checks.
enum ChecksumAlgorithm {
  sha256('SHA-256', 64, 'sha256'),
  sha1('SHA-1', 40, 'sha1'),
  md5('MD5', 32, 'md5'),
  blake3('BLAKE3', 64, 'b3');

  const ChecksumAlgorithm(this.label, this.hexLength, this.extension);

  /// The algorithm's own name, the same in every language.
  final String label;

  /// Hex digits of a hash.
  final int hexLength;

  /// The extension of a checksum file of it (`name.sha256`).
  final String extension;

  /// The algorithm named by a `:checksum` argument (`sha256`, `SHA-1`,
  /// `md5`, `b3`…), or `null`.
  static ChecksumAlgorithm? parse(String text) {
    final key = text.trim().toLowerCase().replaceAll('-', '');
    for (final algorithm in values) {
      if (algorithm.name == key || algorithm.extension == key) {
        return algorithm;
      }
    }
    return null;
  }

  /// The algorithm of a checksum file by its name (`disk.iso.sha256`,
  /// `SHA1SUMS`, `MD5SUMS.txt`, `x.b3`), or `null` for any other file. The
  /// core reads such a file with the same rules.
  static ChecksumAlgorithm? ofSumsFile(String name) {
    final lower = name.toLowerCase();
    final dot = lower.lastIndexOf('.');
    final extension = dot < 0 ? '' : lower.substring(dot + 1);
    final byExtension = switch (extension) {
      'sha256' || 'sha256sum' || 'sha256sums' => sha256,
      'sha1' || 'sha1sum' || 'sha1sums' => sha1,
      'md5' || 'md5sum' || 'md5sums' => md5,
      'b3' || 'b3sum' || 'b3sums' || 'blake3' => blake3,
      _ => null,
    };
    if (byExtension != null) return byExtension;
    final stem = extension == 'txt' ? lower.substring(0, dot) : lower;
    return switch (stem) {
      'sha256sums' || 'sha256sum' => sha256,
      'sha1sums' || 'sha1sum' => sha1,
      'md5sums' || 'md5sum' => md5,
      'b3sums' || 'blake3sums' => blake3,
      _ => null,
    };
  }
}

/// Hash the files under [paths] (folders walked).
@immutable
class ChecksumRequest extends Equatable {
  const ChecksumRequest({
    required this.paths,
    required this.base,
    required this.algorithm,
    this.recursive = true,
    this.includeHidden = false,
  });

  final List<String> paths;

  /// The folder names are relative to (the panel's folder).
  final String base;
  final ChecksumAlgorithm algorithm;
  final bool recursive;
  final bool includeHidden;

  @override
  List<Object?> get props => [paths, base, algorithm, recursive, includeHidden];
}

/// How a file fared.
enum ChecksumStatus {
  /// Hashed; checked against a checksum file, it matches.
  ok,

  /// Its hash differs from the one listed.
  mismatch,

  /// The file listed is not there.
  missing,

  /// It could not be read.
  error,
}

/// One file of the table, before its hash comes.
@immutable
class ChecksumFile extends Equatable {
  const ChecksumFile({
    required this.index,
    required this.name,
    required this.path,
    required this.size,
    this.expected,
  });

  final int index;

  /// Relative to the base (or the checksum file's folder), with `/`.
  final String name;
  final String path;
  final int size;

  /// Checking a checksum file: the hash it lists.
  final String? expected;

  @override
  List<Object?> get props => [index, name, path, size, expected];
}

@immutable
class ChecksumOutcome extends Equatable {
  const ChecksumOutcome({
    required this.index,
    required this.status,
    this.hash,
    this.error,
  });

  final int index;
  final ChecksumStatus status;
  final String? hash;

  /// Why the file could not be read.
  final FerryxException? error;

  @override
  List<Object?> get props => [index, status, hash, error];
}

/// What a running checksum task says: the files first, then their
/// outcomes by index.
@immutable
class ChecksumUpdate extends Equatable {
  const ChecksumUpdate({
    required this.taskId,
    this.algorithm,
    this.files = const [],
    this.outcomes = const [],
    this.filesDone = 0,
    this.filesTotal = 0,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.current,
    this.badLines = 0,
    this.done = false,
    this.error,
  });

  final int taskId;

  /// The algorithm a checksum file uses (when checking one).
  final ChecksumAlgorithm? algorithm;
  final List<ChecksumFile> files;
  final List<ChecksumOutcome> outcomes;
  final int filesDone;
  final int filesTotal;
  final int bytesDone;
  final int bytesTotal;
  final String? current;

  /// Checking a checksum file: lines that list nothing readable.
  final int badLines;
  final bool done;
  final String? error;

  @override
  List<Object?> get props => [
    taskId,
    algorithm,
    files,
    outcomes,
    filesDone,
    filesTotal,
    bytesDone,
    bytesTotal,
    current,
    badLines,
    done,
    error,
  ];
}

/// One line of a checksum file to save.
@immutable
class ChecksumLine extends Equatable {
  const ChecksumLine({required this.hash, required this.name});

  final String hash;
  final String name;

  @override
  List<Object?> get props => [hash, name];
}
