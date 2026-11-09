/// The one place that knows every reflowable format, for apps that read
/// them all (`package:pagecraft/all_formats.dart`); a format's own library
/// names only its source.
library;

import '../text_book/text_book_source.dart';
import 'epub/epub_book.dart';
import 'epub/epub_text_source.dart';
import 'fb2/fb2_book.dart';
import 'fb2/fb2_text_source.dart';
import 'mobi/mobi_book.dart';
import 'mobi/mobi_text_source.dart';

/// The source for an opened EPUB, FB2 or MOBI book, by its type.
TextBookSource textBookSourceOf(Object book) => switch (book) {
  EpubBook() => EpubTextSource(book),
  Fb2Book() => Fb2TextSource(book),
  MobiBook() => mobiTextSource(book),
  _ => throw ArgumentError.value(book, 'book', 'not a reflowable book'),
};
