import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

const container =
    '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';

final ttf = File('test/fixtures/fonts/NotoSans-Ascii.ttf').readAsBytesSync();
final woff = File('test/fixtures/fonts/NotoSans-Ascii.woff').readAsBytesSync();

Future<EpubTextSource> book() async => EpubTextSource(
  await EpubBook.load(
    MemoryEpubFiles({
      'META-INF/container.xml': utf8.encode(container),
      'OEBPS/content.opf': utf8.encode(
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/>'
        '<manifest>'
        '<item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="css" href="css/book.css" media-type="text/css"/>'
        '<item id="base" href="css/base.css" media-type="text/css"/>'
        '<item id="f1" href="fonts/sans.woff" media-type="font/woff"/>'
        '</manifest><spine><itemref idref="c1"/></spine></package>',
      ),
      'OEBPS/text/c1.xhtml': utf8.encode(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title>'
        '<link rel="stylesheet" href="../css/book.css"/>'
        '<style>@font-face { font-family: "Inline Face"; src: url(../fonts/sans.woff); }</style>'
        '</head><body><p class="e">iiii</p><p>iiii</p></body></html>',
      ),
      'OEBPS/css/book.css': utf8.encode(
        '@import url(base.css);\n'
        '@font-face { font-family: "Book Sans"; '
        'src: url(../fonts/missing.woff2) format("woff2"), url(../fonts/sans.woff) format("woff"); }\n'
        '@font-face { font-family: "Book Sans"; font-weight: bold; src: url(../fonts/sans.woff); }\n'
        '@font-face { font-family: Gone; src: url(../fonts/gone.ttf); }\n'
        '.e { font-family: "Book Sans", serif; }',
      ),
      'OEBPS/css/base.css': utf8.encode(
        '@font-face { font-family: Imported; src: local(Arial), url(../fonts/sans.woff); }',
      ),
      'OEBPS/fonts/sans.woff': woff,
    }),
  ),
);

void main() {
  test('WOFF unpacks to the same tables as the TrueType file', () {
    final sfnt = sfntOf(woff)!;
    final tables = tablesOf(sfnt);
    expect(tables.keys, unorderedEquals(tablesOf(ttf).keys));
    tablesOf(
      ttf,
    ).forEach((tag, data) => expect(tables[tag], data, reason: tag));
    expect(ByteData.sublistView(sfnt).getUint32(0), 0x00010000);
    expect(sfntOf(ttf), same(ttf));
  });

  test('what is not a loadable font is null', () {
    expect(
      sfntOf(Uint8List.fromList(ascii.encode('wOF2 and more bytes'))),
      isNull,
    );
    expect(
      sfntOf(Uint8List.fromList(ascii.encode('<html>not a font</html>'))),
      isNull,
    );
    expect(sfntOf(Uint8List(4)), isNull);
    expect(
      sfntOf(Uint8List.sublistView(woff, 0, 200)),
      isNull,
      reason: 'cut short',
    );
  });

  test(
    'sections collect their faces with the hrefs they resolve from',
    () async {
      final source = await book();
      final section = await SectionPreparer(
        source,
      ).prepare(0, const BookStyle());
      expect(
        [
          for (final f in section.fontFaces)
            (f.family, f.base, f.sources.length),
        ],
        [
          ('Imported', 'OEBPS/css/base.css', 1),
          ('Book Sans', 'OEBPS/css/book.css', 2),
          ('Book Sans', 'OEBPS/css/book.css', 1),
          ('Gone', 'OEBPS/css/book.css', 1),
          ('Inline Face', 'OEBPS/text/c1.xhtml', 1),
        ],
      );
      expect(section.fontFaces[2].weight, 'bold');
    },
  );

  test(
    'each family registers once, from the first source that loads',
    () async {
      final source = await book();
      final section = await SectionPreparer(
        source,
      ).prepare(0, const BookStyle());
      final registered = <String, List<Uint8List>>{};
      final loader = BookFontLoader(
        source,
        register: (family, fonts) async => registered[family] = fonts,
      );
      expect(await loader.load(section.fontFaces), isTrue);
      expect(loader.families.keys.toSet(), {
        'imported',
        'book sans',
        'inline face',
      });
      // The same file under three CSS names: one engine family.
      expect(registered, hasLength(1));
      expect(registered.values.single, hasLength(1), reason: 'bold reuses it');
      expect(
        tablesOf(registered.values.single.single).keys,
        unorderedEquals(tablesOf(ttf).keys),
        reason: 'WOFF unpacked',
      );
      expect(loader.families['book sans'], startsWith('pagecraft-'));
      expect(await loader.load(section.fontFaces), isFalse, reason: 'tried');
      expect(registered, hasLength(1));
    },
  );

  testWidgets('a registered book font lays text out with its glyphs', (
    tester,
  ) async {
    const style = BookStyle(fontScale: 1, overrideFont: false);
    final source = await tester.runAsync(book);
    final section = (await tester.runAsync(
      () => SectionPreparer(source!).prepare(0, style),
    ))!;
    final loader = BookFontLoader(source!);
    await tester.runAsync(() => loader.load(section.fontFaces));
    final column = ColumnLayout.layout(
      section.boxes,
      width: 400,
      pageHeight: 400,
      bookStyle: style,
      text: TextLayoutEnvironment(
        styler: InlineStyler(
          bookStyle: style,
          fonts: const BookFonts().withBookFamilies(loader.families),
        ),
        imageSize: (_) => null,
        maxImageHeight: 400,
      ),
    );
    addTearDown(column.dispose);
    final [embedded, plain] = column.items.whereType<ColumnText>().toList();
    // The test font draws every glyph as wide as the font size; Noto
    // Sans's "i" is far narrower.
    double inked(ColumnText item) =>
        item.paragraph.boxesFor(0, 4).first.toRect().width;
    final width = inked(embedded);
    expect(inked(plain), 4 * 16);
    expect(width, lessThan(4 * 16 * 0.5));
    expect(width, greaterThan(0));
  });
}

/// An sfnt's tables by tag.
Map<String, List<int>> tablesOf(Uint8List font) {
  final data = ByteData.sublistView(font);
  final count = data.getUint16(4);
  return {
    for (var i = 0; i < count; i++)
      ascii.decode(font.sublist(12 + 16 * i, 16 + 16 * i)): font.sublist(
        data.getUint32(20 + 16 * i),
        data.getUint32(20 + 16 * i) + data.getUint32(24 + 16 * i),
      ),
  };
}
