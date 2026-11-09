import 'dart:async';

/// Owns one streamed task, including the interval before its start reply.
///
/// A new start, stop or close invalidates the previous run immediately. Its
/// eventual id is cancelled without changing the new run. Early events are
/// replayed only after their task id is known; overflowing that bounded buffer
/// fails the run instead of presenting incomplete results as a success.
class TaskSession<T> {
  TaskSession({
    required Stream<T> updates,
    required this._idOf,
    required this._isDone,
    required this._cancel,
    required this._onUpdate,
    required this._onError,
    required this._onCleanupError,
    this._onStarted,
  }) {
    _subscription = updates.listen(
      _receive,
      onError: (Object error, StackTrace stackTrace) {
        final run = _run;
        if (run != null) _fail(run, error, stackTrace);
      },
      onDone: () {
        _streamEnded = true;
        final run = _run;
        if (run != null) {
          _fail(
            run,
            StateError('Task event stream closed'),
            StackTrace.current,
          );
        }
      },
    );
  }

  static const maxEarlyEvents = 128;

  final int Function(T update) _idOf;
  final bool Function(T update) _isDone;
  final Future<void> Function(int id) _cancel;
  final void Function(T update) _onUpdate;
  final void Function(Object error, StackTrace stackTrace) _onError;
  final void Function(Object error, StackTrace stackTrace) _onCleanupError;
  final void Function(int id)? _onStarted;
  late final StreamSubscription<T> _subscription;
  _TaskRun<T>? _run;
  bool _closed = false;
  bool _streamEnded = false;

  Future<void> start(Future<int> Function() launch) async {
    if (_closed) return;
    if (_streamEnded) {
      _onError(StateError('Task event stream closed'), StackTrace.current);
      return;
    }
    final previous = _run;
    final run = _TaskRun<T>();
    _run = run;
    previous?.early.clear();
    if (previous?.id case final id?) unawaited(_cancelSafely(id));

    final int id;
    try {
      id = await launch();
    } on Object catch (error, stackTrace) {
      if (identical(_run, run)) _fail(run, error, stackTrace);
      return;
    }
    if (!identical(_run, run)) {
      await _cancelSafely(id);
      return;
    }
    run.id = id;
    _onStarted?.call(id);
    final early = List<T>.of(run.early);
    run.early.clear();
    for (final update in early) {
      if (!identical(_run, run)) break;
      _deliver(run, update);
    }
  }

  void _receive(T update) {
    final run = _run;
    if (run == null) return;
    if (run.id != null) {
      _deliver(run, update);
    } else if (run.early.length < maxEarlyEvents) {
      run.early.add(update);
    } else {
      _fail(
        run,
        StateError('Too many task events before its start reply'),
        StackTrace.current,
      );
    }
  }

  void _deliver(_TaskRun<T> run, T update) {
    if (_idOf(update) != run.id) return;
    if (_isDone(update)) _run = null;
    _onUpdate(update);
  }

  void _fail(_TaskRun<T> run, Object error, StackTrace stackTrace) {
    _run = null;
    run.early.clear();
    if (run.id case final id?) unawaited(_cancelSafely(id));
    _onError(error, stackTrace);
  }

  Future<void> _cancelSafely(int id) async {
    try {
      await _cancel(id);
    } on Object catch (error, stackTrace) {
      // Cleanup may finish after the owner closed or started another task.
      _onCleanupError(error, stackTrace);
    }
  }

  Future<void> stop() async {
    final run = _run;
    _run = null;
    run?.early.clear();
    if (run?.id case final id?) await _cancelSafely(id);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final stopping = stop();
    await _subscription.cancel();
    await stopping;
  }
}

class _TaskRun<T> {
  int? id;
  final early = <T>[];
}
