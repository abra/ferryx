part of 'workspace_screen.dart';

/// The file commands, one method each; the handlers map the commands to
/// them and the menus run the same.
extension _WorkspaceActions on _WorkspaceScreenState {
  Preferences get _prefs => widget.preferences.current;

  FerryxLocalizations get _l10n => context.l10n;

  PanelTabState? get _tab => _active.state.active;

  /// The rows a command works on; a notice when there are none.
  List<FileEntry> _targetsOrNotice() {
    final targets = _tab?.targets ?? const [];
    if (targets.isEmpty) showAppNotice(context, _l10n.noticeNothingSelected);
    return targets;
  }

  /// The paths on disk of [targets]; a notice inside an archive or on a
  /// server.
  List<String>? _nativePaths(List<FileEntry> targets) {
    final tab = _tab;
    if (tab == null) return null;
    if (!tab.location.isNative) {
      showAppNotice(context, _notHere(tab.location));
      return null;
    }
    return [for (final t in targets) t.path];
  }

  void _notice(FerryxException error) =>
      showAppNotice(context, _l10n.errorMessage(error));

  Future<void> _guarded(Future<void> Function() action) async {
    try {
      await action();
    } on FerryxException catch (error) {
      if (mounted) _notice(error);
    }
  }

  Map<AppCommand, VoidCallback> _globalHandlers(BuildContext context) =>
      _previewFocus.hasFocus || _previewController.state.fullWindow
      ? {
          AppCommand.preview: _closePreview,
          AppCommand.internalViewer: _togglePreviewWindow,
          AppCommand.focusLeftPanel: () => _focusPanel(PanelSide.left),
          AppCommand.focusRightPanel: () => _focusPanel(PanelSide.right),
          AppCommand.openSettings: () =>
              unawaited(widget.navigation.openSettings(context)),
          AppCommand.cheatSheet: () =>
              unawaited(widget.navigation.openCheatSheet(context)),
          if (!_previewController.state.fullWindow) ..._terminalHandlers(),
        }
      : _fileHandlers(context);

