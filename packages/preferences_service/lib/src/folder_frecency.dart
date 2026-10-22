import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'side_storage.dart';

/// A folder the panels showed, ranked as zoxide ranks directories: a point
/// per visit, aged down as the total grows, weighted at query time by how
/// long ago the last visit was ([scoreAt]).
@immutable
class FrecentFolder extends Equatable {
  const FrecentFolder({
    required this.path,
    required this.rank,
    required this.lastVisit,
  });

  final String path;

  /// Visits, aged: every point decays together once the ranks of all
  /// folders pass [FolderFrecency.maxTotalRank].
  final double rank;
  final DateTime lastVisit;

  /// The rank weighted by recency: ×4 within the hour, ×2 within the day,
  /// ×½ within the week, ×¼ after.
  double scoreAt(DateTime now) {
    final age = now.difference(lastVisit);
    final factor = age < const Duration(hours: 1)
        ? 4.0
        : age < const Duration(days: 1)
        ? 2.0
        : age < const Duration(days: 7)
        ? 0.5
        : 0.25;
    return rank * factor;
  }

  @override
  List<Object?> get props => [path, rank, lastVisit];
}

/// A folder that matched a query, with the ranges of its path to
/// highlight (`[start, end)`, ordered).
@immutable
class FolderMatch extends Equatable {
  const FolderMatch({
    required this.folder,
    required this.score,
    this.ranges = const [],
    this.inLastSegment = true,
  });

  final FrecentFolder folder;
  final double score;
  final List<(int, int)> ranges;

  /// The query's last word matched the folder's own name, not a parent's.
  final bool inLastSegment;

  @override
  List<Object?> get props => [folder, score, ranges, inLastSegment];
}

/// The folders matching [query], zoxide's way: every word of the query
/// (case aside) appears in the path, in order; the last word preferably
/// in the folder's own name, which ranks those first; then the frecency.
/// An empty query answers every folder, the most frecent first. [exclude]
/// (the folder the panel is in) is left out.
List<FolderMatch> matchFolders(
  Iterable<FrecentFolder> folders,
  String query, {
  required DateTime now,
  String? exclude,
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList(growable: false);
  final out = <FolderMatch>[];
  for (final folder in folders) {
    if (folder.path == exclude) continue;
    final score = folder.scoreAt(now);
    if (words.isEmpty) {
      out.add(FolderMatch(folder: folder, score: score));
      continue;
    }
    final match = _match(folder.path, words);
    if (match == null) continue;
    out.add(
      FolderMatch(
        folder: folder,
        score: score,
        ranges: match.$1,
        inLastSegment: match.$2,
      ),
    );
  }
  out.sort((a, b) {
    if (a.inLastSegment != b.inLastSegment) return a.inLastSegment ? -1 : 1;
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byLength = a.folder.path.length.compareTo(b.folder.path.length);
    if (byLength != 0) return byLength;
    return a.folder.path.compareTo(b.folder.path);
  });
  return out;
}

/// The ranges [words] take in [path] in order, and whether the last word
/// fell in the last segment; `null` when one is missing.
(List<(int, int)>, bool)? _match(String path, List<String> words) {
  final lower = path.toLowerCase();
  // Lower-casing can change a length (rare letters); ranges must index
  // the path itself, so such a path is matched as written.
  final text = lower.length == path.length ? lower : path;
  final ranges = <(int, int)>[];
  var from = 0;
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final last = i == words.length - 1;
    // The last word as far right as it goes: in the folder's own name
    // when it is there at all.
    final at = last ? text.lastIndexOf(word) : text.indexOf(word, from);
    if (at < from) return null;
    ranges.add((at, at + word.length));
    from = at + word.length;
  }
  final lastSlash = path.endsWith('/') && path.length > 1
      ? path.lastIndexOf('/', path.length - 2)
      : path.lastIndexOf('/');
  return (ranges, ranges.last.$1 > lastSlash);
}

/// Every folder the panels showed, with its frecency, kept under its own
/// key in a [SideStorage]: written at most once per [writeDelay] after a
/// change (never on each navigation) and on [flush]. Bounded to
/// [maxEntries]; the least frecent go first.
class FolderFrecency {
  FolderFrecency._(this._storage, this._now, this.writeDelay, this.maxEntries);

