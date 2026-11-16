import 'package:shortcuts/shortcuts.dart';

import '../native/quick_look_pick.dart';
import '../panel/panel_state.dart';

enum PanelActionTarget { targets, focusedItem, directory }

enum PanelActionGroup {
  open,
  clipboard,
  transfer,
  rename,
  archive,
  inspect,
  organize,
  selection,
  folder,
  shelf,
}

/// One executable continuation, with the same target rules as its handler.
/// A binding is optional: menus must retain actions the user has unbound.
class PanelAction {
  const PanelAction(
    this.command, {
    required this.target,
    required this.group,
    this.labelCommand,
  });

  final AppCommand command;
  final PanelActionTarget target;
  final PanelActionGroup group;
  final AppCommand? labelCommand;
}

/// Synchronous presentation facts supplied by the workspace. Building an
/// inventory never reads the clipboard, discovers tools or touches files.
class PanelActionContext {
  const PanelActionContext({
    required this.tab,
    required this.shortcuts,
    this.opposite,
    this.vim = false,
    this.hasShelf = false,
    this.hasArchives = false,
    this.finderTags = false,
    this.isFavorite = false,
    this.comparisonAvailable = false,
    this.deletionPending = false,
  });

  final PanelTabState? tab;
  final ShortcutMap shortcuts;
  final PanelTabState? opposite;
  final bool vim;
  final bool hasShelf;

  /// At least one target is known to be an archive. Extraction can perform
  /// further format detection when invoked, independently of this inventory.
  final bool hasArchives;
  final bool finderTags;
  final bool isFavorite;
  final bool comparisonAvailable;
  final bool deletionPending;
}

