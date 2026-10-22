import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// How well a text matched a query, and which of its characters did, as
/// `[start, end)` ranges in order.
@immutable
class FuzzyMatch extends Equatable {
  const FuzzyMatch(this.score, this.ranges);

  final int score;
  final List<(int, int)> ranges;

  @override
  List<Object?> get props => [score, ranges];
}

/// Scores [text] for [query] as a command palette does: the query's
/// characters (case and spaces aside) must appear in [text] in order;
/// among the ways they do, the best one counts, a match earning more at
/// the start of the text, at the start of a word (after a space or a
/// mark, or a capital after a small letter) and right after the previous
/// match, and less for every character skipped. `null` when the query is
/// not in [text]; an empty query matches with nothing highlighted.
///
/// One pass per query character over the text (dynamic programming, the
/// best predecessor carried along), so a palette scores a few hundred
/// labels per keystroke in well under a frame.
FuzzyMatch? fuzzyMatch(String query, String text) {
  final needle = query.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (needle.isEmpty) return const FuzzyMatch(0, []);
  final m = needle.length;
  final n = text.length;
  if (m > n) return null;
  final lower = text.toLowerCase();
  // Lower-casing a rare letter changes the length; then match per code
  // unit, which keeps the indices those of [text].
  final hay = lower.length == n ? lower : _lowerEach(text);
  final bonus = List<int>.generate(n, (j) => _bonusAt(text, j));

  const none = -1 << 30;
  // score[i * n + j]: the best with query char i on text char j.
  final score = List<int>.filled(m * n, none);
  final from = List<int>.filled(m * n, -1);
  for (var i = 0; i < m; i++) {
    final char = needle.codeUnitAt(i);
    // The best earlier position to jump from with a gap, its penalty paid.
    var gapped = none;
    var gappedAt = -1;
    for (var j = i; j < n; j++) {
      if (i > 0 && j >= 2) {
        // Each step right costs the waiting candidates a point more; the
        // position two back joins at the gap's opening cost.
        if (gapped != none) gapped += _gapExtension;
        final entering = score[(i - 1) * n + j - 2];
        if (entering != none && entering + _gapOpen > gapped) {
          gapped = entering + _gapOpen;
          gappedAt = j - 2;
        }
      }
      if (hay.codeUnitAt(j) != char) continue;
      if (i == 0) {
        score[j] =
            _match +
            bonus[j] * _firstCharMultiplier +
            (j == 0 ? _prefix : -j.clamp(0, _leadingCap));
        continue;
      }
      var best = none;
      var bestFrom = -1;
      final previous = score[(i - 1) * n + j - 1];
      if (previous != none) {
        best = previous + _match + _consecutive + bonus[j];
        bestFrom = j - 1;
      }
      if (gapped != none && gapped + _match + bonus[j] > best) {
        best = gapped + _match + bonus[j];
        bestFrom = gappedAt;
      }
      score[i * n + j] = best;
      from[i * n + j] = bestFrom;
    }
  }
  var best = none;
  var end = -1;
  for (var j = m - 1; j < n; j++) {
    final s = score[(m - 1) * n + j];
    if (s > best) {
      best = s;
      end = j;
    }
  }
  if (end < 0) return null;
  final positions = List<int>.filled(m, 0);
  for (var i = m - 1, j = end; i >= 0; i--) {
    positions[i] = j;
    j = from[i * n + j];
  }
  return FuzzyMatch(best, _ranges(positions));
}

const _match = 16;
const _consecutive = 12;
const _prefix = 12;
const _firstCharMultiplier = 2;
const _gapOpen = -3;
const _gapExtension = -1;

/// The farthest a first match's place lowers its score: a word start
/// late in a long label still beats a letter inside an early word.
const _leadingCap = 6;
const _boundary = 10;
const _camel = 7;

/// What starting a match at [j] is worth: the start of the text or of a
/// word, a capital after a small letter.
int _bonusAt(String text, int j) {
  if (j == 0) return _boundary;
  final previous = text.codeUnitAt(j - 1);
  final current = text.codeUnitAt(j);
  if (!_isWordChar(previous)) return _isWordChar(current) ? _boundary : 0;
  if (_isLower(previous) && _isUpper(current)) return _camel;
  return 0;
}

bool _isWordChar(int unit) {
  final char = String.fromCharCode(unit);
  return char.toLowerCase() != char.toUpperCase() ||
      (unit >= 0x30 && unit <= 0x39);
}

bool _isLower(int unit) {
  final char = String.fromCharCode(unit);
  return char != char.toUpperCase();
}

bool _isUpper(int unit) {
  final char = String.fromCharCode(unit);
  return char != char.toLowerCase();
}

String _lowerEach(String text) {
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    final lower = String.fromCharCode(unit).toLowerCase();
    out.writeCharCode(lower.length == 1 ? lower.codeUnitAt(0) : unit);
  }
  return out.toString();
}

/// Matched positions as ranges, neighbours merged.
List<(int, int)> _ranges(List<int> positions) {
  final out = <(int, int)>[];
  for (final at in positions) {
    if (out.isNotEmpty && out.last.$2 == at) {
      out[out.length - 1] = (out.last.$1, at + 1);
    } else {
      out.add((at, at + 1));
    }
  }
  return out;
}
