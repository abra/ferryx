// Navigation composition root.
//
// The only place that composes features: routes inject repositories and
// services into Screen entry points, and features express navigation as
// callbacks handled here.

import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx/app/dependency_container.dart';
import 'package:ferryx/app/dialog_page.dart';
import 'package:ferryx/app/terminal_link.dart';
import 'package:ferryx/app/window_chrome.dart';
import 'package:checksums_feature/checksums_feature.dart';
import 'package:duplicates_feature/duplicates_feature.dart';
import 'package:find_feature/find_feature.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:network_feature/network_feature.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:settings_feature/settings_feature.dart';
import 'package:sync_feature/sync_feature.dart';
import 'package:terminal_feature/terminal_feature.dart';
import 'package:viewer_feature/viewer_feature.dart';

/// Route paths.
abstract final class AppRoutes {
  static const root = '/';
  static const workspace = '/workspace';
  static const viewer = '/viewer';
  static const settings = '/settings';
}

/// What the viewer route carries; passed as `extra` so paths stay out of
/// URLs.
class ViewerRouteArguments {
  const ViewerRouteArguments(this.location, {this.preview = false});

  final Location location;
  final bool preview;
}

GoRouter buildRouter({
  required DependenciesContainer deps,
  required WindowTitle windowTitle,
}) {
  final rootNavigator = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootNavigator,
    initialLocation: AppRoutes.root,
    debugLogDiagnostics: false,
    redirect: (context, state) =>
        state.uri.path == AppRoutes.root ? AppRoutes.workspace : null,
    routes: [
      GoRoute(
        path: AppRoutes.root,
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: AppRoutes.workspace,
        builder: (context, state) =>
            _WorkspaceRoute(deps: deps, windowTitle: windowTitle),
      ),
      GoRoute(
        path: AppRoutes.viewer,
        // The viewer takes the whole window over the panels, at once and
        // with no scrim; Esc closes it and the keys go back to the panel.
        pageBuilder: (context, state) {
          final args = state.extra! as ViewerRouteArguments;
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: ViewerScreen(
              files: deps.files,
              preferences: deps.preferencesService,
              shortcutMap: deps.shortcutMap,
              windowDecor: windowDecor(deps.windowFrame),
              location: args.location,
              startInPreview: args.preview,
              onClose: () => context.pop(),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        // A modal over the workspace.
        pageBuilder: (context, state) => DialogPage<void>(
          key: state.pageKey,
          builder: (context) => SettingsScreen(
            preferencesService: deps.preferencesService,
            platform: deps.platform,
            version: deps.packageInfo.version,
            unavailableCommands: deps.unavailableCommands,
            initialSection: state.extra is SettingsSection
                ? state.extra! as SettingsSection
                : SettingsSection.general,
            defaultShell: deps.terminal.defaultShell(),
            loadMonospaceFonts: deps.platformServices.monospaceFontFamilies,
            onClose: () => context.pop(),
          ),
        ),
      ),
    ],
  );
}

/// Opens the settings window on [section].
Future<void> openSettings(
  BuildContext context, [
  SettingsSection section = SettingsSection.general,
]) => context.push<void>(AppRoutes.settings, extra: section);

/// The workspace route: the two panels over the file system, wired to the
/// app's services and to the routes it opens.
class _WorkspaceRoute extends StatelessWidget {
  const _WorkspaceRoute({required this.deps, required this.windowTitle});

  final DependenciesContainer deps;
  final WindowTitle windowTitle;

  @override
  Widget build(BuildContext context) {
    final preferences = deps.preferencesService.current;
    final saved = preferences.panelState;
    final home = deps.files.standardFolders().home;
    return WindowTitleIntegration(
      title: windowTitle,
      // ─── Network ───
      // The questions a connection asks (a host key, a password) come here
      // from wherever it is made.
      child: NetworkPromptHost(
        service: deps.network,
        child: WorkspaceScreen(
          files: deps.files,
          operations: deps.operations,
          rename: deps.rename,
          platformServices: deps.platformServices,
          capabilities: deps.files.capabilities(),
          preferences: deps.preferencesService,
          logger: deps.logger,
          shortcutMap: deps.shortcutMap,
          windowDecor: windowDecor(deps.windowFrame),
          savedLeft: SavedPanel.decode(saved[PanelSide.left.key]),
          savedRight: SavedPanel.decode(saved[PanelSide.right.key]),
          savedActive: saved['active'] == PanelSide.right.name
              ? PanelSide.right
              : PanelSide.left,
          fallbackLocation: Location.native(home),
          frecency: deps.frecency,
          terminal: WorkspaceTerminal(
            create: () => TerminalLink(
              service: deps.terminal,
              preferences: deps.preferencesService,
              platform: deps.platform,
            ),
            builder: (context, controller, view) => TerminalPane(
              cubit: TerminalLink.of(controller).cubit,
              focusNode: view.focusNode,
              shortcutMap: deps.shortcutMap,
              fontSize: deps.preferencesService.current.terminal.fontSize,
              fontFamily: deps.preferencesService.current.terminal.fontFamily,
              placement: TerminalPlacement(
                panelsHidden: view.panelsHidden,
                fullWindow: view.fullWindow,
                decor: view.decor,
              ),
              onHide: view.onHide,
              onTogglePanels: view.onTogglePanels,
              onToggleFullWindow: view.onToggleFullWindow,
            ),
          ),
          onSnapshot: (snapshot) {
            windowTitle.location =
                (snapshot.active == PanelSide.left
                        ? snapshot.left
                        : snapshot.right)
                    .tabs
                    .elementAtOrNull(
                      snapshot.active == PanelSide.left
                          ? snapshot.left.activeIndex
                          : snapshot.right.activeIndex,
                    )
                    ?.location
                    .name;
            unawaited(
              deps.preferencesService.update(
                (p) => p.copyWith(
                  panelState: {
                    PanelSide.left.key: snapshot.left.encode(),
                    PanelSide.right.key: snapshot.right.encode(),
                    'active': snapshot.active.name,
                  },
                  singlePane: snapshot.singlePane,
                  splitFraction: snapshot.splitFraction,
                ),
              ),
            );
          },
          navigation: WorkspaceNavigation(
            openViewer: (context, location, {bool preview = false}) =>
                context.push<void>(
                  AppRoutes.viewer,
                  extra: ViewerRouteArguments(location, preview: preview),
                ),
            openFind: (context, root, {required view}) => showFindDialog(
              context,
              root: root,
              find: deps.find,
              onView: view,
              spotlight: deps.files.capabilities().spotlight,
            ),
            openSettings: (context) => openSettings(context),
            openCheatSheet: (context) => showCheatSheet(
              context,
              shortcutMap: deps.shortcutMap,
              platform: deps.platform,
              vim: deps.preferencesService.current.vimMode,
            ),
            // ─── Operations stream ───
            openSync: (context, {required left, required right}) {
              final prefs = deps.preferencesService.current;
              return showSyncDialog(
                context,
                left: left,
                right: right,
                service: deps.folderSync,
                options: prefs.compareOptions,
                onOptions: (options) => unawaited(
                  deps.preferencesService.update(
                    (p) => p.copyWith(compareOptions: options),
                  ),
                ),
                preserveAttributes: prefs.preserveAttributes,
                verify: prefs.verifyCopies,
                shortcutMap: deps.shortcutMap,
              );
            },
            openChecksums:
                (context, {required paths, required base, algorithm}) =>
                    showChecksumsDialog(
                      context,
                      paths: paths,
                      base: base,
                      algorithm: algorithm,
                      service: deps.checksums,
                    ),
            openDuplicates: (context, {required root, other}) =>
                showDuplicatesDialog(
                  context,
                  root: root,
                  other: other,
                  service: deps.duplicates,
                  operations: deps.operations,
                  shortcutMap: deps.shortcutMap,
                ),
          ),
          folderSync: deps.folderSync,
          network: _network(),
        ),
      ),
    );
  }

  // ─── Network ───

  /// The window's servers: the core's connections and the dialogs of the
  /// network feature that make them.
  WorkspaceNetwork _network() {
    final connector = ServerConnector(
      service: deps.network,
      servers: () => deps.preferencesService.current.servers,
    );
    return WorkspaceNetwork(
      service: deps.network,
      connectToServer: (context) => showConnectDialog(
        context,
        service: deps.network,
        servers: deps.preferencesService.current.servers,
        onServersChanged: (servers) => unawaited(
          deps.preferencesService.update((p) => p.copyWith(servers: servers)),
        ),
        shortcutMap: deps.shortcutMap,
        recent: deps.recentServers.items,
        onRecent: (address) => unawaited(deps.recentServers.record(address)),
      ),
      connectServer: connector.reconnect,
      connectProfile: connector.connect,
      connectAddress: connector.connectAddress,
    );
  }
}
