import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;

/// Find Duplicates: a search runs in the core and reports on [updates].
class DuplicatesService {
  DuplicatesService({required rust.FerryxBackend backend}) {
    _subscription = backend.events.listen(_onEvent);
  }

  final _updates = StreamController<DuplicatesUpdate>.broadcast();
  StreamSubscription<rust.AppEvent>? _subscription;

  /// Every search's phase, counts and groups, by task id.
  Stream<DuplicatesUpdate> get updates => _updates.stream;

  void _onEvent(rust.AppEvent event) {
    if (event.kind != rust.AppEventKind.duplicatesProgress) return;
    final view = event.duplicates;
    if (view != null) _updates.add(rust.duplicatesUpdateFromView(view));
  }

  /// Starts the search; answers its id.
  Future<int> start(DuplicatesRequest request) => rust.FerryxBackend.guard(
    () => rust.startDuplicates(request: rust.duplicatesRequestToView(request)),
  );

  Future<void> cancel(int taskId) =>
      rust.FerryxBackend.guard(() => rust.cancelDuplicates(taskId: taskId));

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _updates.close();
  }
}
