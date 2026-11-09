/// Title, author, description and cover of an FB2 book for the library's
/// import: what the headless WebView used to read through foliate-js
/// (`book.metadata` and `getCover()`), from the native parser.
library;

import '../../metadata/book_metadata.dart';
import '../../metadata/book_metadata_fields.dart';
import '../../metadata/cover_thumbnail.dart';
import 'fb2_book.dart';

/// The metadata of the FB2 (or zipped FB2) at [path]. The description is
/// the annotation's XHTML, as the WebView import stored it.
Future<BookMetadata> readFb2Metadata(
  String path, {
  CoverThumbnailSpec spec = const CoverThumbnailSpec(),
}) async {
  final book = await Fb2Book.open(path);
  final metadata = book.metadata;
  return BookMetadata(
    title: titleOrFileName(metadata.title, path),
    author: joinAuthorNames(metadata.authors.map((a) => a.name)),
    description: nonEmptyText(metadata.description),
    cover: await coverThumbnailOf(book.readCover()?.bytes, spec),
  );
}
