/// Where a command is meaningful; used to group the cheat sheet and to pick
/// which bindings are active.
enum CommandScope {
  /// Chords with modifiers, live everywhere in the window.
  global,

  /// Single keys of a file panel (the arrows, Return, Backspace, Tab…),
  /// installed around the panels so typing elsewhere never triggers them.
  panel,

  /// The built-in viewer's own keys.
  viewer,

  /// Lists in dialogs and pop-ups.
  lists,
  dialogs,

  /// The integrated terminal's own keys (copy, paste, clear…), installed
  /// around it: inside it they win over the window's chords.
  terminal,
}

/// Every user action that can be bound to a key or run from a menu.
enum AppCommand {
  // ─── File ───
  newFolder(CommandScope.global),
  newFolderWithSelection(CommandScope.global),
  newFile(CommandScope.global),
  newTab(CommandScope.global),
  closeTab(CommandScope.global),
  closeOtherTabs(CommandScope.global),
  reopenClosedTab(CommandScope.global),
  nextTab(CommandScope.global),
  previousTab(CommandScope.global),
  toggleTabBar(CommandScope.global),
  openItem(CommandScope.global),
  revealInOppositePanel(CommandScope.global),
  revealInOppositeTab(CommandScope.global),
  calcFolderSizes(CommandScope.global),
  calcAllFolderSizes(CommandScope.global),
  duplicate(CommandScope.global),
  addToFavorites(CommandScope.global),
  manageFavorites(CommandScope.global),
  findFiles(CommandScope.global),

  // ─── Edit ───
  copyPaths(CommandScope.global),
  pasteItems(CommandScope.global),
  moveItemsHere(CommandScope.global),
  selectAll(CommandScope.global),
  deselectAll(CommandScope.global),
  invertSelection(CommandScope.global),
  selectWithMask(CommandScope.global),
  deselectWithMask(CommandScope.global),
  selectWithExtension(CommandScope.global),
  deselectWithExtension(CommandScope.global),

  // ─── View ───
  toggleSinglePane(CommandScope.global),
  swapPanels(CommandScope.global),
  syncPanels(CommandScope.global),
  viewMode1(CommandScope.global),
  viewMode2(CommandScope.global),
  viewMode3(CommandScope.global),
  viewMode4(CommandScope.global),
  viewMode5(CommandScope.global),
  sortByName(CommandScope.global),
  sortByExtension(CommandScope.global),
  sortByModified(CommandScope.global),
  sortBySize(CommandScope.global),
  sortByCreated(CommandScope.global),
  sortByAdded(CommandScope.global),
  sortByAccessed(CommandScope.global),
  toggleFoldersFirst(CommandScope.global),
  toggleExtensionlessFolders(CommandScope.global),
  collationNatural(CommandScope.global),
  collationCaseInsensitive(CommandScope.global),
  collationCaseSensitive(CommandScope.global),
  toggleHiddenFiles(CommandScope.global),
  panelsMoveLeft(CommandScope.global),
  panelsMoveRight(CommandScope.global),
  resizePanels(CommandScope.global),
  refresh(CommandScope.global),
  toggleOperations(CommandScope.global),

  // ─── Go ───
  goToLeftPanel(CommandScope.global),
  goToRightPanel(CommandScope.global),
  goBack(CommandScope.global),
  goForward(CommandScope.global),
  goEnclosingFolder(CommandScope.global),
  goInto(CommandScope.global),
  followSymlink(CommandScope.global),
  goDocuments(CommandScope.global),
  goDesktop(CommandScope.global),
  goDownloads(CommandScope.global),
  goHome(CommandScope.global),
  goLibrary(CommandScope.global),
  goApplications(CommandScope.global),
  goUtilities(CommandScope.global),
  goRoot(CommandScope.global),
  quickListParents(CommandScope.global),
  quickListHistory(CommandScope.global),
  quickListFavorites(CommandScope.global),
  quickListVolumes(CommandScope.global),
  goToFolder(CommandScope.global),

  // ─── Command ───
  fileAttributes(CommandScope.global),
  copyItemName(CommandScope.global),
  copyItemPath(CommandScope.global),
  copyItemDirectory(CommandScope.global),
  preview(CommandScope.global),
  internalViewer(CommandScope.global),
  externalEditor(CommandScope.global),
  ejectVolume(CommandScope.global),
  batchRename(CommandScope.global),
  copyTo(CommandScope.global),
  copyAs(CommandScope.global),
  moveTo(CommandScope.global),
  moveAs(CommandScope.global),
  renameInPlace(CommandScope.global),
  createDirectory(CommandScope.global),
  createDirectoryInOppositePanel(CommandScope.global),
  moveToTrash(CommandScope.global),
  deleteItems(CommandScope.global),
  deletePermanently(CommandScope.global),
  compress(CommandScope.global),
  compressTo(CommandScope.global),
  createSymlink(CommandScope.global),
  createHardlink(CommandScope.global),
  editSymlink(CommandScope.global),
  revealInFileManager(CommandScope.global),
  openWith(CommandScope.global),

