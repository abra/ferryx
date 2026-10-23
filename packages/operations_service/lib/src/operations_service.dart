import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;
import 'package:monitoring/monitoring.dart';

/// Starts operations and follows them: every report comes on [progress]
/// and the latest of each is kept in [current] until the operation is
/// forgotten.
class OperationsService {
  OperationsService({
    required rust.FerryxBackend backend,
    required this.logger,
  }) {
    _subscription = backend.events.listen(_onEvent);
  }

  final Logger logger;
  final _progress = StreamController<OperationProgress>.broadcast();
  final _current = <int, OperationProgress>{};
  StreamSubscription<rust.AppEvent>? _subscription;

  /// Every progress report of every operation, in order.
  Stream<OperationProgress> get progress => _progress.stream;

  /// The latest report of each operation not yet forgotten, by id.
  Map<int, OperationProgress> get current => Map.unmodifiable(_current);

  void _onEvent(rust.AppEvent event) {
    if (event.kind == rust.AppEventKind.journalChanged) {
      _onJournal(event);
      return;
    }
    if (event.kind != rust.AppEventKind.operationProgress) return;
    final view = event.progress;
    if (view == null) return;
    final report = rust.progressFromView(view);
    _current[report.id] = report;
    _progress.add(report);
  }

  /// Starts [request]; its progress follows on [progress]. One with a
  /// server on a side ([OperationRequest.crossesNetwork]) goes over the
  /// network: a copy, a move, a delete or folder sizes, never journaled.
  Future<int> start(OperationRequest request) =>
      rust.FerryxBackend.guard(() async {
        final id = request.crossesNetwork
            ? await rust.startNetworkOperation(
                request: rust.networkOperationToView(request),
              )
            : await rust.startOperation(
                request: rust.operationRequestToView(request),
              );
        logger.debug('operation $id started: ${request.kind.name}');
        return id;
      });

  /// Starts [request] and waits until it finished; questions are answered
  /// with [answer], the first offered answer when it gives none.
  Future<OperationProgress> run(
    OperationRequest request, {
    Answer? Function(OperationQuestion question)? answer,
  }) async {
    final completer = Completer<OperationProgress>();
    late final StreamSubscription<OperationProgress> subscription;
    int? id;
    subscription = progress.listen((report) {
      if (report.id != id) return;
      final question = report.question;
      if (question != null && report.state == OpState.waiting) {
        final chosen = answer?.call(question) ?? question.answers.first;
        unawaited(this.answer(report.id, question.id, chosen));
      }
      if (report.state.isFinished && !completer.isCompleted) {
        completer.complete(report);
        subscription.cancel();
      }
    });
    id = await start(request);
    final known = _current[id];
    if (known != null && known.state.isFinished && !completer.isCompleted) {
      completer.complete(known);
      await subscription.cancel();
    }
    return completer.future;
  }

  Future<void> pause(int id) =>
      rust.FerryxBackend.guard(() => rust.pauseOperation(id: id));

  Future<void> resume(int id) =>
      rust.FerryxBackend.guard(() => rust.resumeOperation(id: id));

  Future<void> cancel(int id) =>
      rust.FerryxBackend.guard(() => rust.cancelOperation(id: id));

  Future<void> answer(int id, int questionId, Answer answer) =>
      rust.FerryxBackend.guard(
        () => rust.answerOperation(
          id: id,
          questionId: questionId,
          answer: rust.answerToView(answer),
        ),
      );

  Future<OperationProgress?> progressOf(int id) =>
      rust.FerryxBackend.guard(() async {
        final view = await rust.operationProgress(id: id);
        return view == null ? null : rust.progressFromView(view);
      });

  Future<List<OperationProgress>> list() => rust.FerryxBackend.guard(() async {
    final views = await rust.listOperations();
    return views.map(rust.progressFromView).toList(growable: false);
  });

  /// Drops a finished operation from the core and from [current].
  Future<void> forget(int id) async {
    _current.remove(id);
    await rust.FerryxBackend.guard(() => rust.forgetOperation(id: id));
  }

  // ─── Undo and redo ───

  final _journal = StreamController<JournalSummary>.broadcast();
  JournalSummary _journalNow = JournalSummary.empty;

  /// What undo and redo would do next, on every change: an operation
  /// ended, a rename, a new folder, an undo.
  Stream<JournalSummary> get journal => _journal.stream;

  /// The latest of [journal].
  JournalSummary get currentJournal => _journalNow;

  void _onJournal(rust.AppEvent event) {
    final view = event.journal;
    if (view == null) return;
    _journalNow = rust.journalSummaryFromView(view);
    _journal.add(_journalNow);
  }

  /// Reads what undo and redo would do from the core (at start).
  Future<JournalSummary> refreshJournal() => rust.FerryxBackend.guard(() async {
    _journalNow = rust.journalSummaryFromView(await rust.journalSummary());
    _journal.add(_journalNow);
    return _journalNow;
  });

  /// A look at the step undo ([redo] false) or redo would take: what of
  /// it cannot be done as it was. `null` when there is nothing to do.
  Future<UndoCheck?> checkStep({required bool redo}) =>
      rust.FerryxBackend.guard(() async {
        final view = await rust.checkJournalStep(redo: redo);
        return view == null ? null : rust.undoCheckFromView(view);
      });

  /// Undoes the step [stepId] (the one [checkStep] looked at) as an
  /// operation; answers its id. Throws [FerryxException] with
  /// [FerryxErrorKind.notFound] when another step came first meanwhile.
  Future<int> undo(int stepId) => _walk(stepId, redo: false);

  /// Redoes the step [stepId]; as [undo].
  Future<int> redo(int stepId) => _walk(stepId, redo: true);

  Future<int> _walk(int stepId, {required bool redo}) =>
      rust.FerryxBackend.guard(() async {
        final id = await rust.walkJournalStep(redo: redo, stepId: stepId);
        logger.debug('${redo ? 'redo' : 'undo'} of step $stepId: op $id');
        return id;
      });

  /// Drops the step [stepId], which can no longer be done, so the one
  /// before it comes next.
  Future<bool> forgetStep(int stepId, {required bool redo}) =>
      rust.FerryxBackend.guard(
        () => rust.forgetJournalStep(redo: redo, stepId: stepId),
      );

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _progress.close();
    await _journal.close();
  }
}
