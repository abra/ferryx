import 'package:meta/meta.dart';

import '../../container/zip_entry.dart';

/// One page of a comic: an image entry in reading order.
@immutable
class ComicPage {
  const ComicPage({required this.index, required this.entry});

  /// Zero-based position in reading order.
  final int index;

  /// The archive entry holding the image; its name is the page's id for
  /// the table of contents and `resolveHref`.
  final ZipEntry entry;

  String get name => entry.name;

  /// Image byte count before decoding, known without reading the entry.
  /// Callers with a memory budget (thumbnails, prefetch) decide on it.
  int get size => entry.uncompressedSize;

  @override
  bool operator ==(Object other) =>
      other is ComicPage && other.index == index && other.entry == entry;

  @override
  int get hashCode => Object.hash(index, entry);

  @override
  String toString() => 'ComicPage($index, ${entry.name})';
}
