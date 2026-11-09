/// Plain-text search with the WebView reader's rules (`search.js`):
/// case-insensitive, diacritic-insensitive matching with excerpts of
/// 50 characters of context on each side.
library;

/// Characters of context kept before and after a match in an excerpt.
const searchContextLength = 50;

/// A match in the original text, with its excerpt.
class TextSearchMatch {
  const TextSearchMatch({
    required this.start,
    required this.end,
    required this.pre,
    required this.match,
    required this.post,
  });

  /// Offsets into the original text, [end] exclusive.
  final int start;
  final int end;

  /// Up to [searchContextLength] characters before the match, whitespace
  /// collapsed, with a leading ellipsis when cut.
  final String pre;

  /// The matched original text.
  final String match;

  /// Up to [searchContextLength] characters after the match, whitespace
  /// collapsed, with a trailing ellipsis when cut.
  final String post;

  @override
  String toString() => 'TextSearchMatch($start–$end "$pre[$match]$post")';
}

/// Every match of [query] in [text], in order. Matching ignores case and
/// diacritics on both sides (see [foldSearchText]); offsets are in [text].
List<TextSearchMatch> searchText(String text, String query) {
  final needle = foldSearchText(query).text;
  if (needle.isEmpty || text.isEmpty) return const [];
  final haystack = foldSearchText(text);
  final matches = <TextSearchMatch>[];
  var index = haystack.text.indexOf(needle);
  while (index >= 0) {
    final start = haystack.originalStart(index);
    final end = haystack.originalEnd(index + needle.length);
    matches.add(
      TextSearchMatch(
        start: start,
        end: end,
        pre: _contextBefore(text, start),
        match: text.substring(start, end),
        post: _contextAfter(text, end),
      ),
    );
    index = haystack.text.indexOf(needle, index + 1);
  }
  return matches;
}

/// [text] folded for matching, with a map back to original offsets.
class FoldedText {
  const FoldedText(this.text, this.starts, this.ends);

  /// Lowercase, diacritics removed, whitespace runs as one space.
  final String text;

  /// For each folded character, the original offset it came from.
  final List<int> starts;

  /// For each folded character, the original offset just past it and
  /// past any combining marks or extra whitespace folded away with it.
  final List<int> ends;

  int originalStart(int foldedIndex) => starts[foldedIndex];

  /// The original offset just past the folded character at [foldedEnd - 1].
  int originalEnd(int foldedEnd) => foldedEnd <= 0 ? 0 : ends[foldedEnd - 1];
}

/// Folds [text] as the WebView search did with `sensitivity: 'base'`:
/// lowercase, Latin and Cyrillic diacritics removed, combining marks
/// dropped, whitespace runs collapsed to one space. Letters outside those
/// tables keep their accents.
FoldedText foldSearchText(String text) {
  final out = StringBuffer();
  final starts = <int>[];
  final ends = <int>[];
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (_isWhitespace(unit)) {
      if (starts.isNotEmpty && _isWhitespace(text.codeUnitAt(starts.last))) {
        ends[ends.length - 1] = i + 1;
        continue;
      }
      out.write(' ');
      starts.add(i);
      ends.add(i + 1);
      continue;
    }
    if (_isCombining(unit)) {
      if (ends.isNotEmpty) ends[ends.length - 1] = i + 1;
      continue;
    }
    final lower = String.fromCharCode(_foldUnit(unit)).toLowerCase();
    for (var j = 0; j < lower.length; j++) {
      out.write(lower[j]);
      starts.add(i);
      ends.add(i + 1);
    }
  }
  return FoldedText(out.toString(), starts, ends);
}

String _contextBefore(String text, int offset) {
  var length = searchContextLength;
  while (true) {
    final from = offset - length < 0 ? 0 : offset - length;
    final collapsed = _collapse(text.substring(from, offset)).trimLeft();
    if (collapsed.length >= searchContextLength) {
      return '…${collapsed.substring(collapsed.length - searchContextLength)}';
    }
    if (from == 0) return collapsed;
    length *= 2;
  }
}

String _contextAfter(String text, int offset) {
  var length = searchContextLength;
  while (true) {
    final to = offset + length > text.length ? text.length : offset + length;
    final collapsed = _collapse(text.substring(offset, to)).trimRight();
    if (collapsed.length >= searchContextLength) {
      return '${collapsed.substring(0, searchContextLength)}…';
    }
    if (to == text.length) return collapsed;
    length *= 2;
  }
}

final _whitespaceRun = RegExp(r'\s+');

String _collapse(String text) => text.replaceAll(_whitespaceRun, ' ');

bool _isWhitespace(int unit) =>
    unit == 0x20 ||
    (unit >= 0x09 && unit <= 0x0D) ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200A) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000;

bool _isCombining(int unit) =>
    (unit >= 0x0300 && unit <= 0x036F) ||
    (unit >= 0x1AB0 && unit <= 0x1AFF) ||
    (unit >= 0x1DC0 && unit <= 0x1DFF) ||
    (unit >= 0x20D0 && unit <= 0x20FF) ||
    (unit >= 0xFE20 && unit <= 0xFE2F);

