import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

import '../formats/mobi/mobi_fixture_books.dart';

/// Counts style sheet reads, to see the book-wide cache work.
class CountingSource implements TextBookSource {
  CountingSource(this.inner);

  final TextBookSource inner;
  final sheetReads = <String>[];

  @override
  int get sectionCount => inner.sectionCount;

  @override
  bool isLinear(int index) => inner.isLinear(index);

  @override
  Future<TextSection> section(int index) => inner.section(index);

  @override
  List<String> get defaultStyleSheets => inner.defaultStyleSheets;

  @override
  bool get isFixedLayout => inner.isFixedLayout;

  @override
  BookCssRewrite? get cssRewrite => inner.cssRewrite;

  @override
  Future<String?> readStyleSheet(String href) {
    sheetReads.add(href);
    return inner.readStyleSheet(href);
  }

  @override
  String imageKey(String sectionHref, String src) =>
      inner.imageKey(sectionHref, src);

  @override
  Future<Uint8List?> readImage(String key) => inner.readImage(key);

  @override
  Future<void> close() => inner.close();

  @override
  int sectionSize(int index) => inner.sectionSize(index);

  @override
  String sectionCfi(int index) => inner.sectionCfi(index);

  @override
  int? sectionOfCfi(String cfi) => inner.sectionOfCfi(cfi);

  @override
  List<BookNavItem>? get toc => inner.toc;

  @override
  List<BookNavItem>? get pageList => inner.pageList;

  @override
  Future<TextTarget?> resolveHref(String href) => inner.resolveHref(href);

  @override
  String resolveLink(int index, String href) => inner.resolveLink(index, href);

  @override
  bool isExternal(String href) => inner.isExternal(href);

  @override
  String? get language => inner.language;

  @override
  bool get rtl => inner.rtl;
}

