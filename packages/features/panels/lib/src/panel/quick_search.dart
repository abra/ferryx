import 'package:domain_models/domain_models.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// Whether [name] matches [query] (case-insensitively) and, if so, the
/// ranges to underline, as `(start, end)` over the name's grapheme
/// clusters (`characters`), the units a row slices the name by: a
/// decomposed `é` is one cluster of two runes. The same rules as the
/// core's `quick_search`.
List<(int, int)>? quickMatch(
  String query,
  String name,
  QuickSearchWhere where,
) {
  if (query.isEmpty) return const [];
  final q = query.toLowerCase().characters.toList();
  final n = name.toLowerCase().characters.toList();
  switch (where) {
    case QuickSearchWhere.fuzzy:
      final ranges = <(int, int)>[];
      var qi = 0;
      for (var i = 0; i < n.length && qi < q.length; i++) {
        if (n[i] == q[qi]) {
          if (ranges.isNotEmpty && ranges.last.$2 == i) {
            ranges[ranges.length - 1] = (ranges.last.$1, i + 1);
          } else {
            ranges.add((i, i + 1));
          }
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
