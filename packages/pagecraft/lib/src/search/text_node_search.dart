/// Search over a document's text nodes: foliate-js's `search.js` as the
/// reader runs it (`simpleSearch`, case and diacritics ignored, words not
/// required whole). Text is folded per character (lowercase, canonical
/// decomposition, combining marks dropped) and matched with `indexOf`,
/// overlapping matches included; offsets map back through the folds that
/// changed a character's length.
library;

part 'search_fold_table.dart';

/// Characters of context kept on each side of a match in an excerpt.
const textNodeSearchContext = 50;

/// A match: from character [startOffset] of string [startIndex] to
/// [endOffset] of [endIndex], and its excerpt.
class TextNodeMatch {
  const TextNodeMatch({
    required this.startIndex,
    required this.startOffset,
    required this.endIndex,
    required this.endOffset,
    required this.pre,
    required this.match,
    required this.post,
  });

  final int startIndex;
  final int startOffset;
  final int endIndex;
  final int endOffset;

  /// Up to [textNodeSearchContext] characters of the first string before
  /// the match, whitespace collapsed, `…` first when cut.
  final String pre;

  /// The matched text as written.
  final String match;

  /// Up to [textNodeSearchContext] characters of the last string after
  /// the match, whitespace collapsed, `…` last when cut.
  final String post;

  @override
  String toString() =>
      'TextNodeMatch($startIndex:$startOffset–$endIndex:$endOffset '
      '"$pre[$match]$post")';
}

/// Every match of [query] in the concatenation of [strings] (the text
/// nodes of a document, in order). [locale] is the book's language: it
/// only changes lowercasing for Turkish and Azerbaijani.
List<TextNodeMatch> searchTextNodes(
  List<String> strings,
  String query, {
  String locale = 'en',
  int? maxMatches,
}) {
  if (query.isEmpty || strings.isEmpty) return const [];
  final folder = SearchFolder(locale);
  final haystack = folder.fold(strings.join());
  final needle = folder.fold(query).text;
  if (needle.isEmpty) return const [];
  final startOf = _OffsetMapper(haystack.edits, endBoundary: false);
  final endOf = _OffsetMapper(haystack.edits, endBoundary: true);
  final matches = <TextNodeMatch>[];
  var startIndex = -1;
  var endIndex = -1;
  var startSum = 0;
  var endSum = 0;
  for (
    var index = haystack.text.indexOf(needle);
    index >= 0 && (maxMatches == null || matches.length < maxMatches);
    index = haystack.text.indexOf(needle, index + 1)
  ) {
    final start = startOf(index);
    final end = endOf(index + needle.length);
    while (startSum <= start) {
      startSum += strings[++startIndex].length;
    }
    final startOffset = start - (startSum - strings[startIndex].length);
    while (endSum < end) {
      endSum += strings[++endIndex].length;
    }
    final endOffset = end - (endSum - strings[endIndex].length);
    final first = strings[startIndex];
    final last = strings[endIndex];
    matches.add(
      TextNodeMatch(
        startIndex: startIndex,
        startOffset: startOffset,
        endIndex: endIndex,
        endOffset: endOffset,
        pre: _context(first, startOffset, before: true),
        match: startIndex == endIndex
            ? first.substring(startOffset, endOffset)
            : first.substring(startOffset) +
                  strings.sublist(startIndex + 1, endIndex).join() +
                  last.substring(0, endOffset),
        post: _context(last, endOffset, before: false),
      ),
    );
  }
  return matches;
}

/// A span of the original text whose fold has another length: folded
/// `[start, end)` came from original `[originalStart, originalEnd)`;
/// [delta] is the total length change up to its end.
class SearchFoldEdit {
  const SearchFoldEdit(
    this.start,
    this.end,
    this.originalStart,
    this.originalEnd,
    this.delta,
  );

  final int start;
  final int end;
  final int originalStart;
  final int originalEnd;
  final int delta;
}

/// Folds text for matching, as `normalizeSearchText` does at sensitivity
/// `base`: each character and its combining marks become the lowercase
/// base letter (`É` → `e`, `ё` → `е`, `ς` → `σ`, Hangul syllables their
/// jamo), lone marks vanish. Results are cached per character.
class SearchFolder {
  SearchFolder([String locale = 'en'])
    : _turkic = RegExp(r'^(tr|az)\b', caseSensitive: false).hasMatch(locale);

  final bool _turkic;
  final _cache = <int, String>{};

