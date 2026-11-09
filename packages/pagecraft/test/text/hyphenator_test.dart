import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// [word] with `-` at its breaks.
String hyphenate(
  String language,
  String word, {
  int minBefore = 2,
  int minAfter = 2,
}) {
  final breaks = Hyphenator.forLanguage(
    language,
  )!.breaks(word, minBefore: minBefore, minAfter: minAfter);
  final out = StringBuffer();
  for (var i = 0; i < word.length; i++) {
    if (breaks.contains(i)) out.write('-');
    out.write(word[i]);
  }
  return out.toString();
}

void main() {
  test('American English, as TeX hyphenates it', () {
    expect(hyphenate('en', 'hyphenation'), 'hy-phen-ation');
    expect(hyphenate('en-US', 'algorithm'), 'al-go-rithm');
    expect(hyphenate('en', 'computer'), 'com-puter', reason: 'er is short');
    // The patterns keep three letters after a break.
    expect(hyphenate('en', 'chapter'), 'chap-ter');
    // Exceptions win: "as-so-ciate".
    expect(hyphenate('en', 'associate'), 'as-so-ciate');
  });

  test('case does not matter; the word keeps its own', () {
    expect(hyphenate('en', 'Hyphenation'), 'Hy-phen-ation');
  });

  test('Russian and other languages', () {
    expect(hyphenate('ru', 'переменные'), 'пе-ре-мен-ные');
    expect(hyphenate('ru', 'операторы'), 'опе-ра-то-ры');
    expect(hyphenate('de', 'Silbentrennung'), 'Sil-ben-tren-nung');
  });

  test('limits: before and after the break, and short words', () {
    expect(hyphenate('ru', 'операторы', minBefore: 3), 'опе-ра-то-ры');
    expect(hyphenate('ru', 'операторы', minBefore: 4), 'опера-то-ры');
    expect(hyphenate('ru', 'операторы', minAfter: 3), 'опе-ра-торы');
    expect(hyphenate('en', 'on'), 'on');
  });

  test('languages it does not know give nothing', () {
    expect(Hyphenator.forLanguage('ja'), isNull);
    expect(Hyphenator.forLanguage(null), isNull);
    expect(
      identical(Hyphenator.forLanguage('en'), Hyphenator.forLanguage('en-us')),
      isTrue,
      reason: 'built once',
    );
    expect(
      Hyphenator.forLanguage('en-GB')!.patterns,
      isNot(same(Hyphenator.forLanguage('en')!.patterns)),
    );
  });

  test('American English exceptions and Ukrainian apostrophes', () {
    expect(hyphenate('en', 'present'), 'present', reason: 'an exception');
    expect(hyphenate('en', 'reciprocity'), 'reci-procity');
    expect(hyphenate('uk', 'перемога'), 'пе-ре-мо-га');
  });

  test('LICENSE carries the notice of every bundled pattern file', () {
    final license = File('LICENSE').readAsStringSync();
    final files = Directory('lib/src/text')
        .listSync()
        .whereType<File>()
        .where(
          (f) => RegExp(r'hyphenation_patterns_\w+\.dart$').hasMatch(f.path),
        )
        .toList();
    expect(files, hasLength(9));
    for (final file in files) {
      final source = file.readAsStringSync();
      final name = RegExp(
        r'hyph-([\w-]+)\. Do not edit',
      ).firstMatch(source)![1];
      final copyright = RegExp(r'// copyright: (.+)').firstMatch(source)![1]!;
      expect(license, contains('hyph-utf8 hyphenation patterns, $name\n'));
      expect(license, contains(copyright), reason: name);
    }
  });
}
