import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/text_book/document_normalizer.dart';
import 'package:pagecraft/all_formats.dart';

ContentDocument _doc(
  String body, {
  String html = '',
}) => ContentDocument.parseXml(
  '<html xmlns="http://www.w3.org/1999/xhtml"$html><head><title>t</title></head>'
  '<body>$body</body></html>',
);

int _byId(ContentDocument doc, String id) => doc.elementIndexById(id);

int _body(ContentDocument doc) => doc
    .childrenOf(ContentDocument.rootIndex)
    .firstWhere((n) => doc.isElement(n) && doc.localNameOf(n) == 'body');

ComputedStyles _styles(ContentDocument doc, {String css = ''}) =>
    StyleResolver([
      CssSheetSource(
        CssStyleSheet.parse(cssUserAgentStyleSheet),
        CssOrigin.userAgent,
      ),
      CssSheetSource(CssStyleSheet.parse(css), CssOrigin.author),
    ]).resolve(doc);

/// Text long enough to count as a code block (80 characters).
final _long = List.filled(9, 'word word').join(' ');

void main() {
  const root = ContentDocument.rootIndex;

  group('language and direction', () {
    test('the root takes the book\'s language unless it has one', () {
      final doc = _doc('<p>a</p>');
      normalizeLanguageAndDirection(doc, language: 'en_us');
      expect(doc.attributeOf(root, 'lang'), 'en-US');
      final declared = _doc('<p>a</p>', html: ' lang="fr"');
      normalizeLanguageAndDirection(declared, language: 'en');
      expect(declared.attributeOf(root, 'lang'), 'fr');
    });

    test('a right-to-left language turns the root and body', () {
      final doc = _doc('<p>a</p>');
      normalizeLanguageAndDirection(doc, language: 'ar');
      expect(doc.attributeOf(root, 'dir'), 'rtl');
      expect(doc.attributeOf(_body(doc), 'dir'), 'rtl');
      final styles = _styles(doc);
      expect(styles[_body(doc)].direction, CssDirection.rtl);
    });

    test('the document\'s own direction wins', () {
      final doc = _doc('<p>a</p>', html: ' dir="ltr"');
      normalizeLanguageAndDirection(doc, language: 'he');
      expect(doc.attributeOf(_body(doc), 'dir'), 'ltr');
    });

    test('mostly right-to-left letters make the text right to left', () {
      final hebrew = _doc('<p>שלום עולם, this is a test</p>');
      normalizeLanguageAndDirection(hebrew);
      expect(hebrew.attributeOf(root, 'dir'), isNull, reason: 'fewer');
      final mostly = _doc('<p>שלום עולם שלום עולם ab</p>');
      normalizeLanguageAndDirection(mostly);
      expect(mostly.attributeOf(root, 'dir'), 'rtl');
    });

    test('Chinese, Japanese and Korean books keep their direction', () {
      final doc = _doc('<p>شلام</p>');
      normalizeLanguageAndDirection(doc, language: 'ja');
      expect(doc.attributeOf(root, 'lang'), 'ja');
      expect(doc.attributeOf(root, 'dir'), isNull);
    });

    test('left-to-right languages say so', () {
      final doc = _doc('<p>a</p>');
      normalizeLanguageAndDirection(doc, language: 'en');
      expect(doc.attributeOf(root, 'dir'), 'ltr');
    });
  });

  group('code-like blocks', () {
    bool marked(String body, {String css = ''}) {
      final doc = _doc(body);
      markCodeLikeBlocks(doc, _styles(doc, css: css));
      final x = _byId(doc, 'x');
      return (doc.attributeOf(x, 'class') ?? '')
          .split(' ')
          .contains(
            codeBlockClass,
          );
    }

    test('a code class marks a long block', () {
      expect(marked('<div id="x" class="programlisting">$_long</div>'), isTrue);
      expect(marked('<p id="x" class="SourceCode">$_long</p>'), isTrue);
      expect(marked('<div id="x" class="codeBlock">$_long</div>'), isTrue);
      expect(marked('<div id="x" class="program">$_long</div>'), isFalse);
    });

    test('short text, captions and look-alike classes are not code', () {
      expect(marked('<div id="x" class="programlisting">short</div>'), isFalse);
      expect(
        marked('<div id="x" class="codeCaption">$_long</div>'),
        isFalse,
        reason: 'describes a listing',
      );
      expect(marked('<div id="x" class="unicode">$_long</div>'), isFalse);
    });

    test('a monospace block that keeps whitespace or reads like code', () {
      const mono = 'div { font-family: Consolas, monospace }';
      expect(
        marked(
          '<div id="x">$_long</div>',
          css: '$mono div { white-space: pre-wrap }',
        ),
        isTrue,
      );
      expect(marked('<div id="x">$_long {}</div>', css: mono), isTrue);
      expect(marked('<div id="x">$_long</div>', css: mono), isFalse);
      // Generic monospace alone does not match, as the browser's
      // `\bmono\b` reads it.
      expect(
        marked(
          '<div id="x">$_long {}</div>',
          css: 'div { font-family: monospace }',
        ),
        isFalse,
      );
    });

    test('not inside pre or a marked block; inline elements never', () {
      expect(
        marked('<pre><div id="x" class="programlisting">$_long</div></pre>'),
        isFalse,
      );
      final doc = _doc(
        '<div id="outer" class="programlisting"><div id="x" class="programlisting">$_long</div></div>',
      );
      markCodeLikeBlocks(doc, _styles(doc));
      expect(
        doc.attributeOf(_byId(doc, 'x'), 'class'),
        'programlisting',
        reason: 'the outer block is the code',
      );
      expect(
        marked(
          '<p><span id="x" class="programlisting">$_long</span></p>',
        ),
        isFalse,
      );
    });

    test(
      'marked blocks take the reader\'s code rules in the cascade',
      () async {
        final doc = _doc('<div id="x" class="programlisting">$_long</div>');
        final (:styles, fontFaces: _) = await resolveSectionStyles(
          doc,
          href: 'ch.xhtml',
          styleSheets: const {},
          defaultStyleSheets: const [],
          style: const BookStyle(
            overrideColor: false,
            readerStyleSheet: '.readflex-code-block { color: #ff0000 }',
          ),
        );
        expect(styles[_byId(doc, 'x')].color, 0xFFFF0000);
      },
    );
  });

  test('added attributes join the element\'s own; ids stay the book\'s', () {
    final doc = _doc('<p id="x" class="a">t</p><p id="y">u</p>');
    final x = _byId(doc, 'x');
    final y = _byId(doc, 'y');
    doc
      ..addClass(x, 'b')
      ..addClass(x, 'b')
      ..addClass(y, 'c')
      ..addAttributeIfAbsent(y, 'id', 'other')
      ..addAttributeIfAbsent(y, 'dir', 'rtl');
    expect(doc.attributeOf(x, 'class'), 'a b');
    expect(doc.attributesOf(x).toList(), [('id', 'x'), ('class', 'a b')]);
    expect(doc.attributesOf(y).toList(), [
      ('id', 'y'),
      ('class', 'c'),
      ('dir', 'rtl'),
    ]);
    expect(doc.idOf(y), 'y');
    expect(doc.elementIndexById('y'), y);
  });
}
