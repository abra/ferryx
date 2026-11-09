import '../../pagecraft_exception.dart';
import 'natural_order_tables.dart';

/// The page-order rules new comics are imported with. Stored per book as
/// `comicPageOrderVersion`; older books keep the version they were imported
/// with so their saved positions stay on the same pages.
const currentComicPageOrderVersion = 1;

const _imageExtensions = [
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.bmp',
  '.webp',
  '.svg',
  '.jxl',
  '.avif',
];

/// Picks the page images out of an archive's entry names and orders them
/// by the rules used by the former WebView reader (`comic-book.js`), so
/// existing saved positions keep naming the same pages.
///
/// Version 0 (books imported before natural ordering): names ending in a
/// lowercase image extension, in UTF-16 code-unit order. Version 1: any
/// case of extension, `__MACOSX` folders and `._` resource forks skipped,
/// natural order per [naturalFilenameCompare].
List<String> selectComicPages(
  Iterable<String> names, {
  required int pageOrderVersion,
}) {
  final List<String> pages;
  if (pageOrderVersion == 0) {
    pages = [
      for (final name in names)
        if (_imageExtensions.any(name.endsWith)) name,
    ]..sort();
  } else {
    final keyed = <(NaturalSortKey, String)>[
      for (final name in names)
        if (_isPageImage(name)) (NaturalSortKey(name), name),
    ];
    keyed.sort((a, b) => a.$1.compareTo(b.$1));
    pages = [for (final (_, name) in keyed) name];
  }
  if (pages.isEmpty) {
    throw const PagecraftException('No supported image files in archive');
  }
  return pages;
}

bool _isPageImage(String name) {
  final lower = name.toLowerCase();
  if (!_imageExtensions.any(lower.endsWith)) return false;
  for (final part in name.split('/')) {
    if (part == '__MACOSX' || part.startsWith('._')) return false;
  }
  return true;
}

/// Orders file names the way `Intl.Collator('en', {numeric: true,
/// sensitivity: 'variant'})` does, with the collator's ties broken by
/// code-unit order as the former WebView reader did.
///
/// Three levels, as in ICU: digit runs by numeric value and letters by base
/// letter first (punctuation before digits before letters, Latin before
/// Greek before Cyrillic before other scripts); then accents; then case,
/// lowercase first. See [NaturalSortKey] for what is and is not modelled.
int naturalFilenameCompare(String a, String b) =>
    NaturalSortKey(a).compareTo(NaturalSortKey(b));

/// A file name's collation elements, computed once so a sort does not
/// re-derive them on every comparison.
///
/// Modelled from ICU's root collation: ASCII punctuation in CLDR order,
/// dashes after `-`, currency after other symbols, decimal digits of any
/// script by value with leading zeros ignored, Latin letters with
/// diacritics as secondary differences (tables in
/// `natural_order_tables.dart`), `ß`/`æ`/`œ`/`ĳ` as expansions, `þ` after
/// `z`, Cyrillic `ё` as a variant of `е`. Not modelled: contractions of other
/// languages, non-decimal numerals (`²`, `½`), script-specific tailorings.
/// Names that differ only in those sort in code-point order.
class NaturalSortKey implements Comparable<NaturalSortKey> {
  NaturalSortKey(this.name) {
    _build();
  }

  final String name;
  final _primary = <int>[];
  final _secondary = <int>[];
  final _tertiary = <int>[];

  // Primary weights are kind-major: all punctuation sorts before all
  // digits, which sort before all letters. Digit runs encode their value
  // in a side table so arbitrarily long numbers compare by magnitude.
  static const _kindPunctuation = 0;
  static const _kindDigits = 1;
  static const _kindLetter = 2;
  static const _kindShift = 40;
  static const _indexMask = (1 << _kindShift) - 1;
  final _digitRuns = <String>[];

  void _build() {
    final runes = name.runes.toList();
    var i = 0;
    while (i < runes.length) {
      final rune = runes[i];
      final digit = _digitValue(rune);
      if (digit != null) {
        final buffer = StringBuffer();
        while (i < runes.length) {
          final value = _digitValue(runes[i]);
          if (value == null) break;
          buffer.writeCharCode(0x30 + value);
          i++;
        }
        _addDigits(buffer.toString());
        continue;
      }
      _addCharacter(rune);
      i++;
    }
  }

  void _addDigits(String digits) {
    var start = 0;
    while (start < digits.length - 1 && digits.codeUnitAt(start) == 0x30) {
      start++;
    }
    _digitRuns.add(digits.substring(start));
    _primary.add((_kindDigits << _kindShift) | (_digitRuns.length - 1));
    _secondary.add(0);
    _tertiary.add(0);
  }

