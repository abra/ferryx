import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

/// The macOS menu uses the same command handlers as the keyboard and the
/// palette. Focus changes update availability without rebuilding the window.
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({required this.shortcutMap, required this.child, super.key});

  final ShortcutMap shortcutMap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.macOS) return child;
    return ListenableBuilder(
      listenable: FocusManager.instance,
      child: child,
      builder: (context, child) => PlatformMenuBar(
        menus: _Menus(context, shortcutMap).build(),
        child: child,
      ),
    );
  }
}

class _Menus {
  _Menus(this.context, this.map);

  final BuildContext context;
  final ShortcutMap map;
  FerryxLocalizations get l10n => context.l10n;
  final BuildContext? target = FocusManager.instance.primaryFocus?.context;
  late final commands = target == null ? <AppCommand>{} : commandsAt(target!);
  late final editing =
      target?.findAncestorStateOfType<EditableTextState>() != null;
  late final terminal = commands.contains(AppCommand.terminalCopy);

  bool _handles(AppCommand command) {
    return map.isAvailable(command) && commands.contains(command);
  }

  void _invoke(AppCommand command) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null || !map.isAvailable(command)) return;
    KeySequenceState.clear();
    invokeCommand(focused, command);
  }

  MenuSerializableShortcut? _shortcut(AppCommand command) {
    final chord = map.primaryChord(command);
    // Native key equivalents bypass Flutter's inner shortcut scopes.
    // Fields keep their editing keys and terminals keep shell control keys;
    // the usual Flutter dispatch still handles window chords there.
    if (chord == null || chord.prefix != null || editing) return null;
    if (terminal && !chord.reachesWindowFromTerminal(TargetPlatform.macOS)) {
      return null;
    }
    return chord.toActivator(TargetPlatform.macOS);
  }

  PlatformMenuItem _command(AppCommand command) => PlatformMenuItem(
    label: l10n.commandLabel(command),
    shortcut: _shortcut(command),
    onSelected: _handles(command) ? () => _invoke(command) : null,
  );

  PlatformMenuItemGroup _group(List<AppCommand> commands) =>
      PlatformMenuItemGroup(
        members: [
          for (final command in commands)
            if (map.isAvailable(command)) _command(command),
        ],
      );

  PlatformMenu _section(
    CommandSection section,
    List<List<AppCommand>> groups,
  ) => PlatformMenu(
    label: l10n.sectionLabel(section),
    menus: [
      for (final commands in groups)
        if (commands.any(map.isAvailable)) _group(commands),
    ],
  );

  PlatformMenuItem _textItem(String label, Intent intent, Chord chord) =>
      PlatformMenuItem(
        label: label,
        shortcut: chord.toActivator(TargetPlatform.macOS),
        onSelected: editing
            ? () {
                final focused = FocusManager.instance.primaryFocus?.context;
                if (focused != null &&
                    focused.findAncestorStateOfType<EditableTextState>() !=
                        null) {
                  Actions.maybeInvoke(focused, intent);
                }
              }
            : null,
      );

  PlatformMenuItem _edit(
    AppCommand command,
    Intent intent,
    Chord chord, {
    AppCommand? terminalCommand,
  }) {
    final resolved = terminal && terminalCommand != null
        ? terminalCommand
        : command;
    return PlatformMenuItem(
      label: l10n.commandLabel(resolved),
      shortcut: editing
          ? chord.toActivator(TargetPlatform.macOS)
          : _shortcut(resolved),
      onSelected: editing || _handles(resolved)
          ? () => _invokeEdit(command, intent, terminalCommand)
          : null,
    );
  }

  void _invokeEdit(
    AppCommand command,
    Intent intent,
    AppCommand? terminalCommand,
  ) {
    // Recheck at activation: focus can change before the next menu update.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return;
    if (focused.findAncestorStateOfType<EditableTextState>() != null) {
      Actions.maybeInvoke(focused, intent);
    } else {
      _invoke(
        terminalCommand != null && canInvokeCommand(focused, terminalCommand)
            ? terminalCommand
            : command,
      );
    }
  }

  List<PlatformMenuItem> build() => [
    PlatformMenu(
      label: l10n.appTitle,
      menus: [
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
          ],
        ),
        _group([AppCommand.openSettings]),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ],
        ),
        const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
      ],
    ),
    _section(CommandSection.file, const [
      [
        AppCommand.newFolder,
        AppCommand.newFile,
        AppCommand.newFolderWithSelection,
      ],
      [
        AppCommand.newTab,
        AppCommand.closeTab,
        AppCommand.closeOtherTabs,
        AppCommand.reopenClosedTab,
      ],
      [
        AppCommand.openItem,
        AppCommand.openWith,
        AppCommand.quickLook,
        AppCommand.internalViewer,
        AppCommand.externalEditor,
      ],
      [
        AppCommand.copyTo,
        AppCommand.moveTo,
        AppCommand.duplicate,
        AppCommand.renameInPlace,
        AppCommand.moveToTrash,
      ],
      [
        AppCommand.compress,
        AppCommand.extractTo,
        AppCommand.share,
        AppCommand.fileAttributes,
      ],
    ]),
    PlatformMenu(
      label: l10n.sectionLabel(CommandSection.edit),
      menus: [
        PlatformMenuItemGroup(
          members: [
            _edit(
              AppCommand.undo,
              const UndoTextIntent(SelectionChangedCause.toolbar),
              const Chord(LogicalKeyboardKey.keyZ, primary: true),
            ),
            _edit(
              AppCommand.redo,
              const RedoTextIntent(SelectionChangedCause.toolbar),
              const Chord(LogicalKeyboardKey.keyZ, primary: true, shift: true),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            _textItem(
              MaterialLocalizations.of(context).cutButtonLabel,
              const CopySelectionTextIntent.cut(SelectionChangedCause.toolbar),
              const Chord(LogicalKeyboardKey.keyX, primary: true),
            ),
            _edit(
              AppCommand.copyPaths,
              CopySelectionTextIntent.copy,
              const Chord(LogicalKeyboardKey.keyC, primary: true),
              terminalCommand: AppCommand.terminalCopy,
            ),
            _edit(
              AppCommand.pasteItems,
              const PasteTextIntent(SelectionChangedCause.toolbar),
              const Chord(LogicalKeyboardKey.keyV, primary: true),
              terminalCommand: AppCommand.terminalPaste,
            ),
            _command(AppCommand.moveItemsHere),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            _edit(
              AppCommand.selectAll,
              const SelectAllTextIntent(SelectionChangedCause.toolbar),
              const Chord(LogicalKeyboardKey.keyA, primary: true),
              terminalCommand: AppCommand.terminalSelectAll,
            ),
            _command(AppCommand.deselectAll),
            _command(AppCommand.invertSelection),
            _command(AppCommand.selectWithMask),
          ],
        ),
        _group([
          AppCommand.copyItemName,
          AppCommand.copyItemPath,
          AppCommand.copyItemDirectory,
          AppCommand.addToShelf,
        ]),
      ],
    ),
    PlatformMenu(
      label: l10n.sectionLabel(CommandSection.view),
      menus: [
        _group([AppCommand.commandPalette]),
        PlatformMenu(
          label: l10n.layoutMenuTitle,
          menus: [
            _group([
              AppCommand.viewMode1,
              AppCommand.viewMode2,
              AppCommand.viewMode3,
              AppCommand.viewMode4,
              AppCommand.viewMode5,
            ]),
          ],
        ),
        PlatformMenu(
          label: l10n.sortMenuTitle,
          menus: [
            _group([
              AppCommand.sortByName,
              AppCommand.sortByExtension,
              AppCommand.sortBySize,
              AppCommand.sortByModified,
              AppCommand.sortByCreated,
              AppCommand.sortByAdded,
              AppCommand.sortByAccessed,
            ]),
            _group([
              AppCommand.toggleFoldersFirst,
              AppCommand.toggleExtensionlessFolders,
            ]),
          ],
        ),
        _group([
          AppCommand.toggleHiddenFiles,
          AppCommand.toggleFlatView,
          AppCommand.toggleTabBar,
          AppCommand.refresh,
        ]),
        _group([
          AppCommand.toggleSinglePane,
          AppCommand.togglePanelsStacked,
          AppCommand.swapPanels,
          AppCommand.toggleShelf,
          AppCommand.toggleOperations,
        ]),
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.toggleFullScreen,
        ),
      ],
    ),
    _section(CommandSection.go, const [
      [
        AppCommand.goBack,
        AppCommand.goForward,
        AppCommand.goEnclosingFolder,
        AppCommand.goInto,
      ],
      [
        AppCommand.goHome,
        AppCommand.goDocuments,
        AppCommand.goDesktop,
        AppCommand.goDownloads,
        AppCommand.goRoot,
      ],
      [AppCommand.jumpToFolder, AppCommand.goToFolder, AppCommand.findFiles],
      [
        AppCommand.quickListFavorites,
        AppCommand.addToFavorites,
        AppCommand.manageFavorites,
      ],
      [AppCommand.connectToServer, AppCommand.disconnectServer],
    ]),
    _section(CommandSection.command, const [
      [
        AppCommand.compareFolders,
        AppCommand.synchronizeFolders,
        AppCommand.findDuplicates,
      ],
      [
        AppCommand.batchRename,
        AppCommand.renameInEditor,
        AppCommand.checksums,
        AppCommand.editTags,
      ],
    ]),
    _section(CommandSection.terminal, const [
      [
        AppCommand.toggleTerminal,
        AppCommand.showTerminal,
        AppCommand.hideTerminal,
        AppCommand.togglePanelsOverTerminal,
      ],
      [AppCommand.terminalClear],
    ]),
    PlatformMenu(
      label: l10n.sectionLabel(CommandSection.window),
      menus: [
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
          ],
        ),
        _group([AppCommand.previousTab, AppCommand.nextTab]),
        _group([AppCommand.focusLeftPanel, AppCommand.focusRightPanel]),
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
        ),
      ],
    ),
    PlatformMenu(
      label: l10n.menuHelp,
      menus: [
        _group([AppCommand.cheatSheet, AppCommand.hintMode]),
      ],
    ),
  ];
}
