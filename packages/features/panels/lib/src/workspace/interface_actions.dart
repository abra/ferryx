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
}
