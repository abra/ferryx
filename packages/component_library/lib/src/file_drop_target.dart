import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// What a drop of files would do where they hang, as the drag's feedback
/// shows it (the pointer's badge) and the drop then does.
enum FileDropOperation {
  /// Nothing: the place takes no files, or they are where they would go.
  none,
  copy,
  move,
  link,

  /// The place refuses them (read-only, the files onto themselves): the
  /// desktop's "not allowed" feedback, and the drag goes back.
  forbidden,
}

/// Files dragged over the window, from it or from another application.
@immutable
class FileDragInfo {
  const FileDragInfo({
    required this.allowed,
    this.paths = const [],
    this.local,
    this.itemCount = 0,
  });

  /// The operations the source allows, as the desktop narrowed them by the
  /// modifier keys held: one alone when a key forces it (⌥ copies on
  /// macOS, Ctrl and Shift on GNOME), none for macOS's ⌘ (a "generic"
  /// operation, which Finder reads as a move).
  final Set<FileDropOperation> allowed;

  /// The files on disk the drag carries, as far as they are known: the
  /// first while the drag hangs (another application's are read as it
  /// moves), every one on the drop.
  final List<String> paths;

  /// What the drag's source in this window attached to it; `null` for
  /// another application's drag.
  final Object? local;

  /// How many items are dragged.
  final int itemCount;

  /// The drag started in this window.
  bool get isLocal => local != null;
}

/// A place in the window that takes files dragged over it: a folder row,
/// a panel. The window gets the drag from the system and asks the target
/// under the pointer what a drop would do ([onOver]), tells it when the
/// drag moves on ([onLeave]) and hands it the files on the drop
/// ([onDrop]). Found by hit-testing, so the innermost target under the
/// pointer wins (a folder row over its panel).
class FileDropTarget extends StatelessWidget {
  const FileDropTarget({
    required this.id,
    required this.onOver,
    required this.onLeave,
    required this.onDrop,
    required this.child,
    super.key,
  });

  /// Tells targets apart across rebuilds: the drag has moved to another
  /// target only when the id under the pointer changes.
  final Object id;

  /// The drag hangs over the target (again on every move): what would a
  /// drop do? The answer is the drag's feedback.
  final FileDropOperation Function(FileDragInfo drag) onOver;

  /// The drag moved on to another target, out of the window, or ended.
  final VoidCallback onLeave;

  /// The files were dropped with [operation], the last answer of
  /// [onOver]; [drag] has every path now.
  final void Function(FileDragInfo drag, FileDropOperation operation) onDrop;

  final Widget child;

  /// The target under [global] in [context]'s view, if any: the innermost
  /// one along the hit-test path.
  static FileDropTarget? at(BuildContext context, Offset global) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      global,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is FileDropTarget) {
        return target.metaData as FileDropTarget;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => MetaData(
    metaData: this,
    behavior: HitTestBehavior.translucent,
    child: child,
  );
}

/// The files the app knows as pictures, by extension: what Flutter decodes
/// on every desktop (PNG, JPEG, GIF, WebP, BMP).
bool isImagePath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return const {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
  }.contains(path.substring(dot + 1).toLowerCase());
}
