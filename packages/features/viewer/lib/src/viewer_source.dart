import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';
import 'package:path/path.dart' as p;

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

/// Resolves a relative asset in the same filesystem, archive or server.
abstract interface class RelativeViewerSource implements ViewerSource {
  ViewerSource? resolveRelative(Uri reference);
}

abstract interface class ConvertedDocumentSource implements ViewerSource {
  Future<String> renderTextDocument(Uint8List bytes, TextDocumentFormat format);
}

/// A [Location] read through the file repository.
class FileRepositorySource
    implements
        DocumentFileSource,
        RelativeViewerSource,
        ConvertedDocumentSource {
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

  @override
  Future<String> renderTextDocument(
    Uint8List bytes,
    TextDocumentFormat format,
  ) => _files.renderTextDocument(bytes, format);

  @override
  ViewerSource? resolveRelative(Uri reference) {
    if (reference.hasScheme ||
        reference.hasAuthority ||
        reference.path.isEmpty) {
      return null;
    }
    final paths = location.isNative ? p.context : p.posix;
    final String relative;
    try {
      relative = Uri.decodeComponent(reference.path);
    } on FormatException {
      return null;
    }
    if (relative.contains('\\') || paths.rootPrefix(relative).isNotEmpty) {
      return null;
    }
    final path = paths.normalize(
      paths.join(paths.dirname(location.path), relative),
    );
    if (location.kind == LocationKind.archive &&
        (path == '..' || path.startsWith('../'))) {
      return null;
    }
    return FileRepositorySource(_files, switch (location.kind) {
      LocationKind.native => Location.native(
        path.replaceAll(paths.separator, '/'),
      ),
      LocationKind.archive => Location.inArchive(
        archive: location.archive!,
        path: path,
      ),
      LocationKind.remote => Location.remote(
        server: location.server!,
        path: path,
      ),
    });
  }
}