  /// Reads the folders saved under [key]; an unreadable value starts the
  /// list empty.
  static Future<FolderFrecency> load(
    SideStorage storage, {
    DateTime Function()? now,
    Duration writeDelay = const Duration(seconds: 2),
    int maxEntries = defaultMaxEntries,
  }) async {
    final store = FolderFrecency._(
      storage,
      now ?? DateTime.now,
      writeDelay,
      maxEntries,
    );
    try {
      final raw = await storage.read(key);
      if (raw != null) store._decode(raw);
    } on FormatException {
      // A damaged value is replaced on the next write.
    }
    return store;
  }

  static const key = 'ferryx.folderFrecency';
  static const defaultMaxEntries = 1000;

  /// When the ranks together pass this, every rank shrinks (zoxide's
  /// `_ZO_MAXAGE`), so old habits fade and new ones can overtake them.
  static const double maxTotalRank = 10000;

  final SideStorage _storage;
  final DateTime Function() _now;
  final Duration writeDelay;
  final int maxEntries;
  final _folders = <String, FrecentFolder>{};
  Timer? _write;
  bool _closed = false;

  /// Every folder known, in no particular order.
  Iterable<FrecentFolder> get folders => _folders.values;

  /// [matchFolders] over the folders known, as of now.
  List<FolderMatch> query(String query, {String? exclude}) =>
      matchFolders(_folders.values, query, now: _now(), exclude: exclude);

  /// The panels showed [path]: a point more, and now its last visit.
  void visit(String path) {
    if (_closed || path.isEmpty) return;
    final now = _now();
    final before = _folders[path];
    _folders[path] = FrecentFolder(
      path: path,
      rank: (before?.rank ?? 0) + 1,
      lastVisit: now,
    );
    _age(keep: path);
    _prune(now);
    _scheduleWrite();
  }

  /// Forgets [path]: it is gone from the disk, or the user said so.
  void remove(String path) {
    if (_folders.remove(path) != null) _scheduleWrite();
  }

  /// Shrinks every rank once the total passes [maxTotalRank]; a folder
  /// left under a point goes, except [keep], just visited.
  void _age({required String keep}) {
    final total = _folders.values.fold<double>(0, (sum, f) => sum + f.rank);
    if (total <= maxTotalRank) return;
    final factor = 0.9 * maxTotalRank / total;
    final aged = <String, FrecentFolder>{};
    for (final folder in _folders.values) {
      final rank = folder.rank * factor;
      if (rank >= 1 || folder.path == keep) {
        aged[folder.path] = FrecentFolder(
          path: folder.path,
          rank: rank,
          lastVisit: folder.lastVisit,
        );
      }
    }
    _folders
      ..clear()
      ..addAll(aged);
  }

  void _prune(DateTime now) {
    final extra = _folders.length - maxEntries;
    if (extra <= 0) return;
    final ranked = _folders.values.toList()
      ..sort((a, b) => a.scoreAt(now).compareTo(b.scoreAt(now)));
    for (final folder in ranked.take(extra)) {
      _folders.remove(folder.path);
    }
  }

  void _scheduleWrite() {
    if (_closed) return;
    _write ??= Timer(writeDelay, () {
      _write = null;
      unawaited(_save());
    });
  }

  /// Writes what changed now instead of after [writeDelay].
  Future<void> flush() async {
    if (_write == null) return;
    _write!.cancel();
    _write = null;
    await _save();
  }

  /// Writes what is pending; nothing is recorded after.
  Future<void> dispose() async {
    await flush();
    _closed = true;
  }

  Future<void> _save() async {
    try {
      await _storage.write(key, encode());
    } on Object {
      // Kept in memory for the session; the next change tries again.
    }
  }

  /// The JSON the store writes: `[path, rank, last visit ms]` per folder.
  @visibleForTesting
  String encode() => jsonEncode({
    'version': 1,
    'folders': [
      for (final f in _folders.values)
        [
          f.path,
          // Two decimals are plenty for a rank and keep the value small.
          (f.rank * 100).roundToDouble() / 100,
          f.lastVisit.millisecondsSinceEpoch,
        ],
    ],
  });

  void _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return;
    final folders = decoded['folders'];
    if (folders is! List) return;
    for (final item in folders) {
      if (item
          case [
            final String path,
            final num rank,
            final int lastVisit,
          ]
          when path.isNotEmpty && rank > 0) {
        _folders[path] = FrecentFolder(
          path: path,
          rank: rank.toDouble(),
          lastVisit: DateTime.fromMillisecondsSinceEpoch(lastVisit),
        );
      }
    }
    _prune(_now());
  }
}
