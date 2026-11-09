import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// Links and notes as foliate-js's view.js and footnotes.js treat them.
const container =
    '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';

String chapter(String body) =>
    '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
    '<head><title>t</title></head><body>$body</body></html>';

Future<EpubTextSource> source() async => EpubTextSource(
  await EpubBook.load(
    MemoryEpubFiles({
      'META-INF/container.xml': utf8.encode(container),
      'OEBPS/content.opf': utf8.encode(
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/>'
        '<manifest>'
        '<item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c2" href="text/c2.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>',
      ),
      'OEBPS/text/c1.xhtml': utf8.encode(
        chapter(
          '<p>Plain <a href="c2.xhtml#target">link</a> and '
          '<a href="https://example.com/x">web</a>.</p>'
          '<p>Noted<a epub:type="noteref" href="#n1">1</a> text.</p>'
          '<p>Raised<sup><a href="c2.xhtml#e2">2</a></sup> and '
          '<a href="c2.xhtml#e3"><sup>3</sup></a> and back '
          '<a epub:type="backlink" href="#n1"><sup>4</sup></a>.</p>'
          '<aside epub:type="footnote" id="n1"><p>The first note.</p></aside>',
        ),
      ),
      'OEBPS/text/c2.xhtml': utf8.encode(
        chapter(
          '<h1 id="target">Target</h1>'
          '<ol><li id="e2" epub:type="endnote"><p>Second note text.</p></li></ol>'
          '<p>Some text with <span id="e3">an anchor</span> inside.</p>',
        ),
      ),
    }),
  ),
);

const style = BookStyle(fontScale: 12 / 16, lineHeight: 1.5);

