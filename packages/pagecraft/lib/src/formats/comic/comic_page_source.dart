import 'dart:typed_data';

/// What the image layer needs from a comic: how many pages, how big each
/// is on disk, and its encoded bytes on demand.
///
/// `ComicBook` is the real one; tests use an in-memory source. Two sources
/// are the same page set when they are the same object, which is what
/// image cache keys compare.
abstract interface class ComicPageSource {
  int get pageCount;

  /// Encoded byte count of a page, known without reading it.
  int pageSize(int index);

  /// The encoded image; [maxBytes] refuses pages above a budget before
  /// anything is read.
  Future<Uint8List> readPage(int index, {int? maxBytes});
}
