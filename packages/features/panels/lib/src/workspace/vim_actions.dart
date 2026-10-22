part of 'workspace_screen.dart';

/// What Vim mode asks of the window: the register `yy` and `dd` fill and
/// `p` empties, the marks `m` sets and `'` goes to, and the `:` lines.
extension _VimActions on _WorkspaceScreenState {
  // ─── The register ───

  /// The footer's note on what the register holds.
  String? _registerNote(FerryxLocalizations l10n, VimRegister? register) {
    if (register == null) return null;
    return register.move
        ? l10n.vimRegisterCut(register.paths.length)
        : l10n.vimRegisterYank(register.paths.length);
  }

  /// `yy` / `dd`: the targets go to the register, to be copied or moved
  /// where `p` is pressed. Both panels share it.
  void _vimTake({required bool move}) {
    final targets = _targetsOrNotice();
    if (targets.isEmpty) return;
    final paths = _nativePaths(targets);
    if (paths == null) return;
    _workspace.takeRegister(VimRegister(paths: paths, move: move));
    _active.clearSelection();
  }

  /// `p`: the register's rows come to the active folder; a cut register
  /// empties, a yanked one stays for the next `p`. With nothing in the
  /// register, the paths on the clipboard are pasted instead.
  Future<void> _vimPaste() async {
    final register = _workspace.state.register;
    if (register == null) {
      await _pasteItems(move: false);
      return;
    }
    final tab = _tab;
    if (tab == null || !tab.location.isNative) {
      showAppNotice(context, _l10n.noticeNotInArchive);
      return;
    }
    await _guarded(() async {
      await widget.operations.start(
        OperationRequest(
          kind: register.move ? OpKind.move : OpKind.copy,
          sources: register.paths,
          destination: tab.location.path,
          preserveAttributes: _prefs.preserveAttributes,
          verify: _prefs.verifyCopies,
        ),
      );
      if (register.move) _workspace.clearRegister();
    });
  }

  /// `uy`: the register empties.
  void _vimCancelRegister() => _workspace.clearRegister();

  // ─── Marks ───

  /// `m` and a letter: the active folder is remembered under it, across
  /// runs.
  Future<void> _vimSetMark(String letter) async {
    final tab = _tab;
    if (tab == null) return;
    await widget.preferences.update(
      (p) =>
          p.copyWith(vimMarks: {...p.vimMarks, letter: tab.location.encode()}),
    );
    if (mounted) showAppNotice(context, _l10n.vimMarkSet(letter));
  }

  /// `'` and a letter: the folder remembered under it; `''` is the folder
  /// before.
  Future<void> _vimGoMark(String letter) async {
    if (letter == "'") {
      await _active.goBack();
      return;
    }
    final location = Location.decode(_prefs.vimMarks[letter] ?? '');
    if (location == null) {
      showAppNotice(context, _l10n.vimNoMark(letter));
      return;
    }
    await _guarded(() => _active.open(location));
  }

  /// `:marks`: every mark, to pick one.
  Future<void> _vimMarks() async {
    final marks = _prefs.vimMarks.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (marks.isEmpty) {
      showAppNotice(context, _l10n.vimNoMarks);
      return;
    }
    final picked = await showAppMenu<String>(
      context: context,
      anchor: _rowAnchor(),
      entries: [
        AppMenuSection(_l10n.vimMarksTitle),
        for (final mark in marks)
          AppMenuAction(
            value: mark.key,
            label: PathText.shortened(
              Location.decode(mark.value)?.display ?? mark.value,
            ),
            leading: AppKeyCap(mark.key),
          ),
      ],
    );
    if (picked != null && mounted) await _vimGoMark(picked);
  }

  // ─── The command line ───

