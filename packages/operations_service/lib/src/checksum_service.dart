import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;

/// Checksums: hashing files, checking a checksum file, saving one. The
/// work runs in the core and reports on [updates].
class ChecksumService {
  ChecksumService({required rust.FerryxBackend backend}) {
    _subscription = backend.events.listen(_onEvent);
  }

  final _updates = StreamController<ChecksumUpdate>.broadcast();
  StreamSubscription<rust.AppEvent>? _subscription;

  /// Every task's files and outcomes, by task id.
  Stream<ChecksumUpdate> get updates => _updates.stream;

  void _onEvent(rust.AppEvent event) {
    if (event.kind != rust.AppEventKind.checksumProgress) return;
    final view = event.checksum;
    if (view != null) _updates.add(rust.checksumUpdateFromView(view));
  }

  /// Starts hashing the files of [request]; answers the task's id.
  Future<int> start(ChecksumRequest request) => rust.FerryxBackend.guard(
    () => rust.startChecksums(request: rust.checksumRequestToView(request)),
  );

  /// Starts checking the files the checksum file at [path] lists.
  Future<int> verify(String path) =>
      rust.FerryxBackend.guard(() => rust.startChecksumVerify(sumsPath: path));

  Future<void> cancel(int taskId) =>
      rust.FerryxBackend.guard(() => rust.cancelChecksums(taskId: taskId));

  /// Writes [lines] as a checksum file at [path]; an existing file is
  /// replaced only with [overwrite] (else [FerryxErrorKind.alreadyExists]).
  Future<void> save(
    String path,
    List<ChecksumLine> lines, {
    bool overwrite = false,
  }) => rust.FerryxBackend.guard(
    () => rust.saveChecksumFile(
      path: path,
      lines: [
        for (final line in lines)
          rust.ChecksumLineView(hash: line.hash, name: line.name),
      ],
      overwrite: overwrite,
    ),
  );

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _updates.close();
  }
}
