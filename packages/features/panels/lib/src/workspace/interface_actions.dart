part of 'workspace_screen.dart';

/// Jump to Folder by frecency, the shelf and the names editor.
extension _InterfaceActions on _WorkspaceScreenState {
  String get _home => widget.files.standardFolders().home;

  // ─── Jump to Folder ───

  /// The folder the active panel is in, which a jump never offers.
  String? get _hereOnDisk {
    final tab = _tab;
    return tab != null && tab.location.isNative ? tab.location.path : null;
  }

  /// ⌘G: the frecent folders to pick from.
  Future<void> _jumpToFolder({String query = ''}) async {
    final pick = await showJumpToFolder(
      context,
      frecency: widget.frecency,
      home: _home,
      exclude: _hereOnDisk,
      initialQuery: query,
    );
    if (pick == null || !mounted) return;
    await _openFrecent(pick.value, pick.action);
  }

  /// Opens [path] where [action] says: the active panel, a new tab of it,
  /// or the other panel. A folder gone from the disk leaves the list.
  Future<void> _openFrecent(String path, AppQuickPickerAction action) async {
    if (!widget.files.isDirectory(path)) {
      widget.frecency.remove(path);
      showAppNotice(
        context,
        _l10n.jumpGone(PathText.tilde(path, home: _home)),
      );
      return;
    }
    final location = Location.native(path);
    await _guarded(() async {
      switch (action) {
        case AppQuickPickerAction.primary:
          await _active.open(location);
        case AppQuickPickerAction.secondary:
          await _active.openInNewTab(location);
        case AppQuickPickerAction.alternate:
          await _opposite.open(location);
          // Alone on the screen, the other panel comes forward to show it.
          if (_workspace.state.singlePane) {
            _focusPanel(_workspace.state.active.opposite);
          }
      }
    });
  }

  /// `:z words`: straight to the best folder for the words, as zoxide's
  /// `z`; `:z` alone opens the list.
  Future<void> _vimJump(String query) async {
    if (query.trim().isEmpty) {
      await _jumpToFolder();
      return;
    }
    for (final match in widget.frecency.query(query, exclude: _hereOnDisk)) {
      final path = match.folder.path;
      if (widget.files.isDirectory(path)) {
        await _guarded(() => _active.open(Location.native(path)));
        return;
      }
      widget.frecency.remove(path);
    }
    if (mounted) showAppNotice(context, _l10n.jumpNoMatch(query.trim()));
  }

  // ─── The shelf ───

  /// The footer's note on what the shelf holds.
  String? _shelfNote(FerryxLocalizations l10n, Shelf shelf) {
    if (shelf.isEmpty) return null;
    final cut = shelf.cutCount;
    if (cut == shelf.length) return l10n.vimRegisterCut(cut);
    final note = l10n.shelfNote(shelf.length);
    return cut == 0 ? note : l10n.joinedDetails(note, l10n.vimRegisterCut(cut));
  }

  /// Where Copy Here and Move Here put the items, as the strip names it:
  /// the active panel's folder on disk, `null` inside an archive.
  String? _shelfDestination(PanelTabState? tab) =>
      tab != null && tab.location.isNative
      ? PathText.tilde(tab.location.path, home: _home)
      : null;

  /// The targets go on the shelf, marked [cut] for `p` to move them; in
  /// place of what is there with [replace] (`yy`, `dd`). The strip shows
  /// the first items; a notice tells of the next ones while it is hidden.
  void _shelveTargets({required bool cut, required bool replace}) {
    final targets = _targetsOrNotice();
    if (targets.isEmpty || _nativePaths(targets) == null) return;
    final wasShown = _workspace.state.shelfShown;
    final wasEmpty = _workspace.state.shelf.isEmpty;
    _workspace.shelve([
      for (final entry in targets) ShelfItem(entry, cut: cut),
    ], replace: replace);
    _active.clearSelection();
    if (!wasShown && !wasEmpty) {
      showAppNotice(context, _l10n.shelfAdded(targets.length));
    }
  }

