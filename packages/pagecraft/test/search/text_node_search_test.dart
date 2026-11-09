import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// Checked against foliate-js itself: `test/fixtures/foliate_search.json`
/// records its `search()` before the WebView reader's removal;
/// `tool/search_fold_table.mjs` folds every code point the way
/// `normalizeSearchText` does.
void main() {
  test('every code point folds as in the JS', () {
    final fixture =
        jsonDecode(File('test/fixtures/search_fold.json').readAsStringSync())
            as Map<String, Object?>;
    final changed = (fixture['changed']! as Map<String, Object?>).map(
      (k, v) => MapEntry(int.parse(k), v! as String),
    );
    final folder = SearchFolder();
    final mismatches = <String>[];
    for (var cp = 0x80; cp <= 0x2FFFF; cp++) {
      if (cp >= 0xD800 && cp <= 0xDFFF) continue;
      final hangul = cp >= 0xAC00 && cp <= 0xD7A3;
      if (hangul && !changed.containsKey(cp)) continue;
      final s = String.fromCharCode(cp);
      final expected = changed[cp] ?? s;
      final actual = folder.fold(s).text;
      if (actual != expected) {
        mismatches.add(
          '${cp.toRadixString(16)}: expected '
          '${expected.runes.map((r) => r.toRadixString(16))}, '
          'got ${actual.runes.map((r) => r.toRadixString(16))}',
        );
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.take(20).join('\n'));
  });

  test('matches, offsets and excerpts are the JS ones', () {
    final cases =
        (jsonDecode(
                  File('test/fixtures/foliate_search.json').readAsStringSync(),
                )
                as List)
            .cast<Map<String, Object?>>();
    for (final c in cases) {
      final strings = (c['strs']! as List).cast<String>();
      final query = c['query']! as String;
      final expected = (c['results']! as List).cast<Map<String, Object?>>();
      final actual = searchTextNodes(strings, query);
      expect(
        [
          for (final m in actual)
            {
              'startIndex': m.startIndex,
              'startOffset': m.startOffset,
              'endIndex': m.endIndex,
              'endOffset': m.endOffset,
              'pre': m.pre,
              'match': m.match,
              'post': m.post,
            },
        ],
        expected,
        reason: '${jsonEncode(strings)} / $query',
      );
    }
  });

  test('Turkish lowercases dotted and dotless i apart', () {
    final turkish = SearchFolder('tr-TR');
    expect(turkish.fold('ISPARTA İzmir').text, 'ısparta izmir');
    expect(
      searchTextNodes(['IŞIK ışık isik'], 'ışık', locale: 'tr'),
      hasLength(2),
    );
    expect(SearchFolder('en').fold('I').text, 'i');
  });

  test('length changes are recorded as edits', () {
    final folded = SearchFolder().fold('éx̀́y');
    expect(folded.text, 'exy');
    expect(
      [
        for (final e in folded.edits)
          (e.start, e.end, e.originalStart, e.originalEnd),
      ],
      [(0, 1, 0, 2), (1, 2, 2, 5)],
    );
  });
}
