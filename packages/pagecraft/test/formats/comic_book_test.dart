import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

import 'package:pagecraft/testing.dart';

void main() {
  late Directory tempDir;
  var fileCount = 0;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pagecraft_comic_');
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<String> write(List<int> bytes, {String name = 'Issue #1.cbz'}) async {
    final path = '${tempDir.path}/${fileCount++}/$name';
    await File(path).create(recursive: true);
    await File(path).writeAsBytes(bytes);
    return path;
  }

  Future<ComicBook> open(
    List<int> bytes, {
    int version = 1,
    String? name,
  }) async {
    final book = await ComicBook.open(
      await write(bytes, name: name ?? 'Issue #1.cbz'),
      pageOrderVersion: version,
    );
    addTearDown(book.close);
    return book;
  }

  test(
    'lists pages in natural order, skipping macOS junk and non-images',
    () async {
      final pages = [
        ...portraitPages(12, folder: 'Issue 1/'),
        (name: 'Issue 1/cover.png', width: 600, height: 900),
      ];
      final book = await open(
        buildComicArchive(
          pages,
          withMacOsJunk: true,
          extraEntries: ['Issue 1/ComicInfo.xml', 'Issue 1/'],
        ),
      );

      expect(book.pageCount, 13);
      expect(book.pages.map((p) => p.name).take(3), [
        'Issue 1/001.png',
        'Issue 1/002.png',
        'Issue 1/003.png',
      ]);
      expect(book.pages.last.name, 'Issue 1/cover.png');
      expect(book.pages.map((p) => p.index), List.generate(13, (i) => i));
      expect(book.pageOrderVersion, 1);
      expect(book.title, 'Issue #1');
      expect(book.path, endsWith('Issue #1.cbz'));
    },
  );

  test(
    'version 0 keeps the legacy order and includes resource forks',
    () async {
      final pages = [
        (name: 'page10.png', width: 10, height: 10),
        (name: 'page9.png', width: 10, height: 10),
        (name: 'Page1.png', width: 10, height: 10),
      ];
      final legacy = await open(
        buildComicArchive(pages, withMacOsJunk: true),
        version: 0,
      );
      expect(legacy.pages.map((p) => p.name), [
        'Page1.png',
        '__MACOSX/._Page1.png',
        '__MACOSX/._page10.png',
        '__MACOSX/._page9.png',
        'page10.png',
        'page9.png',
      ]);

      final natural = await open(
        buildComicArchive(pages, withMacOsJunk: true),
        version: 1,
      );
      expect(natural.pages.map((p) => p.name), [
        'Page1.png',
        'page9.png',
        'page10.png',
      ]);
    },
  );

  test('reads page bytes that decode to the fixture sizes', () async {
    final pages = [
      (name: '001.png', width: 600, height: 900),
      (name: '002.png', width: 1800, height: 900),
    ];
    final book = await open(buildComicArchive(pages, deflate: true));

    expect(
      probeImageDimensions(await book.readPage(0)),
      const ImageDimensions(600, 900),
    );
    expect(
      probeImageDimensions(await book.readPage(1)),
      const ImageDimensions(1800, 900),
    );
    expect(await book.readCover(), await book.readPage(0));
    expect(
      book.pages[0].size,
      encodeSolidPng(600, 900, rgba: 0x10203040).length,
    );
  });

  test('refuses pages above a byte budget without reading them', () async {
    final book = await open(buildComicArchive(portraitPages(1)));
    expect(
      () => book.readPage(0, maxBytes: 10),
      throwsA(isA<PagecraftException>()),
    );
    expect(await book.readCover(maxBytes: book.pages[0].size), isNotEmpty);
  });

  test('resolves hrefs to pages', () async {
    final book = await open(buildComicArchive(portraitPages(3)));
    expect(book.resolveHref('002.png'), book.pages[1]);
    expect(book.resolveHref('missing.png'), isNull);
    expect(book.pages[1].toString(), 'ComicPage(1, 002.png)');
  });

  test('throws on archives without images and on non-archives', () async {
    final empty = await write(
      buildComicArchive(const [], extraEntries: ['readme.txt']),
    );
    await expectLater(
      ComicBook.open(empty, pageOrderVersion: 1),
      throwsA(isA<PagecraftException>()),
    );
    final garbage = await write(List.filled(64, 7));
    await expectLater(
      ComicBook.open(garbage, pageOrderVersion: 1),
      throwsA(isA<PagecraftException>()),
    );
  });

  test('page index out of range is a programming error', () async {
    final book = await open(buildComicArchive(portraitPages(2)));
    expect(() => book.readPage(2), throwsRangeError);
    expect(() => book.readPage(-1), throwsRangeError);
  });

  test('fromArchive owns the archive it is given', () async {
    final archive = await ZipArchive.open(
      await write(buildComicArchive(portraitPages(1))),
    );
    final book = ComicBook.fromArchive(archive, pageOrderVersion: 1);
    await book.close();
    expect(() => archive.read(archive.entries.first), throwsStateError);
  });

  group('titleFromFileName', () {
    test('strips the directory and comic extensions of any case', () {
      expect(ComicBook.titleFromFileName('/books/Saga v1.CBZ'), 'Saga v1');
      expect(ComicBook.titleFromFileName('x/y/Issue.cbr'), 'Issue');
      expect(ComicBook.titleFromFileName('Issue.cb7'), 'Issue');
      expect(ComicBook.titleFromFileName('Issue.cbt'), 'Issue');
    });

    test('keeps other extensions and dots inside the name', () {
      expect(ComicBook.titleFromFileName('Vol. 2.zip'), 'Vol. 2.zip');
      expect(ComicBook.titleFromFileName('a.cbz.bak'), 'a.cbz.bak');
    });
  });
}
