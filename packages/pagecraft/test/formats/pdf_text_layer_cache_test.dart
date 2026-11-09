import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

const fixtures = 'test/fixtures/pdf';

void main() {
  late PdfBook book;

  setUpAll(() async {
    await preparePdfEngineForTests();
    book = await PdfBook.open('$fixtures/many_pages.pdf');
  });

  tearDownAll(() => book.close());

  test('loads a page once and serves it again', () async {
    final cache = PdfTextLayerCache(book, capacity: 3);
    addTearDown(cache.dispose);
    var notified = 0;
    cache.addListener(() => notified++);
    expect(cache.peek(0), isNull);
    final first = cache.load(0);
    final again = cache.load(0);
    expect(identical(first, again), isTrue, reason: 'one load in flight');
    final layer = await first;
    expect(layer.text, 'Page 1');
    expect(cache.peek(0), same(layer));
    expect(await cache.load(0), same(layer));
    expect(notified, 1);
  });

  test('keeps the pages read last', () async {
    final cache = PdfTextLayerCache(book, capacity: 2);
    addTearDown(cache.dispose);
    await cache.load(0);
    await cache.load(1);
    cache.peek(0);
    await cache.load(2);
    expect(cache.loadedPages, [0, 2]);
    expect(cache.peek(1), isNull);
  });

  test('loadedLayers reads without touching recency', () async {
    final cache = PdfTextLayerCache(book, capacity: 2);
    addTearDown(cache.dispose);
    await cache.load(0);
    await cache.load(1);
    expect(cache.loadedLayers.map((layer) => layer.text.isNotEmpty), [
      true,
      true,
    ]);
    // Listeners read the layers while the cache notifies; nothing moves.
    var seen = 0;
    cache.addListener(() => seen = cache.loadedLayers.length);
    await cache.load(2);
    expect(seen, 2);
    expect(cache.loadedPages, [1, 2], reason: 'page 0 stayed the oldest');
  });

  test('a disposed cache keeps nothing', () async {
    final cache = PdfTextLayerCache(book);
    final pending = cache.load(5);
    cache.dispose();
    final layer = await pending;
    expect(layer.text, 'Page 6');
    expect(cache.loadedPages, isEmpty);
  });
}
