import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/mobi.dart';
import 'package:pagecraft/testing.dart';

import 'mobi_fixture_books.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pagecraft-mobi-native-');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<String> write(String name, List<int> bytes) async {
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  for (final dart in [false, true]) {
    test('accepted stream read completes before close; Dart=$dart', () async {
      final builder = MobiBuilder(compress: true, trailingMultibyte: true);
      final expected = utf8.encode('<p>${'words ' * 4000}</p>');
      builder.addText(expected);
      final path = await write('many.mobi', builder.build());
      final container = await MobiContainer.open(
        await PdbFile.open(path),
        useDartTextReader: dart,
      );
      final stream = container.loadAllText();
      final closing = container.close();
      expect(identical(closing, container.close()), isTrue);
      expect(await stream, expected);
      await closing;
      await expectLater(container.loadText(0), throwsStateError);
    });
  }

  test(
    'native and Dart text reads match for first, middle and last records',
    () async {
      final builder = MobiBuilder(compress: true, trailingMultibyte: true);
      builder.addText(utf8.encode('<p>${'chapter text ' * 4000}</p>'));
      final path = await write('ranges.mobi', builder.build());
      final native = await MobiContainer.open(await PdbFile.open(path));
      final dart = await MobiContainer.open(
        await PdbFile.open(path),
        useDartTextReader: true,
      );
      try {
        final last = native.headers.palmdoc.numTextRecords - 1;
        for (final index in [0, 1, last ~/ 2, last, 0]) {
          expect(await native.loadText(index), await dart.loadText(index));
        }
        expect(await native.loadAllText(), await dart.loadAllText());
      } finally {
        await native.close();
        await dart.close();
      }
    },
  );

  test(
    'record offsets are snapshots, and damaged initialization can be closed',
    () async {
      final builder = MobiBuilder()..addText(utf8.encode('<p>Text</p>'));
      final bytes = builder.build();
      final data = ByteData.sublistView(bytes);
      final recordZero = data.getUint32(78);
      data.setUint16(recordZero, 17480);
      data.setUint32(recordZero + 112, 0xffffffff);
      data.setUint32(recordZero + 116, 1);
      final path = await write('bad-huff.mobi', bytes);
      final pdb = await PdbFile.open(path);
      final offsets = pdb.recordOffsets;
      offsets[0] = -1;
      expect(pdb.recordOffsets[0], recordZero);
      final container = await MobiContainer.open(pdb);
      expect(container.metadata.title, 'Test Book');
      await expectLater(
        container.loadText(0),
        throwsA(isA<PagecraftException>()),
      );
      await container.close();
      await container.close();
    },
  );

  test('KF8 remains lazy when a later text record is unreadable', () async {
    final bytes = MobiFixtureBooks.kf8();
    final original = ByteData.sublistView(bytes);
    final records = original.getUint16(76);
    final tableEnd = 78 + records * 8;
    final extended = Uint8List(bytes.length + 8)
      ..setRange(0, tableEnd, bytes)
      ..setRange(tableEnd + 8, bytes.length + 8, bytes, tableEnd);
    final data = ByteData.sublistView(extended)..setUint16(76, records + 1);
    for (var i = 0; i < records; i++) {
      data.setUint32(78 + i * 8, original.getUint32(78 + i * 8) + 8);
    }
    data.setUint32(tableEnd, extended.length);
    data.setUint16(data.getUint32(78) + 8, records);
    final path = await write('lazy.azw3', extended);
    final sparse = await File(path).open(mode: FileMode.append);
    await sparse.truncate(extended.length + 64 * 1024 * 1024 + 1);
    await sparse.close();
    final book = (await MobiBook.open(path) as MobiKf8).book;
    try {
      expect(await book.loadText(0), contains(MobiFixtureBooks.fragment1));
      await expectLater(
        book.container.loadText(records - 1),
        throwsA(isA<PagecraftException>()),
      );
    } finally {
      await book.close();
    }
  });
}
