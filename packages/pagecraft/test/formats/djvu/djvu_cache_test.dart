import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/djvu.dart';

import 'djvu_fixture.dart';

void main() {
  test(
    'coalesces reads, bounds retained layers and rejects disposed access',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pagecraft-djvu-cache-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/original.djvu');
      await file.writeAsBytes(djvuFixtureBytes());
      final book = await DjvuBook.open(file.path);
      addTearDown(book.close);
      final cache = DjvuTextLayerCache(book, capacity: 2);
      var disposed = false;
      addTearDown(() {
        if (!disposed) cache.dispose();
      });
      final first = cache.load(0);
      expect(cache.load(0), same(first));
      expect((await first).text, contains('café'));
      await cache.load(1);
      expect(cache.loadedPages, [0, 1]);
      expect(cache.peek(0), isNotNull);
      await cache.load(2);
      expect(cache.loadedPages, [0, 2]);
      expect(cache.peek(1), isNull);
      cache.dispose();
      disposed = true;
      expect(cache.loadedPages, isEmpty);
      await expectLater(cache.load(0), throwsStateError);
    },
  );
}
