// Application bootstrap: error zone, binding, runApp.
//
// Every unhandled error (zone, framework, platform dispatcher) is routed to
// the logger. A failed initialization shows a recovery screen with retry
// instead of crashing.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ferryx/app/app_bootstrap.dart';
import 'package:ferryx/app/app_scopes.dart';
import 'package:ferryx/app/bloc/app_bloc_observer.dart';
import 'package:ferryx/app/screens/initialization_failed_screen.dart';
import 'package:ferryx/app/window_setup.dart';
import 'package:ferryx/app/window_state.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:monitoring/monitoring.dart';

/// Initializes dependencies and runs the app.
Future<void> starter() async {
  final logger = Logger(
    observers: [
      if (!kReleaseMode) const PrintingLogObserver(logLevel: LogLevel.debug),
    ],
  );

  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    final windowFrame = await configureWindow();

    FlutterError.onError = logger.logFlutterError;
    WidgetsBinding.instance.platformDispatcher.onError =
        logger.logPlatformDispatcherError;
    Bloc.observer = AppBlocObserver(logger);

    final bootstrap = AppBootstrap(logger: logger, windowFrame: windowFrame);
    WindowStateSaver? windowState;
    Future<void> composeAndRun() => bootstrap.run(
      onReady: (dependencies) async {
        runApp(AppScopes(dependencies: dependencies));
        windowState?.dispose();
        windowState = WindowStateSaver(dependencies.preferencesService);
        await showWindow(dependencies.preferencesService.current);
      },
      onFailure: (error, stackTrace) async {
        runApp(
          InitializationFailedScreen(
            error: error,
            stackTrace: stackTrace,
            onRetry: composeAndRun,
          ),
        );
        await showWindow(const Preferences());
      },
    );

    await composeAndRun();
  }, logger.logZoneError);
}
