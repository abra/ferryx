import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

const fixtures = 'test/fixtures/pdf';

void main() {
  setUpAll(preparePdfEngineForTests);

  test('finds hits page by page with excerpts', () async {
    final book = await PdfBook.open('$fixtures/many_pages.pdf');
    addTearDown(book.close);
    final pages = await searchPdfBook(book, 'page 17').toList();
    expect(pages.map((hits) => hits.single.page), [
      16,
      169,
      170,
      171,
      172,
      173,
      174,
      175,
      176,
      177,
      178,
    ]);
    final first = pages.first.single;
    expect(first.match.match, 'Page 17');
    expect(first.range, const PdfTextRange(0, 7));
    expect(first.match.pre, '');
    expect(first.match.post, '');
  });

  test('is diacritic- and case-insensitive and uses the cache', () async {
    final book = await PdfBook.open('$fixtures/text_lines.pdf');
    addTearDown(book.close);
    final cache = PdfTextLayerCache(book);
    addTearDown(cache.dispose);
    final pages = await searchPdfBook(book, 'CAFE', cache: cache).toList();
    expect(pages.single.single.match.match, 'café');
    expect(cache.loadedPages, [0]);
  });

  test('a blank query or a book without the text yields nothing', () async {
    final book = await PdfBook.open('$fixtures/text_lines.pdf');
    addTearDown(book.close);
    expect(await searchPdfBook(book, '   ').toList(), isEmpty);
    expect(await searchPdfBook(book, 'zebra').toList(), isEmpty);
  });

  test('cancelling stops reading pages', () async {
    final book = await PdfBook.open('$fixtures/many_pages.pdf');
    addTearDown(book.close);
    final cache = PdfTextLayerCache(book, capacity: 300);
    addTearDown(cache.dispose);
    final subscription = searchPdfBook(book, 'page', cache: cache).listen(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await subscription.cancel();
    final loaded = cache.loadedPages.length;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(cache.loadedPages.length, lessThanOrEqualTo(loaded + 1));
    expect(loaded, lessThan(200));
  });
}
