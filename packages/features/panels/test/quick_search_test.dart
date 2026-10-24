import 'package:domain_models/domain_models.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/panel/quick_search.dart';

void main() {
  // `é` as macOS writes it on disk: an `e` and a combining acute, two
  // runes in one grapheme cluster.
  const decomposed = 'é.txt';

  /// The ranges applied to the name's grapheme clusters, as a row does.
  String underlined(String name, List<(int, int)> ranges) {
    final chars = name.characters.toList();
    return [for (final (s, e) in ranges) chars.sublist(s, e).join()].join('|');
  }

  test('ranges count grapheme clusters, so a decomposed name slices', () {
    final ranges = quickMatch('txt', decomposed, QuickSearchWhere.anywhere);
    expect(ranges, [(2, 5)]);
    expect(underlined(decomposed, ranges!), 'txt');
    expect(decomposed.runes.length, 6);
    expect(decomposed.characters.length, 5);
  });

  test('the ending and the beginning are found over clusters', () {
    expect(quickMatch('txt', decomposed, QuickSearchWhere.ending), [(2, 5)]);
    expect(
      quickMatch('é', decomposed, QuickSearchWhere.beginning),
      [(0, 1)],
    );
    expect(
      quickMatch('.t', decomposed, QuickSearchWhere.beginningOrEnding),
      isNull,
    );
  });

  test('a fuzzy match joins neighbouring clusters into one range', () {
    final ranges = quickMatch('et', decomposed, QuickSearchWhere.fuzzy);
    expect(ranges, isNull);
    final found = quickMatch('ét', decomposed, QuickSearchWhere.fuzzy);
    expect(found, [(0, 1), (2, 3)]);
    expect(underlined(decomposed, found!), 'é|t');
  });

  test('matching is case-insensitive and an empty query matches all', () {
    expect(quickMatch('', 'Readme.md', QuickSearchWhere.anywhere), isEmpty);
    expect(quickMatch('READ', 'Readme.md', QuickSearchWhere.beginning), [
      (0, 4),
    ]);
    expect(quickMatch('x', 'Readme.md', QuickSearchWhere.anywhere), isNull);
  });

  test('plain ASCII names match as their clusters do, in every mode', () {
    const names = ['Readme.md', 'a.txt', 'abcabc', 'x', 'ReadMe-Final.TXT'];
    const queries = ['r', 'md', 'abc', 'rf', 'txt', 'x', 'READ', 'eme'];
    for (final where in QuickSearchWhere.values) {
      for (final name in names) {
        // A cluster path: the same text with a non-ASCII rune after it.
        final wide = FoldedText('$name\u00e9');
        final narrow = FoldedText(name);
        expect(narrow.ascii, isTrue);
        expect(wide.ascii, isFalse);
        for (final q in queries) {
          final query = FoldedText(q);
          final ascii = quickMatchFolded(query, narrow, where);
          final clusters = switch (where) {
            // Over the same clusters but for the one appended.
            QuickSearchWhere.ending ||
            QuickSearchWhere.beginningOrEnding => quickMatch(q, name, where),
            _ => quickMatchFolded(query, wide, where),
          };
          expect(ascii, clusters, reason: '$where "$q" in "$name"');
        }
      }
    }
  });
}
