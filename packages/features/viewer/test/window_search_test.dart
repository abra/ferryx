import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_feature/src/text_window.dart';
import 'package:viewer_feature/src/window_search.dart';

void main() {
  test('a complete result at the cap differs from a truncated result', () {
    for (final hex in [false, true]) {
      for (final count in [10000, 10001]) {
        final text = 'a' * count;
        final result = searchWindow(
          lines: [text],
          bytes: Uint8List.fromList(utf8.encode(text)),
          query: 'a',
          hex: hex,
        );
        expect(result.matches, hasLength(10000));
        expect(result.capped, count == 10001);
      }
    }
  });

  test(
    'worker cancellation completes callers and keeps only the replacement',
    () async {
      final worker = WindowSearchWorker();
      addTearDown(worker.cancel);
      final first = worker.search(
        lines: ['a' * (256 * 1024)],
        bytes: Uint8List(0),
        query: 'a',
        hex: false,
      );
      final next = worker.search(
        lines: const [],
        bytes: Uint8List.fromList(utf8.encode('aaaaAb')),
        query: 'aab',
        hex: true,
      );
      expect(await first, isNull);
      expect((await next)!.matches, [
        const ViewerMatch(line: 0, start: 3, end: 6),
      ]);
      final cancelled = worker.search(
        lines: const ['no match'],
        bytes: Uint8List(0),
        query: 'missing',
        hex: false,
      );
      worker.cancel();
      worker.cancel();
      expect(await cancelled, isNull);
    },
  );
}
