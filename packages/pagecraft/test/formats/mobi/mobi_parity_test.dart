import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:pagecraft/all_formats.dart';
import 'package:xml/xml.dart';

/// Parity with `mobi.js` in Chromium: `test/fixtures/mobi/expected.json`
/// records what the browser made of the fixture books (recorded by
/// `mobi_fixtures.mjs` before the WebView reader's removal): metadata,
/// every section's parsed document, sizes, navigation and resolutions.
void main() {
  const dir = 'test/fixtures/mobi';
  final expected =
      jsonDecode(File('$dir/expected.json').readAsStringSync())
          as Map<String, dynamic>;

  Object? describe(dom.Node node) {
    if (node is dom.Text) return node.data;
    if (node is! dom.Element) return null;
    return {
      'tag': node.localName,
      'attrs': {
        for (final entry in node.attributes.entries)
          entry.key.toString(): entry.value,
      },
      'children': [for (final child in node.nodes) ?describe(child)],
    };
  }

  /// KF8 sections are XHTML in the browser; the same XML view here.
  Object? describeXml(XmlNode node) {
    if (node is XmlText || node is XmlCDATA) return node.value;
    if (node is! XmlElement) return null;
    return {
      'tag': node.name.local,
      'attrs': {for (final a in node.attributes) a.name.qualified: a.value},
      'children': [for (final child in node.children) ?describeXml(child)],
    };
  }

  Map<String, dynamic> navItem(BookNavItem item) => {
    'label': item.label,
    'href': item.href,
    'subitems': item.subitems?.map(navItem).toList(),
    if (item.type != null) 'type': item.type,
  };

  for (final entry in expected.entries) {
    final name = entry.key;
    final data = entry.value as Map<String, dynamic>;

    group(name, () {
      late MobiBook book;

      setUpAll(() async {
        book = await MobiBook.open('$dir/$name');
      });

      tearDownAll(() => book.close());

      test('is the kind the browser opened', () {
        expect(
          book is MobiKf8 ? 'kf8' : 'mobi6',
          data['kind'],
        );
      });

      test('metadata matches', () {
        final m = data['metadata'] as Map<String, dynamic>;
        final metadata = switch (book) {
          MobiKf8(:final book) => book.metadata,
          MobiLegacy(:final book) => book.metadata,
        };
        expect(metadata.identifier, m['identifier']);
        expect(metadata.title, m['title']);
        expect(metadata.authors, m['author']);
        expect(metadata.publisher, m['publisher']);
        // mobi.js gives EXTH languages as a list and the header's locale
        // language as a bare string; pagecraft always has a list.
        final language = m['language'];
        expect(metadata.language, language is String ? [language] : language);
        expect(metadata.published, m['published']);
        expect(metadata.description, m['description']);
        expect(metadata.subjects, m['subject']);
        expect(metadata.rights, m['rights']);
        expect(metadata.contributors, m['contributor']);
      });

      test('cover, direction and rendition match', () async {
        final cover = await switch (book) {
          MobiKf8(:final book) => book.readCover(),
          MobiLegacy(:final book) => book.readCover(),
        };
        expect(cover?.bytes.length, data['cover']);
        if (book case MobiKf8(:final book)) {
          expect(book.dir, data['dir']);
          final rendition = data['rendition'] as Map<String, dynamic>;
          expect(book.isFixedLayout, rendition['layout'] == 'pre-paginated');
          final viewport = rendition['viewport'] as Map<String, dynamic>;
          expect(
            book.viewport == null
                ? <String, String>{}
                : {
                    'width': '${book.viewport!.width}',
                    'height': '${book.viewport!.height}',
                  },
            viewport,
          );
        }
      });

      test('sections match, document for document', () async {
        final recorded = data['sections'] as List;
        switch (book) {
          case MobiLegacy(:final book):
            expect(book.sections, hasLength(recorded.length));
            for (var i = 0; i < recorded.length; i++) {
              final s = recorded[i] as Map<String, dynamic>;
              expect(book.sections[i].size, s['size'], reason: 'section $i');
              expect(
                describe(book.createDocument(i).documentElement!),
                s['document'],
                reason: 'section $i',
              );
            }
          case MobiKf8(:final book):
            expect(book.sections, hasLength(recorded.length));
            for (var i = 0; i < recorded.length; i++) {
              final s = recorded[i] as Map<String, dynamic>;
              final section = book.sections[i];
              if (!s.containsKey('document')) {
                expect(section.isLinear, isFalse, reason: 'section $i');
                expect(s['linear'], 'no');
                continue;
              }
              expect(section.size, s['size'], reason: 'section $i');
              expect(section.pageSpread?.name, s['pageSpread']);
              final text = await book.loadText(i);
              expect(
                describeXml(XmlDocument.parse(text).rootElement),
                s['document'],
                reason: 'section $i',
              );
            }
        }
      });

      test('navigation and link targets match', () async {
        final (toc, landmarks) = switch (book) {
          MobiKf8(:final book) => (book.toc, book.landmarks),
          MobiLegacy(:final book) => (book.toc, book.landmarks),
        };
        expect(toc?.map(navItem).toList(), data['toc']);
        expect(landmarks?.map(navItem).toList(), data['landmarks']);
        for (final target
            in (data['resolveHref'] as Map<String, dynamic>).entries) {
          final index = switch (book) {
            MobiKf8(:final book) => (await book.resolveHref(target.key))?.index,
            MobiLegacy(:final book) => book.resolveHref(target.key).index,
          };
          expect(index, target.value, reason: target.key);
        }
      });
    });
  }
}
