import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A place in the window that takes files dragged over it from the desktop
/// (a document's outline). The window gets the drag from the system; it
/// tells the target under the pointer where the files are and hands it the
/// paths when they are dropped. Found by hit-testing, so the topmost
/// target under the pointer wins.
class FileDropTarget extends StatelessWidget {
  const FileDropTarget({
    required this.onHover,
    required this.onLeave,
    required this.onDrop,
    required this.child,
    super.key,
  });

  /// Files hang over [global]: show where they would go.
  final ValueChanged<Offset> onHover;

  /// The files left, or went to another target.
  final VoidCallback onLeave;

  /// [paths] were dropped at [global]; resolves to the paths the target did
  /// not take, for the window to deal with (PDFs, files it cannot use).
  final Future<List<String>> Function(List<String> paths, Offset global) onDrop;

  final Widget child;

  /// The target under [global] in [context]'s view, if any.
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
