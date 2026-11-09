/// TeX hyphenation patterns (hyph-utf8) for the languages the reader
/// hyphenates: what Android's hyphenator, and the WebView reader there,
/// is built from. The data is generated (`tool/hyphenation_patterns.mjs`)
/// as constants, so any isolate reads it without a copy. Pure Dart.
library;

import 'package:meta/meta.dart';

part 'hyphenation_patterns_de.dart';
part 'hyphenation_patterns_en_gb.dart';
part 'hyphenation_patterns_en_us.dart';
part 'hyphenation_patterns_es.dart';
part 'hyphenation_patterns_fr.dart';
part 'hyphenation_patterns_it.dart';
part 'hyphenation_patterns_pt.dart';
part 'hyphenation_patterns_ru.dart';
part 'hyphenation_patterns_uk.dart';

/// One language's patterns as hyph-utf8 gives them: Liang patterns and
/// exception words, space separated, and the fewest letters the
/// language leaves before ([left]) and after ([right]) a break.
@immutable
class HyphenationPatterns {
  const HyphenationPatterns({
    required this.left,
    required this.right,
    required this.patterns,
    required this.exceptions,
  });

  final int left;
  final int right;
  final String patterns;

  /// Words with their breaks marked by `-`.
  final String exceptions;
}

/// The patterns for [language], a BCP 47 tag (`en`, `en-GB`, `pt-BR`), or
/// null for a language the reader does not hyphenate. English is American
/// unless the tag names a Commonwealth region.
HyphenationPatterns? hyphenationPatternsFor(String? language) {
  final parts = (language ?? '').toLowerCase().replaceAll('_', '-').split('-');
  return switch (parts.first) {
    'en' =>
      parts.length > 1 && _commonwealth.contains(parts[1]) ? _enGb : _enUs,
    'ru' => _ru,
    'uk' => _uk,
    'de' => _de,
    'fr' => _fr,
    'es' => _es,
    'it' => _it,
    'pt' => _pt,
    _ => null,
  };
}

const _commonwealth = {'gb', 'uk', 'au', 'nz', 'ie', 'za', 'in'};
