import 'package:component_library/component_library.dart';
import 'package:flutter/widgets.dart';

/// A drag of files out of the window, as the pointer started it on a row.
@immutable
class FileDragRequest {
  const FileDragRequest({
    required this.position,
    required this.image,
    required this.imageSize,
    required this.itemCount,
    this.paths = const [],
    this.local,
    this.allowed = const {FileDropOperation.copy, FileDropOperation.move},
  });

  /// Where the pointer is, in the window's logical coordinates; the image
  /// hangs centred under it.
  final Offset position;

  /// What hangs under the pointer (the item's icon, a count badge),
  /// painted off screen at the window's pixel ratio with the theme of the
  /// context the drag starts from.
  final Widget image;
  final Size imageSize;

  /// How many items are dragged.
  final int itemCount;

  /// The files on disk other applications get, one URL each; empty for
  /// items only this window can take (an archive's members).
  final List<String> paths;

  /// What a drop in this window gets back as [FileDragInfo.local]: values
  /// the platform carries across (null, bool, num, String, and Lists and
  /// Maps of them).
  final Object? local;

  /// The operations a drop may do with the items (an archive's members
  /// can only be copied out).
  final Set<FileDropOperation> allowed;
}
