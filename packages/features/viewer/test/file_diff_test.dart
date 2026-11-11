import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_feature/src/file_diff.dart';

FileDiff compare(String left, String right) => compareFileBytes((
  Uint8List.fromList(utf8.encode(left)),
  Uint8List.fromList(utf8.encode(right)),
));

void main() {
  test('insertions, removals and replacements align line numbers', () {
    final result = compare('one\ntwo\nthree', 'one\nchanged\nthree\nfour');
    expect(result.failure, isNull);
    expect(result.rows.map((row) => row.kind), [
      FileDiffKind.equal,
      FileDiffKind.changed,
      FileDiffKind.equal,
      FileDiffKind.added,
    ]);
    expect(result.changes, [1, 3]);
    expect(result.rows.last.leftNumber, isNull);
    expect(result.rows.last.rightNumber, 4);
    final removed = compare('one\ntwo', 'one');
    expect(removed.rows.last.kind, FileDiffKind.removed);
    expect(removed.rows.last.leftNumber, 2);
  });

  test('empty files, final newline and repeated lines retain every line', () {
    expect(compare('', '').identicalBytes, isTrue);
    expect(compare('', '').rows, isEmpty);
    expect(compare('one', 'one\n').changes, isNotEmpty);
    final random = Random(42);
    for (var iteration = 0; iteration < 100; iteration++) {
      String text() => List.generate(
        random.nextInt(80),
        (_) => ['same', 'a', 'b', '🛳️', 'текст', ''][random.nextInt(6)],
      ).join('\n');
      final left = text(), right = text();
      final result = compare(left, right);
      expect(
        result.rows
            .where((row) => row.left != null)
            .map((row) => row.left)
            .join('\n'),
        left,
      );
      expect(
        result.rows
            .where((row) => row.right != null)
            .map((row) => row.right)
            .join('\n'),
        right,
      );
    }
  });

  test('line endings and UTF-8 BOM are distinguished from identical bytes', () {
    final result = compare('\ufeffone\r\ntwo\r\n', 'one\ntwo\n');
    expect(result.identicalBytes, isFalse);
    expect(result.changes, isEmpty);
    expect(result.rows.length, 3);
  });

  test('binary, malformed UTF-8 and bounded inputs have explicit outcomes', () {
    expect(compare('\u0000one', '\u0000two').failure, FileDiffFailure.binary);
    expect(
      compareFileBytes((Uint8List.fromList([255]), Uint8List(0))).failure,
      FileDiffFailure.binary,
    );
    expect(
      compareFileBytes((Uint8List(FileDiff.maxBytes + 1), Uint8List(0)))
          .failure,
      FileDiffFailure.tooLarge,
    );
    expect(
      compare('x' * (FileDiff.maxLineLength + 1), '').failure,
      FileDiffFailure.tooLarge,
    );
    expect(
      compare('\n' * FileDiff.maxLines, '').failure,
      FileDiffFailure.tooLarge,
    );
  });
}
