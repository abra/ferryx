import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

enum ArchiveType {
  zip('zip', 'ZIP'),
  sevenZip('7z', '7z'),
  tar('tar', 'TAR'),
  tarGzip('tar.gz', 'TAR + gzip'),
  tarBzip2('tar.bz2', 'TAR + bzip2'),
  tarXz('tar.xz', 'TAR + xz'),
  tarZstd('tar.zst', 'TAR + zstd'),
  tarLz4('tar.lz4', 'TAR + LZ4'),
  gzip('gz', 'gzip'),
  bzip2('bz2', 'bzip2'),
  xz('xz', 'xz'),
  zstd('zst', 'zstd'),
  lz4('lz4', 'LZ4'),
  rar('rar', 'RAR');

  const ArchiveType(this.extension, this.label);
  final String extension;
  final String label;

  bool get singleFileOnly => switch (this) {
    gzip || bzip2 || xz || zstd || lz4 => true,
    _ => false,
  };
  ArchiveType get container => switch (this) {
    gzip => tarGzip,
    bzip2 => tarBzip2,
    xz => tarXz,
    zstd => tarZstd,
    lz4 => tarLz4,
    _ => this,
  };

  static ArchiveType? parse(String value) {
    for (final type in values) {
      if (type.name == value || type.extension == value.toLowerCase()) {
        return type;
      }
    }
    return null;
  }

  String nameFor(String name) {
    var stem = name;
    final sorted = values.toList()
      ..sort((a, b) => b.extension.length.compareTo(a.extension.length));
    for (final type in sorted) {
      if (stem.toLowerCase().endsWith('.${type.extension}')) {
        stem = stem.substring(0, stem.length - type.extension.length - 1);
        break;
      }
    }
    return '$stem.$extension';
  }
}

enum ArchiverEngine {
  sevenZip('7-Zip'),
  tar('tar / bsdtar'),
  bsdTar('BSD tar'),
  gzip('gzip'),
  pigz('pigz'),
  bzip2('bzip2'),
  pbzip2('pbzip2'),
  xz('xz'),
  zstd('zstd'),
  lz4('LZ4'),
  zip('ZIP'),
  unzip('UnZip'),
  rar('RAR'),
  unrar('UnRAR'),
  unar('The Unarchiver');

  const ArchiverEngine(this.label);
  final String label;

  List<ArchiveType> get creates => switch (this) {
    sevenZip => const [ArchiveType.sevenZip, ArchiveType.zip],
    tar || bsdTar => const [
      ArchiveType.tarGzip,
      ArchiveType.tar,
      ArchiveType.tarBzip2,
      ArchiveType.tarXz,
      ArchiveType.tarZstd,
    ],
    gzip || pigz => const [ArchiveType.tarGzip, ArchiveType.gzip],
    bzip2 || pbzip2 => const [ArchiveType.tarBzip2, ArchiveType.bzip2],
    xz => const [ArchiveType.tarXz, ArchiveType.xz],
    zstd => const [ArchiveType.tarZstd, ArchiveType.zstd],
    lz4 => const [ArchiveType.tarLz4, ArchiveType.lz4],
    zip => const [ArchiveType.zip],
    rar => const [ArchiveType.rar],
    _ => const [],
  };
  bool get extracts => this != zip;
  bool get passwords => this == sevenZip;
  bool get isStream => switch (this) {
    gzip || pigz || bzip2 || pbzip2 || xz || zstd || lz4 => true,
    _ => false,
  };

  /// Prefer a dedicated compressor, then TAR's own codec.
  int get compressionPriority => switch (this) {
    pigz || pbzip2 => 0,
    gzip || bzip2 || xz || zstd || lz4 => 1,
    _ => 2,
  };
  int? get maxLevel => switch (this) {
    sevenZip || zip || bsdTar || gzip || pigz || bzip2 || pbzip2 || xz => 9,
    zstd => 22,
    lz4 => 12,
    rar => 5,
    _ => null,
  };
  int get minLevel => switch (this) {
    sevenZip || zip || rar || pigz || xz => 0,
    _ => 1,
  };
  bool get threads => switch (this) {
    sevenZip || bsdTar || pigz || pbzip2 || xz || zstd || rar => true,
    _ => false,
  };
  bool get solid => this == sevenZip || this == rar;

