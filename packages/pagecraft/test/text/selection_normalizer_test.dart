import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// Every range of short texts against what the WebView reader's
/// `readflex_selection_normalizer.js` computes
/// (`test/fixtures/readflex_selection.json`, recorded before that reader's
/// removal; historical sources are identified in the package README).
void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/readflex_selection.json').readAsStringSync(),
          )
          as Map<String, Object?>;

  test('ranges grow to whole words as in the JS', () {
    final rows = (fixture['ranges']! as List).cast<List<Object?>>();
    expect(rows.length, greaterThan(800));
    final mismatches = <String>[];
    for (final [text as String, start as int, end as int, s, e, kind] in rows) {
      final r = normalizeTextRange(text, start, end);
      if (r.normalizedStart != s ||
          r.normalizedEnd != e ||
          r.kind.wireName != kind) {
        mismatches.add(
          '${jsonEncode(text)} [$start, $end): expected [$s, $e) $kind, '
          'got [${r.normalizedStart}, ${r.normalizedEnd}) ${r.kind.wireName}',
        );
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.take(10).join('\n'));
  });

  test('the texts are the slices, offsets are clamped', () {
    final r = normalizeTextRange("don't stop", 2, 4);
    expect(r.selectedText, 'n\'');
    expect(r.normalizedText, "don't");
    expect(r.kind, SelectionKind.partialWord);
    final clamped = normalizeTextRange('word', -3, 99);
    expect((clamped.start, clamped.end), (0, 4));
    expect(clamped.kind, SelectionKind.exact);
    expect(isInsideWord('word', 2), isTrue);
    expect(isInsideWord('a b', 1), isFalse);
    expect(isInsideWord('a-b', 1), isTrue, reason: 'a hyphen inside a word');
  });
}
