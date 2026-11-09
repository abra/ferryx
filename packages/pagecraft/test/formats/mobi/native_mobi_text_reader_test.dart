import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/formats/mobi/native/native_mobi_text_reader.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pagecraft-native-mobi-');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<NativeMobiTextReader> open({
    int compression = 1,
    int trailingFlags = 0,
  }) async {
    final file = File('${directory.path}/records');
    await file.writeAsBytes([65, 66, 67, 68, 69, 70]);
    return NativeMobiTextReader.open(
      path: file.path,
      recordOffsets: Int64List.fromList([0, 3, 6]),
      textStart: 0,
      textCount: 2,
      dictionaryStart: 0,
      dictionaryCount: 0,
      compression: compression,
      trailingFlags: trailingFlags,
    );
  }

  test('record and batch reads preserve order and bytes', () async {
    final reader = await open();
    addTearDown(reader.close);
    expect(await reader.readRecord(1), [68, 69, 70]);
    expect(await reader.readRecord(0), [65, 66, 67]);
    expect(await reader.readRecords(0, 2), [65, 66, 67, 68, 69, 70]);
    expect(await reader.readRecords(2, 0), isEmpty);
  });

  test('concurrent reads complete before idempotent close', () async {
    final reader = await open(compression: 2);
    final reads = [
      reader.readRecord(1),
      reader.readRecords(0, 2),
      reader.readRecord(0),
    ];
    final closing = reader.close();
    expect(identical(closing, reader.close()), isTrue);
    expect(() => reader.readRecord(0), throwsStateError);
    expect(await Future.wait(reads), [
      [68, 69, 70],
      [65, 66, 67, 68, 69, 70],
      [65, 66, 67],
    ]);
    await closing;
    expect(() => reader.readRecords(0, 0), throwsStateError);
  });

  test('bad indices do not poison later reads', () async {
    final reader = await open();
    addTearDown(reader.close);
    expect(() => reader.readRecord(-1), throwsRangeError);
    expect(() => reader.readRecord(2), throwsRangeError);
    expect(() => reader.readRecords(1, 2), throwsRangeError);
    expect(await reader.readRecord(0), [65, 66, 67]);
  });

  test(
    'native file and configuration errors retain readable messages',
    () async {
      await expectLater(
        open(compression: 99),
        throwsA(
          isA<MobiNativeException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported MOBI compression'),
          ),
        ),
      );
      await expectLater(
        NativeMobiTextReader.open(
          path: '${directory.path}/missing',
          recordOffsets: Int64List.fromList([0, 1]),
          textStart: 0,
          textCount: 1,
          dictionaryStart: 0,
          dictionaryCount: 0,
          compression: 1,
          trailingFlags: 0,
        ),
        throwsA(isA<MobiNativeException>()),
      );
    },
  );

  test('offset snapshots and malformed ranges are validated in Rust', () async {
    final file = File('${directory.path}/records');
    await file.writeAsBytes([65, 66, 67]);
    for (final offsets in [
      [-1, 3],
      [0, 4],
      [2, 1, 3],
    ]) {
      await expectLater(
        NativeMobiTextReader.open(
          path: file.path,
          recordOffsets: Int64List.fromList(offsets),
          textStart: 0,
          textCount: 1,
          dictionaryStart: 0,
          dictionaryCount: 0,
          compression: 1,
          trailingFlags: 0,
        ),
        throwsA(isA<MobiNativeException>()),
      );
    }
  });
}
