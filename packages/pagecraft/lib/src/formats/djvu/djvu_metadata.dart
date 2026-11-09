import '../../metadata/book_metadata.dart';
import '../../metadata/cover_thumbnail.dart';
import 'djvu_book.dart';

Future<BookMetadata> readDjvuMetadata(
  String path, {
  CoverThumbnailSpec spec = const CoverThumbnailSpec(),
}) async {
  final book = await DjvuBook.open(path);
  try {
    final first = book.pages.first;
    final size = spec.fit(first.width, first.height);
    final frame = await book.renderPage(0, targetWidth: size.width);
    return BookMetadata(
      title: book.title,
      author: book.author,
      cover: await encodeCoverFromPixels(
        frame.pixels,
        width: frame.width,
        height: frame.height,
        order: CoverPixelOrder.rgba,
        spec: spec,
      ),
    );
  } finally {
    await book.close();
  }
}