  bool reads(String path) {
    final name = path.toLowerCase();
    final extensions = switch (this) {
      zip => const <String>[],
      unzip => const ['zip', 'jar', 'apk', 'ipa', 'whl', 'cbz', 'epub'],
      rar || unrar => const ['rar'],
      gzip || pigz => const ['gz', 'tgz'],
      bzip2 || pbzip2 => const ['bz2', 'tbz', 'tbz2'],
      xz => const ['xz', 'txz'],
      zstd => const ['zst', 'zstd', 'tzst'],
      lz4 => const ['lz4'],
      tar || bsdTar => const [
        'tar',
        'tgz',
        'tbz',
        'tbz2',
        'txz',
        'tzst',
        'tar.gz',
        'tar.bz2',
        'tar.xz',
        'tar.zst',
      ],
      sevenZip || unar => const [
        'zip',
        '7z',
        'rar',
        'tar',
        'tgz',
        'tbz',
        'tbz2',
        'txz',
        'tzst',
        'gz',
        'bz2',
        'xz',
        'zst',
        'iso',
        'cab',
        'wim',
        'arj',
        'lzh',
        'rpm',
        'deb',
        'dmg',
        'xar',
        'cpio',
        'jar',
        'apk',
        'ipa',
        'whl',
        'cbz',
        'epub',
        'lz4',
      ],
    };
    return extensions.any((extension) => name.endsWith('.$extension'));
  }
}

@immutable
class ArchiveTool extends Equatable {
  const ArchiveTool({
    required this.name,
    required this.path,
    required this.engine,
  });
  final String name;
  final String path;
  final ArchiverEngine engine;
  String get id => '${engine.name}:$path';

  Map<String, Object?> toJson() => {
    'name': name,
    'path': path,
    'engine': engine.name,
  };
  static ArchiveTool? fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final path = json['path'];
    final engine = ArchiverEngine.values.asNameMap()[json['engine']];
    if (name is! String ||
        path is! String ||
        name.trim().isEmpty ||
        path.trim().isEmpty ||
        engine == null) {
      return null;
    }
    return ArchiveTool(name: name.trim(), path: path.trim(), engine: engine);
  }

  @override
  List<Object?> get props => [name, path, engine];
}

/// Empty tool id selects automatically; built-in remains an explicit choice.
const builtInArchiverId = 'builtin';
typedef ArchiverDiscovery = Future<List<ArchiveTool>> Function(
  List<ArchiveTool> manual, {
  bool refresh,
});

@immutable
class ArchiverOptions extends Equatable {
  const ArchiverOptions({
    this.level,
    this.threads,
    this.solid,
    this.arguments = const [],
  });
  final int? level;
  final int? threads;
  final bool? solid;
  final List<String> arguments;
  Map<String, Object?> toJson() => {
    if (level != null) 'level': level,
    if (threads != null) 'threads': threads,
    if (solid != null) 'solid': solid,
    if (arguments.isNotEmpty) 'arguments': arguments,
  };
  factory ArchiverOptions.fromJson(Object? value) {
    if (value is! Map<String, Object?>) return const ArchiverOptions();
    return ArchiverOptions(
      level:
          value['level'] is int &&
              (value['level'] as int) >= 0 &&
              (value['level'] as int) <= 22
          ? value['level'] as int
          : null,
      threads:
          value['threads'] is int &&
              (value['threads'] as int) >= 1 &&
              (value['threads'] as int) <= 256
          ? value['threads'] as int
          : null,
      solid: value['solid'] is bool ? value['solid'] as bool : null,
      arguments: value['arguments'] is List
          ? List.unmodifiable((value['arguments'] as List).whereType<String>())
          : const [],
    );
  }
  @override
  List<Object?> get props => [level, threads, solid, arguments];
}

typedef ArchiverOptionsValidator = Future<void> Function(
  ArchiverEngine? engine,
  ArchiverOptions options,
);