  Map<AppCommand, VoidCallback> _fileHandlers(BuildContext context) => {
    // File
    AppCommand.newFolder: () => unawaited(_newItem(folder: true)),
    AppCommand.newFolderWithSelection: () =>
        unawaited(_newFolderWithSelection()),
    AppCommand.newFile: () => unawaited(_newItem(folder: false)),
    AppCommand.newTab: () => unawaited(_active.newTab()),
    AppCommand.closeTab: () => unawaited(_active.closeTab()),
    AppCommand.closeOtherTabs: () => unawaited(_active.closeOtherTabs()),
    AppCommand.reopenClosedTab: () => unawaited(_active.reopenClosedTab()),
    AppCommand.nextTab: _active.nextTab,
    AppCommand.previousTab: _active.previousTab,
    AppCommand.toggleTabBar: () => unawaited(
      widget.preferences.update(
        (p) => p.copyWith(showTabBarAlways: !p.showTabBarAlways),
      ),
    ),
    AppCommand.openItem: () => unawaited(_openFocused()),
    AppCommand.revealInOppositePanel: () =>
        unawaited(_revealInOpposite(newTab: false)),
    AppCommand.revealInOppositeTab: () =>
        unawaited(_revealInOpposite(newTab: true)),
    AppCommand.calcFolderSizes: () => unawaited(
      _active.calcSizes(
        names: [for (final t in _tab?.targets ?? <FileEntry>[]) t.name],
      ),
    ),
    AppCommand.calcAllFolderSizes: () => unawaited(_active.calcSizes()),
    AppCommand.duplicate: () => unawaited(_duplicate()),
    AppCommand.addToFavorites: () => unawaited(_addToFavorites()),
    AppCommand.removeFromFavorites: () => unawaited(_removeFromFavorites()),
    AppCommand.manageFavorites: () => unawaited(_manageFavorites()),
    AppCommand.findFiles: () => unawaited(_findFiles()),
    // Edit
    AppCommand.copyPaths: () => unawaited(_copyPaths()),
    AppCommand.pasteItems: () => unawaited(_pasteItems(move: false)),
    AppCommand.moveItemsHere: () => unawaited(_pasteItems(move: true)),
    AppCommand.selectAll: _active.selectAll,
    AppCommand.deselectAll: _active.deselectAll,
    AppCommand.invertSelection: _active.invertSelection,
    AppCommand.selectWithMask: () => unawaited(_selectWithMask(select: true)),
    AppCommand.deselectWithMask: () =>
        unawaited(_selectWithMask(select: false)),
    AppCommand.selectWithExtension: () =>
        _active.selectByExtension(select: true),
    AppCommand.deselectWithExtension: () =>
        _active.selectByExtension(select: false),
    // View
    AppCommand.toggleSinglePane: _toggleSinglePane,
    AppCommand.togglePanelsStacked: _togglePanelsStacked,
    AppCommand.swapPanels: () => unawaited(_swapPanels()),
    AppCommand.syncPanels: () => unawaited(_syncPanels()),
    for (var i = 0; i < 5; i++)
      AppCommand.values.byName('viewMode${i + 1}'): () => _active.setLayout(i),
    AppCommand.sortByName: () =>
        unawaited(_active.toggleSortField(SortField.name)),
    AppCommand.sortByExtension: () =>
        unawaited(_active.toggleSortField(SortField.extension)),
    AppCommand.sortByModified: () =>
        unawaited(_active.toggleSortField(SortField.modified)),
    AppCommand.sortBySize: () =>
        unawaited(_active.toggleSortField(SortField.size)),
    AppCommand.sortByCreated: () =>
        unawaited(_active.toggleSortField(SortField.created)),
    AppCommand.sortByAdded: () =>
        unawaited(_active.toggleSortField(SortField.added)),
    AppCommand.sortByAccessed: () =>
        unawaited(_active.toggleSortField(SortField.accessed)),
    AppCommand.toggleFoldersFirst: () => unawaited(
      _changeSort((s) => s.copyWith(foldersFirst: !s.foldersFirst)),
    ),
    AppCommand.toggleExtensionlessFolders: () => unawaited(
      _changeSort(
        (s) => s.copyWith(extensionlessFolders: !s.extensionlessFolders),
      ),
    ),
    AppCommand.collationNatural: () =>
        unawaited(_changeSort((s) => s.copyWith(collation: Collation.natural))),
    AppCommand.collationCaseInsensitive: () => unawaited(
      _changeSort((s) => s.copyWith(collation: Collation.caseInsensitive)),
    ),
    AppCommand.collationCaseSensitive: () => unawaited(
      _changeSort((s) => s.copyWith(collation: Collation.caseSensitive)),
    ),
    AppCommand.toggleHiddenFiles: () => unawaited(
      widget.preferences.update(
        (p) => p.copyWith(showHiddenFiles: !p.showHiddenFiles),
      ),
    ),
    AppCommand.panelsMoveLeft: () => _moveSplit(-0.05),
    AppCommand.panelsMoveRight: () => _moveSplit(0.05),
    AppCommand.resizePanels: _resizeWithKeys,
    AppCommand.refresh: () => unawaited(_active.refresh()),
    AppCommand.toggleOperations: () {
      _workspace.toggleOperations();
      unawaited(
        widget.preferences.update(
          (p) =>
              p.copyWith(operationsVisible: _workspace.state.operationsShown),
        ),
      );
    },
    // Go
    AppCommand.goToLeftPanel: () => unawaited(_goToPopup(PanelSide.left)),
    AppCommand.goToRightPanel: () => unawaited(_goToPopup(PanelSide.right)),
    AppCommand.goBack: () => unawaited(_active.goBack()),
    AppCommand.goForward: () => unawaited(_active.goForward()),
    AppCommand.goEnclosingFolder: () => unawaited(_active.goParent()),
    AppCommand.goInto: () => unawaited(_goInto()),
    AppCommand.followSymlink: () => unawaited(_active.followSymlink()),
    AppCommand.goDocuments: () => unawaited(_goStandard((f) => f.documents)),
    AppCommand.goDesktop: () => unawaited(_goStandard((f) => f.desktop)),
    AppCommand.goDownloads: () => unawaited(_goStandard((f) => f.downloads)),
    AppCommand.goHome: () => unawaited(_goStandard((f) => f.home)),
    AppCommand.goLibrary: () => unawaited(_goStandard((f) => f.library)),
    AppCommand.goApplications: () =>
        unawaited(_goStandard((f) => f.applications)),
    AppCommand.goUtilities: () => unawaited(_goStandard((f) => f.utilities)),
    AppCommand.goRoot: () => unawaited(_goStandard((f) => f.root)),
    AppCommand.quickListParents: () =>
        unawaited(_quickList(AppCommand.quickListParents)),
    AppCommand.quickListHistory: () =>
        unawaited(_quickList(AppCommand.quickListHistory)),
    AppCommand.quickListFavorites: () =>
        unawaited(_quickList(AppCommand.quickListFavorites)),
    AppCommand.quickListVolumes: () =>
        unawaited(_quickList(AppCommand.quickListVolumes)),
    AppCommand.goToFolder: () => unawaited(_goToFolder()),
    // Command
    AppCommand.fileAttributes: () => unawaited(_attributes()),
    AppCommand.copyItemName: () =>
        unawaited(_copyText((t) => t.name, single: true)),
    AppCommand.copyItemPath: () =>
        unawaited(_copyText((t) => _shownPath(t.path))),
    AppCommand.copyItemDirectory: () =>
        unawaited(_copyText((t) => _shownPath(t.parentPath), single: true)),
    AppCommand.preview: () => unawaited(_preview()),
    AppCommand.internalViewer: () => unawaited(_view(preview: false)),
    AppCommand.externalEditor: () => unawaited(_externalEditor()),
    AppCommand.ejectVolume: () => unawaited(_eject()),
    AppCommand.batchRename: () => unawaited(_batchRename()),
    AppCommand.copyTo: () => unawaited(_copyOrMove(move: false, asName: false)),
    AppCommand.copyAs: () => unawaited(_copyOrMove(move: false, asName: true)),
    AppCommand.moveTo: () => unawaited(_copyOrMove(move: true, asName: false)),
    AppCommand.moveAs: () => unawaited(_copyOrMove(move: true, asName: true)),
    AppCommand.renameInPlace: _active.startRenaming,
    AppCommand.createDirectory: () =>
        unawaited(_createDirectory(opposite: false)),
    AppCommand.createDirectoryInOppositePanel: () =>
        unawaited(_createDirectory(opposite: true)),
    AppCommand.moveToTrash: () =>
        unawaited(_delete(trashDefault: true, ask: _prefs.confirmTrash)),
    AppCommand.deleteItems: () =>
        unawaited(_delete(trashDefault: true, ask: true)),
    AppCommand.deletePermanently: () =>
        unawaited(_delete(trashDefault: false, ask: true)),
    AppCommand.compress: () => unawaited(_compress(toOpposite: false)),
    AppCommand.compressTo: () => unawaited(_compress(toOpposite: true)),
    AppCommand.createSymlink: () => unawaited(_link(LinkDialogKind.symlink)),
    AppCommand.createHardlink: () => unawaited(_link(LinkDialogKind.hardlink)),
    AppCommand.editSymlink: () => unawaited(_link(LinkDialogKind.editSymlink)),
    AppCommand.revealInFileManager: () => unawaited(_revealInFileManager()),
    AppCommand.openWith: () => unawaited(_openWith()),
    // Window and help
    AppCommand.focusLeftPanel: () => _focusPanel(PanelSide.left),
    AppCommand.focusRightPanel: () => _focusPanel(PanelSide.right),
    AppCommand.openSettings: () =>
        unawaited(widget.navigation.openSettings(context)),
    AppCommand.cheatSheet: () =>
        unawaited(widget.navigation.openCheatSheet(context)),
    AppCommand.contextMenu: () => unawaited(_rowMenu(_rowAnchor())),
    // ─── Interface ───
    AppCommand.jumpToFolder: () => unawaited(_jumpToFolder()),
    AppCommand.addToShelf: () => _shelveTargets(cut: false, replace: false),
    AppCommand.toggleShelf: _toggleShelf,
    AppCommand.renameInEditor: () => unawaited(_renameInEditor()),
    // ─── Native ───
    AppCommand.quickLook: () => unawaited(_toggleQuickLook()),
    AppCommand.share: () => unawaited(_share()),
    // ─── Terminal ───
    ..._terminalHandlers(),
    // ─── Operations ───
    ..._operationsHandlers(),
    // ─── Files core ───
    AppCommand.extractTo: () => unawaited(_extractTo()),
    AppCommand.toggleFlatView: () {
      if (!_onServer()) unawaited(_active.toggleFlatView());
    },
    AppCommand.editTags: () => unawaited(_editTags()),
    // ─── Network ───
    ..._networkHandlers(),
  };