void main() {
  late EpubTextSource book;
  late SectionPreparer preparer;
  late PreparedSection one;

  setUp(() async {
    book = await source();
    preparer = SectionPreparer(book);
    one = await preparer.prepare(0, style);
  });

  int linkTo(String href) {
    final doc = one.document;
    for (var i = 0; i < doc.nodeCount; i++) {
      if (doc.isElement(i) && doc.attributeOf(i, 'href') == href) return i;
    }
    throw StateError(href);
  }

  test('links resolve to the book or out of it', () async {
    final plain =
        (await resolveTextLink(book, one, linkTo('c2.xhtml#target')))!
            as InternalTextLink;
    expect(plain.href, 'OEBPS/text/c2.xhtml#target');
    expect(plain.target.index, 1);
    expect((plain.target.anchor! as IdAnchor).id, 'target');
    expect(plain.reference, FootnoteReference.no);
    final web = await resolveTextLink(
      book,
      one,
      linkTo('https://example.com/x'),
    );
    expect(web, isA<ExternalTextLink>());
    expect(web!.href, 'https://example.com/x');
  });

  test('note references: declared, raised, and back links', () async {
    Future<FootnoteReference> referenceOf(String href, [int nth = 0]) async {
      final doc = one.document;
      var seen = 0;
      for (var i = 0; i < doc.nodeCount; i++) {
        if (doc.isElement(i) &&
            doc.attributeOf(i, 'href') == href &&
            seen++ == nth) {
          return ((await resolveTextLink(book, one, i))! as InternalTextLink)
              .reference;
        }
      }
      throw StateError(href);
    }

    expect(await referenceOf('#n1'), FootnoteReference.yes);
    expect(await referenceOf('c2.xhtml#e2'), FootnoteReference.maybe);
    expect(await referenceOf('c2.xhtml#e3'), FootnoteReference.maybe);
    expect(await referenceOf('#n1', 1), FootnoteReference.no);
    expect(one.boxes.raisedElements, isNotEmpty);
  });

  test('a declared note shows its aside, hidden in the chapter', () async {
    expect(
      [for (final p in one.boxes.paragraphs) p.text],
      isNot(contains('The first note.')),
      reason: 'the user sheet hides footnote asides',
    );
    final note = (await preparer.prepareFootnote(
      const TextTarget(0, TextAnchor.id('n1')),
      style,
    ))!;
    expect(
      [for (final p in note.content.boxes.paragraphs) p.text],
      [
        'The first note.',
      ],
    );
    expect(note.type, 'footnote');
    expect(note.content.index, 0);
  });

  test('an endnote list item shows its contents without a marker', () async {
    final note = (await preparer.prepareFootnote(
      const TextTarget(1, TextAnchor.id('e2')),
      style,
    ))!;
    expect(note.type, 'endnote');
    final column = ColumnLayout.layout(
      note.content.boxes,
      width: 200,
      pageHeight: 400,
      bookStyle: style,
      text: TextLayoutEnvironment(
        styler: InlineStyler(bookStyle: style, fonts: const BookFonts()),
        imageSize: (_) => null,
        maxImageHeight: 400,
      ),
    );
    addTearDown(column.dispose);
    expect(column.items.whereType<ColumnMarker>(), isEmpty);
    expect(
      [
        for (final t in column.items.whereType<ColumnText>())
          t.paragraph.box.text,
      ],
      ['Second note text.'],
    );
  });

  test('a raised link to an inline anchor shows the block around it', () async {
    final note = (await preparer.prepareFootnote(
      const TextTarget(1, TextAnchor.id('e3')),
      style,
      extract: true,
    ))!;
    expect(
      [for (final p in note.content.boxes.paragraphs) p.text],
      [
        'Some text with an anchor inside.',
      ],
    );
    expect(note.type, isNull);
    expect(
      await preparer.prepareFootnote(
        const TextTarget(1, TextAnchor.id('missing')),
        style,
      ),
      isNull,
    );
  });

  test('a target directly in the body takes the block after it', () {
    final doc = ContentDocument.parseXml(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
      '<a id="x"/><p>After.</p><a id="y"/><span>no</span></body></html>',
    );
    final x = const TextAnchor.id('x').find(doc);
    expect(doc.localNameOf(extractFootnote(doc, x)), 'p');
    expect(extractFootnote(doc, const TextAnchor.id('y').find(doc)), -1);
  });

  testWidgets('taps find links, raised note numbers included', (tester) async {
    final column = ColumnLayout.layout(
      one.boxes,
      width: 300,
      pageHeight: 400,
      bookStyle: style,
      text: TextLayoutEnvironment(
        styler: InlineStyler(bookStyle: style, fonts: const BookFonts()),
        imageSize: (_) => null,
        maxImageHeight: 400,
      ),
    );
    addTearDown(column.dispose);
    final images = BookImageCache(read: (_) async => null);
    addTearDown(images.dispose);
    const padding = EdgeInsets.all(10);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: TextColumnPage(
            column: column,
            page: ColumnPage(0, column.height),
            images: images,
            imageKey: (src) => src,
            padding: padding,
          ),
        ),
      ),
    );
    final page = tester.renderObject<RenderTextColumnPage>(
      find.byType(TextColumnPage),
    );
    final texts = column.items.whereType<ColumnText>().toList();
    Offset at(ColumnText item, int offset) =>
        padding.topLeft +
        item.rect.topLeft +
        item.paragraph.boxesFor(offset, offset + 1).first.toRect().center;
    final first = texts[0];
    expect(
      page.linkAt(at(first, 'Plain '.length + 1)),
      linkTo('c2.xhtml#target'),
    );
    expect(page.linkAt(at(first, 1)), isNull, reason: 'plain text');
    final third = texts[2];
    final sup = third.paragraph.box.text.indexOf(objectReplacementCharacter);
    expect(page.linkAt(at(third, sup)), linkTo('c2.xhtml#e2'));
    expect(page.linkAt(const Offset(2, 2)), isNull, reason: 'margin');
  });

  testWidgets('a note lays out at its width and scrolls when long', (
    tester,
  ) async {
    final note = (await tester.runAsync(
      () => preparer.prepareFootnote(
        const TextTarget(1, TextAnchor.id('e2')),
        style,
      ),
    ))!;
    final images = BookImageCache(read: (_) async => null);
    addTearDown(images.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 120,
            height: 30,
            child: TextFragmentView(
              boxes: note.content.boxes,
              bookStyle: style,
              styler: InlineStyler(bookStyle: style, fonts: const BookFonts()),
              images: images,
              imageKey: (src) => note.content.imageKeys[src],
              document: note.content.document,
            ),
          ),
        ),
      ),
    );
    final page = tester.renderObject<RenderTextColumnPage>(
      find.byType(TextColumnPage),
    );
    expect(page.size.width, 120);
    expect(page.size.height, greaterThan(30), reason: 'taller than its box');
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
