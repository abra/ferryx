import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

/// Parity with `epub.js` in Chromium: `test/fixtures/epub/expected.json`
/// records what the browser made of each fixture directory (recorded by
/// `epub_fixtures.mjs` before the WebView reader's removal); the same
/// files must give the same spine, navigation, metadata, cover and
/// resolutions here.
void main() {
  const root = 'test/fixtures/epub';
  final expected =
      jsonDecode(File('$root/expected.json').readAsStringSync())
          as Map<String, dynamic>;

  Map<String, List<int>> filesOf(String name) {
    final dir = Directory('$root/$name');
    return {
      for (final entity in dir.listSync(recursive: true))
        if (entity is File)
          entity.path.substring(dir.path.length + 1): entity.readAsBytesSync(),
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
      late EpubBook book;

      setUpAll(() async {
        book = await EpubBook.load(MemoryEpubFiles(filesOf(name)));
      });

      tearDownAll(() => book.close());

      test('spine sections match', () {
        expect(
          [
            for (final s in book.sections)
              {
                'id': s.href,
                'size': s.size,
                'cfi': s.cfi.toString(),
                'linear': s.spineItem.linear,
                'pageSpread': s.pageSpread?.name,
                'mediaOverlay': s.mediaOverlay?.href,
              },
          ],
          data['sections'],
        );
      });

      test('navigation matches', () {
        expect(book.toc?.map(navItem).toList(), data['toc']);
        expect(book.pageList?.map(navItem).toList(), data['pageList']);
        expect(book.landmarks?.map(navItem).toList(), data['landmarks']);
        expect(book.resources.navPath, data['navPath']);
        expect(book.resources.ncxPath, data['ncxPath']);
      });

      test('direction, rendition and media match', () {
        expect(book.dir, data['dir']);
        expect(book.rendition, data['rendition']);
        final media = data['media'] as Map<String, dynamic>;
        expect(book.media.narrators, media['narrator']);
        expect(book.media.durations, media['duration']);
        expect(book.media.activeClass, media['activeClass']);
        expect(book.media.playbackActiveClass, media['playbackActiveClass']);
      });

      test('metadata summary matches', () {
        final m = data['metadata'] as Map<String, dynamic>;
        final metadata = book.metadata;
        expect(metadata.title, m['title']);
        expect(metadata.subtitle, m['subtitle']);
        expect(metadata.sortAs, m['sortAs']);
        expect(metadata.language, m['language']);
        expect(metadata.identifier, m['identifier']);
        expect(metadata.description, m['description']);
        expect(metadata.publisher, m['publisher']);
        expect(metadata.published, m['published']);
        expect(metadata.modified, m['modified']);
        expect(metadata.rights, m['rights']);
        expect(
          metadata.subjects
              .map((s) => {'name': s.name, 'code': s.code, 'scheme': s.scheme})
              .toList(),
          m['subject'],
        );
        const roles = [
          'author',
          'artist',
          'producer',
          'colorist',
          'editor',
          'illustrator',
          'narrator',
          'translator',
          // Not `publisher`: epub.js keeps the dc:publisher string under
          // that key, so a publisher role would collide with it there.
          'contributor',
        ];
        for (final role in roles) {
          expect(
            metadata.contributors[role]
                ?.map((c) => {'name': c.name, 'sortAs': c.sortAs})
                .toList(),
            m[role],
            reason: role,
          );
        }
      });

      test('manifest matches', () {
        expect(
          [
            for (final item in book.resources.manifest)
              {
                'id': item.id,
                'href': item.href,
                'mediaType': item.mediaType,
                'properties': item.properties,
              },
          ],
          data['manifest'],
        );
        expect(book.resources.cover?.href, data['coverHref']);
      });

      test('cover matches', () async {
        final cover = await book.readCover();
        final recorded = data['cover'] as Map<String, dynamic>?;
        if (recorded == null) {
          expect(cover, isNull);
        } else {
          expect(cover!.bytes, hasLength(recorded['size']));
          expect(cover.mediaType, recorded['type']);
        }
      });

      test('hrefs resolve to the same sections', () {
        for (final entry
            in (data['resolveHref'] as Map<String, dynamic>).entries) {
          expect(
            book.resolveHref(entry.key)?.index,
            entry.value,
            reason: entry.key,
          );
        }
      });

      test('CFIs resolve to the same sections', () {
        for (final entry
            in (data['resolveCfi'] as Map<String, dynamic>).entries) {
          expect(
            book.resolveCfi(Cfi.parse(entry.key)).index,
            entry.value,
            reason: entry.key,
          );
        }
      });
    });
  }

  group('epub3 details', () {
    late EpubBook book;

    setUpAll(() async {
      book = await EpubBook.load(MemoryEpubFiles(filesOf('epub3')));
    });

    tearDownAll(() => book.close());

    test('deobfuscates IDPF and Adobe fonts, leaves DRM alone', () async {
      final files = filesOf('epub3');
      expect(
        await book.readResource('OEBPS/fonts/Serif.ttf'),
        files['OEBPS/fonts/Serif.plain'],
      );
      expect(
        await book.readResource('OEBPS/fonts/Sans.ttf'),
        files['OEBPS/fonts/Sans.plain'],
      );
      expect(
        await book.readResource('OEBPS/text/drm.xhtml'),
        files['OEBPS/text/drm.xhtml'],
      );
      expect(await book.readResource('OEBPS/nope'), isNull);
    });

    test('reads section text and resolves links from a section', () async {
      final text = await book.readSectionText(1);
      expect(text, contains('First paragraph'));
      expect(
        book.sections[1].resolveHref('../images/cover.png'),
        'OEBPS/images/cover.png',
      );
      expect(
        book.resolveHref('OEBPS/text/chapter2.xhtml#pg2')?.fragment,
        'pg2',
      );
      expect(book.resolveHref('OEBPS/text/chapter2.xhtml#')?.fragment, isNull);
    });

    test('parsed metadata keeps refines and legacy attributes', () {
      final parsed = book.parsedMetadata;
      final title = parsed.titles.first;
      expect(title.value, 'The Fixture Book');
      expect(title.lang, 'en');
      expect(title.dir, 'ltr');
      expect(title.prop('alternate-script')?.value, 'Книга-фикстура');
      expect(title.prop('alternate-script')?.lang, 'ru');
      expect(
        parsed.identifiers[1].prop('identifier-type')?.attrs['scheme'],
        'onix:codelist5',
      );
      expect(parsed.collections.single.value, 'Fixture Series');
      expect(parsed.collections.single.prop('group-position')?.value, '3');
      expect(parsed.sources, ['Original print edition']);
      expect(book.isFixedLayout, isFalse);
    });

    test('the DRM algorithm is listed as unknown, not decoded', () {
      final encryption = EpubEncryption.parse(
        XmlCfiDocument.parse(
          utf8.decode(filesOf('epub3')['META-INF/encryption.xml']!),
        ).document,
        book.resources.opf,
      );
      expect(encryption.isObfuscated('OEBPS/fonts/Serif.ttf'), isTrue);
      expect(encryption.isObfuscated('OEBPS/text/drm.xhtml'), isFalse);
      expect(encryption.isEmpty, isFalse);
    });
  });

  group('epub2 details', () {
    test('legacy role and file-as attributes become contributors', () async {
      final book = await EpubBook.load(MemoryEpubFiles(filesOf('epub2')));
      addTearDown(book.close);
      expect(book.metadata.authors, [
        const EpubContributor(name: 'Jane Austen', sortAs: 'Austen, Jane'),
      ]);
      expect(book.metadata.contributors['editor'], [
        const EpubContributor(name: 'Some Editor'),
      ]);
      expect(
        book.parsedMetadata.identifiers.first.prop('identifier-type')?.value,
        'ISBN',
      );
      expect(
        book.metadata.subjects.single,
        const EpubSubject(name: 'Classics', code: 'T1', scheme: 'AUTH'),
      );
      expect(book.isFixedLayout, isFalse);
    });
  });

  group('fixed layout', () {
    test(
      'display options set the layout and the first linear spread',
      () async {
        final book = await EpubBook.load(MemoryEpubFiles(filesOf('fixed')));
        addTearDown(book.close);
        expect(book.isFixedLayout, isTrue);
        expect(book.sections[0].pageSpread, isNull, reason: 'not linear');
        expect(
          book.sections[1].pageSpread,
          SpreadSide.left,
          reason: 'rtl opens on the left',
        );
        expect(book.sections[2].pageSpread, SpreadSide.center);
      },
    );
  });

  test('a manifest href escaping a reserved character finds its file', () async {
    // Calibre writes `%26` for a file named with `&`; decodeURI keeps the
    // escape, so the href stays as written and the lookup decodes it.
    final book = await EpubBook.load(
      MemoryEpubFiles.text({
        'META-INF/container.xml':
            '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
        'OEBPS/content.opf':
            '<package xmlns="http://www.idpf.org/2007/opf" version="2.0"><metadata/>'
            '<manifest><item id="c" href="Text/Brian%20%26%20Kevin.html" media-type="application/xhtml+xml"/></manifest>'
            '<spine><itemref idref="c"/></spine></package>',
        'OEBPS/Text/Brian & Kevin.html':
            '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Paul</p></body></html>',
      }),
    );
    expect(book.sections.single.href, 'OEBPS/Text/Brian %26 Kevin.html');
    expect(book.sections.single.size, greaterThan(0));
    expect(await book.readSectionText(0), contains('Paul'));
    expect(fullyDecodedPath('a%26b'), 'a&b');
    expect(fullyDecodedPath('plain'), isNull);
    expect(fullyDecodedPath('bad%zz'), isNull);
    expect(fullyDecodedPath('bad%ff'), isNull, reason: 'not UTF-8');
  });

  group('errors', () {
    test('a container without a package document fails', () async {
      await expectLater(
        EpubBook.load(MemoryEpubFiles.text({})),
        throwsA(isA<PagecraftException>()),
      );
      await expectLater(
        EpubBook.load(
          MemoryEpubFiles.text({
            'META-INF/container.xml':
                '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles/></container>',
          }),
        ),
        throwsA(isA<PagecraftException>()),
      );
      await expectLater(
        EpubBook.load(
          MemoryEpubFiles.text({
            'META-INF/container.xml':
                '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="x.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
          }),
        ),
        throwsA(isA<PagecraftException>()),
      );
    });

    test(
      'a malformed package document fails, a malformed nav is ignored',
      () async {
        const container =
            '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="x.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';
        await expectLater(
          EpubBook.load(
            MemoryEpubFiles.text({
              'META-INF/container.xml': container,
              'x.opf': '<package><metadata>',
            }),
          ),
          throwsA(isA<PagecraftException>()),
        );
        final book = await EpubBook.load(
          MemoryEpubFiles.text({
            'META-INF/container.xml': container,
            'x.opf':
                '<package xmlns="http://www.idpf.org/2007/opf"><metadata/><manifest><item id="n" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/></spine></package>',
            'nav.xhtml': '<html><body><nav',
            'a.xhtml': '<html/>',
          }),
        );
        addTearDown(book.close);
        expect(book.toc, isNull);
        expect(book.sections.single.href, 'a.xhtml');
        expect(book.sections.single.size, '<html/>'.length);
      },
    );

    test('a missing section file fails when read, not when opened', () async {
      final book = await EpubBook.load(
        MemoryEpubFiles.text({
          'META-INF/container.xml':
              '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="x.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
          'x.opf':
              '<package xmlns="http://www.idpf.org/2007/opf"><metadata/><manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/></spine></package>',
        }),
      );
      addTearDown(book.close);
      expect(book.sections.single.size, 0);
      await expectLater(
        book.readSectionText(0),
        throwsA(isA<PagecraftException>()),
      );
      expect(await book.readCover(), isNull);
    });
  });

  group('from a ZIP on disk', () {
    test('opens the epub3 fixture through the container', () async {
      final files = filesOf('epub3');
      final builder = ZipBuilder();
      for (final entry in files.entries) {
        builder.add(entry.key, entry.value, deflate: entry.key != 'mimetype');
      }
      final dir = await Directory.systemTemp.createTemp('pagecraft_epub');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/fixture.epub';
      await File(path).writeAsBytes(builder.build());
      final book = await EpubBook.open(path);
      addTearDown(book.close);
      expect(book.metadata.title, 'The Fixture Book');
      expect(book.sections, hasLength(5));
      expect(
        await book.readResource('OEBPS/fonts/Serif.ttf'),
        files['OEBPS/fonts/Serif.plain'],
      );
      final cover = await book.readCover();
      expect(cover!.mediaType, 'image/png');
      expect(Uint8List.fromList(cover.bytes.take(4).toList()), [
        0x89,
        0x50,
        0x4E,
        0x47,
      ]);
    });

    test('a missing file is an error at open', () async {
      await expectLater(EpubBook.open('/nowhere/book.epub'), throwsA(anything));
    });
  });
}
