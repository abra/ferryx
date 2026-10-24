import 'package:domain_models/domain_models.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// Whether [name] matches [query] (case-insensitively) and, if so, the
/// ranges to underline, as `(start, end)` over the name's grapheme
/// clusters (`characters`), the units a row slices the name by: a
/// decomposed `é` is one cluster of two runes.
List<(int, int)>? quickMatch(
  String query,
  String name,
  QuickSearchWhere where,
) => quickMatchFolded(FoldedText(query), FoldedText(name), where);

/// A name or a query folded for quick search once: in lower case and, when
/// it is not plain printable ASCII, cut into grapheme clusters (in plain
/// ASCII each code unit is a cluster of its own, so the string itself
/// serves). A listing folds its names once; a key typed folds the query.
final class FoldedText {
  FoldedText(String text)
    : lower = text.toLowerCase(),
      ascii = _plainAscii(text);

  final String lower;
  final bool ascii;

  List<String>? _clusters;
  List<String> get clusters => _clusters ??= lower.characters.toList();

  static bool _plainAscii(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit < 0x20 || unit > 0x7e) return false;
    }
    return true;
  }
}

/// [quickMatch] over texts folded already.
List<(int, int)>? quickMatchFolded(
  FoldedText query,
  FoldedText name,
  QuickSearchWhere where,
) {
  if (query.lower.isEmpty) return const [];
  if (query.ascii && name.ascii) {
    return _matchAscii(query.lower, name.lower, where);
  }
  final q = query.clusters;
  final n = name.clusters;
  switch (where) {
    case QuickSearchWhere.fuzzy:
      final ranges = <(int, int)>[];
      var qi = 0;
      for (var i = 0; i < n.length && qi < q.length; i++) {
        if (n[i] == q[qi]) {
          _extend(ranges, i);
          qi++;
        }
      }
      return qi == q.length ? ranges : null;
    case QuickSearchWhere.anywhere:
      final at = _find(q, n);
      return at < 0 ? null : [(at, at + q.length)];
    case QuickSearchWhere.beginning:
      return _startsWith(n, q) ? [(0, q.length)] : null;
    case QuickSearchWhere.ending:
      return _endsWith(n, q) ? [(n.length - q.length, n.length)] : null;
    case QuickSearchWhere.beginningOrEnding:
      if (_startsWith(n, q)) return [(0, q.length)];
      if (_endsWith(n, q)) return [(n.length - q.length, n.length)];
      return null;
  }
}

/// Plain ASCII: code units are the clusters.
List<(int, int)>? _matchAscii(String q, String n, QuickSearchWhere where) {
  switch (where) {
    case QuickSearchWhere.fuzzy:
      final ranges = <(int, int)>[];
      var qi = 0;
      for (var i = 0; i < n.length && qi < q.length; i++) {
        if (n.codeUnitAt(i) == q.codeUnitAt(qi)) {
          _extend(ranges, i);
          qi++;
        }
      }
      return qi == q.length ? ranges : null;
    case QuickSearchWhere.anywhere:
      final at = n.indexOf(q);
      return at < 0 ? null : [(at, at + q.length)];
    case QuickSearchWhere.beginning:
      return n.startsWith(q) ? [(0, q.length)] : null;
    case QuickSearchWhere.ending:
      return n.endsWith(q) ? [(n.length - q.length, n.length)] : null;
    case QuickSearchWhere.beginningOrEnding:
      if (n.startsWith(q)) return [(0, q.length)];
      if (n.endsWith(q)) return [(n.length - q.length, n.length)];
      return null;
  }
}

/// Grows the last range when [i] touches it, else starts one.
void _extend(List<(int, int)> ranges, int i) {
  if (ranges.isNotEmpty && ranges.last.$2 == i) {
    ranges[ranges.length - 1] = (ranges.last.$1, i + 1);
  } else {
    ranges.add((i, i + 1));
  }
}

/// Whether a match of a longer query is always a match of [where] for the
/// shorter one it extends: then only the shorter one's matches need trying.
bool narrowsAsTyped(QuickSearchWhere where) => switch (where) {
  QuickSearchWhere.fuzzy ||
  QuickSearchWhere.anywhere ||
  QuickSearchWhere.beginning => true,
  QuickSearchWhere.ending || QuickSearchWhere.beginningOrEnding => false,
};

int _find(List<String> q, List<String> n) {
  if (q.length > n.length) return -1;
  outer:
  for (var i = 0; i + q.length <= n.length; i++) {
    for (var j = 0; j < q.length; j++) {
      if (n[i + j] != q[j]) continue outer;
    }
    return i;
  }
  return -1;
}

bool _startsWith(List<String> n, List<String> q) {
  if (q.length > n.length) return false;
  for (var i = 0; i < q.length; i++) {
    if (n[i] != q[i]) return false;
  }
  return true;
}

bool _endsWith(List<String> n, List<String> q) {
  if (q.length > n.length) return false;
  final offset = n.length - q.length;
  for (var i = 0; i < q.length; i++) {
    if (n[offset + i] != q[i]) return false;
  }
  return true;
}
