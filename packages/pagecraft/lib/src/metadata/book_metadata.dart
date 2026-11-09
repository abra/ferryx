import 'dart:typed_data';

/// What the library stores about a book when it is imported: the
/// counterpart of `book.metadata` and `getCover()` in foliate-js.
///
/// Formats fill what they have; a comic has only a title and a cover.
class BookMetadata {
  const BookMetadata({
    required this.title,
    this.author,
    this.description,
    this.cover,
  });

  final String title;
  final String? author;
  final String? description;

  /// The cover ready to store, or null when the book has none or it could
  /// not be decoded. An import without a cover still succeeds.
  final CoverImage? cover;
}

/// An encoded cover image and its pixel size.
class CoverImage {
  const CoverImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;

  /// The MIME type of [bytes], e.g. `image/jpeg`.
  final String mimeType;

  final int width;
  final int height;
}
