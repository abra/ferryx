import 'package:domain_models/domain_models.dart';
import 'package:meta/meta.dart';

/// Two files of one size whose contents decide (Compare Folders with the
/// contents option).
@immutable
class ContentCandidate {
  const ContentCandidate({
    required this.left,
    required this.right,
    required this.newer,
  });

  final FileEntry left;
  final FileEntry right;

  /// Which side is newer: -1 the left, 1 the right, 0 neither (the same
  /// time, give or take the tolerance).
  final int newer;
}

/// What Compare Folders selects: the names in each panel, and the pairs
/// whose contents are still to compare.
@immutable
class FolderComparison {
  const FolderComparison({
    this.left = const {},
    this.right = const {},
    this.candidates = const [],
  });

  final Set<String> left;
  final Set<String> right;
  final List<ContentCandidate> candidates;

  /// [left] and [right] with the candidates whose contents differ (by
  /// their indexes in [candidates]): the newer one, both when neither is.
  FolderComparison withDiffering(Iterable<int> indexes) {
    final left = {...this.left};
    final right = {...this.right};
    for (final index in indexes) {
      if (index < 0 || index >= candidates.length) continue;
      final candidate = candidates[index];
      if (candidate.newer <= 0) left.add(candidate.left.name);
      if (candidate.newer >= 0) right.add(candidate.right.name);
    }
    return FolderComparison(left: left, right: right);
  }
}

/// Total Commander's Compare Directories over two listings already read:
/// a file or folder on one side only is selected there; of two files of
/// one name, the newer is selected, or both when their times agree and
/// their sizes do not. Folders on both sides are left alone; a file
/// against a folder of its name selects both. Names pair as the panels
/// sort them: exactly, then (unless [caseSensitive]) ignoring case.
/// Times closer than [tolerance] agree (file systems keep times to a
/// second or two). With [byContents], files of one size are not decided
/// here but listed as [FolderComparison.candidates]. No disk is touched.
FolderComparison compareFolderEntries({
  required List<FileEntry> left,
  required List<FileEntry> right,
  required bool caseSensitive,
  bool byContents = false,
  Duration tolerance = const Duration(seconds: 1),
}) {
  final leftSelected = <String>{};
  final rightSelected = <String>{};
  final candidates = <ContentCandidate>[];
  final pairs = pairByName(
    left.where((e) => !e.isParent).toList(),
    right.where((e) => !e.isParent).toList(),
    caseSensitive: caseSensitive,
  );
  for (final (l, r) in pairs) {
    if (l == null) {
      rightSelected.add(r!.name);
      continue;
    }
    if (r == null) {
      leftSelected.add(l.name);
      continue;
    }
    if (l.isDir && r.isDir) continue;
    if (l.isDir != r.isDir) {
      leftSelected.add(l.name);
      rightSelected.add(r.name);
      continue;
    }
    final newer = newerSide(l.modified, r.modified, tolerance);
    final sameSize = (l.size ?? 0) == (r.size ?? 0);
    if (byContents && sameSize) {
      candidates.add(ContentCandidate(left: l, right: r, newer: newer));
      continue;
    }
    if (newer < 0) {
      leftSelected.add(l.name);
    } else if (newer > 0) {
      rightSelected.add(r.name);
    } else if (!sameSize) {
      leftSelected.add(l.name);
      rightSelected.add(r.name);
    }
  }
  return FolderComparison(
    left: leftSelected,
    right: rightSelected,
    candidates: candidates,
  );
}

/// -1 when [left] is newer, 1 when [right] is, 0 when they are within
/// [tolerance] of each other or a time is unknown.
int newerSide(DateTime? left, DateTime? right, Duration tolerance) {
  if (left == null || right == null) return 0;
  final difference = left.difference(right);
  if (difference.abs() <= tolerance) return 0;
  return difference.isNegative ? 1 : -1;
}

/// The entries of both sides paired by name: exactly first, then (unless
/// [caseSensitive]) ignoring case, each entry at most once; the unpaired
/// with `null` on the other side. Left entries in their order, then the
/// right ones left over.
List<(FileEntry?, FileEntry?)> pairByName(
  List<FileEntry> left,
  List<FileEntry> right, {
  required bool caseSensitive,
}) {
  final exact = <String, int>{};
  for (var i = 0; i < right.length; i++) {
    exact[right[i].name] = i;
  }
  final taken = List<bool>.filled(right.length, false);
  final matched = List<int?>.filled(left.length, null);
  for (var i = 0; i < left.length; i++) {
    final j = exact[left[i].name];
    if (j != null && !taken[j]) {
      matched[i] = j;
      taken[j] = true;
    }
  }
  if (!caseSensitive) {
    final folded = <String, List<int>>{};
    for (var j = 0; j < right.length; j++) {
      if (!taken[j]) {
        folded.putIfAbsent(right[j].name.toLowerCase(), () => []).add(j);
      }
    }
    for (var i = 0; i < left.length; i++) {
      if (matched[i] != null) continue;
      final slots = folded[left[i].name.toLowerCase()];
      if (slots == null || slots.isEmpty) continue;
      final j = slots.removeAt(0);
      matched[i] = j;
      taken[j] = true;
    }
  }
  return [
    for (var i = 0; i < left.length; i++)
      (left[i], matched[i] == null ? null : right[matched[i]!]),
    for (var j = 0; j < right.length; j++)
      if (!taken[j]) (null, right[j]),
  ];
}
