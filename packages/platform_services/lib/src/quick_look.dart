import 'package:flutter/foundation.dart';

/// What Quick Look shows: files on disk, and the one to show first. With
/// several, the panel's own arrows step through them.
@immutable
class QuickLookItems {
  QuickLookItems(List<String> paths, {int index = 0})
    : paths = List.unmodifiable(paths),
      index = paths.isEmpty ? 0 : index.clamp(0, paths.length - 1);

  final List<String> paths;
  final int index;

  bool get isEmpty => paths.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is QuickLookItems &&
      other.index == index &&
      listEquals(other.paths, paths);

  @override
  int get hashCode => Object.hash(index, Object.hashAll(paths));

  @override
  String toString() => 'QuickLookItems(${paths.length} paths, at $index)';
}

/// What the Quick Look panel tells the window.
sealed class QuickLookEvent {
  const QuickLookEvent();
}

/// The panel closed: by its own button, Esc, Space or ⌘Y while it had the
/// keys, or because the window lost control of it.
final class QuickLookClosed extends QuickLookEvent {
  const QuickLookClosed();

  @override
  bool operator ==(Object other) => other is QuickLookClosed;

  @override
  int get hashCode => 0;
}

/// ↑ or ↓ pressed while the panel had the keys: the panel's cursor moves
/// by [delta] rows, as Finder's selection follows its Quick Look.
final class QuickLookStep extends QuickLookEvent {
  const QuickLookStep(this.delta);

  final int delta;

  @override
  bool operator ==(Object other) =>
      other is QuickLookStep && other.delta == delta;

  @override
  int get hashCode => delta.hashCode;
}
