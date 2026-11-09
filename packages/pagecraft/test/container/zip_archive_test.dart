import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

import 'package:pagecraft/testing.dart';

void main() {
  late Directory tempDir;
  var fileCount = 0;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pagecraft_zip_');
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<String> write(List<int> bytes) async {
    final path = '${tempDir.path}/archive_${fileCount++}.zip';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  Future<ZipArchive> open(List<int> bytes) async {
    final archive = await ZipArchive.open(await write(bytes));
    addTearDown(archive.close);
    return archive;
  }

  final page = Uint8List.fromList(List.generate(50_000, (i) => (i * 7) & 0xFF));
  final text = utf8.encode('The sea and the sky. ' * 200);

  group('central directory', () {
    test('lists stored and deflated entries with their sizes', () async {
      final zip = await open(
        ZipBuilder()
            .add('mimetype', utf8.encode('application/epub+zip'))
            .add('OEBPS/ch1.xhtml', text, deflate: true)
            .add('pages/001.png', page)
            .build(),
      );

      expect(zip.entries.map((e) => e.name), [
        'mimetype',
        'OEBPS/ch1.xhtml',
        'pages/001.png',
      ]);
      final chapter = zip.entry('OEBPS/ch1.xhtml')!;
      expect(chapter.compression, ZipCompression.deflate);
      expect(chapter.uncompressedSize, text.length);
      expect(chapter.compressedSize, lessThan(text.length));
      expect(chapter.isEncrypted, isFalse);
      expect(chapter.isDirectory, isFalse);
      final image = zip.entry('pages/001.png')!;
      expect(image.compression, ZipCompression.stored);
      expect(image.compressedSize, page.length);
      expect(zip.entry('missing'), isNull);
    });

    test('marks directories and keeps directory order', () async {
      final zip = await open(
        ZipBuilder()
            .add('b/', const [])
            .add('b/2.jpg', page)
            .add('a/1.jpg', page)
            .build(),
      );
      expect(zip.entries.map((e) => e.name), ['b/', 'b/2.jpg', 'a/1.jpg']);
      expect(zip.entries.first.isDirectory, isTrue);
    });

    test('finds the end record behind an archive comment', () async {
      final zip = await open(
        ZipBuilder(comment: 'made by a test ' * 100).add('x.txt', text).build(),
      );
      expect(zip.entries.single.name, 'x.txt');
      expect(await zip.read(zip.entries.single), text);
    });

    test('reads ZIP64 end records and extra fields', () async {
      final zip = await open(
        ZipBuilder(zip64Eocd: true)
            .addEntry(ZipBuilderEntry('first.png', page, zip64: true))
            .addEntry(
              ZipBuilderEntry('second.png', text, zip64: true, deflate: true),
            )
            .build(),
      );
      expect(zip.entries.map((e) => e.name), ['first.png', 'second.png']);
      expect(zip.entries[0].uncompressedSize, page.length);
      expect(zip.entries[1].uncompressedSize, text.length);
      expect(await zip.read(zip.entries[0]), page);
      expect(await zip.read(zip.entries[1]), text);
    });

    test('decodes UTF-8 names with the flag, UTF-8 bytes without it, '
        'and CP437 otherwise', () async {
      final zip = await open(
        ZipBuilder()
            .add('глава/страница.png', page, utf8Flag: true)
            .addEntry(
              ZipBuilderEntry(
                // latin1-encoded by the builder: these are the UTF-8 bytes
                // of "é" written by a tool that left the flag clear.
                String.fromCharCodes(utf8.encode('café.jpg')),
                page,
              ),
            )
            // 0x82 is "é" in CP437 and invalid as UTF-8.
            .addEntry(ZipBuilderEntry('caf\u0082.jpg', page))
            .build(),
      );
      expect(zip.entries.map((e) => e.name), [
        'глава/страница.png',
        'café.jpg',
        'café.jpg',
      ]);
    });

    test('opens an archive written by package:archive', () async {
      final written = archive.Archive()
        ..add(archive.ArchiveFile.bytes('a/1.txt', text))
        ..add(
          archive.ArchiveFile.bytes('b/2.bin', page)
            ..compression = archive.CompressionType.none,
        );
      final zip = await open(archive.ZipEncoder().encodeBytes(written));
      expect(zip.entries.map((e) => e.name), ['a/1.txt', 'b/2.bin']);
      expect(await zip.read(zip.entries[0]), text);
      expect(await zip.read(zip.entries[1]), page);
    });

    test('opens a 10 000-entry directory quickly', () async {
      final builder = ZipBuilder();
      for (var i = 0; i < 10_000; i++) {
        builder.add('pages/${i.toString().padLeft(5, '0')}.jpg', const [1, 2]);
      }
      final path = await write(builder.build());
      final watch = Stopwatch()..start();
      final zip = await ZipArchive.open(path);
      addTearDown(zip.close);
      watch.stop();
      expect(zip.entries, hasLength(10_000));
      expect(watch.elapsedMilliseconds, lessThan(500));
    });
  });

  group('damage', () {
    test('rejects files that are not archives', () async {
      final letters = await write(List.filled(100, 0x41));
      final empty = await write(const []);
      await expectLater(
        ZipArchive.open(letters),
        throwsA(isA<PagecraftException>()),
      );
      await expectLater(
        ZipArchive.open(empty),
        throwsA(isA<PagecraftException>()),
      );
    });

    test('rejects a truncated central directory', () async {
      final bytes = ZipBuilder().add('x.txt', text).add('y.txt', text).build();
      // Cut the second directory entry in half, keep the end record.
      final eocd = bytes.length - 22;
      final truncated = Uint8List.fromList([
        ...bytes.sublist(0, eocd - 20),
        ...bytes.sublist(eocd),
      ]);
      final path = await write(truncated);
      await expectLater(
        ZipArchive.open(path),
        throwsA(isA<PagecraftException>()),
      );
    });

    test('reports a damaged local header on read', () async {
      final zip = await open(
        ZipBuilder()
            .addEntry(
              ZipBuilderEntry('x.txt', text, corruptLocalSignature: true),
            )
            .build(),
      );
      await expectLater(
        zip.read(zip.entries.single),
        throwsA(
          isA<PagecraftException>().having(
            (e) => e.message,
            'message',
            contains('local header'),
          ),
        ),
      );
    });

    test('reports a size that does not match the directory', () async {
      final zip = await open(
        ZipBuilder()
            .addEntry(
              ZipBuilderEntry(
                'x.txt',
                text,
                deflate: true,
                declaredUncompressedSize: text.length + 1,
              ),
            )
            .build(),
      );
      await expectLater(
        zip.read(zip.entries.single),
        throwsA(isA<PagecraftException>()),
      );
    });

    test('reports a damaged deflate stream', () async {
      final bytes = ZipBuilder().add('x.txt', text, deflate: true).build();
      // Scribble over the compressed payload after the local header.
      final entry = (await open(bytes)).entries.single;
      final dataStart = entry.localHeaderOffset + 30 + 'x.txt'.length;
      for (var i = 0; i < 16; i++) {
        bytes[dataStart + 4 + i] = 0xFF;
      }
      final zip = await open(bytes);
      await expectLater(
        zip.read(zip.entries.single),
        throwsA(isA<PagecraftException>()),
      );
    });

    test('reports a truncated file on read', () async {
      final bytes = ZipBuilder().add('x.bin', page).add('y.txt', text).build();
      final zip = await open(bytes);
      // Shorten the file under the open handle: the directory still lists
      // the full entry.
      await File(zip.path).writeAsBytes(bytes.sublist(0, 1000));
      await expectLater(
        zip.read(zip.entry('x.bin')!),
        throwsA(isA<PagecraftException>()),
      );
    });
  });

  group('refusals', () {
    test(
      'lists encrypted and unsupported entries but refuses to read them',
      () async {
        final zip = await open(
          ZipBuilder()
              .addEntry(ZipBuilderEntry('secret.txt', text, encrypted: true))
              .addEntry(ZipBuilderEntry('bzip.txt', text, method: 12))
              .add('plain.txt', text)
              .build(),
        );
        expect(zip.entries, hasLength(3));
        expect(zip.entries[0].isEncrypted, isTrue);
        expect(zip.entries[1].compression, ZipCompression.unsupported);
        expect(
          () => zip.read(zip.entries[0]),
          throwsA(isA<PagecraftException>()),
        );
        expect(
          () => zip.read(zip.entries[1]),
          throwsA(isA<PagecraftException>()),
        );
        expect(await zip.read(zip.entries[2]), text);
      },
    );

    test('refuses entries above maxBytes before reading', () async {
      final zip = await open(ZipBuilder().add('big.png', page).build());
      expect(
        () => zip.read(zip.entries.single, maxBytes: page.length - 1),
        throwsA(
          isA<PagecraftException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
      expect(await zip.read(zip.entries.single, maxBytes: page.length), page);
    });

    test('refuses reads after close', () async {
      final zip = await ZipArchive.open(
        await write(ZipBuilder().add('x.txt', text).build()),
      );
      await zip.close();
      await zip.close();
      expect(() => zip.read(zip.entries.single), throwsStateError);
    });
  });

  group('reading', () {
    test('serves concurrent reads on one handle correctly', () async {
      final builder = ZipBuilder();
      final expected = <String, List<int>>{};
      for (var i = 0; i < 40; i++) {
        final data = List<int>.generate(10_000 + i, (j) => (i + j) & 0xFF);
        expected['$i.bin'] = data;
        builder.add('$i.bin', data, deflate: i.isOdd);
      }
      final zip = await open(builder.build());
      final reads = await Future.wait(zip.entries.map(zip.read));
      for (var i = 0; i < 40; i++) {
        expect(reads[i], expected['$i.bin'], reason: 'entry $i');
      }
    });

    test('a failed read does not block later reads', () async {
      final zip = await open(
        ZipBuilder()
            .addEntry(
              ZipBuilderEntry('bad.txt', text, corruptLocalSignature: true),
            )
            .add('good.txt', text)
            .build(),
      );
      await expectLater(
        zip.read(zip.entries[0]),
        throwsA(isA<PagecraftException>()),
      );
      expect(await zip.read(zip.entries[1]), text);
    });

    test('readDetached works from another isolate with plain data', () async {
      final path = await write(
        ZipBuilder().add('pages/001.png', page, deflate: true).build(),
      );
      final zip = await ZipArchive.open(path);
      final entry = zip.entries.single;
      await zip.close();

      final bytes = await Isolate.run(
        () => ZipArchive.readDetached(path, entry),
      );
      expect(bytes, page);
      expect(
        () => ZipArchive.readDetached(path, entry, maxBytes: 10),
        throwsA(isA<PagecraftException>()),
      );
    });

    test('entries are value objects', () async {
      final bytes = ZipBuilder().add('x.txt', text).build();
      final a = await open(bytes);
      final b = await open(bytes);
      expect(a.entries.single, b.entries.single);
      expect(a.entries.single.hashCode, b.entries.single.hashCode);
      expect(a.entries.single.toString(), contains('x.txt'));
    });
  });
}
