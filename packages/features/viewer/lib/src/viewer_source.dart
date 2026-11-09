import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';

/// Where the viewer reads from: a file on disk or a member of an archive;
/// tests hand it bytes of their own.
abstract interface class ViewerSource {
  Future<int> size();

  /// Up to [length] bytes from [offset]; fewer at the end.
  Future<Uint8List> read(int offset, int length);

  String get displayName;

  /// The folder the file is in, as a panel shows it.
  String get displayPath;
  bool get isNative;

  /// The path on disk, when the file is there (a preview can open it).
  String? get nativePath;
}

/// A source that can lend a local file to a document decoder. Closing the
/// lease cancels preparation and releases any owned temporary copy.
abstract interface class DocumentFileSource implements ViewerSource {
  PreviewFileLease preparePreview();
}

/// A [Location] read through the file repository.
class FileRepositorySource implements DocumentFileSource {
  const FileRepositorySource(this._files, this.location);

  final FileRepository _files;
  final Location location;

  @override
  Future<int> size() => _files.fileSize(location);

  @override
  Future<Uint8List> read(int offset, int length) =>
      _files.readRange(location, offset, length);

  @override
  String get displayName => location.name;

  @override
  String get displayPath => location.parent?.display ?? '';

  @override
  bool get isNative => location.isNative;

  @override
  String? get nativePath => location.isNative ? location.path : null;

  @override
  PreviewFileLease preparePreview() => _files.preparePreview(location);
}
