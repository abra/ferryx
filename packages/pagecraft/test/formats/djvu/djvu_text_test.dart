import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/djvu.dart';

import 'djvu_fixture.dart';

void main() {
  late Directory directory;
  late DjvuBook book;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pagecraft-djvu-text-');
    final file = File('${directory.path}/original.djvu');
    await file.writeAsBytes(djvuFixtureBytes());
    book = await DjvuBook.open(file.path);
  });

  tearDown(() async {
    await book.close();
    await directory.delete(recursive: true);
  });

  test('reads Unicode words with offsets and top-left page geometry', () async {
    final layer = await book.pageText(0);
    expect(layer.pageIndex, 0);
    expect(layer.width, 600);
    expect(layer.height, 900);
    expect(layer.text, contains('Quiet café Привет reader'));
    final word = layer.words.firstWhere((word) => word.text == 'Привет');
    expect(layer.text.substring(word.start, word.end), 'Привет');
    expect(word.box.left, greaterThan(50));
    expect(word.box.top, inInclusiveRange(190, 225));
    expect(word.box.width, greaterThan(50));
    expect(word.box.height, greaterThan(10));
    expect(word.box.right, lessThanOrEqualTo(layer.width));
    expect(word.box.bottom, lessThanOrEqualTo(layer.height));
    for (final word in layer.words) {
      expect(layer.text.substring(word.start, word.end), word.text);
      expect(word.box.isEmpty, isFalse);
    }
  });

  test('an image-only page has no invented text', () async {
    final layer = await book.pageText(2);
    expect(layer.text, isEmpty);
    expect(layer.words, isEmpty);
  });

  test('searches page by page using case and diacritic folding', () async {
    final quiet = await searchDjvuBook(book, 'QUIET').toList();
    expect(quiet.map((hits) => hits.single.page), [0, 1]);
    expect(quiet.first.single.match.match, 'Quiet');
    expect(quiet.last.single.match.match, 'quiet');
    final accent = await searchDjvuBook(book, 'CAFE').toList();
    expect(accent.single.single.page, 0);
    expect(accent.single.single.match.match, 'café');
    final cyrillic = await searchDjvuBook(book, 'привет').toList();
    expect(cyrillic.single.single.match.match, 'Привет');
  });

  test('blank and absent queries produce no hits', () async {
    expect(await searchDjvuBook(book, '   ').toList(), isEmpty);
    expect(
      await searchDjvuBook(book, 'not-in-this-document').toList(),
      isEmpty,
    );
  });

  test(
    'cancellation stops after an already accepted empty-page read',
    () async {
      final controlled = _ControlledDjvuBook();
      final subscription = searchDjvuBook(controlled, 'absent').listen((_) {
        fail('no page contains the query');
      });
      await controlled.firstRequest.future;
      final cancelled = subscription.cancel();
      controlled.firstResult.complete(_emptyLayer(0));
      await cancelled;
      expect(controlled.readPages, [0]);
    },
  );
}

DjvuTextLayer _emptyLayer(int page) => DjvuTextLayer(
  pageIndex: page,
  width: 600,
  height: 900,
  text: '',
  words: const [],
);

class _ControlledDjvuBook implements DjvuBook {
  final firstRequest = Completer<void>();
  final firstResult = Completer<DjvuTextLayer>();
  final readPages = <int>[];

  @override
  int get pageCount => 100;

  @override
  Future<DjvuTextLayer> pageText(int index) {
    readPages.add(index);
    if (index != 0) return Future.value(_emptyLayer(index));
    firstRequest.complete();
    return firstResult.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
