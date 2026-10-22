import 'app_command.dart';

/// Where a command sits among the window's commands, as a menu bar would
/// group them: the command palette's groups and the muted word beside a
/// command there.
enum CommandSection {
  file,
  edit,
  view,
  go,
  command,
  window,

  /// The single keys of a file panel.
  panel,

  /// Keys of Vim mode.
  vim,
  viewer,

  /// The integrated terminal: where it is, and its own keys.
  terminal,
  lists,
  dialogs,
}

extension AppCommandSection on AppCommand {
  /// The section the command belongs to: the one whose first command
  /// comes last at or before it in [AppCommand.values]. A command added at
  /// the end of its block of the enum lands in that block's section.
  CommandSection get section {
    if (_placed[this] case final section?) return section;
    var found = CommandSection.file;
    for (final (first, section) in _starts) {
      if (first.index > index) break;
      found = section;
    }
    return found;
  }
}

/// The first command of each block of [AppCommand], in order.
const _starts = [
  (AppCommand.newFolder, CommandSection.file),
  (AppCommand.copyPaths, CommandSection.edit),
  (AppCommand.toggleSinglePane, CommandSection.view),
  (AppCommand.goToLeftPanel, CommandSection.go),
  (AppCommand.fileAttributes, CommandSection.command),
  (AppCommand.focusLeftPanel, CommandSection.window),
  (AppCommand.moveUp, CommandSection.panel),
  (AppCommand.vimVisual, CommandSection.vim),
  (AppCommand.viewerText, CommandSection.viewer),
  (AppCommand.terminalCopy, CommandSection.terminal),
  (AppCommand.renameItem, CommandSection.lists),
  (AppCommand.confirm, CommandSection.dialogs),
];

/// Commands of a stream's own block that belong to another section than
/// the block they sit in.
const _placed = {
  AppCommand.jumpToFolder: CommandSection.go,
  AppCommand.addToShelf: CommandSection.edit,
  AppCommand.toggleShelf: CommandSection.view,
  AppCommand.renameInEditor: CommandSection.command,
  // Where Finder has them.
  AppCommand.quickLook: CommandSection.file,
  AppCommand.share: CommandSection.file,
  AppCommand.toggleTerminal: CommandSection.terminal,
  AppCommand.showTerminal: CommandSection.terminal,
  AppCommand.hideTerminal: CommandSection.terminal,
  AppCommand.togglePanelsOverTerminal: CommandSection.terminal,
  AppCommand.undo: CommandSection.edit,
  AppCommand.redo: CommandSection.edit,
  AppCommand.extractTo: CommandSection.file,
  AppCommand.editTags: CommandSection.file,
  AppCommand.toggleFlatView: CommandSection.view,
};
