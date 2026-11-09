import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:flutter/foundation.dart';
import 'package:operations_service/operations_service.dart';

/// The window's operation cards, questions and delayed dismissals.
class WorkspaceOperationsController extends ChangeNotifier {
  WorkspaceOperationsController({
    required OperationsService service,
    required this._ask,
    required this._onFinished,
  }) : _service = service {
    _progress = service.progress.listen(_onProgress);
    for (final progress in service.current.values) {
      _onProgress(progress);
    }
  }

  final OperationsService _service;
  final Future<Answer?> Function(OperationQuestion question) _ask;
  final VoidCallback _onFinished;
  late final StreamSubscription<OperationProgress> _progress;
  final _shownOperations = <int, OperationProgress>{};
  final _dismissTimers = <int, Timer>{};
  final _operationTitles = <int, String>{};

  // The core starts question numbers over for each operation.
  final _askedQuestions = <(int, int)>{};
  final _openQuestions = <(int, int)>{};
  bool _disposed = false;

  List<OperationProgress> get operations =>
      _shownOperations.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  Map<int, String> get titles => Map.unmodifiable(_operationTitles);

  void setTitle(int id, String title) {
    if (_disposed || _operationTitles[id] == title) return;
    _operationTitles[id] = title;
    notifyListeners();
  }

  void _onProgress(OperationProgress progress) {
    if (_disposed || progress.kind == OpKind.calcSizes) return;
    _shownOperations[progress.id] = progress;
    final question = progress.question;
    if (progress.state == OpState.waiting &&
        question != null &&
        !_askedQuestions.contains((progress.id, question.id))) {
      unawaited(ask(progress.id));
    }
    if (progress.state.isFinished) {
      _onFinished();
      _dismissTimers.remove(progress.id)?.cancel();
      final keep =
          progress.errors.isNotEmpty ||
          progress.state == OpState.failed ||
          progress.state == OpState.doneWithErrors;
      if (!keep) {
        _dismissTimers[progress.id] = Timer(
          const Duration(seconds: 3),
          () => dismiss(progress.id),
        );
      }
    }
    notifyListeners();
  }

  /// Opens a waiting card's question again, unless its dialog is still open.
  Future<void> ask(int id) async {
    if (_disposed) return;
    final progress = _shownOperations[id];
    final question = progress?.question;
    if (progress?.state != OpState.waiting || question == null) return;
    final key = (id, question.id);
    if (!_openQuestions.add(key)) return;
    _askedQuestions.add(key);
    try {
      final answer = await _ask(question);
      if (_disposed) return;
      final current = _shownOperations[id];
      if (current?.state != OpState.waiting ||
          current?.question?.id != question.id) {
        return;
      }
      await _service.answer(id, question.id, answer ?? Answer.abort);
    } finally {
      _openQuestions.remove(key);
    }
  }

  void dismiss(int id) {
    if (_disposed) return;
    _dismissTimers.remove(id)?.cancel();
    _operationTitles.remove(id);
    _askedQuestions.removeWhere((asked) => asked.$1 == id);
    if (_shownOperations.remove(id) == null) return;
    notifyListeners();
    unawaited(_service.forget(id));
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_progress.cancel());
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    _dismissTimers.clear();
    _shownOperations.clear();
    _operationTitles.clear();
    _askedQuestions.clear();
    _openQuestions.clear();
    super.dispose();
  }
}