/// Precomposed letters whose base the collator compares at `base`
/// sensitivity: Latin-1 Supplement, Latin Extended-A and the two Cyrillic
/// letters that decompose (й, ё).
int _foldUnit(int unit) {
  if (unit < 0xC0) return unit;
  if (unit <= 0x17F) {
    final base = _latinBases[unit - 0xC0];
    return base == 0 ? unit : base;
  }
  return switch (unit) {
    0x0419 => 0x0418, // Й → И
    0x0439 => 0x0438, // й → и
    0x0401 => 0x0415, // Ё → Е
    0x0451 => 0x0435, // ё → е
    _ => unit,
  };
}

// Base letters for U+00C0–U+017F; 0 keeps the letter (æ, ð, ø, þ, ß, ...).
const _latinBases = <int>[
  // U+00C0–U+00CF: À Á Â Ã Ä Å Æ Ç È É Ê Ë Ì Í Î Ï
  0x41,
  0x41,
  0x41,
  0x41,
  0x41,
  0x41,
  0,
  0x43,
  0x45,
  0x45,
  0x45,
  0x45,
  0x49,
  0x49,
  0x49,
  0x49,
  // U+00D0–U+00DF: Ð Ñ Ò Ó Ô Õ Ö × Ø Ù Ú Û Ü Ý Þ ß
  0,
  0x4E,
  0x4F,
  0x4F,
  0x4F,
  0x4F,
  0x4F,
  0,
  0,
  0x55,
  0x55,
  0x55,
  0x55,
  0x59,
  0,
  0,
  // U+00E0–U+00EF: à á â ã ä å æ ç è é ê ë ì í î ï
  0x61,
  0x61,
  0x61,
  0x61,
  0x61,
  0x61,
  0,
  0x63,
  0x65,
  0x65,
  0x65,
  0x65,
  0x69,
  0x69,
  0x69,
  0x69,
  // U+00F0–U+00FF: ð ñ ò ó ô õ ö ÷ ø ù ú û ü ý þ ÿ
  0,
  0x6E,
  0x6F,
  0x6F,
  0x6F,
  0x6F,
  0x6F,
  0,
  0,
  0x75,
  0x75,
  0x75,
  0x75,
  0x79,
  0,
  0x79,
  // U+0100–U+010F: Ā ā Ă ă Ą ą Ć ć Ĉ ĉ Ċ ċ Č č Ď ď
  0x41,
  0x61,
  0x41,
  0x61,
  0x41,
  0x61,
  0x43,
  0x63,
  0x43,
  0x63,
  0x43,
  0x63,
  0x43,
  0x63,
  0x44,
  0x64,
  // U+0110–U+011F: Đ đ Ē ē Ĕ ĕ Ė ė Ę ę Ě ě Ĝ ĝ Ğ ğ
  0,
  0,
  0x45,
  0x65,
  0x45,
  0x65,
  0x45,
  0x65,
  0x45,
  0x65,
  0x45,
  0x65,
  0x47,
  0x67,
  0x47,
  0x67,
  // U+0120–U+012F: Ġ ġ Ģ ģ Ĥ ĥ Ħ ħ Ĩ ĩ Ī ī Ĭ ĭ Į į
  0x47,
  0x67,
  0x47,
  0x67,
  0x48,
  0x68,
  0,
  0,
  0x49,
  0x69,
  0x49,
  0x69,
  0x49,
  0x69,
  0x49,
  0x69,
  // U+0130–U+013F: İ ı Ĳ ĳ Ĵ ĵ Ķ ķ ĸ Ĺ ĺ Ļ ļ Ľ ľ Ŀ
  0x49,
  0,
  0,
  0,
  0x4A,
  0x6A,
  0x4B,
  0x6B,
  0,
  0x4C,
  0x6C,
  0x4C,
  0x6C,
  0x4C,
  0x6C,
  0x4C,
  // U+0140–U+014F: ŀ Ł ł Ń ń Ņ ņ Ň ň ŉ Ŋ ŋ Ō ō Ŏ ŏ
  0x6C,
  0,
  0,
  0x4E,
  0x6E,
  0x4E,
  0x6E,
  0x4E,
  0x6E,
  0,
  0,
  0,
  0x4F,
  0x6F,
  0x4F,
  0x6F,
  // U+0150–U+015F: Ő ő Œ œ Ŕ ŕ Ŗ ŗ Ř ř Ś ś Ŝ ŝ Ş ş
  0x4F,
  0x6F,
  0,
  0,
  0x52,
  0x72,
  0x52,
  0x72,
  0x52,
  0x72,
  0x53,
  0x73,
  0x53,
  0x73,
  0x53,
  0x73,
  // U+0160–U+016F: Š š Ţ ţ Ť ť Ŧ ŧ Ũ ũ Ū ū Ŭ ŭ Ů ů
  0x53,
  0x73,
  0x54,
  0x74,
  0x54,
  0x74,
  0,
  0,
  0x55,
  0x75,
  0x55,
  0x75,
  0x55,
  0x75,
  0x55,
  0x75,
  // U+0170–U+017F: Ű ű Ų ų Ŵ ŵ Ŷ ŷ Ÿ Ź ź Ż ż Ž ž ſ
  0x55,
  0x75,
  0x55,
  0x75,
  0x57,
  0x77,
  0x59,
  0x79,
  0x59,
  0x5A,
  0x7A,
  0x5A,
  0x7A,
  0x5A,
  0x7A,
  0,
];
