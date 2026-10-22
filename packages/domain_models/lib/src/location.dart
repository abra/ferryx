import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'servers.dart';

enum LocationKind {
  native,
  archive,

  // ─── Network ───
  remote,
}

/// Where a panel is: a folder on disk, a folder inside an archive, or a
/// folder on a server.
@immutable
class Location extends Equatable {
  const Location.native(this.path)
    : kind = LocationKind.native,
      archive = null,
      server = null;

  /// [path] is `/`-separated inside [archive], empty at its root.
  const Location.inArchive({required String this.archive, this.path = ''})
    : kind = LocationKind.archive,
      server = null;

  // ─── Network ───

  /// [server] is the server's key (`sftp://me@host:22`, see [ServerKey]);
  /// [path] is absolute and `/`-separated, as the server spells it.
  const Location.remote({required String this.server, this.path = '/'})
    : kind = LocationKind.remote,
      archive = null;

  final LocationKind kind;
  final String path;
  final String? archive;

  /// The server's key, for a folder on a server.
  final String? server;

  /// A folder on this computer's disks: what the commands that hand
  /// paths to the desktop, the terminal or the journal need.
  bool get isNative => kind == LocationKind.native;

  bool get isArchiveRoot => kind == LocationKind.archive && path.isEmpty;

  bool get isRemote => kind == LocationKind.remote;

  bool get isRemoteRoot => isRemote && (path == '/' || path.isEmpty);

  /// The path as a panel's header shows it: `/Users/me/a.zip/dir`,
  /// `sftp://me@host/srv`.
  String get display => switch (kind) {
    LocationKind.native => path,
    LocationKind.archive => path.isEmpty ? archive! : '$archive/$path',
    LocationKind.remote =>
      ServerKey.parse(server!)?.urlOf(path) ?? '$server$path',
  };

  /// The last component: the folder's name, the archive's name at its
  /// root, the server's host at its root, `/` for the root of the file
  /// system.
  String get name {
    if (isRemoteRoot) return ServerKey.parse(server!)?.host ?? server!;
    final text = isRemote ? path : display;
    if (text == '/' || text.isEmpty) return '/';
    final trimmed = text.endsWith('/')
        ? text.substring(0, text.length - 1)
        : text;
    final slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }

  /// The folder this one is in; `null` at the root of the file system or
  /// of a server.
  Location? get parent {
    switch (kind) {
      case LocationKind.native:
        final parent = _parentPath(path);
        return parent == null ? null : Location.native(parent);
      case LocationKind.archive:
        if (path.isEmpty) {
          final parent = _parentPath(archive!);
          return parent == null ? null : Location.native(parent);
        }
        final slash = path.lastIndexOf('/');
        return Location.inArchive(
          archive: archive!,
          path: slash < 0 ? '' : path.substring(0, slash),
        );
      case LocationKind.remote:
        final parent = _parentPath(path);
        return parent == null
            ? null
            : Location.remote(server: server!, path: parent);
    }
  }

  Location join(String name) => switch (kind) {
    LocationKind.native => Location.native(
      path.endsWith('/') ? '$path$name' : '$path/$name',
    ),
    LocationKind.archive => Location.inArchive(
      archive: archive!,
      path: path.isEmpty ? name : '$path/$name',
    ),
    LocationKind.remote => Location.remote(
      server: server!,
      path: path.isEmpty || path.endsWith('/') ? '$path$name' : '$path/$name',
    ),
  };

  /// Every folder from the root down to this one, this one last.
  List<Location> get ancestry {
    final chain = <Location>[];
    for (Location? at = this; at != null; at = at.parent) {
      chain.add(at);
    }
    return chain.reversed.toList(growable: false);
  }

  static String? _parentPath(String path) {
    if (path == '/' || path.isEmpty) return null;
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final slash = trimmed.lastIndexOf('/');
    if (slash < 0) return null;
    return slash == 0 ? '/' : trimmed.substring(0, slash);
  }

  /// One line for the preferences: `native:/path`,
  /// `archive:/file.zip#inner` or `remote:sftp://me@host:22#/path` (a
  /// server's key holds no `#`).
  String encode() => switch (kind) {
    LocationKind.native => 'native:$path',
    LocationKind.archive => 'archive:$archive#$path',
    LocationKind.remote => 'remote:$server#$path',
  };

  static Location? decode(String encoded) {
    if (encoded.startsWith('native:')) {
      return Location.native(encoded.substring(7));
    }
    if (encoded.startsWith('archive:')) {
      final rest = encoded.substring(8);
      final hash = rest.lastIndexOf('#');
      if (hash < 0) return Location.inArchive(archive: rest);
      return Location.inArchive(
        archive: rest.substring(0, hash),
        path: rest.substring(hash + 1),
      );
    }
    if (encoded.startsWith('remote:')) {
      final rest = encoded.substring(7);
      final hash = rest.indexOf('#');
      final server = hash < 0 ? rest : rest.substring(0, hash);
      if (ServerKey.parse(server) == null) return null;
      final path = hash < 0 ? '/' : rest.substring(hash + 1);
      return Location.remote(server: server, path: path.isEmpty ? '/' : path);
    }
    return null;
  }

  @override
  List<Object?> get props => [kind, path, archive, server];

  @override
  String toString() => display;
}
