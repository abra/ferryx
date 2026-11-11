// Dependency assembly: what to create and in which order.
//
// Separated from starter.dart (how to launch) so bootstrap tests can replace
// this factory as a whole.

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:domain_models/domain_models.dart';

import 'package:ferryx/app/dependency_container.dart';
import 'package:ferryx/app/resource_disposer.dart';
import 'package:ferryx/app/window_frame.dart';
import 'package:ferryx_backend/ferryx_backend.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:monitoring/monitoring.dart';
import 'package:network_service/network_service.dart';
import 'package:operations_service/operations_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:platform_services/platform_services.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:terminal_service/terminal_service.dart';
import 'package:thumbnail_service/thumbnail_service.dart';

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

    // The bridge outlives bootstrap attempts; the services below do not.
    final backend = await FerryxBackend.initialize();

    // ─── Preferences ───
    final preferencesService = await PreferencesService.create();
    resources.add('preferencesService.dispose', preferencesService.dispose);
    // High-churn values beside the preferences, under keys of their own.
    final sideStorage = SharedPreferencesSideStorage();
    final savedSearches = await SavedProfiles.load<FindRequest>(
      sideStorage,
      key: 'ferryx.savedSearches',
      encode: (request) => request.toJson(),
      decode: FindRequest.fromJson,
    );
    resources.add('savedSearches.dispose', savedSearches.dispose);
    final frecency = await FolderFrecency.load(sideStorage);
    resources.add('frecency.dispose', frecency.dispose);
    final recentCommands = await RecentItems.load(
      sideStorage,
      key: RecentItems.commandsKey,
    );

    // ─── Files and operations ───
    final files = FileRepository(backend: backend, logger: logger);
    resources.add('files.dispose', files.dispose);
    final thumbnails = ThumbnailService(files: files);
    resources.add('thumbnails.dispose', thumbnails.dispose);
    final operations = OperationsService(backend: backend, logger: logger);
    resources.add('operations.dispose', operations.dispose);
    final find = FindService(backend: backend);
    resources.add('find.dispose', find.dispose);
    // ─── Operations stream ───
    final folderSync = FolderSyncService(backend: backend);
    resources.add('folderSync.dispose', folderSync.dispose);
    final checksums = ChecksumService(backend: backend);
    resources.add('checksums.dispose', checksums.dispose);
    final duplicates = DuplicatesService(backend: backend);
    resources.add('duplicates.dispose', duplicates.dispose);
    // What undo and redo would do, before the first change reports it.
    try {
      await operations.refreshJournal();
    } on Object catch (error) {
      logger.warn('journal summary', error: error);
    }

    // ─── The desktop's own services ───
    final platformServices = PlatformServices.forPlatform(
      defaultTargetPlatform,
    );
    resources.add('platformServices.dispose', platformServices.dispose);
    // Chords on a layout of another script go by the keys' places.
    final latinKeyboard = platformServices.latinKeyboard;
    void followKeyboard() => ChordLayout.latin = latinKeyboard.value;
    latinKeyboard.addListener(followKeyboard);
    resources.add(
      'keyboard.removeListener',
      () => latinKeyboard.removeListener(followKeyboard),
    );
    followKeyboard();
    // ─── Terminal ───
    final terminal = TerminalService();
    resources.add('terminal.dispose', terminal.dispose);
    // ─── Network ───
    final network = CoreNetworkService(backend: backend, logger: logger);
    resources.add('network.dispose', network.dispose);
    final recentServers = await RecentItems.load(
      sideStorage,
      key: RecentItems.serversKey,
    );

    stopwatch.stop();
    logger.info('Dependencies ready in ${stopwatch.elapsedMilliseconds} ms');

    return DependenciesContainer(
      logger: logger,
      packageInfo: packageInfo,
      backend: backend,
      preferencesService: preferencesService,
      files: files,
      thumbnails: thumbnails,
      operations: operations,
      find: find,
      rename: const RenameService(),
      frecency: frecency,
      recentCommands: recentCommands,
      platformServices: platformServices,
      terminal: terminal,
      folderSync: folderSync,
      checksums: checksums,
      duplicates: duplicates,
      network: network,
      recentServers: recentServers,
      sideStorage: sideStorage,
      savedSearches: savedSearches,
      resourceDisposer: resources,
      windowFrame: windowFrame,
    );
  } on Object {
    await resources.dispose(rollback: true);
    rethrow;
  }
}
