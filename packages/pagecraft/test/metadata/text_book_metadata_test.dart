import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

import '../formats/mobi/mobi_fixture_books.dart';

void main() {
  late Directory tempDir;

  setUpAll(preparePdfEngineForTests);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('text_metadata_');
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<String> write(String name, List<int> bytes) async {
    final path = '${tempDir.path}/$name';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// The unpacked fixture zipped, with a cover the engine decodes in place
  /// of the fixture's hand-written 1×1 image.
  Future<String> writeEpub(String name, String fixture) async {
    final dir = Directory('test/fixtures/epub/$fixture');
    final zip = ZipBuilder();
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        final path = entity.path.substring(dir.path.length + 1);
        final bytes = path == 'OEBPS/images/cover.png'
            ? encodeSolidPng(600, 900)
            : entity.readAsBytesSync();
        zip.add(path, bytes, deflate: path != 'mimetype');
      }
    }
    return write(name, zip.build());
  }

  String fb2({String titleInfo = '', String cover = ''}) =>
      '<FictionBook xmlns:l="http://www.w3.org/1999/xlink">'
      '<description><title-info>$titleInfo</title-info></description>'
      '<body><section><p>x</p></section></body>$cover</FictionBook>';

  group('EPUB', () {
    test(
      'reads title, joined authors, description and a scaled cover',
      () async {
        final metadata = await readEpubMetadata(
          await writeEpub('book.epub', 'epub3'),
        );
        expect(metadata.title, 'The Fixture Book');
        expect(metadata.author, 'Ada Lovelace, Grace Hopper');
        expect(metadata.description, 'A book assembled for tests.');
        final cover = metadata.cover!;
        expect(cover.mimeType, 'image/jpeg');
        expect(
          probeImageDimensions(cover.bytes),
          const ImageDimensions(480, 720),
        );
      },
    );

    test('a book without a cover or description keeps the rest', () async {
      final metadata = await readEpubMetadata(
        await writeEpub('fixed.epub', 'fixed'),
      );
      expect(metadata.title, 'Fixed');
      expect(metadata.author, isNull);
      expect(metadata.description, isNull);
      expect(metadata.cover, isNull);
    });

    test('a broken container fails with a PagecraftException', () async {
      final path = await write('bad.epub', utf8.encode('not a zip'));
      await expectLater(
        readEpubMetadata(path),
        throwsA(isA<PagecraftException>()),
      );
    });
  });

  group('FB2', () {
    test('reads the book title, authors and the annotation as XHTML', () async {
      final metadata = await readFb2Metadata('test/fixtures/fb2/rich.fb2');
      expect(metadata.title, 'Книга с пробелами');
      expect(metadata.author, 'Иван Петрович Сидоров, anon42, Only');
      expect(metadata.description, contains('<p class="p">Первый'));
      // The fixture's cover is a 1×1 stub the engine does not decode.
      expect(metadata.cover, isNull);
    });

    test('the cover page image is scaled to the library size', () async {
      final png = base64Encode(encodeSolidPng(300, 600));
      final path = await write(
        'cover.fb2',
        utf8.encode(
          fb2(
            titleInfo:
                '<book-title> Spaced </book-title>'
                '<coverpage><image l:href="#c.png"/></coverpage>',
            cover: '<binary id="c.png" content-type="image/png">$png</binary>',
          ),
        ),
      );
      final metadata = await readFb2Metadata(path);
      expect(metadata.title, 'Spaced');
      expect(
        probeImageDimensions(metadata.cover!.bytes),
        const ImageDimensions(300, 600),
        reason: 'never scaled up',
      );
    });

    test('a zipped FB2 without a title takes the file name', () async {
      final bytes = utf8.encode(fb2());
      final zip = ZipBuilder()..add('inner.fb2', bytes);
      final path = await write('Untitled Story.fb2.zip', zip.build());
      final metadata = await readFb2Metadata(path);
      expect(metadata.title, 'Untitled Story');
      expect(metadata.author, isNull);
      expect(metadata.cover, isNull);
    });
  });

  group('MOBI', () {
    test('reads EXTH metadata and the cover resource', () async {
      final path = await write('six.mobi', MobiFixtureBooks.mobi6());
      final metadata = await readMobiMetadata(path);
      expect(metadata.title, 'Built MOBI <Updated>');
      expect(metadata.author, 'Ada & Grace, Alan');
      expect(metadata.description, 'A built book');
      // The fixture's cover is not a decodable image: no thumbnail.
      expect(metadata.cover, isNull);
    });

    test('a KF8 without a cover', () async {
      final path = await write('eight.azw3', MobiFixtureBooks.kf8());
      final metadata = await readMobiMetadata(path);
      expect(metadata.title, 'Built KF8');
      expect(metadata.author, 'Someone');
      expect(metadata.description, isNull);
      expect(metadata.cover, isNull);
    });

    test('a cover that decodes is scaled to the library size', () async {
      final builder = MobiBuilder(
        title: 'With Cover',
        exth: [MobiExthRecord.uint(201, 0)],
      )..addText(utf8.encode('<html><body><p>x</p></body></html>'));
      builder.addResource(encodeSolidPng(600, 900, rgba: 0x336699FF));
      final path = await write('cover.mobi', builder.build());
      final metadata = await readMobiMetadata(path);
      expect(metadata.title, 'With Cover');
      expect(
        probeImageDimensions(metadata.cover!.bytes),
        const ImageDimensions(480, 720),
      );
    });
  });
}
