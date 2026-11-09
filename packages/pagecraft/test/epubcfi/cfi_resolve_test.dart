import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// Parity with `epubcfi.js` in Chromium: `test/fixtures/cfi/expected.json`
/// records what the browser produced for the fixture documents (recorded
/// by `cfi_fixtures.mjs` before the WebView reader's removal); the same
/// positions must give the same strings here, and the strings must
/// resolve to the same nodes.
void main() {
  const fixtures = 'test/fixtures/cfi';
  final expected =
      jsonDecode(File('$fixtures/expected.json').readAsStringSync())
          as Map<String, dynamic>;

  /// The browser's filter for `skipped.xhtml`.
  CfiNodeFilterResult skipFilter(CfiNode node) {
    if (!node.isElement) return CfiNodeFilterResult.accept;
    if (node.attribute('data-reject') != null) {
      return CfiNodeFilterResult.reject;
    }
    if (node.attribute('data-skip') != null) return CfiNodeFilterResult.skip;
    return CfiNodeFilterResult.accept;
  }

  /// Text nodes in document order, as the generator numbered them.
  List<CfiNode> textNodes(CfiNode root) {
    final out = <CfiNode>[];
    void walk(CfiNode node) {
      for (final child in node.children) {
        if (child.isText) {
          out.add(child);
        } else {
          walk(child);
        }
      }
    }

    walk(root);
    return out;
  }

  List<CfiNode> elements(CfiNode root) {
    final out = <CfiNode>[];
    void walk(CfiNode node) {
      for (final child in node.children) {
        if (child.isElement) {
          out.add(child);
          walk(child);
        }
      }
    }

    walk(root);
    return out;
  }

  String tagOf(CfiNode node) => switch (node) {
    XmlCfiNode() => (node.xml as dynamic).name.local as String,
    ContentNode() => node.localName!,
    _ => throw ArgumentError.value(node),
  };

  // Both trees the CFI code walks must see what the browser's DOM saw.
  final implementations = <(String, CfiDocument Function(String))>[
    ('XmlCfiDocument', XmlCfiDocument.parse),
    ('ContentDocument', ContentDocument.parseXml),
  ];

  for (final (implementation, parse) in implementations) {
    for (final entry in expected.entries) {
      final name = entry.key;
      final data = entry.value as Map<String, dynamic>;
      final filter = name == 'skipped.xhtml' ? skipFilter : null;

      group('$implementation $name', () {
        late CfiDocument document;
        late List<CfiNode> texts;

        setUp(() {
          document = parse(File('$fixtures/$name').readAsStringSync());
          texts = textNodes(document.root);
        });

        test('sees the text nodes the browser saw', () {
          expect(texts, hasLength(data['textCount'] as int));
        });

        test('points produce the browser\'s CFIs and resolve back', () {
          for (final point in data['points'] as List) {
            final p = point as Map<String, dynamic>;
            final node = texts[p['text'] as int];
            final offset = p['offset'] as int;
            final cfi = cfiFromPoint(CfiPoint(node, offset), filter: filter);
            expect(
              cfi.toString(),
              p['cfi'],
              reason: 'text ${p['text']}:$offset',
            );

            final resolved = cfiToRange(
              document,
              Cfi.parse(p['cfi'] as String),
              filter: filter,
            );
            final back = p['resolved'] as Map<String, dynamic>;
            expect(resolved.isCollapsed, isTrue);
            expect(
              texts.indexOf(resolved.start.node),
              back['text'],
              reason: p['cfi'] as String,
            );
            expect(
              resolved.start.offset,
              back['offset'],
              reason: p['cfi'] as String,
            );
          }
        });

        test('ranges produce the browser\'s CFIs and resolve back', () {
          for (final range in data['ranges'] as List) {
            final r = range as Map<String, dynamic>;
            final start = r['start'] as Map<String, dynamic>;
            final end = r['end'] as Map<String, dynamic>;
            final cfi = cfiFromRange(
              CfiNodeRange(
                CfiPoint(texts[start['text'] as int], start['offset'] as int),
                CfiPoint(texts[end['text'] as int], end['offset'] as int),
              ),
              filter: filter,
            );
            expect(cfi.toString(), r['cfi']);

            final resolved = cfiToRange(
              document,
              Cfi.parse(r['cfi'] as String),
              filter: filter,
            );
            final back = r['resolved'] as Map<String, dynamic>;
            final backStart = back['start'] as Map<String, dynamic>;
            final backEnd = back['end'] as Map<String, dynamic>;
            expect(
              texts.indexOf(resolved.start.node),
              backStart['text'],
              reason: r['cfi'] as String,
            );
            expect(
              resolved.start.offset,
              backStart['offset'],
              reason: r['cfi'] as String,
            );
            expect(
              texts.indexOf(resolved.end.node),
              backEnd['text'],
              reason: 'end of ${r['cfi']}',
            );
            expect(
              resolved.end.offset,
              backEnd['offset'],
              reason: 'end of ${r['cfi']}',
            );
          }
        });

        test('elements produce the browser\'s CFIs and resolve back', () {
          final all = elements(
            document.root,
          ).where((e) => !identical(e.parent, document.root)).toList();
          final recorded = data['elementCfis'] as List;
          expect(all, hasLength(recorded.length));
          for (var i = 0; i < all.length; i++) {
            final e = recorded[i] as Map<String, dynamic>;
            expect(tagOf(all[i]), e['tag']);
            final cfi = cfisFromElements([all[i]]).single;
            expect(cfi.toString(), e['cfi']);
            final element = cfiToElement(
              document,
              Cfi.parse(e['cfi'] as String),
            );
            expect(tagOf(element), e['resolvedTag']);
            expect(
              identical(element, all[i]),
              isTrue,
              reason: e['cfi'] as String,
            );
          }
        });

        test('fromElements indexes siblings in one walk', () {
          final recorded = (data['fromElements'] as List).cast<String>();
          final container = all(
            document.root,
          ).where((e) => tagOf(e) == 'body' || tagOf(e) == 'spine').firstOrNull;
          final siblings = container == null
              ? <CfiNode>[]
              : container.children.where((c) => c.isElement).toList();
          expect(
            cfisFromElements(siblings).map((c) => c.toString()),
            recorded,
          );
        });
      });
    }
  }

  group('boundaries', () {
    final document = XmlCfiDocument.parse(
      '<html><body><p id="a">one</p><p id="b">two</p></body></html>',
    );
    final body = document.root.children.single;
    final a = body.children[0];
    final b = body.children[1];

    test('index 0 and n+2 are the virtual positions around the children', () {
      // Under body: [before, gap, a, gap, b, gap, after] → a is 2, b is 4.
      expect(
        cfiToRange(document, Cfi.parse('/2/0')).start,
        CfiPoint(document.root, 0),
      );
      expect(
        cfiToRange(document, Cfi.parse('/2/6')).start,
        CfiPoint(document.root, 1),
      );
      expect(cfiToRange(document, Cfi.parse('/2/1')).start, CfiPoint(a, 0));
      expect(cfiToRange(document, Cfi.parse('/2/5')).start, CfiPoint(b, 0));
      expect(
        cfiToRange(document, Cfi.parse('/2/3')).start,
        CfiPoint(body, 1),
        reason: 'the missing chunk between a and b is the point between them',
      );
    });

    test('an id assertion wins over the path, as in epubcfi.js', () {
      expect(cfiToElement(document, Cfi.parse('/2/4[a]')), same(a));
      expect(cfiToElement(document, Cfi.parse('/2/4[missing]')), same(b));
    });

    test('a step past the children fails loudly', () {
      expect(
        () => cfiToRange(document, Cfi.parse('/2/8')),
        throwsA(isA<CfiResolveException>()),
      );
      expect(
        () => cfiToRange(document, Cfi.parse('/2/2/1/2')),
        throwsA(isA<CfiResolveException>()),
      );
    });

    test('an offset past the chunk lands at its end', () {
      final resolved = cfiToRange(document, Cfi.parse('/2/2/1:99'));
      expect(resolved.start, CfiPoint(a.children.single, 3));
    });

    test('an empty local path is the root', () {
      expect(
        cfiToRange(document, Cfi.parse('/6/4!')).start,
        CfiPoint(document.root, 0),
      );
    });

    test('a rejected node has no step; its text does not count', () {
      final doc = XmlCfiDocument.parse(
        '<html><body><p>ab<span x="1">XX</span>cd</p></body></html>',
      );
      CfiNodeFilterResult filter(CfiNode node) => node.attribute('x') != null
          ? CfiNodeFilterResult.reject
          : CfiNodeFilterResult.accept;
      final p = doc.root.children.single.children.single;
      final cd = p.children[2];
      final cfi = cfiFromPoint(CfiPoint(cd, 1), filter: filter);
      // "ab" and "cd" merge into one chunk once XX is rejected: offset 3.
      expect(cfi.toString(), 'epubcfi(/2/2/1:3)');
      expect(cfiToRange(doc, cfi, filter: filter).start, CfiPoint(cd, 1));
      final inside = cfiFromPoint(
        CfiPoint(p.children[1].children.single, 1),
        filter: filter,
      );
      expect(
        inside.toString(),
        'epubcfi(/2/2/1:1)',
        reason: 'a point inside a rejected node keeps its own offset',
      );
    });
  });
}

List<CfiNode> all(CfiNode root) {
  final out = <CfiNode>[];
  void walk(CfiNode node) {
    for (final child in node.children) {
      if (child.isElement) {
        out.add(child);
        walk(child);
      }
    }
  }

  walk(root);
  return out;
}
