import 'package:domain_models/domain_models.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../path_text.dart';

/// An item on the shelf: a file or folder on disk, with its row as the
/// panel listed it (for its icon and name).
@immutable
class ShelfItem extends Equatable {
  const ShelfItem(this.entry, {this.cut = false, this.missing = false});

  final FileEntry entry;

  /// Taken by Vim's `dd`: `p` moves it and it leaves the shelf. Anything
  /// else (`yy`, Add to Shelf) is copied by `p` and stays.
  final bool cut;

  /// Gone from its place on disk since it was shelved.
  final bool missing;

  String get path => entry.path;

  String get name => entry.name;

  /// The folder it is in.
  String get folder => PathText.parentOf(path) ?? '/';

  ShelfItem copyWith({bool? cut, bool? missing}) => ShelfItem(
    entry,
    cut: cut ?? this.cut,
    missing: missing ?? this.missing,
  );

  @override
  List<Object?> get props => [entry, cut, missing];
}

/// Items gathered from any folder of either panel, to be copied or moved
/// together into one (Path Finder's Drop Stack, Yoink): in the order they
/// came, each path once. Kept for the session only: paths gathered for a
/// task at hand go stale once the app is closed (files move, volumes
/// unmount), and an operation must never run on a list the user no longer
/// remembers making.
@immutable
class Shelf extends Equatable {
  const Shelf([this.items = const []]);

  static const empty = Shelf();

  final List<ShelfItem> items;

  bool get isEmpty => items.isEmpty;

  int get length => items.length;

  /// How many `p` would move.
  int get cutCount => items.where((i) => i.cut).length;

  bool contains(String path) => items.any((i) => i.path == path);

  /// [added] after what is there, each path once: an item shelved again
  /// keeps its place and takes the newer mark.
  Shelf add(Iterable<ShelfItem> added) {
    final next = [...items];
    for (final item in added) {
      final at = next.indexWhere((i) => i.path == item.path);
      if (at >= 0) {
        next[at] = item;
      } else {
        next.add(item);
      }
    }
    return Shelf(List.unmodifiable(next));
  }

  Shelf without(Iterable<String> paths) {
    final gone = paths.toSet();
    return Shelf(List.unmodifiable(items.where((i) => !gone.contains(i.path))));
  }

  /// The items marked [missing] as the disk now has them.
  Shelf withMissing(Set<String> missing) => Shelf(
    List.unmodifiable([
      for (final item in items)
        item.missing == missing.contains(item.path)
            ? item
            : item.copyWith(missing: missing.contains(item.path)),
    ]),
  );

  @override
  List<Object?> get props => [items];
}
