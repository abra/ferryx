import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  group('ContentDocument.parseXml', () {
    test('builds the tree with parents, siblings and child counts', () {
      final doc = ContentDocument.parseXml(
        '<html><head><title>T</title></head><body><p>a<b>b</b>c</p></body></html>',
      );
      expect(doc.nodeCount, 10);
      final root = ContentDocument.rootIndex;
      expect(doc.localNameOf(root), 'html');
      expect(doc.parentOf(root), ContentDocument.none);
      expect(doc.childCountOf(root), 2);
      final head = doc.firstChildOf(root);
      final body = doc.nextSiblingOf(head);
      expect(doc.localNameOf(head), 'head');
      expect(doc.localNameOf(body), 'body');
      expect(doc.lastChildOf(root), body);
      expect(doc.nextSiblingOf(body), ContentDocument.none);
      final p = doc.firstChildOf(body);
      expect(doc.childCountOf(p), 3);
      expect(doc.childAt(p, 0), doc.firstChildOf(p));
      expect(doc.childAt(p, 2), doc.lastChildOf(p));
      expect(doc.childAt(p, 3), ContentDocument.none);
      expect(doc.childrenOf(p).map(doc.kindOf), [
        ContentNodeKind.text,
        ContentNodeKind.element,
        ContentNodeKind.text,
      ]);
      expect(doc.textOf(doc.childAt(p, 0)), 'a');
      expect(doc.textContentOf(p), 'abc');
      expect(doc.descendantsOf(body).length, 6, reason: 'body, p, a, b, b, c');
      expect(doc.subtreeEndOf(body), doc.nodeCount);
      expect(doc.subtreeEndOf(head), body);
      expect(doc.subtreeEndOf(doc.childAt(p, 0)), doc.childAt(p, 0) + 1);
      expect(doc.descendantsOf(head).map(doc.localNameOf).first, 'head');
    });

    test('knows previous siblings and element positions', () {
      final doc = ContentDocument.parseXml(
        '<r>t<a/>u<b/><c/>v</r>',
      );
      final children = doc.childrenOf(0).toList();
      final [t, a, u, b, c, v] = children;
      expect(doc.previousSiblingOf(t), ContentDocument.none);
      expect(doc.previousSiblingOf(a), t);
      expect(doc.previousSiblingOf(v), c);
      expect(doc.previousElementSiblingOf(b), a);
      expect(doc.previousElementSiblingOf(a), ContentDocument.none);
      expect(doc.nextElementSiblingOf(a), b);
      expect(doc.nextElementSiblingOf(c), ContentDocument.none);
      expect(doc.elementIndexOf(0), 1);
      expect([a, b, c].map(doc.elementIndexOf), [1, 2, 3]);
      expect(doc.elementChildCountOf(0), 3);
      expect(doc.elementChildCountOf(a), 0);
      expect(doc.childCountOf(0), 6);
      expect(doc.isText(u), isTrue);
    });

    test('keeps text split by comments and CDATA apart, as the DOM does', () {
      final doc = ContentDocument.parseXml(
        '<r>one<!-- c -->two<![CDATA[<three>]]>four<?pi x?>five</r>',
      );
      final kinds = doc.childrenOf(0).map(doc.kindOf).toList();
      expect(kinds, [
        ContentNodeKind.text,
        ContentNodeKind.text,
        ContentNodeKind.cdata,
        ContentNodeKind.text,
        ContentNodeKind.text,
      ]);
      expect(doc.childrenOf(0).map(doc.textOf), [
        'one',
        'two',
        '<three>',
        'four',
        'five',
      ]);
      expect(doc.isText(doc.childAt(0, 2)), isTrue);
    });

    test('decodes XML and HTML named entities and character references', () {
      final doc = ContentDocument.parseXml(
        '<p a="x&amp;y">a&amp;b&nbsp;c&mdash;d&#169;&#x41;</p>',
      );
      expect(doc.textOf(doc.firstChildOf(0)), 'a&b\u00A0c—d©A');
      expect(doc.attributeOf(0, 'a'), 'x&y');
    });

    test('folds line breaks in text and whitespace in attribute values', () {
      final doc = ContentDocument.parseXml(
        '<p title="a\r\nb\tc\nd">one\r\ntwo\rthree</p>',
      );
      expect(doc.textOf(doc.firstChildOf(0)), 'one\ntwo\nthree');
      expect(doc.attributeOf(0, 'title'), 'a b c d');
    });

    test('keeps qualified names and drops namespace declarations', () {
      final doc = ContentDocument.parseXml(
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en">'
        '<section epub:type="chapter"><svg:rect xmlns:svg="x"/></section></html>',
      );
      expect(doc.attributeCountOf(0), 1);
      expect(doc.attributesOf(0).single, ('xml:lang', 'en'));
      final section = doc.firstChildOf(0);
      expect(doc.attributeOf(section, 'epub:type'), 'chapter');
      expect(doc.attributeOf(section, 'type'), isNull);
      final rect = doc.firstChildOf(section);
      expect(doc.qualifiedNameOf(rect), 'svg:rect');
      expect(doc.localNameOf(rect), 'rect');
      expect(doc.attributeCountOf(rect), 0);
    });

    test('indexes ids, the first occurrence winning', () {
      final doc = ContentDocument.parseXml(
        '<r><a id="x">1</a><b id="y"/><c id="x">2</c></r>',
      );
      expect(doc.elementIndexById('x'), 1);
      expect(doc.idOf(doc.elementIndexById('y')), 'y');
      expect(doc.elementIndexById('nope'), ContentDocument.none);
      expect(doc.elementById('x'), same(doc.node(1)));
      expect(doc.elementById('nope'), isNull);
    });

    test('ignores the prolog and trailing comments', () {
      final doc = ContentDocument.parseXml(
        '<?xml version="1.0"?>\n<!DOCTYPE html>\n<!-- a -->\n<r/>\n<!-- b -->\n',
      );
      expect(doc.nodeCount, 1);
      expect(doc.localNameOf(0), 'r');
    });

    test('refuses malformed markup with a ContentParseException', () {
      for (final source in [
        '',
        '   ',
        '<a><b></a>',
        '<a>',
        '<a/><b/>',
        'text only',
        '<a b="unterminated></a>',
      ]) {
        expect(
          () => ContentDocument.parseXml(source),
          throwsA(isA<ContentParseException>()),
          reason: source,
        );
      }
    });

    test('an undefined entity is kept as written, unlike the browser', () {
      // The browser's XML parser gives up on the whole section; a reader
      // is better off showing the text.
      final doc = ContentDocument.parseXml('<p>a&bogus;b</p>');
      expect(doc.textOf(doc.firstChildOf(0)), 'a&bogus;b');
    });
  });

  group('ContentDocument.parseHtml', () {
    test('implies html, head and body and never fails', () {
      final doc = ContentDocument.parseHtml('<p>a<br>b</p><p>c');
      expect(doc.localNameOf(0), 'html');
      expect(doc.childrenOf(0).map(doc.localNameOf), ['head', 'body']);
      final body = doc.lastChildOf(0);
      expect(doc.childrenOf(body).map(doc.localNameOf), ['p', 'p']);
      final p = doc.firstChildOf(body);
      expect(doc.childrenOf(p).map(doc.kindOf), [
        ContentNodeKind.text,
        ContentNodeKind.element,
        ContentNodeKind.text,
      ]);
    });

    test('decodes entities and folds line breaks in text', () {
      final doc = ContentDocument.parseHtml(
        '<p title="a\nb">x&nbsp;y\r\nz&amp;</p>',
      );
      final p = doc.firstChildOf(doc.lastChildOf(0));
      expect(doc.textOf(doc.firstChildOf(p)), 'x\u00A0y\nz&');
      // HTML attribute values keep their line breaks.
      expect(doc.attributeOf(p, 'title'), 'a\nb');
    });

    test('parse picks the parser by media type', () {
      expect(
        ContentDocument.parse('<p>a', mediaType: 'text/html').nodeCount,
        5,
        reason: 'html, head, body, p, text',
      );
      expect(
        () => ContentDocument.parse('<p>a', mediaType: 'application/xhtml+xml'),
        throwsA(isA<ContentParseException>()),
      );
    });
  });

  group('ContentNode', () {
    final doc = ContentDocument.parseXml(
      '<html><body><p id="p">one<em>two</em></p></body></html>',
    );

    test('is one object per node and reads through to the arena', () {
      final body = doc.root.children.single;
      expect(doc.root, same(doc.root));
      expect(body, same(doc.node(1)));
      expect(body.parent, same(doc.root));
      expect(doc.root.parent, isNull);
      final p = body.children.single;
      expect(p.id, 'p');
      expect(p.localName, 'p');
      expect(p.attribute('id'), 'p');
      expect(p.text, isNull);
      expect(p.isElement, isTrue);
      final one = p.children.first;
      expect(one.isText, isTrue);
      expect(one.text, 'one');
      expect(one.id, isNull);
      expect(one.attribute('id'), isNull);
      expect(one.localName, isNull);
      expect(one.kind, ContentNodeKind.text);
      expect(p.children, hasLength(2));
      expect(p.toString(), '<p id="p">');
      expect(one.toString(), '"one"');
    });

    test('resolves CFIs like any CfiDocument', () {
      final p = doc.root.children.single.children.single;
      final two = p.children.last.children.single;
      final cfi = cfiFromPoint(CfiPoint(two, 1));
      expect(cfi.toString(), 'epubcfi(/2/2[p]/2/1:1)');
      final range = cfiToRange(doc, cfi);
      expect(range.start, CfiPoint(two, 1));
      expect(cfiToElement(doc, Cfi.parse('/2/2[p]')), same(p));
    });
  });
}
