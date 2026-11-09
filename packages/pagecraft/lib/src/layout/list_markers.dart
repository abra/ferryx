/// List item markers (CSS Lists 3 and Counter Styles 3, the predefined
/// styles books use): the text a `list-style-type` gives an ordinal.
library;

/// The marker text for item [ordinal] in [type], with its suffix, or null
/// for `none`. A string type is its own marker; an unsupported keyword
/// falls back to `decimal`, as an unknown counter style does.
String? listMarkerText(String type, int ordinal) {
  if (type == 'none') return null;
  final symbol = _symbols[type];
  if (symbol != null) return symbol;
  // `list-style-type: "→ "`: the computed style keeps the string.
  if (!_keywords.contains(type)) return type;
  final text = counterText(type, ordinal);
  return type == 'cjk-decimal' ? '$text、' : '$text. ';
}

/// [value] in counter style [style] without a suffix, as `counter()`
/// shows it: `1`, `iv`, `•`; an unknown style is decimal.
String counterText(String style, int value) {
  if (style == 'none') return '';
  final symbol = _symbols[style];
  if (symbol != null) return symbol;
  return switch (style) {
    'decimal-leading-zero' =>
      '${value < 0 ? '-' : ''}${value.abs().toString().padLeft(2, '0')}',
    'lower-alpha' ||
    'lower-latin' => _alphabetic(value, _latinLower) ?? '$value',
    'upper-alpha' ||
    'upper-latin' => _alphabetic(value, _latinUpper) ?? '$value',
    'lower-greek' => _alphabetic(value, _greekLower) ?? '$value',
    'lower-roman' => _roman(value)?.toLowerCase() ?? '$value',
    'upper-roman' => _roman(value) ?? '$value',
    'cjk-decimal' => _cjkDecimal(value),
    _ => '$value',
  };
}

const _symbols = {
  'disc': '•',
  'circle': '◦',
  'square': '▪',
  'disclosure-open': '▾',
  'disclosure-closed': '▸',
};

/// Whether [type] numbers its items (so an ordinal is worth counting).
bool isOrderedListStyle(String type) =>
    type != 'none' &&
    type != 'disc' &&
    type != 'circle' &&
    type != 'square' &&
    type != 'disclosure-open' &&
    type != 'disclosure-closed' &&
    _keywords.contains(type);

const _keywords = {
  'none',
  'disc',
  'circle',
  'square',
  'disclosure-open',
  'disclosure-closed',
  'decimal',
  'decimal-leading-zero',
  'lower-alpha',
  'lower-latin',
  'upper-alpha',
  'upper-latin',
  'lower-greek',
  'lower-roman',
  'upper-roman',
  'cjk-decimal',
  // Recognized but drawn as decimal.
  'armenian',
  'upper-armenian',
  'lower-armenian',
  'georgian',
  'hebrew',
  'hiragana',
  'katakana',
  'hiragana-iroha',
  'katakana-iroha',
  'cjk-ideographic',
  'arabic-indic',
  'persian',
  'devanagari',
  'bengali',
  'thai',
};

const _latinLower = 'abcdefghijklmnopqrstuvwxyz';
const _latinUpper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _greekLower = 'αβγδεζηθικλμνξοπρστυφχψω';

/// Bijective base-n: a, b, …, z, aa, ab, …; null below 1.
String? _alphabetic(int ordinal, String digits) {
  if (ordinal < 1) return null;
  final n = digits.length;
  final out = <String>[];
  var value = ordinal;
  while (value > 0) {
    value--;
    out.add(digits[value % n]);
    value ~/= n;
  }
  return out.reversed.join();
}

/// 1–3999; null outside, where CSS falls back to decimal.
String? _roman(int ordinal) {
  if (ordinal < 1 || ordinal > 3999) return null;
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const symbols = [
    'M',
    'CM',
    'D',
    'CD',
    'C',
    'XC',
    'L',
    'XL',
    'X',
    'IX',
    'V',
    'IV',
    'I',
  ];
  final buffer = StringBuffer();
  var value = ordinal;
  for (var i = 0; i < values.length; i++) {
    while (value >= values[i]) {
      buffer.write(symbols[i]);
      value -= values[i];
    }
  }
  return buffer.toString();
}

String _cjkDecimal(int ordinal) {
  const digits = '〇一二三四五六七八九';
  final text = ordinal.abs().toString();
  return '${ordinal < 0 ? '-' : ''}${text.split('').map((d) => digits[int.parse(d)]).join()}';
}
