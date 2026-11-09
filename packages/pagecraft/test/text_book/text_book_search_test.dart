import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

const container =
    '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';

String chapter(String body, {String lang = ''}) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title>'
    '<style>p { color: red } /* needle in a style */</style></head>'
    '<body$lang>$body</body></html>';

Future<EpubTextSource> source() async => EpubTextSource(
  await EpubBook.load(
    MemoryEpubFiles({
      'META-INF/container.xml': utf8.encode(container),
      'OEBPS/content.opf': utf8.encode(
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/>'
        '<manifest>'
        '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c3" href="c3.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c4" href="c4.xhtml" media-type="text/html"/>'
        '</manifest><spine><itemref idref="c1"/><itemref idref="c2"/>'
        '<itemref idref="c3"/><itemref idref="c4"/></spine></package>',
      ),
      'OEBPS/c1.xhtml': utf8.encode(
        chapter(
          '<p>A needle in the <em>hay</em>stack, a Needle there.</p>'
          '<script>var needle = 1</script><p>Split nee<b>dle</b> too.</p>',
        ),
      ),
      'OEBPS/c2.xhtml': utf8.encode(chapter('<p>Nothing here.</p>')),
      'OEBPS/c3.xhtml': utf8.encode(
        chapter('<p>${'needle ' * 150}</p>'),
      ),
      'OEBPS/c4.xhtml': utf8.encode(
        '<html><body><p>Broken <b>markup needle</p></body></html>',
      ),
    }),
  ),
);

void main() {
  late EpubTextSource book;
  setUp(() async => book = await source());

  /// The text a hit's CFI restores to in its section.
  Future<String> restored(String cfi) async {
    final index = book.sectionOfCfi(cfi)!;
    final text = await book.section(index);
    final doc = parseSectionDocument(text.text, mediaType: text.mediaType);
    return doc.textOfRange(doc.textRangeOf(cfiToRange(doc, Cfi.parse(cfi))));
  }

  test('the whole book: results by section, progress, done', () async {
    final events = await searchTextBook(book, 'needle').toList();
    final results = events.whereType<TextSearchResults>().toList();
    expect(
      [for (final r in results) (r.section, r.hits.length)],
      [
        (0, 3),
        (2, 64),
        (2, 64),
        (2, 22),
        (3, 1),
      ],
    );
    expect(
      [for (final e in events.whereType<TextSearchProgress>()) e.fraction],
      [0.25, 0.5, 0.75, 1.0],
    );
    expect(events.last, isA<TextSearchDone>());
    // Progress follows each section's results.
    expect(events.indexWhere((e) => e is TextSearchProgress), 1);
    final first = results.first.hits;
    expect([for (final h in first) h.match], ['needle', 'Needle', 'needle']);
    expect(first.first.pre, 'A ');
    expect(first.first.post, ' in the');
    // Excerpts come from the first and last text nodes of a match only.
    expect(first.last.pre, 'Split ');
    expect(first.last.post, '');
    for (final hit in [...first, results.last.hits.single]) {
      expect(await restored(hit.cfi), hit.match, reason: hit.cfi);
    }
    expect(first.first.cfi, startsWith('epubcfi(/6/2!/4/2,'));
  });

  test('a match across elements, scripts and styles left out', () async {
    final hits = (await searchTextBook(
      book,
      'needle',
      section: 0,
    ).toList()).whereType<TextSearchResults>().expand((r) => r.hits).toList();
    expect(hits, hasLength(3), reason: 'not the script or the style');
    expect(hits.last.match, 'needle');
    expect(await restored(hits.last.cfi), 'needle');
  });

  test('a section alone reports no progress', () async {
    final events = await searchTextBook(book, 'NEEDLE', section: 0).toList();
    expect(events.whereType<TextSearchProgress>(), isEmpty);
    expect(events.last, isA<TextSearchDone>());
  });

  test('an empty query is done at once', () async {
    expect(await searchTextBook(book, '  ').toList(), [
      isA<TextSearchDone>(),
    ]);
  });

  test('cancelling stops the search', () async {
    final events = <TextSearchEvent>[];
    final done = Completer<void>();
    late StreamSubscription<TextSearchEvent> subscription;
    subscription = searchTextBook(book, 'needle', parallel: 1).listen((e) {
      events.add(e);
      if (e is TextSearchProgress) {
        unawaited(subscription.cancel());
        done.complete();
      }
    });
    await done.future;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events.whereType<TextSearchProgress>(), hasLength(1));
    expect(events.whereType<TextSearchDone>(), isEmpty);
  });

  test('a document in Turkish searches with Turkish case', () {
    final doc = ContentDocument.parseXml(
      '<html xmlns="http://www.w3.org/1999/xhtml">'
      '<body lang="tr"><p>IŞIK ve ışık ve isik</p></body></html>',
    );
    final hits = searchSectionDocument(
      doc,
      query: 'ışık',
      sectionCfi: 'epubcfi(/6/2)',
    );
    expect([for (final h in hits) h.match], ['IŞIK', 'ışık']);
  });
}
