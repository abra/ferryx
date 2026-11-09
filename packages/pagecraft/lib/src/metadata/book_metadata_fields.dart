/// What every text format's import metadata shares: a title from the
/// file name when the book has none, authors joined as the WebView import
/// stored them, a scaled cover. Used by `readEpubMetadata`,
/// `readFb2Metadata` and `readMobiMetadata`.
library;

import 'dart:typed_data';

import 'book_metadata.dart';
import 'cover_thumbnail.dart';

/// [bytes] scaled to the library's cover size, or null without bytes.
Future<CoverImage?> coverThumbnailOf(
  Uint8List? bytes,
  CoverThumbnailSpec spec,
) {
  if (bytes == null || bytes.isEmpty) return Future.value(null);
  return encodeCoverThumbnail(bytes, spec: spec);
}

/// The non-empty [names] joined with `, `, or null.
String? joinAuthorNames(Iterable<String> names) {
  final kept = [
    for (final name in names)
      if (name.trim().isNotEmpty) name.trim(),
  ];
  return kept.isEmpty ? null : kept.join(', ');
}

/// [text], or null when it is blank.
String? nonEmptyText(String? text) =>
    text == null || text.trim().isEmpty ? null : text;

/// [title] trimmed, or the file name without its extension (`.fb2.zip`
/// counts as one) when the book has no title.
String titleOrFileName(String? title, String path) {
  final trimmed = title?.trim() ?? '';
  if (trimmed.isNotEmpty) return trimmed;
  final slash = path.lastIndexOf('/');
  final name = slash < 0 ? path : path.substring(slash + 1);
  return name.replaceFirst(
    RegExp(r'(\.fb2\.zip|\.[A-Za-z0-9]+)$', caseSensitive: false),
    '',
  );
}
