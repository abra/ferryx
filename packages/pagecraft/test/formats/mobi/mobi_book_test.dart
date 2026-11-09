import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

import 'mobi_fixture_books.dart';

/// Books built by `MobiBuilder` in memory and written to disk: a MOBI 6
/// with everything `mobi.js` reads from one, and a KF8 with skeletons,
/// fragments, flows, an NCX, a guide and page spreads.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('pagecraft_mobi');
  });

  tearDownAll(() => dir.delete(recursive: true));

  Future<String> write(String name, Uint8List bytes) async {
    final path = '${dir.path}/$name';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  group('MOBI 6', () {
    final tocPos = MobiFixtureBooks.tocPos;
    final onePos = MobiFixtureBooks.onePos;
    final sectionPos = MobiFixtureBooks.sectionPos;
    final twoPos = MobiFixtureBooks.twoPos;
    final html = MobiFixtureBooks.mobi6Html;
    String filepos(int offset) => MobiFixtureBooks.filepos(offset);
    final bytes = MobiFixtureBooks.mobi6();

    test('is detected and opened as a MOBI 6 book', () async {
      final path = await write('six.mobi', bytes);
      expect(await isMobiFile(path), isTrue);
      final book = await MobiBook.open(path);
      addTearDown(book.close);
      expect(book, isA<MobiLegacy>());
      final legacy = (book as MobiLegacy).book;
      expect(legacy.container.headers.palmdoc.compression, 2);
      expect(legacy.sections, hasLength(4));
      expect(
        legacy.sections.map((s) => s.size).fold(0, (a, b) => a + b),
        utf8.encode(html).length,
      );
      expect(legacy.sections[1].start, html.indexOf('<mbp:pagebreak/>'));
      expect(legacy.sections[2].start, html.indexOf('<mbp:pagebreak />'));
    });

    test('metadata comes from EXTH with entities decoded', () async {
      final path = await write('six.mobi', bytes);
      final book = (await MobiBook.open(path) as MobiLegacy).book;
      addTearDown(book.close);
      final m = book.metadata;
      expect(m.title, 'Built MOBI <Updated>');
      expect(m.authors, ['Ada & Grace', 'Alan']);
      expect(m.publisher, 'Press — House');
      expect(m.description, 'A built book');
      expect(m.subjects, ['Testing']);
      expect(m.published, '2024-01-02');
      expect(m.contributors, ['Helper']);
      expect(m.rights, 'CC0');
      expect(m.language, ['en-GB']);
      expect(m.identifier, '1234');
      final cover = await book.readCover();
      expect(cover!.bytes.sublist(0, 2), [0xFF, 0xD8]);
    });

    test('sections carry filepos anchors and no pagebreak tags', () async {
      final path = await write('six.mobi', bytes);
      final book = (await MobiBook.open(path) as MobiLegacy).book;
      addTearDown(book.close);
      final chapterOne = book.loadText(2);
      expect(chapterOne, contains('<a id="filepos${filepos(onePos)}"></a>'));
      expect(
        chapterOne,
        contains('<a id="filepos${filepos(sectionPos)}"></a>'),
      );
      expect(chapterOne, isNot(contains('pagebreak')));
      expect(
        chapterOne,
        startsWith(
          '<a id="filepos${filepos(onePos)}"></a><h1>Chapter One</h1>',
        ),
      );
      final doc = book.createDocument(2);
      expect(doc.getElementById('filepos${filepos(sectionPos)}'), isNotNull);
      expect(doc.querySelector('img')?.attributes['recindex'], '00001');
      expect((await book.loadRecindex(1)).sublist(0, 2), [0xFF, 0xD8]);
    });

    test('an old MOBI 3 header ends before the trailing flags', () async {
      // The bytes where the flags would be are the title's ("Chro"):
      // read as flags they would cut every record to pieces.
      final builder = MobiBuilder(
        title: 'The Chronicles of Narnia',
        version: 3,
        compress: true,
        mobiHeaderLength: 0xD0,
      );
      const text =
          '<html><body><p>Once upon a time</p>'
          '<mbp:pagebreak/><p>Narnia</p></body></html>';
      builder.addText(utf8.encode(text));
      final path = await write('narnia.mobi', builder.build());
      final book = (await MobiBook.open(path) as MobiLegacy).book;
      addTearDown(book.close);
      final headers = book.container.headers;
      expect(headers.mobi.length, 0xD0);
      expect(headers.mobi.trailingFlags, 0);
      expect(headers.mobi.indx, 0xFFFFFFFF);
      expect(book.metadata.title, 'The Chronicles of Narnia');
      expect(book.sections, hasLength(2));
      expect(book.loadText(0), contains('Once upon a time'));
      expect(book.loadText(1), contains('Narnia'));
    });

    test('a filepos inside a tag anchors before the tag', () async {
      // The link points into `<p class="x">`: inserted there, the anchor
      // would break the tag and its text would show `class="x">`.
      const before = '<html><body><p><a filepos=0000000000>go</a></p>';
      const target = '<p class="x">Target</p></body></html>';
      final pos = before.length + 5;
      final text =
          before.replaceFirst(
            '0000000000',
            pos.toString().padLeft(10, '0'),
          ) +
          target;
      final builder = MobiBuilder()..addText(utf8.encode(text));
      final path = await write('inside.mobi', builder.build());
      final book = (await MobiBook.open(path) as MobiLegacy).book;
      addTearDown(book.close);
      final section = book.loadText(0);
      expect(
        section,
        contains(
          '<a id="filepos${pos.toString().padLeft(10, '0')}"></a>'
          '<p class="x">Target</p>',
        ),
      );
      expect(book.anchorsMovedOutOfTags(0), 1);
      final doc = book.createDocument(0);
      expect(doc.body!.text, isNot(contains('class=')));
    });

    test('a filepos that is not a number opens no section', () async {
      final path = await write('six.mobi', bytes);
      final book = (await MobiBook.open(path) as MobiLegacy).book;
      addTearDown(book.close);
      // A guide reference without `filepos` reads `filepos:null`.
      expect(book.resolveHref('filepos:null').index, -1);
      expect(book.resolveHref('filepos:').index, 0, reason: 'Number("") is 0');
      expect(book.resolveHref('filepos:${filepos(onePos)}').index, 2);
      expect(book.resolveHref('filepos:999999999').index, -1);
    });

    test('the guide and the nested table of contents', () async {
      final path = await write('six.mobi', bytes);
      final book = (await MobiBook.open(path) as MobiLegacy).book;
      addTearDown(book.close);
      expect(book.landmarks, [
        BookNavItem(
          label: 'Table of Contents',
          type: const ['toc'],
          href: 'filepos:${filepos(tocPos)}',
        ),
        BookNavItem(
          label: 'Start',
          type: const ['text'],
          href: 'filepos:${filepos(onePos)}',
        ),
      ]);
      expect(book.toc, [
        BookNavItem(
          label: 'Chapter One',
          href: 'filepos:${filepos(onePos)}',
          subitems: [
            BookNavItem(
              label: 'Section 1.1',
              href: 'filepos:${filepos(sectionPos)}',
            ),
          ],
        ),
        BookNavItem(label: 'Chapter Two', href: 'filepos:${filepos(twoPos)}'),
      ]);
      expect(book.resolveHref('filepos:${filepos(sectionPos)}').index, 2);
      expect(
        book.resolveHref('filepos:${filepos(sectionPos)}').anchorId,
        'filepos${filepos(sectionPos)}',
      );
      expect(book.resolveHref('filepos:${filepos(twoPos)}').index, 3);
      expect(book.resolveHref('filepos:99999').index, -1);
      expect(book.isExternal('filepos:1'), isFalse);
      expect(book.isExternal('https://x'), isTrue);
    });

    test(
      'an uncompressed book without EXTH falls back to the header title',
      () async {
        final plain = MobiBuilder(
          title: 'Plain Title',
          localeLanguage: 25,
          localeRegion: 0,
        )..addText(utf8.encode('<html><body><p>Hi</p></body></html>'));
        final path = await write('plain.mobi', plain.build());
        final book = (await MobiBook.open(path) as MobiLegacy).book;
        addTearDown(book.close);
        expect(book.metadata.title, 'Plain Title');
        expect(book.metadata.language, ['ru']);
        expect(book.metadata.authors, isNull);
        expect(await book.readCover(), isNull);
        expect(book.toc, isNull);
        expect(book.landmarks, isEmpty);
        expect(book.loadText(0), '<html><body><p>Hi</p></body></html>');
      },
    );
  });

  group('KF8', () {
    const skeleton1 = MobiFixtureBooks.skeleton1;
    const fragment1 = MobiFixtureBooks.fragment1;
    const fragment2 = MobiFixtureBooks.fragment2;
    const fragment3 = MobiFixtureBooks.fragment3;
    const css = MobiFixtureBooks.css;
    const text = MobiFixtureBooks.kf8Text;
    final bytes = MobiFixtureBooks.kf8();

    test('opens as a KF8 book with sections, spreads and metadata', () async {
      final path = await write('eight.azw3', bytes);
      final book = (await MobiBook.open(path) as MobiKf8).book;
      addTearDown(book.close);
      expect(book.sections, hasLength(3));
      expect(book.sections[0].isLinear, isTrue);
      expect(book.sections[0].fragments.map((f) => f.index), [0, 1]);
      expect(
        book.sections[0].size,
        skeleton1.length + fragment1.length + fragment2.length,
      );
      expect(book.sections[0].pageSpread, SpreadSide.left);
      expect(book.sections[1].pageSpread, SpreadSide.center);
      expect(book.sections[2].isLinear, isFalse);
      expect(book.sections[2].size, 0);
      expect(book.metadata.title, 'Built KF8');
      expect(book.dir, 'rtl');
      expect(book.isFixedLayout, isTrue);
      expect(book.viewport, (width: 1200, height: 1600));
      expect(book.container.isKf8, isTrue);
    });

    test('section text is the skeleton with fragments inserted', () async {
      final path = await write('eight.azw3', bytes);
      final book = (await MobiBook.open(path) as MobiKf8).book;
      addTearDown(book.close);
      final one = await book.loadText(0);
      expect(
        one,
        '<html><head><title>One</title></head><body><div aid="A"></div>$fragment1$fragment2</body></html>',
      );
      expect(await book.loadText(1), '<html><body>$fragment3</body></html>');
      expect(await book.loadText(2), '');
    });

    test('flows and embedded resources load by kindle: URIs', () async {
      final path = await write('eight.azw3', bytes);
      final book = (await MobiBook.open(path) as MobiKf8).book;
      addTearDown(book.close);
      final flow = await book.loadResource('kindle:flow:0001?mime=text/css');
      expect(utf8.decode(flow!), css);
      expect(await book.loadFlow(5), isNull);
      final embed = await book.loadResource('kindle:embed:0002?mime=image/png');
      expect(embed, [0x89, 0x50, 0x4E, 0x47]);
      expect(await book.loadResource('nonsense'), isNull);
      expect(
        parseKindleResourceUri('kindle:embed:000A?mime=image/jpeg'),
        isA<KindleResourceUri>()
            .having((u) => u.id, 'id', 10)
            .having((u) => u.mediaType, 'mime', 'image/jpeg'),
      );
    });

    test('the table of contents, guide and position links', () async {
      final path = await write('eight.azw3', bytes);
      final book = (await MobiBook.open(path) as MobiKf8).book;
      addTearDown(book.close);
      expect(book.toc, [
        BookNavItem(
          label: 'Chapter One',
          href: const KindlePosition(fid: 0, off: 0).toUri(),
          subitems: [
            BookNavItem(
              label: 'Section',
              href: const KindlePosition(fid: 1, off: 0).toUri(),
            ),
          ],
        ),
        BookNavItem(
          label: 'Chapter Two',
          href: const KindlePosition(fid: 2, off: 0).toUri(),
        ),
      ]);
      expect(book.landmarks, [
        BookNavItem(
          label: 'Start here',
          type: const ['text'],
          href: const KindlePosition(fid: 0, off: 0).toUri(),
        ),
      ]);
      expect(
        const KindlePosition(fid: 1, off: 0).toUri(),
        'kindle:pos:fid:0001:off:0000000000',
      );
      expect(
        parseKindlePosition('kindle:pos:fid:000A:off:000000001F'),
        const KindlePosition(fid: 10, off: 47),
      );

      final first = await book.resolveHref(
        'kindle:pos:fid:0000:off:0000000000',
      );
      expect(first!.index, 0);
      expect(first.selector, '[id="p1"]');
      final second = await book.resolveHref(
        'kindle:pos:fid:0001:off:0000000000',
      );
      expect(second!.selector, '[aid="B"]');
      final third = await book.resolveHref(
        'kindle:pos:fid:0002:off:0000000000',
      );
      expect(third!.index, 1);
      expect(third.selector, '[name="named"]');
      expect(
        await book.resolveHref('kindle:pos:fid:0009:off:0000000000'),
        isNull,
      );
      expect(book.isExternal('kindle:pos:fid:0000:off:0000000000'), isFalse);
      expect(book.isExternal('https://x'), isTrue);
      expect(kindleFragmentSelector('<p id="a\\"b">'), '[id="a\\\\"]');
    });

    test('raw text loads from the end when that is nearer', () async {
      final path = await write('eight.azw3', bytes);
      final book = (await MobiBook.open(path) as MobiKf8).book;
      addTearDown(book.close);
      final tail = await book.loadRaw(text.length - css.length, text.length);
      expect(utf8.decode(tail), css);
      final head = await book.loadRaw(0, 6);
      expect(utf8.decode(head), '<html>');
    });
  });

  group('errors', () {
    test('a file that is not a PDB or not a MOBI fails', () async {
      final notPdb = await write('short.bin', Uint8List(10));
      await expectLater(
        MobiBook.open(notPdb),
        throwsA(isA<PagecraftException>()),
      );
      expect(await isMobiFile(notPdb), isFalse);
      final pdbBytes = MobiBuilder().build();
      pdbBytes.setRange(60, 68, ascii.encode('TEXtREAd'));
      final notMobi = await write('text.pdb', pdbBytes);
      await expectLater(
        MobiBook.open(notMobi),
        throwsA(isA<PagecraftException>()),
      );
    });

    test('an unknown compression fails at open', () async {
      final bytes = (MobiBuilder()..addText(utf8.encode('<p>x</p>'))).build();
      // Compression type lives at the start of record 0.
      final record0 =
          78 + 2 * 8 + 2 + 2 + 2; // header + 2+ records... computed below
      expect(record0, greaterThan(0));
      final headerEnd = 78 + MobiBytes(bytes).u16(76) * 8 + 2;
      bytes.buffer.asByteData().setUint16(headerEnd, 9);
      final path = await write('odd.mobi', bytes);
      await expectLater(
        MobiBook.open(path),
        throwsA(isA<PagecraftException>()),
      );
    });
  });
}
