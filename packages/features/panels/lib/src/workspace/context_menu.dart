import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shortcuts/shortcuts.dart';

/// What a right click on a row offers; every item is a command the
/// window handles, so the menu and the keys never disagree. Every item
/// carries an icon, so the labels line up.
List<AppMenuEntry<AppCommand>> rowMenuEntries(
  BuildContext context, {
  required FileEntry entry,
  required Location location,
  required bool severalSelected,
  required ShortcutMap map,
  bool archive = false,
}) {
  final l10n = context.l10n;
  final platform = Theme.of(context).platform;
  String? chord(AppCommand command) => map.labelOf(command, platform);
  AppMenuAction<AppCommand> action(
    AppCommand command,
    String label, {
    required IconData icon,
    bool danger = false,
  }) => AppMenuAction(
    value: command,
    label: label,
    icon: icon,
    shortcut: chord(command),
    danger: danger,
  );
  final native = location.isNative;
  final fileManager = switch (context.metrics.style.fileManager) {
    FileManager.finder => l10n.menuShowInFinder,
    FileManager.explorer => l10n.menuShowInExplorer,
    FileManager.files => l10n.menuShowInFiles,
  };
  return [
    if (entry.isDir)
      action(AppCommand.enterItem, l10n.cmdEnterItem, icon: AppIcons.folderOpen)
    else
      action(AppCommand.openItem, l10n.menuOpen, icon: AppIcons.externalLink),
    if (!entry.isDir && native)
      action(
        AppCommand.internalViewer,
        l10n.cmdInternalViewer,
        icon: AppIcons.preview,
      ),
    if (native && !entry.isDir)
      action(AppCommand.openWith, l10n.cmdOpenWith, icon: AppIcons.application),
    if (native)
      action(
        AppCommand.revealInFileManager,
        fileManager,
        icon: AppIcons.reveal,
      ),
    const AppMenuSeparator(),
    if (native) ...[
      action(AppCommand.copyTo, l10n.cmdCopyTo, icon: AppIcons.copy),
      action(AppCommand.moveTo, l10n.cmdMoveTo, icon: AppIcons.scissors),
      action(AppCommand.renameInPlace, l10n.actionRename, icon: AppIcons.edit),
      action(AppCommand.duplicate, l10n.cmdDuplicate, icon: AppIcons.documents),
      if (severalSelected)
        action(
          AppCommand.batchRename,
          l10n.cmdBatchRename,
          icon: AppIcons.numberedList,
        ),
      action(AppCommand.compress, l10n.cmdCompress, icon: AppIcons.fileArchive),
      if (archive && !entry.isDir)
        action(
          AppCommand.extractTo,
          l10n.cmdExtractTo,
          icon: AppIcons.fileArchive,
        ),
    ] else ...[
      action(
        AppCommand.copyTo,
        l10n.menuExtractToOpposite,
        icon: AppIcons.fileArchive,
      ),
    ],
    const AppMenuSeparator(),
    if (entry.isDir && native)
      action(
        AppCommand.addToFavorites,
        l10n.cmdAddToFavorites,
        icon: AppIcons.star,
      ),
    action(AppCommand.copyItemPath, l10n.menuCopyPath, icon: AppIcons.link),
    action(AppCommand.copyItemName, l10n.menuCopyName, icon: AppIcons.text),
    if (native) ...[
      const AppMenuSeparator(),
      action(
        AppCommand.fileAttributes,
        l10n.cmdFileAttributes,
        icon: AppIcons.lock,
      ),
      if (entry.isSymlink)
        action(
          AppCommand.editSymlink,
          l10n.cmdEditSymlink,
          icon: AppIcons.fileSymlink,
        ),
      const AppMenuSeparator(),
      action(AppCommand.moveToTrash, l10n.cmdMoveToTrash, icon: AppIcons.trash),
      action(
        AppCommand.deletePermanently,
        l10n.cmdDeletePermanently,
        icon: AppIcons.cancel,
        danger: true,
      ),
    ],
  ];
}

/// The panel's own menu (the ⋯ in its bar). An option that is on shows a
/// check mark; its icon stays the same either way.
List<AppMenuEntry<AppCommand>> panelMenuEntries(
  BuildContext context, {
  required bool showHidden,
  required bool singlePane,
  required bool native,
  required ShortcutMap map,
  bool flat = false,
}) {
  final l10n = context.l10n;
  final platform = Theme.of(context).platform;
  String? chord(AppCommand command) => map.labelOf(command, platform);
  return [
    AppMenuAction(
      value: AppCommand.newTab,
      label: l10n.cmdNewTab,
      icon: AppIcons.add,
      shortcut: chord(AppCommand.newTab),
    ),
    AppMenuAction(
      value: AppCommand.closeTab,
      label: l10n.cmdCloseTab,
      icon: AppIcons.close,
      shortcut: chord(AppCommand.closeTab),
    ),
    const AppMenuSeparator(),
    AppMenuAction(
      value: AppCommand.newFolder,
      label: l10n.menuNewFolder,
      icon: AppIcons.folder,
      shortcut: chord(AppCommand.newFolder),
      enabled: native,
    ),
    AppMenuAction(
      value: AppCommand.newFile,
      label: l10n.menuNewFile,
      icon: AppIcons.file,
      shortcut: chord(AppCommand.newFile),
      enabled: native,
    ),
    const AppMenuSeparator(),
    AppMenuAction(
      value: AppCommand.toggleHiddenFiles,
      label: l10n.cmdToggleHiddenFiles,
      icon: AppIcons.hidden,
      shortcut: chord(AppCommand.toggleHiddenFiles),
      checked: showHidden,
    ),
    AppMenuAction(
      value: AppCommand.refresh,
      label: l10n.cmdRefresh,
      icon: AppIcons.refresh,
      shortcut: chord(AppCommand.refresh),
    ),
    AppMenuAction(
      value: AppCommand.toggleFlatView,
      label: l10n.cmdToggleFlatView,
      icon: AppIcons.layoutList,
      shortcut: chord(AppCommand.toggleFlatView),
      checked: flat,
    ),
    AppMenuAction(
      value: AppCommand.toggleSinglePane,
      label: l10n.cmdToggleSinglePane,
      icon: AppIcons.singlePane,
      shortcut: chord(AppCommand.toggleSinglePane),
      checked: singlePane,
    ),
    const AppMenuSeparator(),
    AppMenuAction(
      value: AppCommand.addToFavorites,
      label: l10n.cmdAddToFavorites,
      icon: AppIcons.star,
      shortcut: chord(AppCommand.addToFavorites),
    ),
    AppMenuAction(
      value: AppCommand.manageFavorites,
      label: l10n.cmdManageFavorites,
      icon: AppIcons.bookmark,
      shortcut: chord(AppCommand.manageFavorites),
    ),
    const AppMenuSeparator(),
    AppMenuAction(
      value: AppCommand.cheatSheet,
      label: l10n.cmdCheatSheet,
      icon: AppIcons.keyboard,
      shortcut: chord(AppCommand.cheatSheet),
    ),
    AppMenuAction(
      value: AppCommand.openSettings,
      label: l10n.cmdOpenSettings,
      icon: AppIcons.settings,
      shortcut: chord(AppCommand.openSettings),
    ),
  ];
}
