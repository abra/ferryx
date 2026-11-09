import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:operations_service/operations_service.dart';
import 'package:preferences_service/preferences_service.dart';

import 'sync_plan.dart';

enum SyncPhase {
  /// Nothing compared yet.
  idle,
  comparing,

  /// A comparison ended (or was stopped): the rows are there to act on.
  compared,
}

/// Why the comparison could not start, before the core is asked.
enum SyncProblem { sameFolder, missingFolder }

/// The dialog as the cubit keeps it.
///
/// A big tree has a hundred thousand rows, so the rows and the rows shown
/// are lists that only grow while a comparison runs (shared between
/// states; a state sees the first [rowCount] and [visibleCount] of them),
/// and the actions are bytes, one a row, copied when they change. Not
/// [Equatable]: comparing such lists on every update would cost more than
/// the update.
@immutable
class SyncState {
  const SyncState({
    required this.options,
    this.phase = SyncPhase.idle,
    this.left = '',
    this.right = '',
    this.rows = const [],
    this.rowCount = 0,
    this.visible = const [],
    this.visibleCount = 0,
    this.actions,
    this.groups = const {},
    this.summary = const SyncSummary(),
    this.folders = 0,
    this.files = 0,
    this.current,
    this.unreadable = 0,
    this.error,
    this.problem,
    this.revision = 0,
  });

  final CompareOptions options;
  final SyncPhase phase;

  /// The folders of the comparison shown.
  final String left;
  final String right;
  final List<CompareRow> rows;
  final int rowCount;

  /// Indexes into [rows] of the rows the filters show, in order.
  final List<int> visible;
  final int visibleCount;

  /// [RowAction.index] of each row.
  final Uint8List? actions;

  /// Rows by filter group, for the filters' counts.
  final Map<RowGroup, int> groups;

  /// What Synchronize would do with the rows shown.
  final SyncSummary summary;
  final int folders;
  final int files;

  /// The folder being read while comparing.
  final String? current;

  /// Folders that could not be read.
  final int unreadable;

  /// The core's reason the comparison could not run.
  final String? error;
  final SyncProblem? problem;

  /// Bumped on every change, for views that select on it.
  final int revision;

  bool get running => phase == SyncPhase.comparing;

  /// The row shown at [index] of the table.
  CompareRow rowAt(int index) => rows[visible[index]];

  RowAction actionOf(int rowIndex) {
    final bytes = actions;
    if (bytes == null || rowIndex >= bytes.length) return RowAction.skip;
    return RowAction.values[bytes[rowIndex]];
  }

  SyncState copyWith({
    CompareOptions? options,
    SyncPhase? phase,
    String? left,
    String? right,
    List<CompareRow>? rows,
    int? rowCount,
    List<int>? visible,
    int? visibleCount,
    Uint8List? actions,
    Map<RowGroup, int>? groups,
    SyncSummary? summary,
    int? folders,
    int? files,
    String? current,
    bool clearCurrent = false,
    int? unreadable,
    String? error,
    bool clearError = false,
    SyncProblem? problem,
    bool clearProblem = false,
  }) => SyncState(
    options: options ?? this.options,
    phase: phase ?? this.phase,
    left: left ?? this.left,
    right: right ?? this.right,
    rows: rows ?? this.rows,
    rowCount: rowCount ?? this.rowCount,
    visible: visible ?? this.visible,
    visibleCount: visibleCount ?? this.visibleCount,
    actions: actions ?? this.actions,
    groups: groups ?? this.groups,
    summary: summary ?? this.summary,
    folders: folders ?? this.folders,
    files: files ?? this.files,
    current: clearCurrent ? null : (current ?? this.current),
    unreadable: unreadable ?? this.unreadable,
    error: clearError ? null : (error ?? this.error),
    problem: clearProblem ? null : (problem ?? this.problem),
    revision: revision + 1,
  );
}

