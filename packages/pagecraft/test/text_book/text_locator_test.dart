import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

const container =
    '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';

String chapter(String body) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>c</title></head><body>$body</body></html>';

Future<EpubBook> book() => EpubBook.load(
  MemoryEpubFiles({
    'META-INF/container.xml': utf8.encode(container),
    'OEBPS/content.opf': utf8.encode(
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/>'
      '<manifest>'
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="c3" href="c3.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/></spine></package>',
    ),
    'OEBPS/nav.xhtml': utf8.encode(
      '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
      '<nav epub:type="toc"><ol>'
      '<li><a href="c1.xhtml">Chapter 1</a><ol><li><a href="c1.xhtml#part2">Part 2</a></li></ol></li>'
      '<li><a href="c2.xhtml">Chapter 2</a></li>'
      '</ol></nav></body></html>',
    ),
    'OEBPS/c1.xhtml': utf8.encode(
      chapter(
        '<h1>One</h1>'
        '${List.generate(12, (i) => '<p>Paragraph $i of the first chapter, with enough words to wrap.</p>').join()}'
        '<h2 id="part2">Part two</h2>'
        '${List.generate(12, (i) => '<p>Second part $i, more words to fill the page.</p>').join()}',
      ),
    ),
    'OEBPS/c2.xhtml': utf8.encode(chapter('<p>Two</p>')),
    'OEBPS/c3.xhtml': utf8.encode(
      chapter('<p>Three, no entry of its own.</p>'),
    ),
  }),
);

const style = BookStyle(fontScale: 10 / 16, lineHeight: 1.5);

