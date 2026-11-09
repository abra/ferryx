import 'dart:typed_data';

import 'comic_book.dart';
import 'comic_page_order.dart';
import '../../pagecraft_exception.dart';
import '../../metadata/book_metadata.dart';
import '../../metadata/cover_thumbnail.dart';

/// First pages above this size are not decoded for a cover.
const defaultMaxCoverBytes = 32 * 1024 * 1024;

/// The title and cover of the comic at [path], for the library's import:
/// the counterpart of `getMetadata` in `book.js` over `comic-book.js`,
/// without a WebView.
///
/// The title is the file name without its extension and the cover is the
/// first page in reading order, encoded by [encodeCoverThumbnail]. A first
/// page above [maxCoverBytes] or one that does not decode leaves
/// [BookMetadata.cover] null. Throws [PagecraftException] when the file is not
/// a comic.
Future<BookMetadata> readComicMetadata(
  String path, {
  CoverThumbnailSpec spec = const CoverThumbnailSpec(),
  int maxCoverBytes = defaultMaxCoverBytes,
}) async {
  final book = await ComicBook.open(
    path,
    pageOrderVersion: currentComicPageOrderVersion,
  );
  try {
    return BookMetadata(
      title: book.title,
      cover: await _readCover(book, spec, maxCoverBytes),
    );
  } finally {
    await book.close();
  }
}

Future<CoverImage?> _readCover(
  ComicBook book,
  CoverThumbnailSpec spec,
  int maxCoverBytes,
) async {
  final Uint8List bytes;
  try {
    bytes = await book.readCover(maxBytes: maxCoverBytes);
  } on PagecraftException {
    return null;
  }
  return encodeCoverThumbnail(bytes, spec: spec);
}
