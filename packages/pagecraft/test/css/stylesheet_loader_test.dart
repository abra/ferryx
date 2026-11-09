import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  final files = <String, String>{
    'OEBPS/css/main.css':
        '@import "base.css"; @import url(print.css) print; p { color: red }',
    'OEBPS/css/base.css':
        '@charset "utf-8"; @import url("../fonts/fonts.css"); body { margin: 0 }',
    'OEBPS/fonts/fonts.css':
        '@font-face { font-family: "Book"; src: local("Book"), url(Book.otf) format("opentype"); font-weight: bold; font-style: italic }'
        '@media screen { @font-face { font-family: Other; src: url("Other.ttf") } }',
    'OEBPS/css/print.css': 'p { display: none }',
    'OEBPS/css/loop-a.css': '@import "loop-b.css"; a { color: blue }',
    'OEBPS/css/loop-b.css': '@import "loop-a.css"; b { color: green }',
  };
  final requested = <String>[];
  Future<String?> read(String href) async {
    requested.add(href);
    return files[href];
  }

  setUp(requested.clear);

  test('links, styles and imports come in cascade order', () async {
    final doc = ContentDocument.parseXml('''
<html xmlns="http://www.w3.org/1999/xhtml"><head>
  <link rel="stylesheet" type="text/css" href="../css/main.css"/>
  <link rel="stylesheet" href="../css/print.css" media="print"/>
  <link rel="icon" href="../x.png"/>
  <link rel="alternate stylesheet" href="../css/missing.css"/>
  <style type="text/css">@import "../css/loop-a.css"; h1 { color: black }</style>
  <style media="print">h2 { display: none }</style>
</head><body><p>x</p></body></html>''');
    final sheets = await loadDocumentStyleSheets(
      doc,
      documentHref: 'OEBPS/text/ch1.xhtml',
      read: read,
    );
    String first(CssStyleSheet sheet) => sheet.rules
        .whereType<CssQualifiedRule>()
        .map((r) => r.prelude.join())
        .join(',');
    expect(sheets.map(first), [
      '', // fonts.css: only at-rules
      'body', // base.css, imported by main.css
      'p', // main.css
      'b', // loop-b.css, imported by loop-a.css, which the style imports
      'a', // loop-a.css
      'h1', // the style element
    ]);
    expect(requested, isNot(contains('OEBPS/css/print.css')));
    expect(
      requested,
      contains('OEBPS/css/missing.css'),
      reason: 'alternate sheets are plain links here',
    );
    expect(
      requested.where((h) => h == 'OEBPS/css/loop-a.css'),
      hasLength(1),
      reason: 'the cycle stops',
    );
  });

  test('a cache parses each external sheet once per book', () async {
    final doc = ContentDocument.parseXml(
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><link rel="stylesheet" href="../css/main.css"/></head><body/></html>',
    );
    final cache = StyleSheetCache();
    final first = await loadDocumentStyleSheets(
      doc,
      documentHref: 'OEBPS/text/a.xhtml',
      read: read,
      cache: cache,
    );
    final reads = requested.length;
    final second = await loadDocumentStyleSheets(
      doc,
      documentHref: 'OEBPS/text/b.xhtml',
      read: read,
      cache: cache,
    );
    expect(requested, hasLength(reads), reason: 'nothing read again');
    expect(cache.length, 3);
    for (var i = 0; i < first.length; i++) {
      expect(second[i], same(first[i]));
    }
  });

  test('import depth is bounded', () async {
    final deep = {
      for (var i = 0; i < 20; i++)
        'd$i.css': '@import "d${i + 1}.css"; .d$i { color: red }',
    };
    final doc = ContentDocument.parseXml(
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><link rel="stylesheet" href="d0.css"/></head><body/></html>',
    );
    final sheets = await loadDocumentStyleSheets(
      doc,
      documentHref: 'ch.xhtml',
      read: (href) async => deep[href],
      maxImportDepth: 3,
    );
    expect(sheets, hasLength(4));
  });

  test('cssImportsOf reads only leading imports with usable media', () {
    final sheet = CssStyleSheet.parse('''
      @charset "utf-8";
      @import "a.css";
      @import url(b.css) screen;
      @import url("c.css") print;
      @import url(d.css) not print;
      p { color: red }
      @import "late.css";
    ''');
    expect(cssImportsOf(sheet), ['a.css', 'b.css', 'd.css']);
  });

  test('media on links, styles and imports is evaluated', () async {
    final media = {
      'kf8.css': 'p { color: red }',
      'phone.css': 'p { color: green }',
      'tablet.css': 'p { color: blue }',
      'main.css':
          '@import url(phone.css) screen and (max-device-width: 480px);'
          '@import url(tablet.css) (min-device-width: 768px);'
          '@import url(layered.css) layer(base) supports(display: grid) screen;',
      'layered.css': 'em { color: gray }',
    };
    final doc = ContentDocument.parseXml('''
<html xmlns="http://www.w3.org/1999/xhtml"><head>
  <link rel="stylesheet" href="kf8.css" media="amzn-kf8"/>
  <link rel="stylesheet" href="main.css" media="all"/>
  <style media="(prefers-color-scheme: dark)">h1 { color: white }</style>
</head><body/></html>''');
    Future<List<String>> load(CssMediaEnvironment environment) async {
      final loaded = <String>[];
      await loadDocumentStyleSheets(
        doc,
        documentHref: 'ch.xhtml',
        read: (href) async {
          loaded.add(href);
          return media[href];
        },
        media: environment,
      );
      return loaded;
    }

    expect(await load(const CssMediaEnvironment()), [
      'main.css',
      'phone.css',
      'layered.css',
    ]);
    expect(
      await load(
        const CssMediaEnvironment(deviceWidth: 820, deviceHeight: 1180),
      ),
      ['main.css', 'tablet.css', 'layered.css'],
    );
    final dark = await loadDocumentStyleSheets(
      doc,
      documentHref: 'ch.xhtml',
      read: (href) async => media[href],
      media: const CssMediaEnvironment(darkColorScheme: true),
    );
    expect(
      dark.last.rules.whereType<CssQualifiedRule>().single.prelude.join(),
      'h1',
    );
  });

  test('cssFontFacesOf reads families, sources, weight and style', () {
    final faces = cssFontFacesOf(
      CssStyleSheet.parse(files['OEBPS/fonts/fonts.css']!),
    );
    expect(faces, hasLength(2));
    expect(faces[0].family, 'Book');
    expect(faces[0].sources, ['Book.otf']);
    expect(faces[0].weight, 'bold');
    expect(faces[0].style, 'italic');
    expect(faces[1].family, 'Other');
    expect(faces[1].sources, ['Other.ttf']);
    expect(faces[1].weight, isNull);
  });
}
