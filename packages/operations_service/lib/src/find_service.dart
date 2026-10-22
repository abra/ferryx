import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;

/// Find Files: a search runs in the core and reports on [updates].
class FindService {
  FindService({required rust.FerryxBackend backend}) {
    _subscription = backend.events.listen(_onEvent);
  }

  final _updates = StreamController<FindUpdate>.broadcast();
  StreamSubscription<rust.AppEvent>? _subscription;

  Stream<FindUpdate> get updates => _updates.stream;

  void _onEvent(rust.AppEvent event) {
    final id = event.findId;
    if (id == null) return;
    switch (event.kind) {
      case rust.AppEventKind.findProgress:
        _updates.add(
          FindUpdate(
            findId: id,
            hits: event.hits.map(rust.findHitFromView).toList(growable: false),
            current: event.findCurrent,
            scanned: event.findScanned,
          ),
        );
      case rust.AppEventKind.findDone:
        _updates.add(
          FindUpdate(
            findId: id,
            scanned: event.findScanned,
            done: true,
            error: event.findError,
            spotlightFailed: event.findSpotlightFailed,
          ),
        );
      case rust.AppEventKind.directoryChanged:
      case rust.AppEventKind.operationProgress:
        break;
    }
  }

  /// Starts the search and answers its id.
  Future<int> start(FindRequest request) => rust.FerryxBackend.guard(
    () => rust.startFind(request: rust.findRequestToView(request)),
  );

  Future<void> cancel(int id) =>
      rust.FerryxBackend.guard(() => rust.cancelFind(id: id));

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _updates.close();
  }
}
