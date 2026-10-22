import 'dart:async';

import 'package:monitoring/monitoring.dart';

typedef ResourceDisposeCallback = FutureOr<void> Function();

/// Owns application resources and releases them in reverse creation order,
/// exactly once. Used both for normal shutdown and for rolling back a failed
/// bootstrap.
class ResourceDisposer {
  ResourceDisposer({required this._logger});

  final Logger _logger;
  final List<_Disposal> _resources = [];
  Future<void>? _disposeFuture;

  void add(
    String name,
    ResourceDisposeCallback callback, {
    bool disposeOnRollback = true,
  }) {
    if (_disposeFuture != null) {
      throw StateError('Cannot add $name after disposal started.');
    }
    _resources.add(_Disposal(name, callback, disposeOnRollback));
  }

  /// With [rollback], resources that outlive a bootstrap attempt (logger)
  /// are kept for the retry.
  Future<void> dispose({bool rollback = false}) =>
      _disposeFuture ??= _run(rollback: rollback);

  Future<void> _run({required bool rollback}) async {
    for (final resource in _resources.reversed) {
      if (rollback && !resource.disposeOnRollback) continue;
      try {
        await resource.callback();
      } on Object catch (error, stackTrace) {
        _logger.warn(
          '${resource.name} failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
}

class _Disposal {
  const _Disposal(this.name, this.callback, this.disposeOnRollback);

  final String name;
  final ResourceDisposeCallback callback;
  final bool disposeOnRollback;
}
