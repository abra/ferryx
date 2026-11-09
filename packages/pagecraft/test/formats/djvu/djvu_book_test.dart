import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/djvu.dart';

import 'djvu_fixture.dart';

void main() {
  late Directory directory;
  late String path;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pagecraft-djvu-test-');
    path = '${directory.path}/original.djvu';
    await File(path).writeAsBytes(djvuFixtureBytes());
  });

  tearDown(() => directory.delete(recursive: true));

  test('opens bundled pages, metadata and nested navigation', () async {
    final book = await DjvuBook.open(path);
    addTearDown(book.close);

    expect(book.pageCount, 3);
    expect(book.pages.map((page) => page.index), [0, 1, 2]);
    expect(book.pages.map((page) => page.width), [600, 900, 600]);
    expect(book.pages.map((page) => page.height), [900, 600, 900]);
    expect(book.pages.first.dpi, 300);
    expect(book.pages.first.aspectRatio, closeTo(2 / 3, 1e-9));
    expect(book.title, 'Pagecraft DjVu fixture');
    expect(book.author, 'Readflex Tests');
    final toc = book.toc!;
    expect(toc.map((item) => item.label), ['First chapter', 'Image only']);
    expect(book.resolveHref(toc.first.href!), 0);
    expect(toc.first.subitems!.single.label, 'Second page');
    expect(book.resolveHref(toc.first.subitems!.single.href!), 1);
    expect(book.resolveHref(toc.last.href!), 2);
    expect(book.resolveHref('#page=99'), isNull);
    expect(book.resolveHref('https://example.org/'), isNull);
  });

  test('rejects foreign, truncated and missing documents', () async {
    final foreign = File('${directory.path}/foreign.djvu');
    await foreign.writeAsString('This is not a DjVu file.');
    final truncated = File('${directory.path}/truncated.djvu');
    final bytes = djvuFixtureBytes();
    await truncated.writeAsBytes(bytes.sublist(0, 32));

    for (final invalidPath in [
      foreign.path,
      truncated.path,
      '${directory.path}/missing.djvu',
    ]) {
      await expectLater(
        DjvuBook.open(invalidPath),
        throwsA(isA<PagecraftException>()),
        reason: invalidPath,
      );
    }
  });

  test('refuses indirect documents and standalone external includes', () async {
    final cases = {
      'indirect.djvu': djvuIndirectFixtureBytes(),
      'external.djvu': djvuExternalIncludeFixtureBytes(),
    };
    for (final entry in cases.entries) {
      final file = File('${directory.path}/${entry.key}');
      await file.writeAsBytes(entry.value);
      await expectLater(
        DjvuBook.open(file.path),
        throwsA(isA<PagecraftException>()),
        reason: entry.key,
      );
    }
  });

  test(
    'a bundled include cycle fails with the decoder nesting guard',
    () async {
      final file = File('${directory.path}/cyclic.djvu');
      await file.writeAsBytes(djvuCyclicBundleFixtureBytes());
      Future<void> decode() async {
        final document = await DjvuBook.open(
          file.path,
          timeout: const Duration(seconds: 3),
        );
        try {
          await document.renderPage(0, targetWidth: 300);
        } finally {
          await document.close();
        }
      }

      await expectLater(
        decode(),
        throwsA(
          isA<PagecraftException>().having(
            (error) => error.message,
            'decoder guard',
            contains('INCL'),
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    'accepted operations complete before close; later work is refused',
    () async {
      final book = await DjvuBook.open(path);
      final rendering = book.renderPage(0, targetWidth: 300);
      final text = book.pageText(1);
      final closing = book.close();
      expect((await rendering).width, 300);
      expect((await text).text, contains('The story continues'));
      await closing;
      await book.close();
      expect(book.pageCount, 3, reason: 'immutable metadata remains readable');
      await expectLater(book.pageText(0), throwsStateError);
      await expectLater(book.renderPage(0, targetWidth: 100), throwsStateError);
    },
  );

  test('independent documents keep their own native handles', () async {
    final first = await DjvuBook.open(path);
    final second = await DjvuBook.open(path);
    addTearDown(first.close);
    addTearDown(second.close);
    await first.close();
    expect(
      (await second.pageText(0)).text,
      contains('Quiet café Привет reader'),
    );
    expect((await second.renderPage(1, targetWidth: 450)).height, 300);
  });

  test(
    'initial page rotation changes dimensions and word geometry once',
    () async {
      final bytes = djvuFixtureBytes();
      final signature = [
        0x49,
        0x4e,
        0x46,
        0x4f,
      ]; // The first uncompressed INFO chunk.
      var info = -1;
      for (var index = 0; index < bytes.length - 18; index++) {
        if (List.generate(
          4,
          (offset) => bytes[index + offset],
        ).indexed.every((entry) => entry.$2 == signature[entry.$1])) {
          info = index;
          break;
        }
      }
      expect(info, greaterThanOrEqualTo(0));
      // DjVuInfo encodes a 90-degree counter-clockwise initial rotation as 6.
      bytes[info + 8 + 9] = 6;
      final rotatedPath = '${directory.path}/rotated.djvu';
      await File(rotatedPath).writeAsBytes(bytes);
      final original = await DjvuBook.open(path);
      final rotated = await DjvuBook.open(rotatedPath);
      addTearDown(original.close);
      addTearDown(rotated.close);
      expect(rotated.pages.first.width, 900);
      expect(rotated.pages.first.height, 600);
      final pixels = await rotated.renderPage(0, targetWidth: 450);
      expect(pixels.width, 450);
      expect(pixels.height, 300);
      final before = (await original.pageText(0)).words.first;
      final after = (await rotated.pageText(0)).words.first;
      expect(after.text, before.text);
      expect(after.box.left, closeTo(before.box.top, 0.001));
      expect(after.box.top, closeTo(600 - before.box.right, 0.001));
      expect(after.box.width, closeTo(before.box.height, 0.001));
      expect(after.box.height, closeTo(before.box.width, 0.001));
    },
  );
}