void main() {
  late EpubTextSource source;
  late PreparedSection section;
  late ColumnLayout column;
  late List<ColumnPage> pages;
  late TextLocator locator;

  setUp(() async {
    source = EpubTextSource(await book());
    section = await SectionPreparer(source).prepare(0, style);
    column = ColumnLayout.layout(
      section.boxes,
      width: 150,
      pageHeight: 120,
      bookStyle: style,
      text: TextLayoutEnvironment(
        styler: InlineStyler(bookStyle: style, fonts: const BookFonts()),
        imageSize: (_) => null,
        maxImageHeight: 120,
      ),
    );
    pages = paginateColumn(column, pageHeight: 120);
    locator = TextLocator(section, column, sectionCfi: source.sectionCfi(0));
  });

  tearDown(() => column.dispose());

  test('every page start round-trips through its CFI', () {
    expect(pages.length, greaterThan(5));
    final cfis = <String>{};
    for (final page in pages) {
      final cfi = locator.cfiAt(page.top);
      expect(
        cfi,
        startsWith('epubcfi(/6/2!/4/'),
        reason: 'spine step, then the body',
      );
      expect(cfis.add(cfi), isTrue, reason: 'each page has its own CFI');
      final y = locator.yOfCfi(cfi)!;
      // The first page starts above the heading's margin; later pages
      // start exactly on a line.
      if (page != pages.first) expect(y, page.top, reason: cfi);
      expect(page.contains(y), isTrue, reason: cfi);
      expect(pageAtY(pages, y), pages.indexOf(page));
    }
  });

  test(
    'a CFI inside a line goes to that line\'s top, ranges to their start',
    () {
      final paragraph = column.paragraphs.elementAt(3);
      final text = section.document.firstChildOf(paragraph.paragraph.box.node);
      // The 40th character of the fourth paragraph's text node.
      final inner = cfiFromPoint(CfiPoint(section.document.node(text), 40));
      final cfi = joinCfiIndirections([source.sectionCfi(0), inner.toString()]);
      final line = paragraph.paragraph.lineAt(40);
      expect(
        locator.yOfCfi(cfi),
        paragraph.rect.top + paragraph.paragraph.lineTop(line),
      );
      final range = cfiFromRange(
        CfiNodeRange(
          CfiPoint(section.document.node(text), 40),
          CfiPoint(section.document.node(text), 45),
        ),
      );
      final rangeCfi = joinCfiIndirections([
        source.sectionCfi(0),
        range.toInnerString(),
      ]);
      expect(locator.yOfCfi(rangeCfi), locator.yOfCfi(cfi));
      expect(
        locator.yOfCfi(source.sectionCfi(0)),
        0,
        reason: 'the section itself',
      );
      expect(
        locator.yOfCfi('epubcfi(/6/2!/4/999)'),
        isNull,
        reason: 'no such node',
      );
      expect(locator.yOfCfi('not a cfi'), isNull);
    },
  );

  test('anchors and elements go to the first content they hold', () {
    final heading = column.paragraphs.firstWhere(
      (p) => p.paragraph.box.text == 'Part two',
    );
    expect(locator.yOfAnchor(const TextAnchor.id('part2')), heading.rect.top);
    expect(locator.yOfAnchor(const TextAnchor.id('missing')), isNull);
    final body = section.document.elementIndexById('part2') - 1;
    expect(locator.yOf(body, 0), isNotNull);
  });

  test('points: the first whole line at or below a height', () {
    final first = locator.pointAt(0)!;
    expect(section.document.textOf(first.node), 'One');
    final second = column.paragraphs.elementAt(1);
    final mid = second.rect.top + second.paragraph.lineTop(1) - 3;
    final point = locator.pointAt(mid)!;
    expect(
      point.offset,
      second.paragraph.lineStart(1),
      reason: 'the partly shown line is skipped',
    );
    expect(locator.pointAt(column.height + 10), isNull);
    expect(locator.cfiAt(column.height + 10), source.sectionCfi(0));
  });

  test('the table of contents entry follows the reading position', () async {
    final toc = await TocProgress.build(
      source.toc!,
      sectionCount: source.sectionCount,
      resolve: source.resolveHref,
    );
    final doc = section.document;
    final part2 = doc.elementIndexById('part2');
    expect(toc.itemAt(0)?.label, 'Chapter 1');
    expect(
      toc.itemAt(0, document: doc, end: TextPoint(part2 - 1, 3))?.label,
      'Chapter 1',
      reason: 'shown up to text before the heading',
    );
    expect(
      toc.itemAt(0, document: doc, end: TextPoint(part2 + 1, 2))?.label,
      'Part 2',
      reason: 'the heading is shown',
    );
    // The pages: a page whose end is past the heading is in Part 2.
    final headingY = locator.yOfAnchor(const TextAnchor.id('part2'))!;
    final page = pages[pageAtY(pages, headingY)];
    expect(
      toc.itemAt(0, document: doc, end: locator.endPointAt(page.bottom))?.label,
      'Part 2',
    );
    final before = pages[pageAtY(pages, headingY) - 1];
    expect(
      toc
          .itemAt(0, document: doc, end: locator.endPointAt(before.bottom))
          ?.label,
      'Chapter 1',
    );
    expect(toc.itemAt(1)?.label, 'Chapter 2');
    expect(
      toc.itemAt(2)?.label,
      'Chapter 2',
      reason: 'carried from the section before',
    );
    expect(toc.itemAt(9), isNull);
  });

  test('sources resolve links into targets with anchors', () async {
    final target = (await source.resolveHref('OEBPS/c1.xhtml#part2'))!;
    expect(target.index, 0);
    expect(target.anchor, isA<IdAnchor>());
    expect(
      target.anchor!.find(section.document),
      section.document.elementIndexById('part2'),
    );
    expect((await source.resolveHref('OEBPS/c2.xhtml'))!.anchor, isNull);
    expect(await source.resolveHref('OEBPS/missing.xhtml'), isNull);
    expect(source.sectionOfCfi('epubcfi(/6/4!/4/2/1:0)'), 1);
    expect(source.sectionOfCfi('nope'), isNull);
    expect(source.sectionSize(0), greaterThan(source.sectionSize(1)));
  });

  test('anchors by attribute and by selector', () {
    final doc = ContentDocument.parseXml(
      '<r><a id="x"/><b data-foliate-id="3"/><c aid="0A"/></r>',
    );
    expect(const TextAnchor.attribute('data-foliate-id', '3').find(doc), 2);
    expect(const TextAnchor.selector('[aid="0A"]').find(doc), 3);
    expect(const TextAnchor.selector('[aid="none"]').find(doc), -1);
    expect(const TextAnchor.selector('###').find(doc), -1);
    expect(
      const TextTarget(2, TextAnchor.id('x')).toString(),
      'TextTarget(2, #x)',
    );
  });
}
