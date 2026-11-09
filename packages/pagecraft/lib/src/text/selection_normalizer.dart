/// Selection edges grown to whole words for lexical actions (dictionary,
/// translation): `readflex_selection_normalizer.js`. A word is letters,
/// digits and marks, with an apostrophe or hyphen inside it ("don't",
/// "well-known"). Characters are UTF-16 code units, as in JavaScript.
library;

/// How a selection relates to whole words.
enum SelectionKind {
  /// Both edges were on word boundaries.
  exact('exact'),

  /// An edge cut a word, and the selection is within one word.
  partialWord('partial_word'),

  /// An edge cut a word, and the selection spans several.
  partialSpan('partial_span');

  const SelectionKind(this.wireName);

  /// The name the WebView reader sends.
  final String wireName;
}

/// A selection of [text] and its whole-word expansion.
typedef NormalizedTextRange = ({
  int start,
  int end,
  int normalizedStart,
  int normalizedEnd,
  String selectedText,
  String normalizedText,
  SelectionKind kind,
});

/// Grows `[start, end)` of [text] to whole words where an edge falls
/// inside one. Offsets are clamped to the text.
NormalizedTextRange normalizeTextRange(String text, int start, int end) {
  final s = start.clamp(0, text.length);
  final e = end.clamp(s, text.length);
  var normalizedStart = s;
  var normalizedEnd = e;
  if (isInsideWord(text, s)) {
    while (normalizedStart > 0 && _isTokenAt(text, normalizedStart - 1)) {
      normalizedStart--;
    }
  }
  if (isInsideWord(text, e)) {
    while (normalizedEnd < text.length && _isTokenAt(text, normalizedEnd)) {
      normalizedEnd++;
    }
  }
  final selectedText = text.substring(s, e);
  final normalizedText = text.substring(normalizedStart, normalizedEnd);
  final changed = normalizedStart != s || normalizedEnd != e;
  return (
    start: s,
    end: e,
    normalizedStart: normalizedStart,
    normalizedEnd: normalizedEnd,
    selectedText: selectedText,
    normalizedText: normalizedText,
    kind: !changed
        ? SelectionKind.exact
        : _space.hasMatch(selectedText.trim()) ||
              _space.hasMatch(normalizedText.trim())
        ? SelectionKind.partialSpan
        : SelectionKind.partialWord,
  );
}

/// Whether offset [offset] of [text] falls between two characters of one
/// word, so an edge there cuts it.
bool isInsideWord(String text, int offset) =>
    offset > 0 &&
    offset < text.length &&
    _isTokenAt(text, offset - 1) &&
    _isTokenAt(text, offset);

final _wordChar = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);
final _space = RegExp(r'\s');

bool _isWordChar(int unit) => unit < 0x80
    ? (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x5A) ||
          (unit >= 0x61 && unit <= 0x7A)
    : _wordChar.hasMatch(String.fromCharCode(unit));

bool _isJoiner(int unit) => unit == 0x27 || unit == 0x2019 || unit == 0x2D;

bool _isTokenAt(String text, int index) {
  if (index < 0 || index >= text.length) return false;
  final unit = text.codeUnitAt(index);
  if (_isWordChar(unit)) return true;
  if (!_isJoiner(unit)) return false;
  return index > 0 &&
      index + 1 < text.length &&
      _isWordChar(text.codeUnitAt(index - 1)) &&
      _isWordChar(text.codeUnitAt(index + 1));
}
