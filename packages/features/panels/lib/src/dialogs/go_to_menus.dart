import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import '../path_text.dart';

/// A place the Go To pop-up or a quick list leads to.
sealed class GoToPick {
  const GoToPick();
}

class GoToLocation extends GoToPick {
  const GoToLocation(this.location);

  final Location location;
}

class GoToEject extends GoToPick {
  const GoToEject(this.mountPoint);

  final String mountPoint;
}

class GoToManageFavorites extends GoToPick {
  const GoToManageFavorites();
}

// ─── Network ───

/// A saved server, connected to with its way of logging in.
class GoToServer extends GoToPick {
  const GoToServer(this.server);

  final ServerProfile server;
}

/// Connect to Server, the dialog.
class GoToConnect extends GoToPick {
  const GoToConnect();
}

/// A location's path as a menu label: shortened in the middle when long,
/// its last two folders kept.
String _pathLabel(Location location) => PathText.shortened(location.display);

/// F1 / F2: favorites, volumes, the other panel's tabs and the history,
/// in one menu by [anchor]; typing filters by the menu's own type-select.
Future<GoToPick?> showGoToPopup(
  BuildContext context, {
  required Rect anchor,
  required List<Favorite> favorites,
  required List<Volume> volumes,
  required List<Location> otherPanel,
  required List<Location> history,
  List<ServerProfile>? servers,
}) {
  final l10n = context.l10n;
  final entries = <AppMenuEntry<GoToPick>>[
    AppMenuSection(l10n.sectionFavorites),
    for (final favorite in favorites)
      AppMenuAction(
        value: GoToLocation(favorite.location),
        label: favorite.label,
        icon: AppIcons.star,
      ),
    AppMenuAction(
      value: const GoToManageFavorites(),
      label: l10n.cmdManageFavorites,
      icon: AppIcons.bookmark,
    ),
    if (volumes.isNotEmpty) ...[
      AppMenuSection(l10n.sectionVolumes),
      for (final volume in volumes)
        AppMenuAction(
          value: GoToLocation(Location.native(volume.mountPoint)),
          label: volume.name,
          icon: volume.removable ? AppIcons.usb : AppIcons.hardDrive,
        ),
    ],
    // ─── Network ───
    // With servers at all: the saved ones, and the dialog for others.
    if (servers != null) ...[
      AppMenuSection(l10n.networkGoToServers),
      for (final server in servers)
        AppMenuAction(
          value: GoToServer(server),
          label: server.label,
          detail: server.displayRoot,
          icon: AppIcons.server,
        ),
      AppMenuAction(
        value: const GoToConnect(),
        label: l10n.cmdConnectToServer,
        icon: AppIcons.globe,
      ),
    ],
    if (otherPanel.isNotEmpty) ...[
      AppMenuSection(l10n.sectionOtherPanel),
      for (final location in otherPanel)
        AppMenuAction(
          value: GoToLocation(location),
          label: _pathLabel(location),
          icon: location.isRemote ? AppIcons.server : AppIcons.folder,
        ),
    ],
    if (history.isNotEmpty) ...[
      AppMenuSection(l10n.sectionHistory),
      for (final location in history.take(10))
        AppMenuAction(
          value: GoToLocation(location),
          label: _pathLabel(location),
          icon: AppIcons.history,
        ),
    ],
  ];
  return showAppMenu<GoToPick>(
    context: context,
    anchor: anchor,
    entries: entries,
    width: AppSizes.menuMaxWidth,
  );
}

/// ⌘1: the folders above the current one, the nearest first.
Future<GoToPick?> showParentsList(
  BuildContext context, {
  required Rect anchor,
  required Location current,
}) {
  final chain = current.ancestry.reversed.skip(1).toList();
  return showAppMenu<GoToPick>(
    context: context,
    anchor: anchor,
    width: AppSizes.menuMaxWidth,
    entries: [
      AppMenuSection(context.l10n.sectionParents),
      if (chain.isEmpty)
        AppMenuAction(
          value: GoToLocation(current),
          label: context.l10n.quickListEmpty,
          enabled: false,
        ),
      for (final location in chain)
        AppMenuAction(
          value: GoToLocation(location),
          label: _pathLabel(location),
          icon: AppIcons.folder,
        ),
    ],
  );
}

/// ⌘2: the places this panel has been, the latest first.
Future<GoToPick?> showHistoryList(
  BuildContext context, {
  required Rect anchor,
  required List<Location> history,
  required int historyIndex,
}) {
  final items = history.asMap().entries.toList().reversed.toList();
  return showAppMenu<GoToPick>(
    context: context,
    anchor: anchor,
    width: AppSizes.menuMaxWidth,
    entries: [
      AppMenuSection(context.l10n.sectionHistory),
      if (items.isEmpty)
        AppMenuAction(
          value: const GoToLocation(Location.native('/')),
          label: context.l10n.quickListEmpty,
          enabled: false,
        ),
      for (final entry in items.take(30))
        AppMenuAction(
          value: GoToLocation(entry.value),
          label: _pathLabel(entry.value),
          icon: AppIcons.history,
          checked: entry.key == historyIndex,
        ),
    ],
  );
}

/// ⌘3: the favorites.
Future<GoToPick?> showFavoritesList(
  BuildContext context, {
  required Rect anchor,
  required List<Favorite> favorites,
}) => showAppMenu<GoToPick>(
  context: context,
  anchor: anchor,
  width: AppSizes.menuMaxWidth,
  entries: [
    AppMenuSection(context.l10n.sectionFavorites),
    if (favorites.isEmpty)
      AppMenuAction(
        value: const GoToLocation(Location.native('/')),
        label: context.l10n.favoritesEmpty,
        enabled: false,
      ),
    for (final favorite in favorites)
      AppMenuAction(
        value: GoToLocation(favorite.location),
        label: favorite.label,
        icon: AppIcons.star,
      ),
    const AppMenuSeparator(),
    AppMenuAction(
      value: const GoToManageFavorites(),
      label: context.l10n.cmdManageFavorites,
      icon: AppIcons.bookmark,
    ),
  ],
);

/// ⌘4: the mounted volumes, each with its free space after the name as
/// the menu's secondary text; removable ones can be ejected.
Future<GoToPick?> showVolumesList(
  BuildContext context, {
  required Rect anchor,
  required List<Volume> volumes,
}) {
  final l10n = context.l10n;
  return showAppMenu<GoToPick>(
    context: context,
    anchor: anchor,
    width: AppSizes.menuMaxWidth,
    entries: [
      AppMenuSection(l10n.sectionVolumes),
      for (final volume in volumes)
        AppMenuAction(
          value: GoToLocation(Location.native(volume.mountPoint)),
          label: volume.name,
          detail: l10n.volumeFree(
            l10n.fileSize(volume.availableBytes),
            l10n.fileSize(volume.totalBytes),
          ),
          icon: volume.removable ? AppIcons.usb : AppIcons.hardDrive,
        ),
      if (volumes.any((v) => v.removable)) ...[
        const AppMenuSeparator(),
        for (final volume in volumes.where((v) => v.removable))
          AppMenuAction(
            value: GoToEject(volume.mountPoint),
            label: l10n.ejectVolume(volume.name),
            icon: AppIcons.eject,
          ),
      ],
    ],
  );
}
