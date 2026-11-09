/// Sentence boundaries by Unicode's default rules (UAX #29, "Sentence
/// Boundaries"): what `Intl.Segmenter` with `granularity: 'sentence'`
/// gives in the WebView reader, which Dart has no equivalent of. No
/// locale tailoring and no abbreviation suppression, as there.
library;

/// The offsets (UTF-16 code units) where sentences of [text] start, plus
/// `text.length`: `[0, …, text.length]`, strictly increasing; `[0]` for
/// empty text.
List<int> sentenceBreaks(String text) {
  if (text.isEmpty) return const [0];
  final starts = <int>[];
  final classes = <_Sb>[];
  for (var i = 0; i < text.length;) {
    final unit = text.codeUnitAt(i);
    var rune = unit;
    var width = 1;
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length) {
      final low = text.codeUnitAt(i + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        rune = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
        width = 2;
      }
    }
    starts.add(i);
    classes.add(_classOf(rune));
    i += width;
  }
  final breaks = <int>[0];
  for (var k = 1; k < classes.length; k++) {
    if (_breaksBefore(classes, k)) breaks.add(starts[k]);
  }
  breaks.add(text.length);
  return breaks;
}

/// The sentence of [text] holding code unit [index]: `(start, end)`.
(int, int) sentenceAt(String text, int index, [List<int>? breaks]) {
  final b = breaks ?? sentenceBreaks(text);
  var lo = 0;
  var hi = b.length - 2;
  if (hi < 0) return (0, 0);
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (b[mid] <= index) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return (b[lo], b[lo + 1]);
}

enum _Sb {
  other,
  cr,
  lf,
  extend,
  sep,
  format,
  sp,
  lower,
  upper,
  oLetter,
  numeric,
  aTerm,
  sContinue,
  sTerm,
  close,
}

bool _isParaSep(_Sb c) => c == _Sb.sep || c == _Sb.cr || c == _Sb.lf;

bool _isSaTerm(_Sb c) => c == _Sb.aTerm || c == _Sb.sTerm;

bool _isIgnored(_Sb c) => c == _Sb.extend || c == _Sb.format;

/// The index of the code point before [k] that rule SB5 does not fold
/// into its predecessor, or -1.
int _previous(List<_Sb> classes, int k) {
  var j = k - 1;
  while (j > 0 && _isIgnored(classes[j]) && !_isParaSep(classes[j - 1])) {
    j--;
  }
  return j;
}

bool _breaksBefore(List<_Sb> c, int k) {
  final cur = c[k];
  final before = c[k - 1];
  // SB3, SB4.
  if (before == _Sb.cr && cur == _Sb.lf) return false;
  if (_isParaSep(before)) return true;
  // SB5: extending characters belong to what they follow.
  if (_isIgnored(cur)) return false;

  final p = _previous(c, k);
  final prev = c[p];
  // SB6, SB7.
  if (prev == _Sb.aTerm) {
    if (cur == _Sb.numeric) return false;
    if (cur == _Sb.upper && p > 0) {
      final pp = c[_previous(c, p)];
      if (pp == _Sb.upper || pp == _Sb.lower) return false;
    }
  }
  // SATerm Close* Sp* before the boundary?
  var j = p;
  var hasSp = false;
  while (j > 0 && c[j] == _Sb.sp) {
    hasSp = true;
    j = _previous(c, j);
  }
  if (j == 0 && c[j] == _Sb.sp) return false;
  while (j > 0 && c[j] == _Sb.close) {
    j = _previous(c, j);
  }
  final term = c[j];
  if (!_isSaTerm(term)) return false; // SB998
  // SB8: ATerm Close* Sp* × (¬(OLetter|Upper|Lower|ParaSep|SATerm))* Lower
  if (term == _Sb.aTerm) {
    var i = k;
    while (i < c.length) {
      final x = c[i];
      if (x == _Sb.oLetter ||
          x == _Sb.upper ||
          x == _Sb.lower ||
          _isParaSep(x) ||
          _isSaTerm(x)) {
        break;
      }
      i++;
    }
    if (i < c.length && c[i] == _Sb.lower) return false;
  }
  // SB8a.
  if (cur == _Sb.sContinue || _isSaTerm(cur)) return false;
  // SB9.
  if (!hasSp && (cur == _Sb.close || cur == _Sb.sp || _isParaSep(cur))) {
    return false;
  }
  // SB10.
  if (cur == _Sb.sp || _isParaSep(cur)) return false;
  // SB11.
  return true;
}

final _ascii = List<_Sb>.generate(128, (i) => _classOfSlow(i));
final _cache = <int, _Sb>{};

_Sb _classOf(int rune) =>
    rune < 128 ? _ascii[rune] : _cache[rune] ??= _classOfSlow(rune);

final _extend = RegExp(r'[\p{Grapheme_Extend}\p{Mc}‍]', unicode: true);
final _format = RegExp(r'\p{Cf}', unicode: true);
final _space = RegExp(r'\p{White_Space}', unicode: true);
final _lower = RegExp(r'\p{Lowercase}', unicode: true);
final _upper = RegExp(r'[\p{Uppercase}\p{Lt}]', unicode: true);
final _letter = RegExp(r'\p{Alphabetic}', unicode: true);
final _numeric = RegExp(r'[\p{Nd}٫٬]', unicode: true);
final _sTerm = RegExp(r'\p{Sentence_Terminal}', unicode: true);
final _close = RegExp(
  r'[\p{Ps}\p{Pe}\p{Pi}\p{Pf}\p{Quotation_Mark}]',
  unicode: true,
);

const _sContinue = {
  0x2C, 0x2D, 0x3A, 0x3B, 0x37E, 0x55D, 0x60C, 0x60D, 0x7F8, 0x1802, //
  0x1808, 0x2013, 0x2014, 0x3001, 0xFE10, 0xFE11, 0xFE13, 0xFE14, 0xFE31,
  0xFE32, 0xFE50, 0xFE51, 0xFE54, 0xFE55, 0xFE58, 0xFE63, 0xFF0C, 0xFF0D,
  0xFF1A, 0xFF1B, 0xFF64,
};

/// Sentence_Break property values by UAX #29's table 4, in its order of
/// precedence.
_Sb _classOfSlow(int rune) {
  switch (rune) {
    case 0x0D:
      return _Sb.cr;
    case 0x0A:
      return _Sb.lf;
    case 0x85 || 0x2028 || 0x2029:
      return _Sb.sep;
    case 0x2E || 0x2024 || 0xFE52 || 0xFF0E:
      return _Sb.aTerm;
    case 0x200C || 0x200D:
      return _Sb.extend;
    case 0x5F3:
      return _Sb.oLetter;
  }
  final char = String.fromCharCode(rune);
  if (_extend.hasMatch(char)) return _Sb.extend;
  if (_format.hasMatch(char)) return _Sb.format;
  if (_space.hasMatch(char)) return _Sb.sp;
  if (_lower.hasMatch(char)) return _Sb.lower;
  if (_upper.hasMatch(char)) return _Sb.upper;
  if (_letter.hasMatch(char)) return _Sb.oLetter;
  if (_numeric.hasMatch(char)) return _Sb.numeric;
  if (_sContinue.contains(rune)) return _Sb.sContinue;
  if (_sTerm.hasMatch(char)) return _Sb.sTerm;
  if (_close.hasMatch(char)) return _Sb.close;
  return _Sb.other;
}
