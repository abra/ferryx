import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('comic_metadata_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<String> write(String name, List<int> bytes) async {
    final path = '${tempDir.path}/$name';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  test(
    'reads the title from the file name and the first page as cover',
    () async {
      final path = await write(
        'Saga v01 (2014).cbz',
        buildComicArchive([
          (name: 'Saga v01/010.png', width: 300, height: 450),
          (name: 'Saga v01/002.png', width: 1200, height: 1800),
          (name: 'Saga v01/001.png', width: 1000, height: 1500),
        ]),
      );
      final metadata = await readComicMetadata(path);
      expect(metadata.title, 'Saga v01 (2014)');
      expect(metadata.author, isNull);
      final cover = metadata.cover!;
      expect(cover.mimeType, 'image/jpeg');
      // 001.png comes first in reading order, whatever the archive order.
      expect(cover.width, 480);
      expect(cover.height, 720);
      expect(
        probeImageDimensions(cover.bytes),
        const ImageDimensions(480, 720),
      );
    },
  );

  test('uses the given thumbnail spec', () async {
    final path = await write('issue.cbz', buildComicArchive(portraitPages(2)));
    final metadata = await readComicMetadata(
      path,
      spec: const CoverThumbnailSpec(maxWidth: 120, maxHeight: 120),
    );
    expect(metadata.cover!.width, lessThanOrEqualTo(120));
    expect(metadata.cover!.height, 120);
  });

  test('leaves the cover out when the first page is over budget', () async {
    final path = await write('issue.cbz', buildComicArchive(portraitPages(2)));
    final metadata = await readComicMetadata(path, maxCoverBytes: 16);
    expect(metadata.title, 'issue');
    expect(metadata.cover, isNull);
  });

  test('leaves the cover out when the first page does not decode', () async {
    final archive = ZipBuilder()
      ..add('001.jpg', Uint8List.fromList(List.filled(80, 0x41)))
      ..add('002.png', encodeSolidPng(200, 300));
    final path = await write('broken.cbz', archive.build());
    final metadata = await readComicMetadata(path);
    expect(metadata.title, 'broken');
    expect(metadata.cover, isNull);
  });

  test('rejects files that are not comics', () async {
    final text = await write('notes.cbz', 'not a zip'.codeUnits);
    await expectLater(
      readComicMetadata(text),
      throwsA(isA<PagecraftException>()),
    );
    final empty = await write(
      'empty.cbz',
      (ZipBuilder()..add('readme.txt', 'hi'.codeUnits)).build(),
    );
    await expectLater(
      readComicMetadata(empty),
      throwsA(isA<PagecraftException>()),
    );
  });
}
