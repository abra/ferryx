import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:flutter/foundation.dart';

import '../panel/panel_side.dart';

/// A captured deletion, before any filesystem operation has started.
@immutable
class PendingDeletion {
  const PendingDeletion({
    required this.id,
    required this.side,
    required this.location,
    required this.request,
    required this.delay,
    required this.dueAt,
  });

  final int id;
  final PanelSide side;
  final Location location;
  final OperationRequest request;
  final Duration delay;

  /// Deadline on the controller's monotonic clock, independent of wall time.
  final Duration dueAt;
}

/// Owns the grace period; widgets only display it and request cancellation.
/// One batch per panel prevents a repeated D from queuing duplicate work.
class PendingDeletionsController extends ChangeNotifier {
  PendingDeletionsController({required this.onExecute});

  static const gracePeriod = Duration(seconds: 5);

  /// The workspace starts the captured request through its normal error path.
  final Future<void> Function(PendingDeletion deletion) onExecute;
  final _clock = Stopwatch()..start();
  final _pending = <PanelSide, PendingDeletion>{};
  final _timers = <PanelSide, Timer>{};
  int _nextId = 0;
  bool _disposed = false;

  bool get hasPending => _pending.isNotEmpty;

  PendingDeletion? pendingFor(PanelSide side) => _pending[side];

  Duration remaining(PendingDeletion deletion) {
    final value = deletion.dueAt - _clock.elapsed;
    return value.isNegative ? Duration.zero : value;
  }

  bool schedule({
    required PanelSide side,
    required Location location,
    required OpKind kind,
    required List<String> paths,
  }) {
    assert(kind == OpKind.trash || kind == OpKind.delete);
    if (_disposed || _pending.containsKey(side) || paths.isEmpty) return false;
    final deletion = PendingDeletion(
      id: _nextId++,
      side: side,
      location: location,
      request: OperationRequest(
        kind: kind,
        sources: List.unmodifiable(paths),
        sourceServer: location.server,
      ),
      delay: gracePeriod,
      dueAt: _clock.elapsed + gracePeriod,
    );
    _pending[side] = deletion;
    _timers[side] = Timer(gracePeriod, () {
      if (_disposed || _pending[side]?.id != deletion.id) return;
      _timers.remove(side);
      _pending.remove(side);
      notifyListeners();
      // Cancellation is complete before this point: no Rust request exists yet.
      unawaited(onExecute(deletion));
    });
    notifyListeners();
    return true;
  }

  bool cancel(PanelSide side) {
    if (_disposed || _pending.remove(side) == null) return false;
    _timers.remove(side)?.cancel();
    notifyListeners();
    return true;
  }

  /// Esc prefers the current panel, then the other panel's pending batch.
  bool cancelFrom(PanelSide side) => cancel(side) || cancel(side.opposite);

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _pending.clear();
    _clock.stop();
    super.dispose();
  }
}
