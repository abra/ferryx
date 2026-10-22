import 'dart:async';

import 'package:ferryx/app/composition.dart';
import 'package:ferryx/app/dependency_container.dart';
import 'package:ferryx/app/window_frame.dart';
import 'package:monitoring/monitoring.dart';

typedef BootstrapReady = FutureOr<void> Function(DependenciesContainer deps);
typedef BootstrapFailure = FutureOr<void> Function(
  Object error,
  StackTrace stackTrace,
);

/// Composes dependencies and hands them to the running app, or reports the
/// failure so the UI can offer a retry. The logger outlives every attempt.
class AppBootstrap {
  AppBootstrap({required this._logger, this._windowFrame});

  final Logger _logger;
  final WindowFrame? _windowFrame;

  Future<void> run({
    required BootstrapReady onReady,
    required BootstrapFailure onFailure,
  }) async {
    try {
      final deps = await composeDependencies(
        logger: _logger,
        windowFrame: _windowFrame,
      );
      await onReady(deps);
    } on Object catch (error, stackTrace) {
      _logger.fatal(
        'Initialization failed',
        error: error,
        stackTrace: stackTrace,
      );
      await onFailure(error, stackTrace);
    }
  }
}