  // ─── Opening ───

  Future<void> _openFile(OpenFileRequest request) => _guarded(() async {
    final location = request.location;
    if (location.isRemote) {
      await _openFromServer(request);
      return;
    }
    if (location.isNative) {
      await widget.files.openDefault(request.entry.path);
    } else {
      if (!await _ensureArchivePassword(location.archive!)) return;
      final path = await widget.files.extractToTemp(
        location.archive!,
        location.path,
      );
      await widget.files.openDefault(path);
    }
  });

  Future<void> _openFocused() async {
    final tab = _tab;
    final focused = tab?.focused;
    if (tab == null || focused == null || focused.isParent) return;
    await _openFile(OpenFileRequest(focused, tab.locationOf(focused)));
  }

  Future<void> _goInto() async {
    final request = await _active.goInto();
    if (request != null) await _openFile(request);
  }

  Future<void> _openWith() => _guarded(() async {
    if (_onServer()) return;
    final tab = _tab;
    final focused = tab?.focused;
    if (tab == null ||
        focused == null ||
        focused.isParent ||
        !tab.location.isNative) {
      return;
    }
    final apps = await widget.files.applicationsFor(focused.path);
    if (!mounted) return;
    final picked = await showAppMenu<String>(
      context: context,
      anchor: _rowAnchor(),
      entries: [
        AppMenuSection(_l10n.menuOpenWith),
        for (final app in apps)
          AppMenuAction(
            value: app,
            label: _appName(app),
            icon: AppIcons.application,
          ),
        if (apps.isNotEmpty) const AppMenuSeparator(),
        AppMenuAction(
          value: '',
          label: _l10n.menuOpenWithOther,
          icon: AppIcons.more,
        ),
      ],
    );
    if (picked == null) return;
    if (picked.isEmpty) {
      await widget.files.reveal(focused.path);
      return;
    }
    await widget.files.openWith(focused.path, picked);
  });

