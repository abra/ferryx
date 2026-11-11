import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  test('optional match budget bounds result construction', () {
    expect(searchText('aaaa', 'a', maxMatches: 2).length, 2);
    expect(searchText('aaaa', 'a', maxMatches: 0), isEmpty);
  });

  group('foldSearchText', () {
    test('lowercases and strips Latin and Cyrillic diacritics', () {
      expect(foldSearchText('Café NAÏVE Ångström').text, 'cafe naive angstrom');
      expect(foldSearchText('Ёлка и йод').text, 'елка и иод');
      expect(foldSearchText('straße').text, 'straße');
    });

    test('drops combining marks and collapses whitespace', () {
      final folded = foldSearchText('étude  \n deux');
      expect(folded.text, 'etude deux');
      expect(folded.originalStart(0), 0);
      expect(folded.originalEnd(1), 2, reason: 'the mark goes with its base');
      expect(folded.originalStart(5), 6);
      expect(folded.originalEnd(6), 10, reason: 'the whole whitespace run');
      expect(folded.originalStart(6), 10);
    });
  });

  group('searchText', () {
    const text =
        'The quick brown fox jumps over the lazy dog. It was a bright cold '
        'day in April, and the clocks were striking thirteen! A café au lait '
        'costs 3.50 euros; the naïve waiter smiled.';

    test('finds every match regardless of case and accents', () {
      final matches = searchText(text, 'CAFE');
      expect(matches, hasLength(1));
      expect(matches.single.match, 'café');
      expect(text.substring(matches.single.start, matches.single.end), 'café');
      expect(searchText(text, 'naive').single.match, 'naïve');
      expect(searchText(text, 'the'), hasLength(4));
    });

    test('keeps fifty characters of context with an ellipsis when cut', () {
      final match = searchText(text, 'April').single;
      expect(match.pre, hasLength(searchContextLength + 1));
      expect(match.pre, startsWith('…'));
      expect(match.pre, endsWith('bright cold day in '));
      expect(match.post, hasLength(searchContextLength + 1));
      expect(match.post, startsWith(', and the clocks'));
      expect(match.post, endsWith('…'));
    });

    test('short context is returned whole without an ellipsis', () {
      final first = searchText(text, 'quick').single;
      expect(first.pre, 'The ');
      final last = searchText(text, 'smiled').single;
      expect(last.post, '.');
    });

    test('context collapses line breaks and runs of spaces', () {
      final match = searchText('one\n\n  two   three\nfour', 'three').single;
      expect(match.pre, 'one two ');
      expect(match.post, ' four');
    });

    test('an empty or whitespace query matches nothing', () {
      expect(searchText(text, ''), isEmpty);
      expect(searchText('', 'a'), isEmpty);
    });

    test('a query with spaces matches across a line break', () {
      final match = searchText('lazy\ndog', 'lazy dog').single;
      expect(match.start, 0);
      expect(match.end, 8);
    });
  });
}