  void _addCharacter(int rune) {
    final expansion = latinExpansions[rune];
    if (expansion != null) {
      final upper = expansion.toUpperCase() == expansion;
      for (final (index, unit) in expansion.toLowerCase().codeUnits.indexed) {
        _primary.add((_kindLetter << _kindShift) | (unit << 2));
        // The ligature is a secondary variant of its letters; `ß` sits
        // above `ss` by case level as ICU files it.
        _secondary.add(index == 0 ? rune : 0);
        _tertiary.add(
          index == 0 && rune == 0xDF
              ? 2
              : index == 0 && rune == 0x1E9E
              ? 3
              : upper
              ? 1
              : 0,
        );
      }
      return;
    }
    final punctuation = _punctuationRank(rune);
    if (punctuation != null) {
      _primary.add((_kindPunctuation << _kindShift) | punctuation);
      _secondary.add(0);
      _tertiary.add(0);
      return;
    }
    final text = String.fromCharCode(rune);
    final lower = text.toLowerCase();
    final isUpper = lower != text;
    final lowerRune = lower.runes.first;
    final base = _baseLetter(lowerRune);
    final primary = switch (lowerRune) {
      // þ is its own letter after z.
      0xFE => (0x7A << 2) | 2,
      _ => base << 2,
    };
    _primary.add((_kindLetter << _kindShift) | primary);
    _secondary.add(base == lowerRune ? 0 : lowerRune);
    _tertiary.add(isUpper ? 1 : 0);
  }

  static int _baseLetter(int lowerRune) {
    final override = latinBaseOverrides[lowerRune];
    if (override != null) return override;
    if (lowerRune >= 0xC0 && lowerRune < 0xC0 + latinBaseTable.length) {
      return latinBaseTable.codeUnitAt(lowerRune - 0xC0);
    }
    return lowerRune;
  }

  static int? _digitValue(int rune) {
    if (rune >= 0x30 && rune <= 0x39) return rune - 0x30;
    if (rune < 0x660) return null;
    for (final zero in _digitZeros) {
      if (rune >= zero && rune <= zero + 9) return rune - zero;
    }
    return null;
  }

  // Zero digits of the decimal scripts a comic scan is likely to use.
  static const _digitZeros = [
    0x660, // Arabic-Indic
    0x6F0, // Extended Arabic-Indic
    0x966, // Devanagari
    0x9E6, // Bengali
    0xE50, // Thai
    0xFF10, // Fullwidth
  ];

  // CLDR root order of ASCII whitespace, punctuation and symbols; currency
  // comes after all other symbols. Other dashes follow `-`.
  static const _punctuationOrder =
      '\t\n\u000B\u000C\r\u0085  _-,;:!?.\'"()[]{}@*/\\&#%`^+<=>|~\$';
  static const _punctuationSpacing = 16;
  static const _otherSymbolRank = 1 << 20;
  static const _currencyRank = 1 << 21;

  static int? _punctuationRank(int rune) {
    if (rune < 0x80 || rune == 0xA0 || rune == 0x85) {
      final index = _punctuationOrder.indexOf(String.fromCharCode(rune));
      if (index >= 0) return index * _punctuationSpacing;
      // ASCII letters and digits never reach here; control characters do.
      if (rune < 0x20 || rune == 0x7F) return rune;
      return null;
    }
    if (rune >= 0x2010 && rune <= 0x2015) {
      // Hyphens and dashes follow the ASCII hyphen, longer ones later.
      return _punctuationOrder.indexOf('-') * _punctuationSpacing +
          1 +
          (rune - 0x2010);
    }
    if (rune >= 0x20A0 && rune <= 0x20CF || rune == 0xA3 || rune == 0xA5) {
      return _currencyRank + rune;
    }
    if (_isSymbol(rune)) return _otherSymbolRank + rune;
    return null;
  }

  // Non-letter, non-digit code points outside the ASCII table: general
  // punctuation, CJK punctuation, Latin-1 symbols, and anything that has
  // no case and is not in a letter block.
  static bool _isSymbol(int rune) =>
      (rune >= 0xA1 && rune <= 0xBF) ||
      rune == 0xD7 ||
      rune == 0xF7 ||
      (rune >= 0x2000 && rune <= 0x2BFF) ||
      (rune >= 0x3000 && rune <= 0x303F) ||
      (rune >= 0xFE30 && rune <= 0xFE4F) ||
      (rune >= 0xFF00 && rune <= 0xFF0F) ||
      (rune >= 0xFF1A && rune <= 0xFF20) ||
      (rune >= 0xFF3B && rune <= 0xFF40) ||
      (rune >= 0xFF5B && rune <= 0xFF65);

  @override
  int compareTo(NaturalSortKey other) {
    final primary = _comparePrimary(other);
    if (primary != 0) return primary;
    final secondary = _compareLevel(_secondary, other._secondary);
    if (secondary != 0) return secondary;
    final tertiary = _compareLevel(_tertiary, other._tertiary);
    if (tertiary != 0) return tertiary;
    return name.compareTo(other.name);
  }

  int _comparePrimary(NaturalSortKey other) {
    final length = _primary.length < other._primary.length
        ? _primary.length
        : other._primary.length;
    for (var i = 0; i < length; i++) {
      final a = _primary[i];
      final b = other._primary[i];
      final kindA = a >> _kindShift;
      final kindB = b >> _kindShift;
      if (kindA != kindB) return kindA.compareTo(kindB);
      if (kindA != _kindDigits) {
        if (a != b) return a.compareTo(b);
        continue;
      }
      // A digit element carries an index into its own key's runs, so two
      // keys' digits are compared by value, never by the element itself.
      final digitsA = _digitRuns[a & _indexMask];
      final digitsB = other._digitRuns[b & _indexMask];
      if (digitsA.length != digitsB.length) {
        return digitsA.length.compareTo(digitsB.length);
      }
      final byValue = digitsA.compareTo(digitsB);
      if (byValue != 0) return byValue;
    }
    return _primary.length.compareTo(other._primary.length);
  }

  static int _compareLevel(List<int> a, List<int> b) {
    final length = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }
}
