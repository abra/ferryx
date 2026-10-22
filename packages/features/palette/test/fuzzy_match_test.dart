import 'package:flutter_test/flutter_test.dart';
import 'package:palette_feature/palette_feature.dart';

void main() {
  int score(String query, String text) => fuzzyMatch(query, text)!.score;

  /// [texts] ordered best first for [query], as the palette ranks them
  /// (ties by the shorter text).
  List<String> ranked(String query, List<String> texts) {
    final scored =
        [
          for (final text in texts)
            if (fuzzyMatch(query, text) case final match?) (text, match.score),
        ]..sort((a, b) {
          final byScore = b.$2.compareTo(a.$2);
          return byScore != 0 ? byScore : a.$1.length.compareTo(b.$1.length);
        });
    return [for (final (text, _) in scored) text];
  }

  test('the query must be a subsequence, case and spaces aside', () {
    expect(fuzzyMatch('cpy', 'Copy'), isNotNull);
    expect(fuzzyMatch('COPY', 'copy'), isNotNull);
    expect(fuzzyMatch('copy to', 'Copy To…'), isNotNull);
    expect(fuzzyMatch('ypc', 'Copy'), isNull);
    expect(fuzzyMatch('copies', 'Copy'), isNull);
  });

  test('an empty query matches with nothing to highlight', () {
    expect(fuzzyMatch('', 'Copy'), const FuzzyMatch(0, []));
    expect(fuzzyMatch('   ', 'Copy'), const FuzzyMatch(0, []));
  });

  test('the ranges are the characters matched, neighbours merged', () {
    expect(fuzzyMatch('copy', 'Copy To…')!.ranges, [(0, 4)]);
    expect(fuzzyMatch('ct', 'Copy To…')!.ranges, [(0, 1), (5, 6)]);
    expect(fuzzyMatch('hid', 'Show Hidden Files')!.ranges, [(5, 8)]);
  });

  test('word starts beat letters inside words', () {
    // `sf`: the S of Show and the F of Files, not the f of "of".
    expect(fuzzyMatch('sf', 'Show of Files')!.ranges, [(0, 1), (8, 9)]);
    expect(
      score('ff', 'Find Files'),
      greaterThan(score('ff', 'Diffing')),
    );
    expect(
      ranked('tp', ['Output', 'Toggle Panels', 'Stop']).first,
      'Toggle Panels',
    );
  });

  test('a prefix beats the same word later on', () {
    expect(
      ranked('copy', ['Reveal and Copy', 'Copy Path', 'Copy']),
      ['Copy', 'Copy Path', 'Reveal and Copy'],
    );
  });

  test('a run of consecutive letters beats the same letters apart', () {
    expect(
      score('new', 'New Folder'),
      greaterThan(score('new', 'Next Window')),
    );
    expect(fuzzyMatch('fold', 'New Folder')!.ranges, [(4, 8)]);
  });

  test('camel case counts as a word start', () {
    expect(fuzzyMatch('fb', 'fooBar')!.ranges, [(0, 1), (3, 4)]);
  });

  test('Cyrillic matches as Latin does', () {
    expect(fuzzyMatch('коп', 'Копировать')!.ranges, [(0, 3)]);
    expect(
      ranked('нп', ['Синяя пена', 'Направо', 'Новая папка']).first,
      'Новая папка',
    );
  });

  test('a long label stays fast enough for every keystroke', () {
    final label = 'Jump to a Name by Its First Letter ' * 4;
    final watch = Stopwatch()..start();
    for (var i = 0; i < 400; i++) {
      fuzzyMatch('jmpltr', label);
    }
    expect(watch.elapsedMilliseconds, lessThan(200));
  });
}
