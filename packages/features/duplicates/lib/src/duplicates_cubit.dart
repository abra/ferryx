import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:operations_service/operations_service.dart';

/// A row of the results: a group's heading, or one of its files.
@immutable
sealed class DuplicateRow {
  const DuplicateRow(this.group);

  /// The group's index in [DuplicatesState.groups].
  final int group;
}

final class GroupRow extends DuplicateRow {
  const GroupRow(super.group);
}

final class FileRow extends DuplicateRow {
  const FileRow(super.group, this.file);

  /// The file's index in its group.
  final int file;
}

/// Which copy of each group stays when marking the others.
enum KeepRule { newest, oldest, shortestPath }

/// The dialog as the cubit keeps it: the groups (the most space to free
/// first), flattened into rows for the table, and the files marked. Not
/// [Equatable]: the lists are long and a state is new on every update.
@immutable
class DuplicatesState {
  const DuplicatesState({
    this.roots = const [],
    this.running = false,
    this.started = false,
    this.groups = const [],
    this.rows = const [],
    this.marked = const {},
    this.phase,
    this.filesScanned = 0,
    this.candidates = 0,
    this.filesHashed = 0,
    this.bytesDone = 0,
    this.current,
    this.error,
    this.revision = 0,
  });

  /// The folders searched.
  final List<String> roots;
  final bool running;

  /// A search ran (or runs): the table speaks of its results.
  final bool started;
  final List<DuplicateGroup> groups;
  final List<DuplicateRow> rows;

  /// Paths of the files marked for the trash.
  final Set<String> marked;
  final DuplicatesPhase? phase;
  final int filesScanned;
  final int candidates;
  final int filesHashed;
  final int bytesDone;
  final String? current;
  final String? error;
  final int revision;

  DuplicateFile? fileAt(int row) => switch (rows[row]) {
    FileRow(:final group, :final file) => groups[group].files[file],
    GroupRow() => null,
  };

  /// What all the groups could free.
  int get wasted => groups.fold(0, (sum, g) => sum + g.wasted);

  /// What the marked files take.
  int get markedBytes {
    var bytes = 0;
    for (final group in groups) {
      for (final file in group.files) {
        if (marked.contains(file.path)) bytes += group.size;
      }
    }
    return bytes;
  }

  /// Groups whose every copy is marked: trashing them leaves none.
  int get fullyMarkedGroups =>
      groups.where((g) => g.files.every((f) => marked.contains(f.path))).length;

  DuplicatesState copyWith({
    bool? running,
    bool? started,
    List<DuplicateGroup>? groups,
    List<DuplicateRow>? rows,
    Set<String>? marked,
    DuplicatesPhase? phase,
    int? filesScanned,
    int? candidates,
    int? filesHashed,
    int? bytesDone,
    String? current,
    bool clearCurrent = false,
    String? error,
    bool clearError = false,
  }) => DuplicatesState(
    roots: roots,
    running: running ?? this.running,
    started: started ?? this.started,
    groups: groups ?? this.groups,
    rows: rows ?? this.rows,
    marked: marked ?? this.marked,
    phase: phase ?? this.phase,
    filesScanned: filesScanned ?? this.filesScanned,
    candidates: candidates ?? this.candidates,
    filesHashed: filesHashed ?? this.filesHashed,
    bytesDone: bytesDone ?? this.bytesDone,
    current: clearCurrent ? null : (current ?? this.current),
    error: clearError ? null : (error ?? this.error),
    revision: revision + 1,
  );
}

/// The folder [parent] as the table shows it: from the name of the folder
/// searched that holds it (`dupes/photos/2025`), the deepest such folder of
/// [roots]; in full when none holds it.
String shownFolder(String parent, List<String> roots) {
  String? best;
  for (final root in roots) {
    final base = root.length > 1 && root.endsWith('/')
        ? root.substring(0, root.length - 1)
        : root;
    if (base == '/') continue;
    final inside = parent == base || parent.startsWith('$base/');
    if (inside && (best == null || base.length > best.length)) best = base;
  }
  if (best == null) return parent;
  final name = best.substring(best.lastIndexOf('/') + 1);
  return '$name${parent.substring(best.length)}';
}

/// The table's rows for [groups]: each group's heading, then its files.
List<DuplicateRow> flatten(List<DuplicateGroup> groups) => [
  for (var g = 0; g < groups.length; g++) ...[
    GroupRow(g),
    for (var f = 0; f < groups[g].files.length; f++) FileRow(g, f),
  ],
];