  /// A `:` line: the command and its argument, as Vim reads them.
  Future<void> _runVimCommand(String line) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    final space = trimmed.indexOf(RegExp(r'\s'));
    final name = space < 0 ? trimmed : trimmed.substring(0, space);
    final arg = space < 0 ? '' : trimmed.substring(space + 1).trim();
    final row = int.tryParse(name);
    if (row != null) {
      _active.moveCursorTo(row - 1);
      return;
    }
    switch (name) {
      case 'cd':
        await _vimCd(arg);
      case 'mkdir':
        await _vimCreate(arg, folder: true);
      case 'touch':
        await _vimCreate(arg, folder: false);
      case 'rename' || 'ren':
        await _vimRename(arg);
      case 'cp' || 'copy':
        await _vimCopyOrMove(arg, move: false);
      case 'mv' || 'move':
        await _vimCopyOrMove(arg, move: true);
      case 'trash':
        await _delete(trashDefault: true, ask: _prefs.confirmTrash);
      case 'delete' || 'rm':
        await _delete(trashDefault: false, ask: _prefs.confirmDelete);
      case 'sort':
        await _vimSort(arg);
      case 'set':
        await _vimSet(arg);
      case 'tabnew' || 'tabe' || 'tabedit':
        await _guarded(
          () => _active.newTab(
            location: arg.isEmpty ? null : Location.native(_vimPath(arg)),
          ),
        );
      case 'tabclose' || 'tabc' || 'q' || 'quit':
        await _active.closeTab();
      case 'tabnext' || 'tabn':
        _active.nextTab();
      case 'tabprevious' || 'tabprev' || 'tabp':
        _active.previousTab();
      case 'e' || 'edit' || 'view':
        if (arg.isEmpty) {
          await _view(preview: false);
        } else {
          await widget.navigation.openViewer(
            context,
            Location.native(_vimPath(arg)),
          );
        }
      case 'find':
        await _findFiles();
      case 'marks':
        await _vimMarks();
      case 'refresh' || 'r':
        await _active.refresh();
      case 'sync':
        await _syncPanels();
      case 'swap':
        await _swapPanels();
      case 'help' || 'h':
        await widget.navigation.openCheatSheet(context);
      // ─── Files core ───
      case 'extract':
        await _extractTo(destination: arg.isEmpty ? null : _vimPath(arg));
      case 'flat':
        await _active.toggleFlatView();
      default:
        showAppNotice(context, _l10n.vimUnknownCommand(name));
    }
  }

  Future<void> _vimCd(String arg) async {
    if (arg == '-') {
      await _active.goBack();
      return;
    }
    if (arg.isEmpty) {
      await _goStandard((f) => f.home);
      return;
    }
    final path = _vimPath(arg);
    await _guarded(() async {
      if (widget.files.isArchive(path) && !widget.files.isDirectory(path)) {
        await _active.open(Location.inArchive(archive: path));
      } else {
        await _active.open(Location.native(path));
      }
    });
  }

  Future<void> _vimCreate(String arg, {required bool folder}) async {
    if (arg.isEmpty) {
      await _newItem(folder: folder);
      return;
    }
    final tab = _tab;
    if (tab == null || !tab.location.isNative) {
      showAppNotice(context, _l10n.noticeNotInArchive);
      return;
    }
    final path = _vimPath(arg);
    await _guarded(() async {
      if (folder) {
        await widget.files.createDirectory(path);
      } else {
        await widget.files.createFile(path);
      }
      final slash = path.lastIndexOf('/');
      final parent = slash <= 0 ? '/' : path.substring(0, slash);
      if (parent == tab.location.path) {
        await _active.open(tab.location, focusName: path.substring(slash + 1));
      }
    });
  }

  Future<void> _vimRename(String arg) async {
    if (arg.isEmpty) {
      _active.startRenaming();
      return;
    }
    final tab = _tab;
    final focused = tab?.focused;
    if (tab == null || focused == null || focused.isParent) return;
    if (!tab.location.isNative) {
      showAppNotice(context, _l10n.noticeNotInArchive);
      return;
    }
    await _guarded(() async {
      final renamed = await widget.files.rename(focused.path, arg);
      final slash = renamed.lastIndexOf('/');
      await _active.open(tab.location, focusName: renamed.substring(slash + 1));
    });
  }

  /// `:cp` / `:mv` with a folder copies or moves the targets there; with
  /// another name, as that name; with nothing, the dialog asks.
  Future<void> _vimCopyOrMove(String arg, {required bool move}) async {
    if (arg.isEmpty) {
      await _copyOrMove(move: move, asName: false);
      return;
    }
    final targets = _targetsOrNotice();
    if (targets.isEmpty) return;
    final paths = _nativePaths(targets);
    if (paths == null) return;
    final path = _vimPath(arg);
    final String destination;
    String? newName;
    if (widget.files.isDirectory(path)) {
      destination = path;
    } else {
      final slash = path.lastIndexOf('/');
      destination = slash <= 0 ? '/' : path.substring(0, slash);
      newName = path.substring(slash + 1);
    }
    await _guarded(() async {
      await widget.operations.start(
        OperationRequest(
          kind: move ? OpKind.move : OpKind.copy,
          sources: paths,
          destination: destination,
          newName: newName,
          preserveAttributes: _prefs.preserveAttributes,
          verify: _prefs.verifyCopies,
        ),
      );
      _active.clearSelection();
    });
  }

  /// `:sort name`, `:sort size!` (the other way round), `:sort` alone
  /// turns the order.
  Future<void> _vimSort(String arg) async {
    final tab = _tab;
    if (tab == null) return;
    if (arg.isEmpty) {
      await _active.sortReverse();
      return;
    }
    final reverse = arg.endsWith('!');
    final wanted = (reverse ? arg.substring(0, arg.length - 1) : arg)
        .trim()
        .toLowerCase();
    final field = SortField.values.cast<SortField?>().firstWhere(
      (f) =>
          f!.name == wanted ||
          f.letter == wanted ||
          (wanted == 'ext' && f == SortField.extension) ||
          (wanted == 'date' && f == SortField.modified),
      orElse: () => null,
    );
    if (field == null) {
      showAppNotice(context, _l10n.vimUnknownCommand('sort $arg'));
      return;
    }
    await _active.setSort(
      tab.sort.copyWith(
        field: field,
        descending: field.defaultDescending != reverse,
      ),
    );
  }

  /// `:set hidden`, `:set nohidden`, `:set hidden!`; also `foldersfirst`,
  /// `parent`, `tabs` and `vim` itself.
  Future<void> _vimSet(String arg) async {
    var option = arg.trim().toLowerCase();
    bool? value;
    if (option.endsWith('!')) {
      option = option.substring(0, option.length - 1);
    } else if (option.startsWith('no')) {
      option = option.substring(2);
      value = false;
    } else {
      value = true;
    }
    final Preferences Function(Preferences p, bool v)? apply = switch (option) {
      'hidden' => (p, v) => p.copyWith(showHiddenFiles: v),
      'foldersfirst' => (p, v) => p.copyWith(foldersFirst: v),
      'parent' => (p, v) => p.copyWith(showParentEntry: v),
      'tabs' => (p, v) => p.copyWith(showTabBarAlways: v),
      'vim' => (p, v) => p.copyWith(vimMode: v),
      _ => null,
    };
    final current = switch (option) {
      'hidden' => _prefs.showHiddenFiles,
      'foldersfirst' => _prefs.foldersFirst,
      'parent' => _prefs.showParentEntry,
      'tabs' => _prefs.showTabBarAlways,
      'vim' => _prefs.vimMode,
      _ => false,
    };
    if (apply == null) {
      showAppNotice(context, _l10n.vimUnknownCommand('set $arg'));
      return;
    }
    final next = value ?? !current;
    await widget.preferences.update((p) => apply(p, next));
  }

  /// A path as typed on the command line: `~` is home, a relative one is
  /// under the active folder, `..` climbs.
  String _vimPath(String raw) {
    final home = widget.files.standardFolders().home;
    final tab = _tab;
    final base = tab?.location.isNative == true ? tab!.location.path : home;
    final String joined;
    if (raw == '~') {
      joined = home;
    } else if (raw.startsWith('~/')) {
      joined = '$home${raw.substring(1)}';
    } else if (raw.startsWith('/')) {
      joined = raw;
    } else {
      joined = '$base/$raw';
    }
    final parts = <String>[];
    for (final part in joined.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    return '/${parts.join('/')}';
  }

  /// Tab on the command line: the command names, or the names under the
  /// folder the last argument points into.
  Future<List<String>> _vimComplete(String line) async {
    final space = line.indexOf(RegExp(r'\s'));
    if (space < 0) {
      return [
        for (final name in _vimCommandNames)
          if (name.startsWith(line.toLowerCase())) '$name ',
      ];
    }
    final head = line.substring(0, space + 1);
    final arg = line.substring(space + 1).trimLeft();
    final slash = arg.lastIndexOf('/');
    final dirPart = slash < 0 ? '' : arg.substring(0, slash + 1);
    final prefix = arg.substring(slash + 1).toLowerCase();
    final folder = dirPart.isEmpty ? _vimPath('.') : _vimPath(dirPart);
    final List<FileEntry> rows;
    try {
      rows = await widget.files.peek(
        Location.native(folder),
        showHidden: _prefs.showHiddenFiles || prefix.startsWith('.'),
      );
    } on FerryxException {
      return const [];
    }
    final names = [
      for (final row in rows)
        if (!row.isParent && row.name.toLowerCase().startsWith(prefix))
          row.isDir ? '${row.name}/' : row.name,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [for (final name in names) '$head$dirPart$name'];
  }

  static const _vimCommandNames = [
    'cd',
    'cp',
    'delete',
    'edit',
    'find',
    'help',
    'marks',
    'mkdir',
    'mv',
    'refresh',
    'rename',
    'set',
    'sort',
    'swap',
    'sync',
    'tabclose',
    'tabnew',
    'tabnext',
    'tabprevious',
    'touch',
    'trash',
    'view',
    // ─── Files core ───
    'extract',
    'flat',
  ];
}
