/// Title, author, description and cover of an EPUB for the library's
/// import: what the headless WebView used to read through foliate-js
/// (`book.metadata` and `getCover()`), from the native parser.
library;

import '../../metadata/book_metadata.dart';
import '../../metadata/book_metadata_fields.dart';
import '../../metadata/cover_thumbnail.dart';
import 'epub_book.dart';

/// The metadata of the EPUB at [path].
Future<BookMetadata> readEpubMetadata(
  String path, {
  CoverThumbnailSpec spec = const CoverThumbnailSpec(),
}) async {
  final book = await EpubBook.open(path);
  try {
    final metadata = book.metadata;
    final cover = await book.readCover();
    return BookMetadata(
      title: titleOrFileName(metadata.title, path),
      author: joinAuthorNames(metadata.authors.map((a) => a.name)),
      description: nonEmptyText(metadata.description),
      cover: await coverThumbnailOf(cover?.bytes, spec),
    );
  } finally {
    await book.close();
  }
}