Future<EpubBook> memoryEpub() => EpubBook.load(
  MemoryEpubFiles({
    'META-INF/container.xml': utf8.encode(
      '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    ),
    'OEBPS/content.opf': utf8.encode(
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/>'
      '<manifest>'
      '<item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="c3" href="text/ch3.html" media-type="text/html"/>'
      '<item id="css" href="css/main.css" media-type="text/css"/>'
      '<item id="base" href="css/base.css" media-type="text/css"/>'
      '<item id="img" href="images/pic.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3" linear="no"/></spine></package>',
    ),
    'OEBPS/text/ch1.xhtml': utf8.encode(
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link type="text/css" href="../css/main.css" rel="stylesheet"/></head>'
      '<body><h1>Title</h1><p class="big">Text <img src="../images/pic.png"/></p></body></html>',
    ),
    'OEBPS/text/ch2.xhtml': utf8.encode(
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      "<link rel='stylesheet' href='../css/main.css'/></head><body><p>Broken &nbsp; <b>bold</p></body></html>",
    ),
    'OEBPS/text/ch3.html': utf8.encode('<p>Loose html<p>second'),
    'OEBPS/css/main.css': utf8.encode(
      '@import url("base.css"); p.big { font-size: 2em }',
    ),
    'OEBPS/css/base.css': utf8.encode('h1 { color: #ff0000 }'),
    'OEBPS/images/pic.png': encodeSolidPng(40, 20),
  }),
);

// The book's own colours stay, so the cascade of its sheets shows.
const style = BookStyle(fontScale: 1, overrideColor: false);

void main() {
  test('EPUB CSS is read as foliate-js read it: pixels in ems', () async {
    final book = await EpubBook.load(
      MemoryEpubFiles({
        'META-INF/container.xml': utf8.encode(
          '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
          '<rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
        ),
        'content.opf': utf8.encode(
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/>'
          '<manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="s" href="s.css" media-type="text/css"/></manifest>'
          '<spine><itemref idref="c"/></spine></package>',
        ),
        'c.xhtml': utf8.encode(
          '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
          '<link rel="stylesheet" href="s.css"/>'
          '<style>h1 { margin-bottom: 48px }</style></head><body>'
          '<h1>T</h1><p style="margin-top: 8px">p</p></body></html>',
        ),
        's.css': utf8.encode('h1 { font-size: 32px; padding-bottom: 16px }'),
      }),
    );
    final source = EpubTextSource(book);
    expect(source.cssRewrite, same(rewriteEpubCss));
    final prepared = await SectionPreparer(source).prepare(
      0,
      // The reader's paragraph spacing would hide the paragraph's own.
      const BookStyle(
        fontScale: 1.5,
        overrideColor: false,
        useBookLayout: false,
      ),
    );
    final [heading, paragraph] = prepared.boxes.paragraphs.toList();
    // 32px is 2em of the body's 24px: 48px; its own 16px and 48px are
    // an em and three of that.
    final h1 = heading.style;
    expect(h1.fontSize, 48);
    expect(h1.padding.bottom, const CssLength.px(48));
    expect(h1.margin.bottom, const CssLength.px(144));
    // The style attribute too: 8px is half an em of the paragraph's 24px.
    expect(paragraph.style.margin.top, const CssLength.px(12));
  });

  group('EPUB', () {
    test(
      'sections are parsed, styled with linked and imported sheets, and boxed',
      () async {
        final source = CountingSource(EpubTextSource(await memoryEpub()));
        final preparer = SectionPreparer(source);
        final first = await preparer.prepare(0, style);
        final paragraphs = first.boxes.paragraphs.toList();
        expect(paragraphs.map((p) => p.text), ['Title', 'Text ￼']);
        expect(
          paragraphs.first.runs.single.style.color,
          0xFFFF0000,
          reason: 'base.css, imported',
        );
        // The reader's sheet follows the engine's and wins its ties.
        final themed =
            await SectionPreparer(
              EpubTextSource(await memoryEpub()),
            ).prepare(
              0,
              style.copyWith(
                overrideColor: true,
                textColor: 0xFF111111,
                readerStyleSheet: 'h1 { color: #00ff00 !important }',
              ),
            );
        expect(
          themed.boxes.paragraphs.first.runs.single.style.color,
          0xFF00FF00,
        );
        expect(
          paragraphs.last.runs.first.style.fontSize,
          32,
          reason: 'main.css',
        );
        expect(first.href, 'OEBPS/text/ch1.xhtml');
        expect(first.imageKeys, {'../images/pic.png': 'OEBPS/images/pic.png'});
        expect(source.sheetReads, ['OEBPS/css/main.css', 'OEBPS/css/base.css']);

        await preparer.prepare(1, style);
        expect(
          source.sheetReads,
          hasLength(2),
          reason: 'sheets are read once a book',
        );
        expect(source.isLinear(2), isFalse);
      },
    );

    test(
      'malformed XHTML falls back to HTML parsing; text/html is HTML',
      () async {
        final preparer = SectionPreparer(EpubTextSource(await memoryEpub()));
        final broken = await preparer.prepare(1, style);
        expect(broken.boxes.paragraphs.single.text, 'Broken   bold');
        final html = await preparer.prepare(2, style);
        expect(html.boxes.paragraphs.map((p) => p.text), [
          'Loose html',
          'second',
        ]);
      },
    );

    test('a prepared section lays out with its images probed', () async {
      final book = await memoryEpub();
      final source = EpubTextSource(book);
      final images = BookImageCache(read: source.readImage);
      addTearDown(images.dispose);
      final section = await SectionPreparer(source).prepare(0, style);
      final column = await layoutSection(
        section,
        width: 300,
        pageHeight: 400,
        style: style,
        fonts: const BookFonts(),
        images: images,
      );
      addTearDown(column.dispose);
      final atomic = column.paragraphs.last.paragraph.atomics.single;
      expect(atomic.rect.size, const Size(40, 20));
      expect(images.sizeOf('OEBPS/images/pic.png'), const Size(40, 20));
      expect(paginateColumn(column, pageHeight: 400), hasLength(1));

      final task = await startSectionLayout(
        section,
        width: 300,
        pageHeight: 400,
        style: style,
        fonts: const BookFonts(),
        images: images,
      );
      addTearDown(task.column.dispose);
      expect(task.isComplete, isTrue, reason: 'a short section fits at once');
      expect(task.column.height, column.height);
    });
  });

  group('FB2', () {
    test('sections take fb2.js\'s style sheet', () async {
      final fb2 = Fb2Book.parse(
        Uint8List.fromList(
          utf8.encode(
            '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">'
            '<description><title-info><book-title>B</book-title></title-info></description>'
            '<body><section><title><p>Chapter</p></title><p>One</p><p>Two</p>'
            '<p><image l:href="#pic"/></p></section></body>'
            '<binary id="pic" content-type="image/png">${base64.encode(encodeSolidPng(8, 4))}</binary>'
            '</FictionBook>',
          ),
        ),
      );
      final source = Fb2TextSource(fb2);
      final section = await SectionPreparer(source).prepare(0, style);
      final paragraphs = section.boxes.paragraphs.toList();
      expect(paragraphs.first.text, 'Chapter');
      expect(
        paragraphs.first.style.textAlign,
        CssTextAlign.center,
        reason: '.title h1',
      );
      expect(
        paragraphs[1].style.textIndent,
        CssLength.zero,
        reason: ':not(p) + p',
      );
      expect(
        paragraphs[2].style.textIndent,
        const CssLength.px(16),
        reason: 'p { text-indent: 1em }',
      );
      final key = section.imageKeys.values.single;
      expect(
        probeImageDimensions((await source.readImage(key))!),
        const ImageDimensions(8, 4),
      );
    });
  });

  group('MOBI', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mobi_source_');
    });

    tearDown(() => dir.delete(recursive: true));

    test('MOBI 6 sections are HTML with recindex images', () async {
      final file = File('${dir.path}/six.mobi')
        ..writeAsBytesSync(MobiFixtureBooks.mobi6());
      final book = await MobiBook.open(file.path);
      final source = textBookSourceOf(book);
      addTearDown(source.close);
      expect(source, isA<Mobi6TextSource>());
      final section = await SectionPreparer(source).prepare(2, style);
      expect(section.boxes.paragraphs.first.text, 'Chapter One');
      expect(section.imageKeys.values.single, 'recindex:00001');
      expect(await source.readImage('recindex:00001'), isNotNull);
      expect(await source.readImage('recindex:x'), isNull);
    });

    test('KF8 sections are XHTML', () async {
      final file = File('${dir.path}/eight.azw3')
        ..writeAsBytesSync(MobiFixtureBooks.kf8());
      final book = await MobiBook.open(file.path);
      final source = textBookSourceOf(book);
      addTearDown(source.close);
      expect(source, isA<Kf8TextSource>());
      final section = await SectionPreparer(source).prepare(0, style);
      expect(
        section.boxes.paragraphs.map((p) => p.text),
        contains('First fragment.'),
      );
      expect(source.isLinear(2), isFalse);
    });
  });

  test('from rejects what is not a reflowable book', () {
    expect(() => textBookSourceOf(Object()), throwsArgumentError);
  });
}
