import 'package:domain_models/domain_models.dart';
import 'package:ferryx/app/resource_disposer.dart';
import 'package:ferryx/app/window_frame.dart';
import 'package:ferryx_backend/ferryx_backend.dart';
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

/// Application-wide dependencies, built once and passed explicitly into
/// feature entry points from `routing.dart`. No service locator.
class DependenciesContainer {
  DependenciesContainer({
    required this.logger,
    required this.packageInfo,
    required this.backend,
    required this.preferencesService,
    required this.files,
    required this.operations,
    required this.find,
    required this.rename,
    required this.frecency,
    required this.recentCommands,
    required this.platformServices,
    required this.terminal,
    required this.folderSync,
    required this.checksums,
    required this.duplicates,
    required this.network,
    required this.recentServers,
    this.sideStorage,
    this.savedSearches,
    this.thumbnails,
    required this._resourceDisposer,
    TargetPlatform? platform,
    WindowFrame? windowFrame,
  }) : platform = platform ?? defaultTargetPlatform,
       windowFrame =
           windowFrame ??
           WindowFrame.forPlatform(platform ?? defaultTargetPlatform);

  final Logger logger;
  final PackageInfo packageInfo;
  final FerryxBackend backend;
  final PreferencesService preferencesService;
  final FileRepository files;
  final OperationsService operations;
  final FindService find;
  final RenameService rename;
  final TerminalService terminal;

  /// The folders the panels showed, for Jump to Folder (⌘G).
  final FolderFrecency frecency;

  /// The commands the palette ran lately, the newest first.
  final RecentItems recentCommands;

  /// What this desktop offers beyond the core: Quick Look, the share
  /// picker, files dragged to and from other applications.
  final PlatformServices platformServices;

  // ─── Operations stream ───
  final FolderSyncService folderSync;
  final ChecksumService checksums;
  final DuplicatesService duplicates;

  // ─── Network ───
  final NetworkService network;

  /// Addresses Connect to Server reached lately, never with a password.
  final RecentItems recentServers;
  final SideStorage? sideStorage;
  final SavedProfiles<FindRequest>? savedSearches;
  final ThumbnailProvider? thumbnails;

  /// The desktop the app runs on; the default chords follow its
  /// conventions.
  final TargetPlatform platform;

  /// How the window is framed on this desktop (who draws the title bar).
  final WindowFrame windowFrame;
  final ResourceDisposer _resourceDisposer;

  /// The platform's defaults, Vim keys when enabled, then the user's
  /// overrides. Read on every build of the window, so it is rebuilt only
  /// when one of those preferences changed (the overrides map is replaced,
  /// never mutated).
  ShortcutMap get shortcutMap {
    final preferences = preferencesService.current;
    final vim = preferences.vimMode;
    final overrides = preferences.shortcutOverrides;
    if (_shortcutMap case (final builtVim, final builtFrom, final map)
        when builtVim == vim && identical(builtFrom, overrides)) {
      return map;
    }
    final map = ShortcutMap.forUser(
      platform,
      vimMotions: vim,
      overrides: overrides,
      unavailable: unavailableCommands,
    );
    _shortcutMap = (vim, overrides, map);
    return map;
  }

  (bool, Map<String, List<String>>, ShortcutMap)? _shortcutMap;

  /// The commands this desktop cannot run: unbound, and left out of the
  /// menus, the palette, the cheat sheet and the hotkeys.
  late final Set<AppCommand> unavailableCommands = unavailableCommandsFor(
    platformServices.capabilities,
    files.capabilities(),
  );

  Future<void> dispose() => _resourceDisposer.dispose();

  Future<void> disposeAfterBootstrapFailure() =>
      _resourceDisposer.dispose(rollback: true);
}

/// The commands whose capability the desktop's services ([platform]) or
/// the core ([core]) lack.
Set<AppCommand> unavailableCommandsFor(
  PlatformCapabilities platform,
  Capabilities core,
) => Set.unmodifiable({
  if (!platform.quickLook) AppCommand.quickLook,
  if (!platform.share) AppCommand.share,
  if (!core.finderTags) AppCommand.editTags,
});
