import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:operations_service/operations_service.dart';

/// Hash the files, or check them against a checksum file.
enum ChecksumMode { calculate, verify }

/// The dialog as the cubit keeps it: the files in the order the core
/// listed them and the outcome of each as it came. Not [Equatable]: the
/// lists can be long, and a state is new on every update.
@immutable
class ChecksumsState {
  const ChecksumsState({
    required this.mode,
    required this.algorithm,
    this.recursive = true,
    this.running = false,
    this.files = const [],
    this.outcomes = const [],
    this.filesDone = 0,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.current,
    this.badLines = 0,
    this.error,
    this.revision = 0,
  });

  final ChecksumMode mode;

  /// The algorithm asked for; checking, the one the checksum file uses.
  final ChecksumAlgorithm algorithm;
  final bool recursive;
  final bool running;
  final List<ChecksumFile> files;

  /// By file index; `null` until the file is done.
  final List<ChecksumOutcome?> outcomes;
  final int filesDone;
  final int bytesDone;
  final int bytesTotal;
  final String? current;

  /// Checking: lines of the checksum file that list nothing readable.
  final int badLines;
  final String? error;
  final int revision;

  bool get done => !running && files.isNotEmpty;

  ChecksumOutcome? outcomeOf(int index) =>
      index < outcomes.length ? outcomes[index] : null;

  /// The files whose hash is [expected] (case and spaces aside); empty for
  /// a blank or partial hash.
  List<int> matching(String expected) {
    final wanted = expected.trim().toLowerCase();
    if (wanted.length < 8) return const [];
    return [
      for (var i = 0; i < outcomes.length; i++)
        if (outcomes[i]?.hash?.toLowerCase() == wanted) i,
    ];
  }

  /// Counts by outcome, for a check's summary.
  Map<ChecksumStatus, int> get statusCounts {
    final counts = <ChecksumStatus, int>{};
    for (final outcome in outcomes) {
      if (outcome != null) {
        counts[outcome.status] = (counts[outcome.status] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// The lines of a checksum file for every file hashed, by name.
  List<ChecksumLine> get lines => [
    for (var i = 0; i < files.length; i++)
      if (outcomeOf(i)?.hash case final hash?)
        ChecksumLine(hash: hash, name: files[i].name),
  ];

  ChecksumsState copyWith({
    ChecksumMode? mode,
    ChecksumAlgorithm? algorithm,
    bool? recursive,
    bool? running,
    List<ChecksumFile>? files,
    List<ChecksumOutcome?>? outcomes,
    int? filesDone,
    int? bytesDone,
    int? bytesTotal,
    String? current,
    bool clearCurrent = false,
    int? badLines,
    String? error,
    bool clearError = false,
  }) => ChecksumsState(
    mode: mode ?? this.mode,
    algorithm: algorithm ?? this.algorithm,
    recursive: recursive ?? this.recursive,
    running: running ?? this.running,
    files: files ?? this.files,
    outcomes: outcomes ?? this.outcomes,
    filesDone: filesDone ?? this.filesDone,
    bytesDone: bytesDone ?? this.bytesDone,
    bytesTotal: bytesTotal ?? this.bytesTotal,
    current: clearCurrent ? null : (current ?? this.current),
    badLines: badLines ?? this.badLines,
    error: clearError ? null : (error ?? this.error),
    revision: revision + 1,
  );
}

/// Runs one checksum task at a time through the core: the hashes of
/// [paths] (folders walked), or the check of the checksum file among
/// them; a change of algorithm or of the subfolder option starts over.
class ChecksumsCubit extends Cubit<ChecksumsState> {
  ChecksumsCubit({
    required ChecksumService service,
    required this.paths,
    required this.base,
    ChecksumAlgorithm? algorithm,
  }) : _service = service,
       super(
         ChecksumsState(
           mode: verifiable(paths)
               ? ChecksumMode.verify
               : ChecksumMode.calculate,
           algorithm:
               algorithm ??
               (verifiable(paths)
                   ? ChecksumAlgorithm.ofSumsFile(_name(paths.single))!
                   : ChecksumAlgorithm.sha256),
         ),
       ) {
    _subscription = service.updates.listen(_onUpdate);
  }

  final ChecksumService _service;
  final List<String> paths;
  final String base;
  StreamSubscription<ChecksumUpdate>? _subscription;
  int? _taskId;

  /// Whether [paths] is one checksum file, which can be checked.
  static bool verifiable(List<String> paths) =>
      paths.length == 1 &&
      ChecksumAlgorithm.ofSumsFile(_name(paths.single)) != null;

  static String _name(String path) => path.substring(path.lastIndexOf('/') + 1);

  /// The checksum file's name, checking.
  String get sumsName => _name(paths.single);

  /// Starts over with the current mode and options.
  Future<void> start() async {
    await stop();
    emit(
      ChecksumsState(
        mode: state.mode,
        algorithm: state.algorithm,
        recursive: state.recursive,
        running: true,
        revision: state.revision + 1,
      ),
    );
    final id = state.mode == ChecksumMode.verify
        ? await _service.verify(paths.single)
        : await _service.start(
            ChecksumRequest(
              paths: paths,
              base: base,
              algorithm: state.algorithm,
              recursive: state.recursive,
            ),
          );
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

  Future<void> setAlgorithm(ChecksumAlgorithm algorithm) async {
    if (algorithm == state.algorithm && state.mode == ChecksumMode.calculate) {
      return;
    }
    emit(state.copyWith(algorithm: algorithm, mode: ChecksumMode.calculate));
    await start();
  }

  Future<void> setRecursive(bool recursive) async {
    emit(state.copyWith(recursive: recursive));
    await start();
  }

  Future<void> setMode(ChecksumMode mode) async {
    if (mode == state.mode) return;
    emit(state.copyWith(mode: mode));
    await start();
  }

  void _onUpdate(ChecksumUpdate update) {
    if (update.taskId != _taskId || isClosed) return;
    var files = state.files;
    var outcomes = state.outcomes;
    if (update.files.isNotEmpty) {
      files = [...files, ...update.files];
    }
    if (outcomes.length < update.filesTotal || update.outcomes.isNotEmpty) {
      outcomes = List<ChecksumOutcome?>.of(outcomes)
        ..length = update.filesTotal > outcomes.length
            ? update.filesTotal
            : outcomes.length;
      for (final outcome in update.outcomes) {
        if (outcome.index < outcomes.length) outcomes[outcome.index] = outcome;
      }
    }
    if (update.done) _taskId = null;
    emit(
      state.copyWith(
        running: !update.done,
        files: files,
        outcomes: outcomes,
        filesDone: update.filesDone,
        bytesDone: update.bytesDone,
        bytesTotal: update.bytesTotal,
        current: update.current,
        clearCurrent: update.done || update.current == null,
        algorithm: update.algorithm,
        badLines: update.badLines,
        error: update.error,
      ),
    );
  }

  /// Saves the hashes as a checksum file named [name] in the base folder
  /// (GNU form); answers the path written.
  Future<String> save(String name, {bool overwrite = false}) async {
    final path = base.endsWith('/') ? '$base$name' : '$base/$name';
    await _service.save(path, state.lines, overwrite: overwrite);
    return path;
  }

  /// The checksum file's default name: the single item's, else the
  /// folder's, with the algorithm's extension.
  String get defaultFileName {
    final stem = paths.length == 1
        ? _name(paths.single)
        : (base == '/' ? 'checksums' : _name(base));
    return '$stem.${state.algorithm.extension}';
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    final id = _taskId;
    if (id != null) unawaited(_service.cancel(id));
    return super.close();
  }
}
