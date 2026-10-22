import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;

/// Compare and synchronize folders: the comparison of two trees runs in
/// the core and reports on [updates]; synchronizing and comparing the
/// contents of files are operations (their progress comes through
/// `OperationsService`).
class FolderSyncService {
  FolderSyncService({required rust.FerryxBackend backend}) {
    _subscription = backend.events.listen(_onEvent);
  }

  final _updates = StreamController<CompareUpdate>.broadcast();
  StreamSubscription<rust.AppEvent>? _subscription;

  /// Every comparison's rows and progress, by task id.
  Stream<CompareUpdate> get updates => _updates.stream;

  void _onEvent(rust.AppEvent event) {
    if (event.kind != rust.AppEventKind.compareProgress) return;
    final view = event.compare;
    if (view != null) _updates.add(rust.compareUpdateFromView(view));
  }

  /// Starts comparing two folder trees; answers the task's id.
  Future<int> compare(FolderCompareRequest request) => rust.FerryxBackend.guard(
    () => rust.startFolderCompare(
      request: rust.folderCompareRequestToView(request),
    ),
  );

  Future<void> cancel(int taskId) =>
      rust.FerryxBackend.guard(() => rust.cancelFolderCompare(taskId: taskId));

  /// Carries out [plan] as an operation; answers its id.
  Future<int> synchronize(SyncPlan plan) => rust.FerryxBackend.guard(
    () => rust.startSynchronize(plan: rust.syncPlanToView(plan)),
  );

  /// Compares each pair byte for byte as an operation; answers its id.
  /// Once it finished, [takeContentDifferences] names the pairs that
  /// differ.
  Future<int> compareContents(List<ContentPair> pairs) =>
      rust.FerryxBackend.guard(
        () => rust.startContentCompare(
          pairs: [
            for (final pair in pairs)
              rust.ContentPairView(left: pair.left, right: pair.right),
          ],
        ),
      );

  /// The indexes of the pairs the content comparison [operationId] found
  /// different (or could not read).
  Future<List<int>> takeContentDifferences(int operationId) =>
      rust.FerryxBackend.guard(() async {
        final indexes = await rust.takeContentDifferences(opId: operationId);
        return indexes.map((i) => i.toInt()).toList(growable: false);
      });

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _updates.close();
  }
}
