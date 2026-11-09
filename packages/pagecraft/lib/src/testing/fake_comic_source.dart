import 'dart:typed_data';

import '../formats/comic/comic_page_source.dart';
import '../pagecraft_exception.dart';

/// In-memory pages for image-layer tests; counts reads and can fail.
class FakeComicSource implements ComicPageSource {
  FakeComicSource(this.pages);

  final List<Uint8List> pages;
  final readCounts = <int, int>{};
  Object? failWith;

  @override
  int get pageCount => pages.length;

  @override
  int pageSize(int index) => pages[index].length;

  @override
  Future<Uint8List> readPage(int index, {int? maxBytes}) async {
    if (maxBytes != null && pages[index].length > maxBytes) {
      throw PagecraftException('Entry too large: page $index');
    }
    readCounts.update(index, (n) => n + 1, ifAbsent: () => 1);
    final error = failWith;
    if (error != null) throw error;
    return pages[index];
  }
}
