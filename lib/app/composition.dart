// Dependency assembly: what to create and in which order.
//
// Separated from starter.dart (how to launch) so bootstrap tests can replace
// this factory as a whole.

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:ferryx/app/dependency_container.dart';
import 'package:ferryx/app/resource_disposer.dart';
import 'package:ferryx/app/window_frame.dart';
import 'package:ferryx_backend/ferryx_backend.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:monitoring/monitoring.dart';
import 'package:operations_service/operations_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:platform_services/platform_services.dart';
import 'package:preferences_service/preferences_service.dart';

/// The app's strings where no widget tree is yet: the language chosen in
/// the preferences, else the system's when the app speaks it, else English.
FerryxLocalizations appStrings(PreferencesService preferences) {
  final code =
      preferences.current.localeCode ??
      PlatformDispatcher.instance.locale.languageCode;
  return lookupFerryxLocalizations(
    Locale(FerryxSupportedLocales.codes.contains(code) ? code : 'en'),
  );
}

/// Creates every dependency, rolling back on failure.
Future<DependenciesContainer> composeDependencies({
  required Logger logger,
  WindowFrame? windowFrame,
}) async {
  final stopwatch = Stopwatch()..start();
  final resources = ResourceDisposer(logger: logger)
    ..add('logger.destroy', logger.destroy, disposeOnRollback: false);

  try {
    final packageInfo = await PackageInfo.fromPlatform();

    // ─── Rust core ───
    final backend = await FerryxBackend.initialize();

    // ─── Preferences ───
    final preferencesService = await PreferencesService.create();
    resources.add('preferencesService.dispose', preferencesService.dispose);

    // ─── Files and operations ───
    final files = FileRepository(backend: backend, logger: logger);
    resources.add('files.dispose', files.dispose);
    final operations = OperationsService(backend: backend, logger: logger);
    resources.add('operations.dispose', operations.dispose);
    final find = FindService(backend: backend);
    resources.add('find.dispose', find.dispose);

    // ─── The desktop's own services ───
    final platformServices = PlatformServices.forPlatform(
      defaultTargetPlatform,
    );
    resources.add('platformServices.dispose', platformServices.dispose);

    stopwatch.stop();
    logger.info('Dependencies ready in ${stopwatch.elapsedMilliseconds} ms');

    return DependenciesContainer(
      logger: logger,
      packageInfo: packageInfo,
      backend: backend,
      preferencesService: preferencesService,
      files: files,
      operations: operations,
      find: find,
      rename: const RenameService(),
      platformServices: platformServices,
      resourceDisposer: resources,
      windowFrame: windowFrame,
    );
  } on Object {
    await resources.dispose(rollback: true);
    rethrow;
  }
}
