/// Title, author, description and cover of a MOBI or KF8 book for the library's
/// import: what the headless WebView used to read through foliate-js
/// (`book.metadata` and `getCover()`), from the native parser.
library;

import '../../metadata/book_metadata.dart';
import '../../metadata/book_metadata_fields.dart';
import '../../metadata/cover_thumbnail.dart';
import 'mobi_book.dart';

/// The metadata of the MOBI or KF8 book at [path].
Future<BookMetadata> readMobiMetadata(
  String path, {
  CoverThumbnailSpec spec = const CoverThumbnailSpec(),
}) async {
  final book = await MobiBook.open(path);
  try {
    final (metadata, cover) = switch (book) {
      MobiKf8(:final book) => (book.metadata, await book.readCover()),
      MobiLegacy(:final book) => (book.metadata, await book.readCover()),
    };
    return BookMetadata(
      title: titleOrFileName(metadata.title, path),
      author: joinAuthorNames(metadata.authors ?? const []),
      description: nonEmptyText(metadata.description),
      cover: await coverThumbnailOf(cover?.bytes, spec),
    );
  } finally {
    await book.close();
  }
}