  /// ⌃⌘S: a hidden shelf shows and takes the keys; one with the keys
  /// hides and gives them back to the panel; one shown elsewhere takes
  /// them.
  void _toggleShelf() {
    final state = _workspace.state;
    if (state.shelfShown && _shelfFocus.hasFocus) {
      _focusOf(state.active).requestFocus();
      _workspace.showShelf(false);
      return;
    }
    _scheduleShelfCheck();
    if (_shelfFocus.context != null) {
      _shelfFocus.requestFocus();
      return;
    }
    // The strip builds in the frame its showing schedules.
    _workspace.showShelf(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _shelfFocus.context != null) _shelfFocus.requestFocus();
    });
  }

  void _clearShelf() => _unshelve([
    for (final item in _workspace.state.shelf.items) item.path,
  ]);

  /// Takes [paths] off the shelf; the keys go back to the panel when the
  /// strip they were in hides with the last item.
  void _unshelve(List<String> paths) {
    final emptied = !_workspace.state.shelf.items.any(
      (i) => !paths.contains(i.path),
    );
    if (emptied && _shelfFocus.hasFocus) {
      _focusOf(_workspace.state.active).requestFocus();
    }
    _workspace.unshelve(paths);
  }

  /// Puts the shelf's items in the active panel's folder through the
  /// operations, conflicts and progress as usual: all copied or all
  /// moved, or with [move] `null` (Vim's `p`) the cut ones moved and the
  /// others copied. Moved items leave the shelf; so do cut ones already
  /// here. Items gone from the disk, or in this folder already, stay out.
  Future<void> _putShelf({bool? move}) async {
    final tab = _tab;
    if (tab == null || !tab.location.isNative) {
      if (tab != null) showAppNotice(context, _notHere(tab.location));
      return;
    }
    final here = tab.location.path;
    final items = _workspace.state.shelf.items;
    bool moves(ShelfItem item) => move ?? item.cut;
    final present = items.where((i) => !i.missing).toList();
    if (present.isEmpty) {
      showAppNotice(context, _l10n.shelfNothingToPut);
      return;
    }
    final away = present.where((i) => i.folder != here).toList();
    final copying = [
      for (final item in away)
        if (!moves(item)) item.path,
    ];
    final moving = [
      for (final item in away)
        if (moves(item)) item.path,
    ];
    final settled = [
      for (final item in present)
        if (moves(item)) item.path,
    ];
    if (copying.isEmpty && moving.isEmpty) {
      _unshelve(settled);
      showAppNotice(context, _l10n.shelfAlreadyHere);
      return;
    }
    await _guarded(() async {
      for (final (kind, sources) in [
        (OpKind.copy, copying),
        (OpKind.move, moving),
      ]) {
        if (sources.isEmpty) continue;
        await widget.operations.start(
          OperationRequest(
            kind: kind,
            sources: sources,
            destination: here,
            preserveAttributes: _prefs.preserveAttributes,
            verify: _prefs.verifyCopies,
          ),
        );
      }
      _unshelve(settled);
    });
  }

  /// Return on an item: the active panel shows it in its folder, and
  /// takes the keys.
  Future<void> _revealShelfItem(ShelfItem item) async {
    final side = _workspace.state.active;
    _focusOf(side).requestFocus();
    await _guarded(
      () => _active.reveal(Location.native(item.folder), focusName: item.name),
    );
  }

  void _scheduleShelfCheck() {
    if (_workspace.state.shelf.isEmpty) return;
    _shelfCheck?.cancel();
    _shelfCheck = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_checkShelf()),
    );
  }

  /// Marks the items gone from the disk (and those back again).
  Future<void> _checkShelf() async {
    final items = _workspace.state.shelf.items;
    final gone = await Future.wait([
      for (final item in items)
        widget.files
            .stat(item.path)
            .then<String?>(
              (_) => null,
              onError: (Object error) =>
                  error is FerryxException &&
                      error.kind == FerryxErrorKind.notFound
                  ? item.path
                  : null,
            ),
    ]);
    if (!mounted) return;
    _workspace.markMissing({...gone.nonNulls});
  }

  // ─── Names in an editor ───

  /// ⌃⇧M: the names as text. The selection's, else every row of the
  /// folder (the rows shown, `..` aside): editing names as lines is for
  /// many at once, and one alone has rename in place.
  Future<void> _renameInEditor() async {
    final tab = _tab;
    if (tab == null) return;
    if (!tab.location.isNative) {
      showAppNotice(context, _notHere(tab.location));
      return;
    }
    // Its checks are one folder's: a name taken there, the same new name
    // on two lines. A flat view's rows are in many.
    if (tab.isFlat) {
      showAppNotice(context, _l10n.noticeNotInFlat);
      return;
    }
    final items = tab.selected.isNotEmpty
        ? tab.targets
        : [
            for (final row in tab.rows)
              if (!row.isParent) row,
          ];
    if (items.isEmpty) {
      showAppNotice(context, _l10n.noticeNothingSelected);
      return;
    }
    // Every name of the folder, hidden ones too: a new name must not take
    // one of them.
    List<FileEntry> all;
    try {
      all = await widget.files.peek(tab.location, showHidden: true);
    } on FerryxException {
      all = tab.listing?.entries ?? const [];
    }
    if (!mounted) return;
    final renamed = {for (final item in items) item.name};
    final changed = await showNamesEditor(
      context,
      items: items,
      existing: {
        for (final entry in all)
          if (!entry.isParent && !renamed.contains(entry.name)) entry.name,
      },
      rename: widget.rename,
    );
    if (changed) await _active.refresh();
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }
}