/// Compares two folder trees through the core, keeps the rows and the
/// action of each, filters them, and hands the plan to Synchronize.
class SyncCubit extends Cubit<SyncState> {
  SyncCubit({
    required FolderSyncService service,
    required CompareOptions options,
    this._onOptions,
  }) : _service = service,
       super(SyncState(options: options)) {
    _task = TaskSession<CompareUpdate>(
      updates: service.updates,
      idOf: (update) => update.taskId,
      isDone: (update) => update.done,
      cancel: service.cancel,
      onUpdate: _onUpdate,
      onError: _onError,
      onCleanupError: addError,
    );
  }

  final FolderSyncService _service;
  final void Function(CompareOptions options)? _onOptions;
  late final TaskSession<CompareUpdate> _task;

  /// The rows of the comparison under way; states share it.
  List<CompareRow> _rows = [];
  List<int> _visible = [];
  Uint8List _actions = Uint8List(0);
  Map<RowGroup, int> _groups = {};

  // ─── Comparing ───

  /// Compares [left] with [right] under the current options, the files
  /// matching [mask] (`*.jpg;*.png`, empty for all), ending a comparison
  /// under way first.
  Future<void> compare({
    required String left,
    required String right,
    String mask = '',
  }) async {
    if (isClosed) return;
    final problem = left.isEmpty || right.isEmpty
        ? SyncProblem.missingFolder
        : _same(left, right)
        ? SyncProblem.sameFolder
        : null;
    if (problem != null) {
      final stopping = stop();
      emit(state.copyWith(problem: problem, clearError: true));
      await stopping;
      return;
    }
    _onOptions?.call(state.options);
    _rows = [];
    _visible = [];
    _actions = Uint8List(0);
    _groups = {};
    emit(
      SyncState(
        options: state.options,
        phase: SyncPhase.comparing,
        left: left,
        right: right,
        rows: _rows,
        visible: _visible,
        actions: _actions,
        revision: state.revision + 1,
      ),
    );
    final options = state.options;
    await _task.start(
      () => _service.compare(
        FolderCompareRequest(
          left: left,
          right: right,
          recursive: options.recursive,
          compareContent: options.byContent,
          timeTolerance: Duration(seconds: options.fatTime ? 2 : 1),
          includeHidden: options.includeHidden,
          // Names pair as the desktop's file systems usually compare them.
          caseSensitive: false,
          nameMask: mask.trim(),
        ),
      ),
    );
  }

  static bool _same(String a, String b) {
    String trim(String p) =>
        p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    return trim(a) == trim(b);
  }

  /// Ends the comparison under way; the rows found stay.
  Future<void> stop() async {
    final stopping = _task.stop();
    if (!isClosed && state.running) {
      emit(state.copyWith(phase: SyncPhase.compared, clearCurrent: true));
    }
    await stopping;
  }

  void _onError(Object error, StackTrace stackTrace) {
    addError(error, stackTrace);
    emit(
      state.copyWith(
        phase: SyncPhase.compared,
        clearCurrent: true,
        error: error is FerryxException ? error.message : error.toString(),
      ),
    );
  }

  void _onUpdate(CompareUpdate update) {
    final options = state.options;
    if (update.rows.isNotEmpty) {
      final start = _rows.length;
      _rows.addAll(update.rows);
      final grown = Uint8List(_rows.length)..setAll(0, _actions);
      for (var i = start; i < _rows.length; i++) {
        final row = _rows[i];
        grown[i] = defaultAction(
          row,
          options.direction,
          deleteMissing: options.deleteMissing,
        ).index;
        final group = groupOf(row);
        _groups[group] = (_groups[group] ?? 0) + 1;
        if (rowShown(row, options)) _visible.add(i);
      }
      _actions = grown;
    }
    emit(
      state.copyWith(
        phase: update.done ? SyncPhase.compared : SyncPhase.comparing,
        rows: _rows,
        rowCount: _rows.length,
        visible: _visible,
        visibleCount: _visible.length,
        actions: _actions,
        groups: Map.unmodifiable(_groups),
        summary: _summary(),
        folders: update.folders,
        files: update.files,
        current: update.current,
        clearCurrent: update.done || update.current == null,
        unreadable: state.unreadable + update.errors.length,
        error: update.error,
        clearProblem: true,
      ),
    );
  }

