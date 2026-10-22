import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/foundation.dart';

import '../panel/panel_side.dart';

/// Where files hanging over a panel would go: its folder, or the folder of
/// the row under the pointer ([row] names it, for the highlight; `..` is
/// the folder above).
@immutable
class DropSpot {
  const DropSpot.panel(this.folder) : row = null;

  const DropSpot.row(this.folder, String this.row);

  final Location folder;
  final String? row;

  @override
  bool operator ==(Object other) =>
      other is DropSpot && other.folder == folder && other.row == row;

  @override
  int get hashCode => Object.hash(folder, row);

  @override
  String toString() => 'DropSpot($folder${row == null ? '' : ', $row'})';
}

/// What a drag started on a panel's rows carries for a drop in this
/// window: where the items are and their paths (on disk, or inside the
/// folder's archive). Sent through the desktop's session as a map.
@immutable
class PanelDragPayload {
  const PanelDragPayload({
    required this.side,
    required this.folder,
    required this.paths,
  });

  final PanelSide side;
  final Location folder;
  final List<String> paths;

  static const _tag = 'ferryx.panelDrag';

  /// The map the desktop's session carries back.
  Map<String, Object?> encode() => {
    _tag: 1,
    'side': side.name,
    'folder': folder.encode(),
    'paths': paths,
  };

  /// The payload in [local], when it is one of ours.
  static PanelDragPayload? decode(Object? local) {
    if (local is! Map || local[_tag] != 1) return null;
    final side = PanelSide.values.asNameMap()[local['side']];
    final folder = Location.decode('${local['folder']}');
    final paths = local['paths'];
    if (side == null || folder == null || paths is! List) return null;
    return PanelDragPayload(
      side: side,
      folder: folder,
      paths: [for (final path in paths) '$path'],
    );
  }
}

/// Dragged files as a drop sees them: from a panel of this window
/// ([payload]), or from another application (paths on disk, as far as
/// they are known).
@immutable
class DragSource {
  const DragSource({required this.paths, this.folder, this.payload});

  factory DragSource.of(FileDragInfo drag) {
    final payload = PanelDragPayload.decode(drag.local);
    if (payload != null) {
      return DragSource(
        paths: payload.paths,
        folder: payload.folder,
        payload: payload,
      );
    }
    final first = drag.paths.firstOrNull;
    final parent = first == null ? null : _parentPath(first);
    return DragSource(
      paths: drag.paths,
      folder: parent == null ? null : Location.native(parent),
    );
  }

  /// On disk, or members of [folder]'s archive.
  final List<String> paths;

  /// The folder the items are in; `null` while another application's
  /// first file is not read yet.
  final Location? folder;
  final PanelDragPayload? payload;

  bool get fromArchive => folder != null && !folder!.isNative;
}

/// What a drop of [source] into [destination] does, Finder's way:
///
/// - into an archive (read-only): refused;
/// - a folder onto itself or into a folder of its own: refused;
/// - into the folder the items are in: nothing;
/// - out of an archive: a copy (an extraction), refused when a move is
///   forced;
/// - a key that forces one operation wins: the desktop leaves it alone in
///   [allowed] (⌥ copy), or leaves none for macOS's ⌘ (a move);
/// - else on one volume a move, across volumes (or unknown) a copy.
///
/// [sameVolume] tells whether the items and [destination] share a volume
/// (`null` when not known).
FileDropOperation planDrop({
  required Location destination,
  required DragSource source,
  required Set<FileDropOperation> allowed,
  required bool? sameVolume,
}) {
  if (!destination.isNative) return FileDropOperation.forbidden;
  if (!source.fromArchive &&
      source.paths.any((path) => _within(destination.path, path))) {
    return FileDropOperation.forbidden;
  }
  if (source.folder == destination) return FileDropOperation.none;
  final forced = switch (allowed.length) {
    0 => FileDropOperation.move,
    1 => allowed.single,
    _ => null,
  };
  if (source.fromArchive) {
    return switch (forced) {
      FileDropOperation.move => FileDropOperation.forbidden,
      FileDropOperation.link => FileDropOperation.none,
      _ => FileDropOperation.copy,
    };
  }
  switch (forced) {
    case FileDropOperation.copy:
    case FileDropOperation.move:
      return forced!;
    case null:
      break;
    default:
      return FileDropOperation.none;
  }
  final canCopy = allowed.contains(FileDropOperation.copy);
  final canMove = allowed.contains(FileDropOperation.move);
  if (canCopy && canMove) {
    return sameVolume == true ? FileDropOperation.move : FileDropOperation.copy;
  }
  if (canCopy) return FileDropOperation.copy;
  if (canMove) return FileDropOperation.move;
  return FileDropOperation.none;
}

/// Whether [operation] takes the files (the target lights up for it).
bool dropAccepts(FileDropOperation operation) => switch (operation) {
  FileDropOperation.copy ||
  FileDropOperation.move ||
  FileDropOperation.link => true,
  FileDropOperation.none || FileDropOperation.forbidden => false,
};

/// Whether [path] is [folder] or inside it, with either separator.
bool _within(String path, String folder) {
  if (path == folder) return true;
  final last = folder.isEmpty ? '' : folder[folder.length - 1];
  if (last == '/' || last == r'\') return path.startsWith(folder);
  return path.startsWith('$folder/') || path.startsWith('$folder\\');
}

/// The folder [path] is in, with either separator; a root keeps its own.
String? _parentPath(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  final at = slash > backslash ? slash : backslash;
  if (at < 0 || path.length == 1) return null;
  final root = at == 0 || path[at - 1] == ':';
  return path.substring(0, root ? at + 1 : at);
}
