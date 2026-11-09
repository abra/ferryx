import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';
import 'package:xml/xml.dart';

/// Parity with `fb2.js` in Chromium: `test/fixtures/fb2/expected.json`
/// holds the converted XHTML, metadata, sizes, table of contents and
/// link resolutions the browser produced for the fixtures (recorded by
/// `fb2_fixtures.mjs` before the WebView reader's removal).
void main() {
  const root = 'test/fixtures/fb2';
  final expected =
      jsonDecode(File('$root/expected.json').readAsStringSync())
          as Map<String, dynamic>;

  /// A tree with element names, the attributes that matter and text, for
  /// comparing the browser's serialization with ours regardless of
  /// namespace declarations and attribute order.
  Object describe(XmlNode node) {
    switch (node) {
      case XmlElement():
        final attributes = <String, String>{};
        for (final a in node.attributes) {
          final name = a.name.prefix == null
              ? a.name.local
              : '${a.name.prefix}:${a.name.local}';
          if (name == 'xmlns' || name.startsWith('xmlns:')) continue;
          // fb2.js assigns `el.alt`/`el.title` on elements its XML document
          // does not reflect to attributes, so the browser's images carry
          // neither; pagecraft keeps both for accessibility.
          if (node.name.local == 'img' && (name == 'alt' || name == 'title')) {
            continue;
          }
          attributes[name] = a.value;
        }
        return {
          'tag': node.name.local,
          'attrs': attributes,
          'children': [
            for (final child in node.children)
              if (child is XmlElement || child is XmlText || child is XmlCDATA)
                describe(child),
          ],
        };
      default:
        return node.value ?? '';
    }
  }

  List<Object> parseBody(String markup) {
    final document = XmlDocument.parse(
      '<body xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">$markup</body>',
    );
    return [
      for (final child in document.rootElement.children)
        if (child is XmlElement || child is XmlText || child is XmlCDATA)
          describe(child),
    ];
  }

  Map<String, dynamic> navItem(BookNavItem item) => {
    'label': item.label,
    'href': item.href,
    'subitems': item.subitems?.map(navItem).toList(),
  };

  for (final entry in expected.entries) {
    final name = entry.key;
    final data = entry.value as Map<String, dynamic>;

    group(name, () {
      late Fb2Book book;

      setUpAll(() {
        book = Fb2Book.parse(File('$root/$name').readAsBytesSync());
      });

      test('sections convert to the same XHTML trees', () {
        final recorded = data['sections'] as List;
        expect(book.sections, hasLength(recorded.length));
        for (var i = 0; i < recorded.length; i++) {
          final section = recorded[i] as Map<String, dynamic>;
          expect(
            parseBody(book.sections[i].element.toXmlString()),
            parseBody(section['body'] as String),
            reason: 'section $i',
          );
          expect(book.sections[i].isLinear, section['linear'] != 'no');
          // The browser's document carries a stylesheet link and the
          // serializer differs; sizes agree within that envelope.
          expect(
            book.sections[i].size,
            closeTo(section['size'] as int, 200),
            reason: 'size of section $i',
          );
        }
      });

      test('metadata matches', () {
        final m = data['metadata'] as Map<String, dynamic>;
        final metadata = book.metadata;
        expect(metadata.title, m['title']);
        expect(metadata.identifier, m['identifier']);
        expect(metadata.language, m['language']);
        Map<String, dynamic> person(Fb2Person p) => {
          'name': p.name,
          'sortAs': p.sortAs,
          if (p.role != null) 'role': p.role,
        };
        // fb2.js returns a nickname as a bare string and leaves `sortAs`
        // out of document-info people; pagecraft always has a person.
        Map<String, dynamic> recorded(Object? p) => switch (p) {
          String() => {'name': p, 'sortAs': null},
          Map<String, dynamic>() => {'sortAs': null, ...p},
          _ => throw StateError('unexpected $p'),
        };
        expect(
          metadata.authors.map(person),
          (m['author'] as List).map(recorded),
        );
        expect(
          metadata.translators.map(person),
          (m['translator'] as List).map(recorded),
        );
        expect(
          metadata.contributors.map(person),
          (m['contributor'] as List).map(recorded),
        );
        expect(metadata.publisher, m['publisher']);
        expect(metadata.published, m['published']);
        expect(metadata.modified, m['modified']);
        expect(metadata.subjects, m['subject']);
        final description = m['description'] as String?;
        if (description == null) {
          expect(metadata.description, isNull);
        } else {
          expect(parseBody(metadata.description!), parseBody(description));
        }
      });

      test('cover matches', () {
        final cover = book.readCover();
        final recorded = data['cover'] as Map<String, dynamic>?;
        if (recorded == null) {
          expect(cover, isNull);
        } else {
          expect(cover!.bytes, hasLength(recorded['size']));
          expect(cover.mediaType, recorded['type']);
        }
      });

      test('table of contents and links match', () {
        expect(book.toc.map(navItem).toList(), data['toc']);
        for (final entry
            in (data['resolveHref'] as Map<String, dynamic>).entries) {
          final target = book.resolveHref(entry.key);
          expect(
            target.index < 0 ? null : target.index,
            entry.value,
            reason: entry.key,
          );
        }
        for (final entry
            in (data['isExternal'] as Map<String, dynamic>).entries) {
          expect(book.isExternal(entry.key), entry.value, reason: entry.key);
        }
      });
    });
  }

  group('details', () {
    late Fb2Book book;

    setUpAll(() {
      book = Fb2Book.parse(File('$root/rich.fb2').readAsBytesSync());
    });

    test('link targets carry their anchors', () {
      final toc = book.resolveHref('3#1') as Fb2TocTarget;
      expect(toc.index, 3);
      expect(toc.titleIndex, 1);
      final id = book.resolveHref('#n1') as Fb2IdTarget;
      expect(id.index, 6);
      expect(id.id, 'n1');
      expect(book.resolveHref('#nope').index, -1);
      expect(book.resolveHref('x#0').index, -1);
    });

    test('subsection titles are numbered in the XHTML for TOC links', () {
      final xhtml = book.sections[3].xhtml;
      expect(xhtml, startsWith('<?xml version="1.0" encoding="utf-8"?>'));
      expect(xhtml, contains('$fb2DataIdAttribute="0"'));
      expect(xhtml, contains('$fb2DataIdAttribute="1"'));
      expect(book.sections[3].titles, ['Глава 1.1', 'Глава 1.2']);
      expect(book.sections[3].ids, containsAll(['ch1', 'ch1-1']));
    });

    test('binaries decode and missing ones are null', () {
      expect(book.readBinary('pic.png')!.sublist(0, 4), [
        0x89,
        0x50,
        0x4E,
        0x47,
      ]);
      expect(book.readBinary('missing'), isNull);
    });

    test('image sources: inline data, external href, empty', () {
      final section = book.sections[3].element.toXmlString();
      expect(section, contains('src="data:image/png;base64,iVBOR'));
      expect(section, contains('src="external.png"'));
      expect(section, contains('src="#missing.png"'));
      expect(section, contains('src="data:,"'));
    });
  });

  group('encodings', () {
    test('windows-1251 is decoded by its declaration', () {
      final book = Fb2Book.parse(File('$root/cp1251.fb2').readAsBytesSync());
      expect(book.metadata.title, 'Кодировка 1251');
      expect(book.sections.single.element.toXmlString(), contains('ёЁ — тире'));
    });

    test('a UTF-8 byte order mark is dropped', () {
      final bytes = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(
          '<FictionBook><description><title-info><book-title>B</book-title></title-info></description><body><section><p>x</p></section></body></FictionBook>',
        ),
      ]);
      expect(Fb2Book.parse(bytes).metadata.title, 'B');
    });

    test('decodeCharset covers the charsets FB2 files declare', () {
      expect(
        decodeCharset(Uint8List.fromList([0xC0, 0xE0]), 'windows-1251'),
        'Аа',
      );
      expect(decodeCharset(Uint8List.fromList([0xC1, 0xE1]), 'koi8-r'), 'аА');
      expect(decodeCharset(Uint8List.fromList([0x80, 0xA0]), 'cp866'), 'Аа');
      expect(
        decodeCharset(Uint8List.fromList([0xB0, 0xD0]), 'iso-8859-5'),
        'Аа',
      );
      expect(decodeCharset(Uint8List.fromList([0xE9]), 'windows-1252'), 'é');
      expect(decodeCharset(Uint8List.fromList([0xE9]), 'latin1'), 'é');
      expect(
        decodeCharset(Uint8List.fromList([0xFF, 0xFE, 0x16, 0x04]), 'utf-16'),
        'Ж',
      );
      expect(
        decodeCharset(Uint8List.fromList([0xFE, 0xFF, 0x04, 0x16]), 'utf-16'),
        'Ж',
      );
      expect(
        decodeCharset(Uint8List.fromList([0xD0, 0x96]), 'unknown-charset'),
        'Ж',
        reason: 'unknown charsets fall back to UTF-8',
      );
      expect(isSupportedCharset('KOI8-R'), isTrue);
      expect(isSupportedCharset('x-mac-cyrillic'), isFalse);
    });
  });

  group('errors and containers', () {
    test('malformed XML fails with a PagecraftException', () {
      expect(
        () => Fb2Book.parse(
          Uint8List.fromList(utf8.encode('<FictionBook><body>')),
        ),
        throwsA(isA<PagecraftException>()),
      );
    });

    test('a book without bodies has no sections', () {
      final book = Fb2Book.parse(
        Uint8List.fromList(
          utf8.encode('<FictionBook><description/></FictionBook>'),
        ),
      );
      expect(book.sections, isEmpty);
      expect(book.toc, isEmpty);
      expect(book.readCover(), isNull);
      expect(book.metadata.title, '');
    });

    test('opens a plain file and a zipped one', () async {
      final dir = await Directory.systemTemp.createTemp('pagecraft_fb2');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = File('$root/rich.fb2').readAsBytesSync();
      await File('${dir.path}/book.fb2').writeAsBytes(bytes);
      final zip = ZipBuilder()
        ..add('readme.txt', utf8.encode('not the book'))
        ..add('book.FB2', bytes, deflate: true);
      await File('${dir.path}/book.fb2.zip').writeAsBytes(zip.build());
      final plain = await Fb2Book.open('${dir.path}/book.fb2');
      final zipped = await Fb2Book.open('${dir.path}/book.fb2.zip');
      expect(plain.metadata.title, 'Книга с пробелами');
      expect(zipped.metadata.title, 'Книга с пробелами');
      expect(zipped.sections.length, plain.sections.length);
      final empty = ZipBuilder()..add('other.txt', utf8.encode('x'));
      await File('${dir.path}/empty.zip').writeAsBytes(empty.build());
      await expectLater(
        Fb2Book.open('${dir.path}/empty.zip'),
        throwsA(isA<PagecraftException>()),
      );
    });
  });
}