  ({String text, List<SearchFoldEdit> edits}) fold(String text) {
    final out = StringBuffer();
    final edits = <SearchFoldEdit>[];
    var delta = 0;
    var i = 0;
    while (i < text.length) {
      final spanStart = i;
      var rune = text.codeUnitAt(i);
      if (rune < 0x80 && !_turkic) {
        // ASCII never changes length.
        out.writeCharCode(rune >= 0x41 && rune <= 0x5A ? rune + 32 : rune);
        i++;
        if (i < text.length && _isMarkAt(text, i)) {
          // A base with marks: drop them as one span.
          while (i < text.length && _isMarkAt(text, i)) {
            i += _width(text, i);
          }
          final length = i - spanStart;
          if (length != 1) {
            final start = out.length - 1;
            delta += 1 - length;
            edits.add(SearchFoldEdit(start, start + 1, spanStart, i, delta));
          }
        }
        continue;
      }
      rune = _runeAt(text, i);
      final isMark = _isMark(rune);
      i += rune > 0xFFFF ? 2 : 1;
      var value = isMark ? '' : _foldRune(rune);
      // A base takes the marks after it; marks alone are one span.
      while (i < text.length && _isMarkAt(text, i)) {
        i += _width(text, i);
      }
      if (isMark) value = '';
      final length = i - spanStart;
      final start = out.length;
      out.write(value);
      if (value.length != length) {
        delta += value.length - length;
        edits.add(
          SearchFoldEdit(start, start + value.length, spanStart, i, delta),
        );
      }
    }
    return (text: out.toString(), edits: edits);
  }

  String _foldRune(int rune) => _cache[rune] ??= _foldSlow(rune);

  String _foldSlow(int rune) {
    if (_turkic) {
      if (rune == 0x49) return '\u0131'; // I → ı
      if (rune == 0x130) return 'i'; // İ → i
    }
    if (rune < 0x80) {
      return String.fromCharCode(
        rune >= 0x41 && rune <= 0x5A ? rune + 32 : rune,
      );
    }
    if (rune >= 0xAC00 && rune <= 0xD7A3) return _hangul(rune);
    final i = _search(_foldKeys, rune);
    if (i < 0) return String.fromCharCode(rune);
    final value = _foldValues[i];
    return value >= 0
        ? String.fromCharCode(value)
        : String.fromCharCodes(_foldSequences[rune]!);
  }
}

/// Canonical decomposition of a Hangul syllable into its jamo.
String _hangul(int rune) {
  final s = rune - 0xAC00;
  return String.fromCharCodes([
    0x1100 + s ~/ 588,
    0x1161 + (s % 588) ~/ 28,
    if (s % 28 != 0) 0x11A7 + s % 28,
  ]);
}

/// The index of [value] in sorted [list], or -1.
int _search(List<int> list, int value) {
  var lo = 0;
  var hi = list.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final key = list[mid];
    if (key == value) return mid;
    if (key < value) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return -1;
}

bool _isMark(int rune) {
  if (rune < 0x300) return false;
  // The last range that starts at or before [rune].
  var lo = 0;
  var hi = _markRanges.length ~/ 2 - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (_markRanges[mid * 2] <= rune) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return _markRanges[lo * 2] <= rune && rune <= _markRanges[lo * 2 + 1];
}

bool _isMarkAt(String text, int i) => _isMark(_runeAt(text, i));

int _runeAt(String text, int i) {
  final unit = text.codeUnitAt(i);
  if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length) {
    final low = text.codeUnitAt(i + 1);
    if (low >= 0xDC00 && low <= 0xDFFF) {
      return 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
    }
  }
  return unit;
}

int _width(String text, int i) => _runeAt(text, i) > 0xFFFF ? 2 : 1;

/// Folded offsets back to original ones (`originalOffsetMapper`): a
/// cursor that only moves forward, as matches come in order.
class _OffsetMapper {
  _OffsetMapper(this._edits, {required this.endBoundary});

  final List<SearchFoldEdit> _edits;
  final bool endBoundary;
  var _cursor = 0;

  int call(int offset) {
    while (_cursor < _edits.length &&
        (endBoundary
            ? _edits[_cursor].end < offset
            : _edits[_cursor].end <= offset)) {
      _cursor++;
    }
    if (_cursor < _edits.length) {
      final edit = _edits[_cursor];
      if (endBoundary ? edit.start < offset : edit.start <= offset) {
        return endBoundary ? edit.originalEnd : edit.originalStart;
      }
    }
    return offset - (_cursor > 0 ? _edits[_cursor - 1].delta : 0);
  }
}

final _whitespace = RegExp(r'\s+');

/// `contextExcerpt`: reads only as much text as the excerpt needs.
String _context(String text, int offset, {required bool before}) {
  var length = textNodeSearchContext;
  while (true) {
    final fragment = before
        ? text.substring(offset - length < 0 ? 0 : offset - length, offset)
        : text.substring(
            offset,
            offset + length > text.length ? text.length : offset + length,
          );
    final normalized = fragment.replaceAll(_whitespace, ' ');
    final trimmed = before ? normalized.trimLeft() : normalized.trimRight();
    if (trimmed.length >= textNodeSearchContext) {
      return before
          ? '…${trimmed.substring(trimmed.length - textNodeSearchContext)}'
          : '${trimmed.substring(0, textNodeSearchContext)}…';
    }
    if (before ? length >= offset : offset + length >= text.length) {
      return trimmed;
    }
    length *= 2;
  }
}