  SyncSummary _summary() => SyncSummary.of(
    _rows,
    _visible,
    (i) => RowAction.values[_actions[i]],
  );

  // ─── Options and filters ───

  /// New options: the filters apply at once; the direction and deletions
  /// set each row's action anew (what the user changed by hand goes).
  void setOptions(CompareOptions options) {
    final old = state.options;
    final refilter =
        options.showLeftOnly != old.showLeftOnly ||
        options.showRightOnly != old.showRightOnly ||
        options.showNewer != old.showNewer ||
        options.showDifferent != old.showDifferent ||
        options.showIdentical != old.showIdentical;
    final reassign =
        options.direction != old.direction ||
        options.deleteMissing != old.deleteMissing;
    if (refilter) {
      _visible = [
        for (var i = 0; i < _rows.length; i++)
          if (rowShown(_rows[i], options)) i,
      ];
    }
    if (reassign) {
      _actions = Uint8List.fromList([
        for (final row in _rows)
          defaultAction(
            row,
            options.direction,
            deleteMissing: options.deleteMissing,
          ).index,
      ]);
    }
    emit(
      state.copyWith(
        options: options,
        visible: _visible,
        visibleCount: _visible.length,
        actions: _actions,
        summary: refilter || reassign ? _summary() : null,
      ),
    );
    _onOptions?.call(options);
  }

  // ─── Actions ───

  bool get _deletions =>
      state.options.deleteMissing &&
      state.options.direction != SyncDirection.bothWays;

  /// The actions [row] may take now.
  List<RowAction> allowedFor(CompareRow row) =>
      allowedActions(row, deletions: _deletions);

  /// Sets [action] on the rows shown at [shown] (table indexes) that can
  /// take it.
  void setAction(Iterable<int> shown, RowAction action) => _change(
    shown,
    (row, _) => allowedFor(row).contains(action) ? action : null,
  );

  /// The next action of each row shown at [shown], as Space walks them;
  /// several rows follow the first so they end up alike.
  void cycleAction(List<int> shown) {
    if (shown.isEmpty) return;
    final first = _visible[shown.first];
    final next = nextAction(
      _rows[first],
      RowAction.values[_actions[first]],
      deletions: _deletions,
    );
    if (shown.length == 1) {
      _change(shown, (_, _) => next);
    } else {
      setAction(shown, next);
    }
  }

  /// The suggested action again for the rows shown at [shown].
  void resetActions(Iterable<int> shown) => _change(
    shown,
    (row, _) => defaultAction(
      row,
      state.options.direction,
      deleteMissing: state.options.deleteMissing,
    ),
  );

  void _change(
    Iterable<int> shown,
    RowAction? Function(CompareRow row, RowAction current) to,
  ) {
    final next = Uint8List.fromList(_actions);
    var changed = false;
    for (final index in shown) {
      if (index < 0 || index >= _visible.length) continue;
      final rowIndex = _visible[index];
      final action = to(_rows[rowIndex], RowAction.values[next[rowIndex]]);
      if (action != null && action.index != next[rowIndex]) {
        next[rowIndex] = action.index;
        changed = true;
      }
    }
    if (!changed) return;
    _actions = next;
    emit(state.copyWith(actions: _actions, summary: _summary()));
  }

  // ─── Synchronizing ───

  /// The plan of the rows shown with an action.
  SyncPlan plan({required bool preserveAttributes, required bool verify}) =>
      SyncPlan(
        left: state.left,
        right: state.right,
        recursive: state.options.recursive,
        preserveAttributes: preserveAttributes,
        verify: verify,
        items: [
          for (final index in _visible)
            if (RowAction.values[_actions[index]].sync case final action?)
              SyncItem(row: _rows[index], action: action),
        ],
      );

  /// Starts the synchronization; answers the operation's id.
  Future<int> synchronize({
    required bool preserveAttributes,
    required bool verify,
  }) => _service.synchronize(
    plan(preserveAttributes: preserveAttributes, verify: verify),
  );

  @override
  Future<void> close() async {
    final closing = _task.close();
    await super.close();
    await closing;
  }
}