  String _appName(String path) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    return name.endsWith('.app') ? name.substring(0, name.length - 4) : name;
  }

  Future<void> _externalEditor() => _guarded(() async {
    final tab = _tab;
    final focused = tab?.focused;
    if (tab == null ||
        focused == null ||
        focused.isParent ||
        !(tab.location.isNative || tab.location.isRemote)) {
      return;
    }
    for (final editor in _prefs.editors) {
      if (_maskMatches(editor.mask, focused.name)) {
        if (tab.location.isRemote) {
          // A copy in the editor; what is saved there stays there.
          await _openFromServer(
            OpenFileRequest(focused, tab.locationOf(focused)),
            app: editor.path,
          );
        } else {
          await widget.files.openWith(focused.path, editor.path);
        }
        return;
      }
    }
    showAppNotice(context, _l10n.noticeNoEditor);
  });

  bool _maskMatches(String mask, String name) {
    for (final part in mask.split(RegExp(r'[;,]'))) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final pattern =
          '^${RegExp.escape(trimmed).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$';
      if (RegExp(pattern, caseSensitive: false).hasMatch(name)) return true;
    }
    return false;
  }

  Future<void> _view({required bool preview}) async {
    if (widget.preview != null) {
      await _showPreview(fullWindow: !preview, startInPreview: preview);
      return;
    }
    final tab = _tab;
    final focused = tab?.focused;
    if (tab == null || focused == null || focused.isParent || focused.isDir) {
      return;
    }
    final archive = tab.location.archive;
    if (archive != null && !await _ensureArchivePassword(archive)) return;
    if (!mounted) return;
    await widget.navigation.openViewer(
      context,
      tab.locationOf(focused),
      preview: preview,
    );
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }

  Future<void> _preview() => _view(preview: true);

  Future<void> _revealInFileManager() => _guarded(() async {
    if (_onServer()) return;
    final tab = _tab;
    if (tab == null || !tab.location.isNative) return;
    final focused = tab.focused;
    await widget.files.reveal(
      focused == null || focused.isParent ? tab.location.path : focused.path,
    );
  });

  Future<void> _revealInOpposite({required bool newTab}) async {
    final tab = _tab;
    final focused = tab?.focused;
    if (tab == null || focused == null || focused.isParent) return;
    // A flat view's row is shown in its own folder.
    final target = focused.isDir
        ? tab.locationOf(focused)
        : focused.folder.isEmpty
        ? tab.location
        : tab.location.join(focused.folder);
    final focusName = focused.isDir ? null : focused.name;
    if (newTab) {
      await _opposite.openInNewTab(target, focusName: focusName);
    } else if (focusName != null) {
      await _opposite.reveal(target, focusName: focusName);
    } else {
      await _opposite.open(target);
    }
    if (_workspace.state.singlePane) {
      _focusPanel(_workspace.state.active.opposite);
    }
  }

  // ─── Navigation ───

  Future<void> _goStandard(
    String Function(StandardFolders folders) pick,
  ) async {
    final folders = widget.files.standardFolders();
    await _active.open(Location.native(pick(folders)));
  }

  Future<void> _goToFolder() async {
    final tab = _tab;
    final location = tab?.location;
    final path = await showGoToFolderDialog(
      context,
      initial: location == null
          ? ''
          : location.isNative
          ? location.path
          : location.isRemote
          ? location.display
          : '',
    );
    if (path == null || !mounted) return;
    if (path.contains('://')) {
      // A server's address: connected to, and gone to.
      await _connectAddress(path.trim(), _active);
      return;
    }
    final home = widget.files.standardFolders().home;
    final resolved = path == '~'
        ? home
        : path.startsWith('~/')
        ? '$home${path.substring(1)}'
        : path;
    if (!resolved.startsWith('/')) {
      final base = tab?.location.isNative == true ? tab!.location.path : home;
      await _active.open(Location.native('$base/$resolved'));
      return;
    }
    if (widget.files.isArchive(resolved) &&
        !widget.files.isDirectory(resolved)) {
      await _active.open(Location.inArchive(archive: resolved));
    } else {
      await _active.open(Location.native(resolved));
    }
  }

  Future<void> _goToPopup(PanelSide side) async {
    final panel = _cubitOf(side);
    final other = _cubitOf(side.opposite);
    final volumes = await _volumes();
    if (!mounted) return;
    final pick = await showGoToPopup(
      context,
      anchor: _panelAnchor(side),
      favorites: _prefs.favorites,
      volumes: volumes,
      otherPanel: [for (final t in other.state.tabs) t.location],
      history: panel.state.active?.history.reversed.toList() ?? const [],
      servers: widget.network == null ? null : _prefs.servers,
    );
    await _followPick(pick, panel: panel, side: side);
  }

  Future<void> _quickList(AppCommand which) async {
    final side = _workspace.state.active;
    final panel = _active;
    final tab = panel.state.active;
    if (tab == null) return;
    final anchor = _panelAnchor(side);
    final GoToPick? pick;
    switch (which) {
      case AppCommand.quickListParents:
        pick = await showParentsList(
          context,
          anchor: anchor,
          current: tab.location,
        );
      case AppCommand.quickListHistory:
        pick = await showHistoryList(
          context,
          anchor: anchor,
          history: tab.history,
          historyIndex: tab.historyIndex,
        );
      case AppCommand.quickListFavorites:
        pick = await showFavoritesList(
          context,
          anchor: anchor,
          favorites: _prefs.favorites,
        );
      case AppCommand.quickListVolumes:
        final volumes = await _volumes();
        if (!mounted) return;
        pick = await showVolumesList(context, anchor: anchor, volumes: volumes);
      default:
        pick = null;
    }
    await _followPick(pick, panel: panel, side: side);
  }

  Future<void> _followPick(
    GoToPick? pick, {
    required PanelCubit panel,
    required PanelSide side,
  }) async {
    switch (pick) {
      case null:
        return;
      case GoToLocation(:final location):
        _focusPanel(side);
        await panel.open(location);
      case GoToManageFavorites():
        _focusPanel(side);
        await _manageFavorites();
      case GoToEject(:final mountPoint):
        await _guarded(() async {
          await widget.files.eject(mountPoint);
          if (mounted) showAppNotice(context, _l10n.noticeEjected(mountPoint));
        });
      // ─── Network ───
      case GoToServer(:final server):
        _focusPanel(side);
        await _connectProfile(server, panel);
      case GoToConnect():
        _focusPanel(side);
        await _connectToServer();
    }
  }

  Future<List<Volume>> _volumes() async {
    try {
      return await widget.files.volumes();
    } on FerryxException catch (error) {
      widget.logger.warn('volumes', error: error);
      return const [];
    }
  }

  Future<void> _eject() => _guarded(() async {
    final tab = _tab;
    if (tab == null || !tab.location.isNative) return;
    final volumes = await _volumes();
    Volume? here;
    for (final volume in volumes) {
      if (tab.location.path.startsWith(volume.mountPoint) &&
          (here == null || volume.mountPoint.length > here.mountPoint.length)) {
        here = volume;
      }
    }
    if (here == null || here.isRoot) {
      if (mounted) showAppNotice(context, _l10n.noticeNoVolume);
      return;
    }
    final home = widget.files.standardFolders().home;
    await _active.open(Location.native(home));
    await widget.files.eject(here.mountPoint);
    if (mounted) showAppNotice(context, _l10n.noticeEjected(here.name));
  });

  // ─── Panels ───

  void _switchPanel() {
    if (_previewController.state.shown) {
      if (_previewFocus.hasFocus) {
        _focusPreviewFiles();
      } else {
        _focusPreview();
      }
      return;
    }
    if (_workspace.state.singlePane) {
      _workspace.switchPanel();
      _scheduleSnapshot();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusOf(_workspace.state.active).requestFocus(),
      );
      return;
    }
    _focusPanel(_workspace.state.active.opposite);
  }

  void _toggleSinglePane() {
    _workspace.toggleSinglePane();
    unawaited(
      widget.preferences.update(
        (p) => p.copyWith(singlePane: _workspace.state.singlePane),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusOf(_workspace.state.active).requestFocus(),
    );
  }

  /// The panels the other way from how they stand now, kept so: whatever
  /// the window's shape, until Settings gives it back the choice.
  void _togglePanelsStacked() {
    final stacked = _panelsStacked(_prefs, MediaQuery.sizeOf(context));
    unawaited(
      widget.preferences.update(
        (p) => p.copyWith(
          panelArrangement: stacked
              ? PanelArrangement.sideBySide
              : PanelArrangement.stacked,
        ),
      ),
    );
  }

  void _moveSplit(double delta) {
    _workspace.moveSplit(delta);
    unawaited(
      widget.preferences.update(
        (p) => p.copyWith(splitFraction: _workspace.state.splitFraction),
      ),
    );
  }

  void _resizeWithKeys() {
    if (_workspace.state.singlePane) return;
    _splitBeforeKeys = _workspace.state.splitFraction;
    _workspace.setResizing(true);
    _splitterFocus.requestFocus();
  }

  Future<void> _swapPanels() async {
    final left = _leftSaved();
    final right = _rightSaved();
    final leftCubit = _cubitOf(PanelSide.left);
    final rightCubit = _cubitOf(PanelSide.right);
    final fallback = widget.fallbackLocation;
    await Future.wait([
      _restart(leftCubit, right, fallback),
      _restart(rightCubit, left, fallback),
    ]);
    _focusPanel(_workspace.state.active.opposite);
  }

  SavedPanel _leftSaved() => _cubitOf(PanelSide.left).saved();

  SavedPanel _rightSaved() => _cubitOf(PanelSide.right).saved();

  Future<void> _restart(
    PanelCubit cubit,
    SavedPanel saved,
    Location fallback,
  ) async {
    while (cubit.state.tabs.length > 1) {
      await cubit.closeTab(cubit.state.tabs.length - 1);
    }
    await cubit.start(saved, fallback);
  }

  Future<void> _syncPanels() async {
    final tab = _tab;
    if (tab == null) return;
    await _opposite.open(tab.location);
  }

  Future<void> _changeSort(
    SortOptions Function(SortOptions sort) change,
  ) async {
    final tab = _tab;
    if (tab == null) return;
    await _active.setSort(change(tab.sort));
    final sort = _tab?.sort;
    if (sort != null) {
      await widget.preferences.update(
        (p) => p.copyWith(
          foldersFirst: sort.foldersFirst,
          extensionlessFolders: sort.extensionlessFolders,
          collation: sort.collation,
        ),
      );
    }
  }

  // ─── Menus ───

  /// Where a menu for the cursor's row opens from the keyboard: by the
  /// row while it is in view, else by the panel's top.
  Rect _rowAnchor() {
    final side = _workspace.state.active;
    final row = _cursorOf(side).currentContext;
    final box = row?.findRenderObject();
    if (row != null &&
        box is RenderBox &&
        box.hasSize &&
        visibleGlobalRect(box) != null) {
      return keyboardMenuAnchor(row);
    }
    return _panelAnchor(side);
  }

  Rect _panelAnchor(PanelSide side) {
    final box = _focusOf(side).context?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final origin = box.localToGlobal(Offset.zero);
      final top = context.metrics.topBarHeight;
      return Rect.fromLTWH(
        origin.dx + AppSpacing.md,
        origin.dy + top,
        box.size.width - AppSpacing.md * 2,
        0,
      );
    }
    return keyboardMenuAnchor(context);
  }

  Future<void> _rowMenu(Rect anchor) async {
    final tab = _tab;
    final focused = tab?.focused;
    if (tab == null || focused == null || focused.isParent) return;
    final picked = await showAppMenu<AppCommand>(
      context: context,
      anchor: anchor,
      entries: rowMenuEntries(
        context,
        entry: focused,
        location: tab.location,
        severalSelected: tab.selected.length > 1,
        isFavorite: _isFavoriteLocation,
        map: widget.shortcutMap,
        archive: tab.location.isNative && widget.files.isArchive(focused.path),
        tags: tab.location.isNative && widget.capabilities.finderTags,
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == AppCommand.enterItem) {
      final request = await _active.enter();
      if (request != null) await _openFile(request);
      return;
    }
    if (picked == AppCommand.share) {
      // The picker points where the menu was opened.
      await _share(anchor: anchor);
      return;
    }
    _globalHandlers(context)[picked]?.call();
  }

  Future<void> _panelMenu(Rect anchor) async {
    final tab = _tab;
    final picked = await showAppMenu<AppCommand>(
      context: context,
      anchor: anchor,
      entries: panelMenuEntries(
        context,
        showHidden: _prefs.showHiddenFiles,
        singlePane: _workspace.state.singlePane,
        stacked: _panelsStacked(_prefs, MediaQuery.sizeOf(context)),
        native: tab?.location.isNative ?? false,
        map: widget.shortcutMap,
        journal: widget.operations.currentJournal,
        flat: tab?.isFlat ?? false,
        remote: tab?.location.isRemote ?? false,
        isFavorite: _isFavoriteLocation,
        canGoBack: tab?.canGoBack ?? false,
        canGoForward: tab?.canGoForward ?? false,
      ),
    );
    if (picked == null || !mounted) return;
    _globalHandlers(context)[picked]?.call();
  }

  // ─── Making and renaming ───

  Future<void> _newItem({required bool folder}) => _guarded(() async {
    final tab = _tab;
    if (tab != null && tab.location.isRemote) {
      await _newOnServer(tab, folder: folder);
      return;
    }
    if (tab == null || !tab.location.isNative) {
      showAppNotice(context, _l10n.noticeNotInArchive);
      return;
    }
    final base = folder ? _l10n.newFolderDefaultName : _l10n.newFileDefaultName;
    final name = widget.files.freeName(tab.location.path, base);
    final path = '${tab.location.path}/$name';
    if (folder) {
      await widget.files.createDirectory(path);
    } else {
      await widget.files.createFile(path);
    }
    await _active.open(tab.location, focusName: name);
    _active.startRenaming();
  });

  Future<void> _newFolderWithSelection() => _guarded(() async {
    final tab = _tab;
    final targets = _targetsOrNotice();
    if (tab == null || targets.isEmpty) return;
    final paths = _nativePaths(targets);
    if (paths == null) return;
    final name = widget.files.freeName(
      tab.location.path,
      _l10n.newFolderDefaultName,
    );
    final folder = '${tab.location.path}/$name';
    await widget.files.createDirectory(folder);
    await widget.operations.start(
      OperationRequest(kind: OpKind.move, sources: paths, destination: folder),
    );
    await _active.open(tab.location, focusName: name);
    _active.startRenaming();
  });

  Future<void> _createDirectory({required bool opposite}) => _guarded(() async {
    final panel = opposite ? _opposite : _active;
    final tab = panel.state.active;
    if (tab == null || !(tab.location.isNative || tab.location.isRemote)) {
      showAppNotice(context, _l10n.noticeNotInArchive);
      return;
    }
    final name = await showCreateDirectoryDialog(context, opposite: opposite);
    if (name == null) return;
    if (tab.location.isRemote) {
      await _makeFoldersOnServer(tab.location, name);
      final first = name.startsWith('/') ? null : name.split('/').first;
      await panel.open(tab.location, focusName: first);
      return;
    }
    final path = name.startsWith('/') ? name : '${tab.location.path}/$name';
    await widget.files.createDirectory(path);
    final first = name.startsWith('/') ? null : name.split('/').first;
    await panel.open(tab.location, focusName: first);
  });

  Future<void> _batchRename() async {
    final targets = _targetsOrNotice();
    if (targets.isEmpty) return;
    final paths = _nativePaths(targets);
    if (paths == null) return;
    final changed = await showBatchRenameDialog(
      context,
      paths: paths,
      rename: widget.rename,
    );
    if (changed) await _active.refresh();
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }

  Future<void> _attributes() async {
    final targets = _targetsOrNotice();
    if (targets.isEmpty) return;
    final paths = _nativePaths(targets);
    if (paths == null) return;
    final changed = await showAttributesDialog(
      context,
      paths: paths,
      files: widget.files,
    );
    if (changed) await _active.refresh();
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }

  Future<void> _link(LinkDialogKind kind) => _guarded(() async {
    final tab = _tab;
    final focused = tab?.focused;
    if (tab == null || !tab.location.isNative) {
      if (tab != null) showAppNotice(context, _notHere(tab.location));
      return;
    }
    var target = focused == null || focused.isParent ? '' : focused.path;
    var link =
        '${tab.location.path}/${focused == null || focused.isParent ? '' : '${focused.name} link'}';
    if (kind == LinkDialogKind.editSymlink) {
      if (focused == null || !focused.isSymlink) {
        showAppNotice(context, _l10n.linkNotSymlink);
        return;
      }
      target =
          focused.symlinkTarget ?? await widget.files.readSymlink(focused.path);
      link = focused.path;
    }
    if (!mounted) return;
    final choice = await showLinkDialog(
      context,
      kind: kind,
      target: target,
      link: link,
    );
    if (choice == null) return;
    switch (kind) {
      case LinkDialogKind.symlink:
        await widget.files.createSymlink(
          target: choice.target,
          link: choice.link,
        );
      case LinkDialogKind.hardlink:
        await widget.files.createHardlink(
          target: choice.target,
          link: choice.link,
        );
      case LinkDialogKind.editSymlink:
        await widget.files.editSymlink(
          link: choice.link,
          target: choice.target,
        );
    }
    await _active.refresh();
  });

  // ─── Copying, moving, deleting ───

  Future<void> _copyOrMove({required bool move, required bool asName}) async {
    final tab = _tab;
    final targets = _targetsOrNotice();
    if (tab == null || targets.isEmpty) return;
    final oppositeTab = _opposite.state.active;
    final home = widget.files.standardFolders().home;
    final defaultDestination = oppositeTab?.location.isNative == true
        ? oppositeTab!.location.path
        : home;
    // The other panel's folder, on disk or on a server.
    final opposite = oppositeTab?.location;
    final offered = opposite != null && (opposite.isNative || opposite.isRemote)
        ? opposite
        : Location.native(home);
    if (!tab.location.isNative && !tab.location.isRemote) {
      // Out of an archive: an extraction into the destination.
      if (move) {
        showAppNotice(context, _l10n.noticeNotInArchive);
        return;
      }
      final archive = tab.location.archive;
      if (archive != null && !await _ensureArchivePassword(archive)) return;
      await _guarded(() async {
        await widget.operations.start(
          OperationRequest(
            kind: OpKind.extract,
            sources: [for (final t in targets) t.path],
            archive: tab.location.archive,
            destination: defaultDestination,
          ),
        );
      });
      return;
    }
    final choice = await showCopyMoveDialog(
      context,
      move: move,
      asName: asName && targets.length == 1,
      names: [for (final t in targets) t.name],
      currentFolder: tab.location.isRemote
          ? tab.location.display
          : tab.location.path,
      defaultDestination: offered.isRemote ? offered.display : offered.path,
      preserveAttributes: _prefs.preserveAttributes,
      verify: _prefs.verifyCopies,
      // A copy over the network is not read back.
      canVerify: !tab.location.isRemote && !offered.isRemote,
    );
    if (choice == null || !mounted) return;
    final destination = await _destinationOf(
      choice.destination,
      known: [tab.location, offered],
    );
    if (destination == null || !mounted) return;
    final local = !tab.location.isRemote && !destination.isRemote;
    await _guarded(() async {
      await widget.operations.start(
        OperationRequest(
          kind: move ? OpKind.move : OpKind.copy,
          sources: [for (final t in targets) t.path],
          destination: destination.path,
          newName: choice.newName,
          conflicts: choice.conflicts,
          preserveAttributes: choice.preserveAttributes,
          verify: choice.verify && local,
          sourceServer: tab.location.server,
          destinationServer: destination.server,
        ),
      );
      _active.clearSelection();
    });
  }

  Future<void> _duplicate() => _guarded(() async {
    final targets = _targetsOrNotice();
    final paths = targets.isEmpty ? null : _nativePaths(targets);
    if (paths == null) return;
    await widget.operations.start(
      OperationRequest(kind: OpKind.duplicate, sources: paths),
    );
    _active.clearSelection();
  });

  Future<void> _delete({required bool trashDefault, required bool ask}) =>
      _guarded(() async {
        final tab = _tab;
        final targets = _targetsOrNotice();
        if (tab == null || targets.isEmpty) return;
        if (tab.location.isRemote) {
          await _deleteOnServer(tab, targets);
          return;
        }
        final paths = _nativePaths(targets);
        if (paths == null) return;
        var choice = trashDefault ? DeleteChoice.trash : DeleteChoice.permanent;
        if (ask) {
          final picked = await showDeleteDialog(
            context,
            names: [for (final t in targets) t.name],
            trashDefault: trashDefault,
            trashAvailable: true,
          );
          if (picked == null) return;
          choice = picked;
        }
        await widget.operations.start(
          OperationRequest(
            kind: choice == DeleteChoice.trash ? OpKind.trash : OpKind.delete,
            sources: paths,
          ),
        );
        _active.clearSelection();
      });

  Future<void> _compress({required bool toOpposite}) => _guarded(() async {
    final tab = _tab;
    final targets = _targetsOrNotice();
    if (tab == null || targets.isEmpty) return;
    final paths = _nativePaths(targets);
    if (paths == null) return;
    final defaultName = targets.length == 1
        ? '${targets.first.stem.isEmpty ? targets.first.name : targets.first.stem}.zip'
        : '${tab.location.name}.zip';
    final choice = await showCompressDialog(
      context,
      names: [for (final t in targets) t.name],
      defaultName: defaultName,
      toOpposite: toOpposite,
    );
    if (choice == null) return;
    final oppositeTab = _opposite.state.active;
    final destination =
        choice.toOpposite && oppositeTab?.location.isNative == true
        ? oppositeTab!.location.path
        : tab.location.path;
    await widget.operations.start(
      OperationRequest(
        kind: OpKind.compress,
        sources: paths,
        destination: destination,
        newName: choice.name,
        password: choice.password,
      ),
    );
    _active.clearSelection();
  });

  // ─── Clipboard ───

  Future<void> _copyPaths() async {
    final targets = _targetsOrNotice();
    if (targets.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(
        text: [for (final t in targets) _shownPath(t.path)].join('\n'),
      ),
    );
    if (mounted) {
      showAppNotice(context, _l10n.noticePathsCopied(targets.length));
    }
  }

  Future<void> _copyText(
    String Function(FileEntry entry) pick, {
    bool single = false,
  }) async {
    final targets = _targetsOrNotice();
    if (targets.isEmpty) return;
    final items = single ? [targets.first] : targets;
    await Clipboard.setData(ClipboardData(text: items.map(pick).join('\n')));
    if (mounted) {
      showAppNotice(
        context,
        single ? _l10n.noticeNameCopied : _l10n.noticePathsCopied(items.length),
      );
    }
  }

  Future<void> _pasteItems({required bool move}) => _guarded(() async {
    final tab = _tab;
    if (tab == null || !(tab.location.isNative || tab.location.isRemote)) {
      showAppNotice(context, _l10n.noticeNotInArchive);
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final lines = (data?.text ?? '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('/'))
        .toList();
    final paths = <String>[];
    for (final line in lines) {
      try {
        await widget.files.stat(line);
        paths.add(line);
      } on FerryxException {
        // Not a path on this machine.
      }
    }
    if (paths.isEmpty) {
      if (mounted) showAppNotice(context, _l10n.noticeClipboardEmpty);
      return;
    }
    await widget.operations.start(
      OperationRequest(
        kind: move ? OpKind.move : OpKind.copy,
        sources: paths,
        destination: tab.location.path,
        preserveAttributes: _prefs.preserveAttributes,
        verify: _prefs.verifyCopies && !tab.location.isRemote,
        destinationServer: tab.location.server,
      ),
    );
  });

  // ─── Selection ───

  Future<void> _selectWithMask({required bool select}) async {
    final choice = await showSelectMaskDialog(context, select: select);
    if (choice == null) return;
    final RegExp regex;
    try {
      regex = choice.regex
          ? RegExp(choice.mask, caseSensitive: false)
          : _maskRegex(choice.mask);
    } on FormatException {
      if (mounted) {
        showAppNotice(
          context,
          _l10n.errorMessage(
            FerryxException(FerryxErrorKind.invalidPattern, choice.mask),
          ),
        );
      }
      return;
    }
    _active.selectWhere((row) => regex.hasMatch(row.name), select: select);
  }

  RegExp _maskRegex(String mask) {
    final parts = mask
        .split(RegExp(r'[;,]'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);
    final alternatives = [
      for (final part in parts)
        part.contains(RegExp(r'[*?\[]'))
            ? RegExp.escape(part).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')
            : '.*${RegExp.escape(part)}.*',
    ];
    return RegExp('^(?:${alternatives.join('|')})\$', caseSensitive: false);
  }

  // ─── Favorites and find ───

  Location? get _favoriteLocation {
    final tab = _tab;
    if (tab == null) return null;
    final focused = tab.focused;
    return focused != null && focused.isDir && !focused.isParent
        ? tab.locationOf(focused)
        : tab.location;
  }

  bool get _isFavoriteLocation =>
      _prefs.favorites.any((f) => f.location == _favoriteLocation);

  Future<void> _addToFavorites() async {
    final location = _favoriteLocation;
    if (location == null) return;
    if (_isFavoriteLocation) {
      showAppNotice(context, _l10n.favoriteAlreadyAdded(location.name));
      return;
    }
    await widget.preferences.update(
      (p) => p.copyWith(
        favorites: [
          ...p.favorites,
          Favorite(location: location),
        ],
      ),
    );
    if (mounted) showAppNotice(context, _l10n.favoriteAdded(location.name));
  }

  Future<void> _removeFromFavorites() async {
    final location = _favoriteLocation;
    if (location == null) return;
    if (!_isFavoriteLocation) {
      showAppNotice(context, _l10n.favoriteNotAdded(location.name));
      return;
    }
    await widget.preferences.update(
      (p) => p.copyWith(
        favorites: [
          for (final favorite in p.favorites)
            if (favorite.location != location) favorite,
        ],
      ),
    );
    if (mounted) showAppNotice(context, _l10n.favoriteRemoved(location.name));
  }

  Future<void> _manageFavorites() async {
    final tab = _tab;
    if (tab == null) return;
    final picked = await showFavoritesDialog(
      context,
      favorites: _prefs.favorites,
      current: tab.location,
      onChanged: (favorites) => unawaited(
        widget.preferences.update((p) => p.copyWith(favorites: favorites)),
      ),
    );
    if (picked != null) await _active.open(picked);
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }

  Future<void> _findFiles() async {
    if (_onServer()) return;
    final tab = _tab;
    final root = tab?.location.isNative == true
        ? tab!.location.path
        : widget.files.standardFolders().home;
    final path = await widget.navigation.openFind(
      context,
      root,
      view: (location) => widget.navigation.openViewer(context, location),
    );
    if (path == null || !mounted) return;
    final slash = path.lastIndexOf('/');
    final folder = slash <= 0 ? '/' : path.substring(0, slash);
    await _active.reveal(
      Location.native(folder),
      focusName: path.substring(slash + 1),
    );
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }
}
