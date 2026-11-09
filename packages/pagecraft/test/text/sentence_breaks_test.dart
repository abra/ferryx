import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// The expected breaks are what `Intl.Segmenter` (ICU, through node)
/// gives for curated text and for random strings over characters of
/// every sentence-break class; `test/fixtures/icu_sentence_breaks.mjs`
/// regenerates them.
void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/icu_sentence_breaks.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  final cases = (fixture['cases']! as List).cast<Map<String, Object?>>();

  test('breaks match ICU for every case', () {
    final mismatches = <String>[];
    for (final c in cases) {
      final text = c['text']! as String;
      final expected = (c['breaks']! as List).cast<int>();
      final actual = sentenceBreaks(text);
      if (!_listEquals(actual, expected)) {
        mismatches.add('${jsonEncode(text)}: expected $expected, got $actual');
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.take(20).join('\n'));
    expect(cases.length, greaterThan(1000));
  });

  test('sentenceAt finds the sentence holding an offset', () {
    const text = 'One here. Two there! Three';
    expect(sentenceAt(text, 0), (0, 10));
    expect(sentenceAt(text, 9), (0, 10));
    expect(sentenceAt(text, 10), (10, 21));
    expect(sentenceAt(text, 25), (21, 26));
    expect(sentenceAt('', 0), (0, 0));
    expect(sentenceBreaks(''), [0]);
  });
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