/// Every file of each group but the one [rule] keeps.
Set<String> allButOne(List<DuplicateGroup> groups, KeepRule rule) {
  final out = <String>{};
  for (final group in groups) {
    if (group.files.length < 2) continue;
    final keep = group.files.reduce((a, b) {
      switch (rule) {
        case KeepRule.newest:
          return _time(b) > _time(a) ? b : a;
        case KeepRule.oldest:
          return _time(b) < _time(a) ? b : a;
        case KeepRule.shortestPath:
          final depth = _depth(b.path).compareTo(_depth(a.path));
          if (depth != 0) return depth < 0 ? b : a;
          return b.path.length < a.path.length ? b : a;
      }
    });
    for (final file in group.files) {
      if (!identical(file, keep)) out.add(file.path);
    }
  }
  return out;
}

int _time(DuplicateFile file) => file.modified?.millisecondsSinceEpoch ?? 0;

int _depth(String path) => '/'.allMatches(path).length;

/// Runs a duplicate search through the core, keeps its groups in order of
/// the space they could free, and the marks.
class DuplicatesCubit extends Cubit<DuplicatesState> {
  DuplicatesCubit({required DuplicatesService service})
    : _service = service,
      super(const DuplicatesState()) {
    _subscription = service.updates.listen(_onUpdate);
  }

  final DuplicatesService _service;
  StreamSubscription<DuplicatesUpdate>? _subscription;
  int? _taskId;

  Future<void> start(DuplicatesRequest request) async {
    await stop();
    emit(
      DuplicatesState(
        roots: request.roots,
        running: true,
        started: true,
        revision: state.revision + 1,
      ),
    );
    final id = await _service.start(request);
    if (isClosed) return;
    if (!state.running) {
      unawaited(_service.cancel(id));
      return;
    }
    _taskId = id;
  }

  Future<void> stop() async {
    final id = _taskId;
    _taskId = null;
    if (state.running) {
      emit(state.copyWith(running: false, clearCurrent: true));
    }
    if (id != null) await _service.cancel(id);
  }

  void _onUpdate(DuplicatesUpdate update) {
    if (update.taskId != _taskId || isClosed) return;
    var groups = state.groups;
    if (update.groups.isNotEmpty) {
      groups = [...groups];
      for (final group in update.groups) {
        groups.insert(_insertAt(groups, group), group);
      }
    }
    if (update.done) _taskId = null;
    emit(
      state.copyWith(
        running: !update.done,
        groups: groups,
        rows: identical(groups, state.groups) ? null : flatten(groups),
        phase: update.phase,
        filesScanned: update.filesScanned,
        candidates: update.candidates,
        filesHashed: update.filesHashed,
        bytesDone: update.bytesDone,
        current: update.current,
        clearCurrent: update.done || update.current == null,
        error: update.error,
      ),
    );
  }

  /// Where [group] goes so the most wasted space stays first.
  static int _insertAt(List<DuplicateGroup> groups, DuplicateGroup group) {
    var low = 0;
    var high = groups.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (groups[mid].wasted >= group.wasted) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  // ─── Marks ───

  /// Marks the files at [rows] (table indexes), or unmarks them when all
  /// were marked already; a group heading stands for its files.
  void toggleMarks(Iterable<int> rows) {
    final paths = <String>{};
    for (final row in rows) {
      if (row < 0 || row >= state.rows.length) continue;
      switch (state.rows[row]) {
        case FileRow(:final group, :final file):
          paths.add(state.groups[group].files[file].path);
        case GroupRow():
          break;
      }
    }
    if (paths.isEmpty) return;
    final marked = {...state.marked};
    if (paths.every(marked.contains)) {
      marked.removeAll(paths);
    } else {
      marked.addAll(paths);
    }
    emit(state.copyWith(marked: marked));
  }

  void markAllBut(KeepRule rule) =>
      emit(state.copyWith(marked: allButOne(state.groups, rule)));

  void unmarkAll() => emit(state.copyWith(marked: const {}));

  /// The marked files went to the trash: they leave their groups, and a
  /// group with one file left is no group.
  void removeFiles(Set<String> paths) {
    final groups = [
      for (final group in state.groups)
        DuplicateGroup(
          size: group.size,
          files: [
            for (final file in group.files)
              if (!paths.contains(file.path)) file,
          ],
        ),
    ].where((g) => g.files.length > 1).toList();
    emit(
      state.copyWith(
        groups: groups,
        rows: flatten(groups),
        marked: state.marked.difference(paths),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    final id = _taskId;
    if (id != null) unawaited(_service.cancel(id));
    return super.close();
  }
}