/// Contextual file actions, independent of Normal/Visual/search presentation.
/// Guards mirror workspace handlers; filesystem permissions and clipboard
/// contents remain validated by those handlers when an action is invoked.
List<PanelAction> panelActionsFor(PanelActionContext context) {
  final tab = context.tab;
  if (tab == null) return const [];
  final native = tab.location.isNative;
  final remote = tab.location.isRemote;
  final writable = native || remote;
  final targets = tab.targets;
  final focused = tab.focused;
  final item = focused != null && !focused.isParent ? focused : null;
  final hasRows = tab.rows.any((row) => !row.isParent);
  final actions = <PanelAction>[];
  void add(
    AppCommand command,
    PanelActionTarget target,
    PanelActionGroup group, {
    AppCommand? labelCommand,
  }) {
    if (!context.shortcuts.isAvailable(command) ||
        (command.isVimOnly && !context.vim)) {
      return;
    }
    actions.add(
      PanelAction(
        command,
        target: target,
        group: group,
        labelCommand: labelCommand,
      ),
    );
  }

  if (item != null) {
    for (final command in [
      AppCommand.toggleSelection,
      AppCommand.toggleSelectionMoveDown,
    ]) {
      add(command, PanelActionTarget.focusedItem, PanelActionGroup.selection);
    }
    add(
      AppCommand.enterItem,
      PanelActionTarget.focusedItem,
      PanelActionGroup.open,
    );
    add(
      AppCommand.openItem,
      PanelActionTarget.focusedItem,
      PanelActionGroup.open,
    );
    if (!item.isDir) {
      add(
        AppCommand.preview,
        PanelActionTarget.focusedItem,
        PanelActionGroup.open,
      );
      add(
        AppCommand.internalViewer,
        PanelActionTarget.focusedItem,
        PanelActionGroup.open,
      );
      if (writable) {
        add(
          AppCommand.externalEditor,
          PanelActionTarget.focusedItem,
          PanelActionGroup.open,
        );
      }
    }
    if (native) {
      add(
        AppCommand.openWith,
        PanelActionTarget.focusedItem,
        PanelActionGroup.open,
      );
      add(
        AppCommand.revealInFileManager,
        PanelActionTarget.focusedItem,
        PanelActionGroup.open,
      );
      add(
        AppCommand.createSymlink,
        PanelActionTarget.focusedItem,
        PanelActionGroup.organize,
      );
      if (!item.isDir) {
        add(
          AppCommand.createHardlink,
          PanelActionTarget.focusedItem,
          PanelActionGroup.organize,
        );
      }
      if (item.isSymlink) {
        add(
          AppCommand.editSymlink,
          PanelActionTarget.focusedItem,
          PanelActionGroup.organize,
        );
        add(
          AppCommand.followSymlink,
          PanelActionTarget.focusedItem,
          PanelActionGroup.open,
        );
      }
    }
    if (writable) {
      add(
        AppCommand.renameInPlace,
        PanelActionTarget.focusedItem,
        PanelActionGroup.rename,
      );
    }
    add(
      AppCommand.revealInOppositePanel,
      PanelActionTarget.focusedItem,
      PanelActionGroup.open,
    );
    add(
      AppCommand.revealInOppositeTab,
      PanelActionTarget.focusedItem,
      PanelActionGroup.open,
    );
  } else if (focused?.isParent == true) {
    add(
      AppCommand.enterItem,
      PanelActionTarget.focusedItem,
      PanelActionGroup.open,
      labelCommand: AppCommand.goEnclosingFolder,
    );
  }

  if (targets.isNotEmpty) {
    for (final command in [
      AppCommand.copyItemName,
      AppCommand.copyItemPath,
      AppCommand.copyPaths,
    ]) {
      add(command, PanelActionTarget.targets, PanelActionGroup.clipboard);
    }
    // This command intentionally copies only the first target's folder.
    if (targets.length == 1) {
      add(
        AppCommand.copyItemDirectory,
        PanelActionTarget.targets,
        PanelActionGroup.clipboard,
      );
    }
    final quickLook = quickLookPick(tab);
    if (!remote &&
        !quickLook.isEmpty &&
        (quickLook.fromSelection || item != null)) {
      add(
        AppCommand.quickLook,
        quickLook.fromSelection
            ? PanelActionTarget.targets
            : PanelActionTarget.focusedItem,
        PanelActionGroup.open,
      );
    }
    if (native || (!remote && targets.any((entry) => !entry.isDir))) {
      add(AppCommand.share, PanelActionTarget.targets, PanelActionGroup.open);
    }
    if (writable) {
      add(
        AppCommand.copyTo,
        PanelActionTarget.targets,
        PanelActionGroup.transfer,
      );
      add(
        AppCommand.moveTo,
        PanelActionTarget.targets,
        PanelActionGroup.transfer,
      );
      if (targets.length == 1) {
        add(
          AppCommand.copyAs,
          PanelActionTarget.targets,
          PanelActionGroup.transfer,
        );
        add(
          AppCommand.moveAs,
          PanelActionTarget.targets,
          PanelActionGroup.transfer,
        );
      }
      if (targets.any((entry) => entry.isDir && !entry.isSymlink)) {
        add(
          AppCommand.calcFolderSizes,
          PanelActionTarget.targets,
          PanelActionGroup.inspect,
        );
      }
      if (!context.deletionPending) {
        if (native) {
          add(
            AppCommand.moveToTrash,
            PanelActionTarget.targets,
            PanelActionGroup.organize,
          );
        }
        add(
          AppCommand.deletePermanently,
          PanelActionTarget.targets,
          PanelActionGroup.organize,
        );
      }
    }
    if (native) {
      for (final command in [
        AppCommand.duplicate,
        AppCommand.newFolderWithSelection,
      ]) {
        add(command, PanelActionTarget.targets, PanelActionGroup.organize);
      }
      add(
        AppCommand.batchRename,
        PanelActionTarget.targets,
        PanelActionGroup.rename,
      );
      for (final command in [AppCommand.compress, AppCommand.compressTo]) {
        add(command, PanelActionTarget.targets, PanelActionGroup.archive);
      }
      for (final command in [AppCommand.checksums, AppCommand.fileAttributes]) {
        add(command, PanelActionTarget.targets, PanelActionGroup.inspect);
      }
      add(
        AppCommand.addToShelf,
        PanelActionTarget.targets,
        PanelActionGroup.shelf,
      );
      if (context.vim) {
        add(
          AppCommand.vimYank,
          PanelActionTarget.targets,
          PanelActionGroup.shelf,
        );
        add(
          AppCommand.vimCut,
          PanelActionTarget.targets,
          PanelActionGroup.shelf,
        );
      }
      if (context.finderTags) {
        add(
          AppCommand.editTags,
          PanelActionTarget.targets,
          PanelActionGroup.organize,
        );
      }
    }
    if (!remote && (!native || context.hasArchives)) {
      add(
        AppCommand.extractTo,
        PanelActionTarget.targets,
        PanelActionGroup.archive,
      );
    }
  }

  if (native && !tab.isVirtual && hasRows) {
    add(
      AppCommand.renameInEditor,
      tab.selected.isEmpty
          ? PanelActionTarget.directory
          : PanelActionTarget.targets,
      PanelActionGroup.rename,
    );
  }
  if (context.hasShelf) {
    add(
      AppCommand.toggleShelf,
      PanelActionTarget.directory,
      PanelActionGroup.shelf,
    );
    if (context.vim) {
      add(
        AppCommand.vimCancelRegister,
        PanelActionTarget.directory,
        PanelActionGroup.shelf,
      );
      if (native) {
        add(
          AppCommand.vimPaste,
          PanelActionTarget.directory,
          PanelActionGroup.shelf,
        );
      }
    }
  }
  if (context.comparisonAvailable) {
    final other = context.opposite;
    final second = other?.focused;
    final selectedPair =
        tab.selected.length == 2 &&
        targets.length == 2 &&
        targets.every((entry) => !entry.isDir && !entry.isParent);
    final cursorPair =
        tab.selected.isEmpty &&
        (other?.selected.isEmpty ?? false) &&
        item != null &&
        !item.isDir &&
        second != null &&
        !second.isDir &&
        !second.isParent;
    if (selectedPair || cursorPair) {
      add(
        AppCommand.compareFiles,
        selectedPair
            ? PanelActionTarget.targets
            : PanelActionTarget.focusedItem,
        PanelActionGroup.inspect,
      );
    }
  }
  if (writable) {
    for (final command in [
      AppCommand.newFolder,
      AppCommand.newFile,
      AppCommand.createDirectory,
    ]) {
      add(command, PanelActionTarget.directory, PanelActionGroup.folder);
    }
    // Clipboard data is read on invocation, never while rendering a menu.
    add(
      AppCommand.pasteItems,
      PanelActionTarget.directory,
      PanelActionGroup.clipboard,
    );
    add(
      AppCommand.moveItemsHere,
      PanelActionTarget.directory,
      PanelActionGroup.clipboard,
    );
    if (tab.rows.any((row) => row.isDir && !row.isParent && !row.isSymlink)) {
      add(
        AppCommand.calcAllFolderSizes,
        PanelActionTarget.directory,
        PanelActionGroup.inspect,
      );
    }
  }
  add(
    context.isFavorite
        ? AppCommand.removeFromFavorites
        : AppCommand.addToFavorites,
    item?.isDir == true
        ? PanelActionTarget.focusedItem
        : PanelActionTarget.directory,
    PanelActionGroup.organize,
  );
  if (hasRows) {
    for (final command in [
      AppCommand.selectAll,
      AppCommand.invertSelection,
      AppCommand.selectWithMask,
    ]) {
      add(command, PanelActionTarget.directory, PanelActionGroup.selection);
    }
  }
  if (tab.selected.isNotEmpty) {
    add(
      AppCommand.deselectAll,
      PanelActionTarget.targets,
      PanelActionGroup.selection,
    );
    add(
      AppCommand.deselectWithMask,
      PanelActionTarget.targets,
      PanelActionGroup.selection,
    );
  }
  if (item != null && !item.isDir) {
    add(
      AppCommand.selectWithExtension,
      PanelActionTarget.focusedItem,
      PanelActionGroup.selection,
    );
    if (tab.selected.isNotEmpty) {
      add(
        AppCommand.deselectWithExtension,
        PanelActionTarget.targets,
        PanelActionGroup.selection,
      );
    }
  }
  return List.unmodifiable(actions);
}