  // ─── Window and help ───
  focusLeftPanel(CommandScope.global),
  focusRightPanel(CommandScope.global),
  openSettings(CommandScope.global),
  hintMode(CommandScope.global),
  cheatSheet(CommandScope.global),
  contextMenu(CommandScope.global),

  // ─── Terminal ───
  toggleTerminal(CommandScope.global),
  showTerminal(CommandScope.global),
  hideTerminal(CommandScope.global),
  togglePanelsOverTerminal(CommandScope.global),

  // ─── File panel keys ───
  moveUp(CommandScope.panel),
  moveDown(CommandScope.panel),
  moveLeft(CommandScope.panel),
  moveRight(CommandScope.panel),
  moveFirst(CommandScope.panel),
  moveLast(CommandScope.panel),
  scrollFirst(CommandScope.panel),
  scrollLast(CommandScope.panel),
  movePageUp(CommandScope.panel),
  movePageDown(CommandScope.panel),
  scrollPageUp(CommandScope.panel),
  scrollPageDown(CommandScope.panel),
  selectMoveUp(CommandScope.panel),
  selectMoveDown(CommandScope.panel),
  selectMoveLeft(CommandScope.panel),
  selectMoveRight(CommandScope.panel),
  selectMoveFirst(CommandScope.panel),
  selectMoveLast(CommandScope.panel),
  selectMovePageUp(CommandScope.panel),
  selectMovePageDown(CommandScope.panel),
  toggleSelection(CommandScope.panel),
  toggleSelectionMoveDown(CommandScope.panel),
  enterItem(CommandScope.panel),
  goParent(CommandScope.panel),
  goHomeKey(CommandScope.panel),
  goRootKey(CommandScope.panel),
  switchPanel(CommandScope.panel),
  showPreview(CommandScope.panel),
  clearQuickSearch(CommandScope.panel),
  showTab1(CommandScope.panel),
  showTab2(CommandScope.panel),
  showTab3(CommandScope.panel),
  showTab4(CommandScope.panel),
  showTab5(CommandScope.panel),
  showTab6(CommandScope.panel),
  showTab7(CommandScope.panel),
  showTab8(CommandScope.panel),
  showTab9(CommandScope.panel),
  showTab10(CommandScope.panel),

  // ─── Vim keys of the panel (chords only while Vim keys are on) ───
  vimVisual(CommandScope.panel),
  vimSearch(CommandScope.panel),
  vimSearchNext(CommandScope.panel),
  vimSearchPrevious(CommandScope.panel),
  vimCommandLine(CommandScope.panel),
  vimCut(CommandScope.panel),
  vimYank(CommandScope.panel),
  vimPaste(CommandScope.panel),
  vimCancelRegister(CommandScope.panel),
  vimFindChar(CommandScope.panel),
  vimFindCharBack(CommandScope.panel),
  vimRepeatFind(CommandScope.panel),
  vimRepeatFindBack(CommandScope.panel),
  vimSetMark(CommandScope.panel),
  vimGoMark(CommandScope.panel),
  vimScreenTop(CommandScope.panel),
  vimScreenMiddle(CommandScope.panel),
  vimScreenBottom(CommandScope.panel),
  vimScrollCenter(CommandScope.panel),
  vimScrollTop(CommandScope.panel),
  vimScrollBottom(CommandScope.panel),
  vimHalfPageDown(CommandScope.panel),
  vimHalfPageUp(CommandScope.panel),
  vimColumnNext(CommandScope.panel),
  vimColumnPrevious(CommandScope.panel),
  vimRenameAppend(CommandScope.panel),
  vimRenamePrepend(CommandScope.panel),
  vimSortReverse(CommandScope.panel),
  vimReselect(CommandScope.panel),

  // ─── Viewer ───
  viewerText(CommandScope.viewer),
  viewerHex(CommandScope.viewer),
  viewerPreview(CommandScope.viewer),
  viewerGoTo(CommandScope.viewer),
  viewerRefresh(CommandScope.viewer),
  viewerFind(CommandScope.viewer),
  viewerFindNext(CommandScope.viewer),
  viewerFindPrevious(CommandScope.viewer),
  viewerToggleWrap(CommandScope.viewer),

  // ─── Terminal ───
  terminalCopy(CommandScope.terminal),
  terminalPaste(CommandScope.terminal),
  terminalSelectAll(CommandScope.terminal),
  terminalClear(CommandScope.terminal),
  terminalScrollPageUp(CommandScope.terminal),
  terminalScrollPageDown(CommandScope.terminal),

  // ─── Lists ───
  renameItem(CommandScope.lists),
  deleteItem(CommandScope.lists),
  filterList(CommandScope.lists),
  moveItemUp(CommandScope.lists),
  moveItemDown(CommandScope.lists),

  // ─── Dialogs and menus ───
  confirm(CommandScope.dialogs),
  dismiss(CommandScope.dialogs);

  const AppCommand(this.scope);

  final CommandScope scope;

  /// Commands shown in the cheat sheet for [scope].
  static List<AppCommand> inScope(CommandScope scope) =>
      values.where((c) => c.scope == scope).toList(growable: false);

  /// A key of Vim mode: it has a chord only while Vim keys are on.
  bool get isVimOnly => name.startsWith('vim');
}
