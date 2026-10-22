part of 'workspace_screen.dart';

/// Archives in the window: Extract To, and the password an encrypted one
/// asks for before it lists, opens or extracts.
extension _ArchiveActions on _WorkspaceScreenState {
  /// The most files whose first bytes are read to find the archives among
  /// them (names already say for most).
  static const _detectAtMost = 64;

  // ─── Extract To ───

  /// ⌥F9, `:extract [dir]`: the archives among the targets, each into the
  /// destination or a folder of its own; inside an archive, the items
  /// picked. With [destination] given (`:extract dir`) no dialog asks
  /// unless a password is needed.
  Future<void> _extractTo({String? destination}) async {
    final tab = _tab;
    final targets = _targetsOrNotice();
    if (tab == null || targets.isEmpty) return;
    if (!tab.location.isNative) {
      await _extractMembers(tab, targets, destination: destination);
      return;
    }
    final archives = await _archivesAmong(targets);
    if (!mounted) return;
    if (archives.isEmpty) {
      showAppNotice(context, _l10n.archiveNoArchives);
      return;
    }
    final sources = [
      for (final archive in archives)
        ExtractSource(
          name: archive.name,
          path: archive.path,
          info: _archiveInfo(archive.path),
        ),
    ];
    ExtractChoice? choice;
    if (destination != null) {
      final infos = await Future.wait([for (final s in sources) s.info!]);
      if (!mounted) return;
      if (!infos.any((i) => i?.asksPassword ?? false)) {
        choice = ExtractChoice(
          destination: destination,
          intoFolders: infos.any((i) => i?.wantsFolder ?? true),
          password: null,
          conflicts: ConflictPolicy.ask,
        );
      }
    }
    choice ??= await showExtractDialog(
      context,
      archives: sources,
      defaultDestination: destination ?? _extractDefault(tab),
      complete: _completeFolder,
      checkPassword: _tryArchivePassword,
    );
    if (choice == null || !mounted) return;
    final chosen = choice;
    await _guarded(() async {
      await widget.operations.start(
        OperationRequest(
          kind: OpKind.extract,
          sources: [for (final a in archives) a.path],
          destination: _resolveTyped(chosen.destination),
          conflicts: chosen.conflicts,
          password: chosen.password,
          intoFolders: chosen.intoFolders,
        ),
      );
      _active.clearSelection();
    });
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }

  /// ⌥F9 inside an archive: the items picked, written out to a folder.
  Future<void> _extractMembers(
    PanelTabState tab,
    List<FileEntry> targets, {
    String? destination,
  }) async {
    final archive = tab.location.archive;
    if (archive == null) return;
    final source = ExtractSource(
      name: PathText.baseName(archive),
      path: archive,
      info: _archiveInfo(archive),
    );
    ExtractChoice? choice;
    if (destination != null && !((await source.info)?.asksPassword ?? false)) {
      choice = ExtractChoice(
        destination: destination,
        intoFolders: false,
        password: null,
        conflicts: ConflictPolicy.ask,
      );
    }
    if (!mounted) return;
    choice ??= await showExtractDialog(
      context,
      archives: [source],
      members: targets.length,
      defaultDestination: destination ?? _extractDefault(tab),
      complete: _completeFolder,
      checkPassword: _tryArchivePassword,
    );
    if (choice == null || !mounted) return;
    final chosen = choice;
    await _guarded(() async {
      await widget.operations.start(
        OperationRequest(
          kind: OpKind.extract,
          sources: [for (final t in targets) t.path],
          archive: archive,
          destination: _resolveTyped(chosen.destination),
          conflicts: chosen.conflicts,
          password: chosen.password,
        ),
      );
      _active.clearSelection();
    });
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }

  /// The archives among [targets]: by their names, else (for a few) by
  /// their first bytes.
  Future<List<FileEntry>> _archivesAmong(List<FileEntry> targets) async {
    final archives = <FileEntry>[];
    var detected = 0;
    for (final target in targets) {
      if (target.isDir || target.isParent) continue;
      if (widget.files.isArchive(target.path)) {
        archives.add(target);
      } else if (detected++ < _detectAtMost) {
        try {
          if (await widget.files.detectArchive(target.path)) {
            archives.add(target);
          }
        } on FerryxException {
          // Unreadable: not one to extract.
        }
      }
    }
    return archives;
  }

  Future<ArchiveInfo?> _archiveInfo(String path) async {
    try {
      return await widget.files.archiveInfo(path);
    } on FerryxException catch (error) {
      widget.logger.warn('archive info $path', error: error);
      return null;
    }
  }

  /// Where an extraction goes unless told: the other panel's folder, or
  /// this one's when the other is inside an archive.
  String _extractDefault(PanelTabState tab) {
    final opposite = _opposite.state.active;
    if (opposite != null && opposite.location.isNative) {
      return opposite.location.path;
    }
    return tab.location.isNative
        ? tab.location.path
        : PathText.parentOf(tab.location.archive ?? '') ??
              widget.files.standardFolders().home;
  }

  /// A typed folder as the core takes it: `~` is home, a relative one is
  /// under the active folder.
  String _resolveTyped(String typed) {
    final home = widget.files.standardFolders().home;
    if (typed == '~') return home;
    if (typed.startsWith('~/')) return '$home${typed.substring(1)}';
    if (PathText.isAbsolute(typed)) return typed;
    final tab = _tab;
    final base = tab != null && tab.location.isNative
        ? tab.location.path
        : home;
    return PathText.join(base, typed);
  }

  Future<List<String>> _completeFolder(String text) {
    final tab = _tab;
    final home = widget.files.standardFolders().home;
    return completeFolderPath(
      text,
      home: home,
      base: tab != null && tab.location.isNative ? tab.location.path : home,
      peek: (folder) async {
        try {
          final rows = await widget.files.peek(
            Location.native(folder),
            showHidden: _prefs.showHiddenFiles,
          );
          return [
            for (final row in rows)
              if (row.isDir && !row.isParent) row.name,
          ];
        } on FerryxException {
          return const [];
        }
      },
    );
  }

  // ─── Passwords ───

  /// Tries [password] on [archive] and keeps it in the core when it opens
  /// it; answers the error otherwise.
  Future<FerryxException?> _tryArchivePassword(
    String archive,
    String password,
  ) async {
    try {
      await widget.files.setArchivePassword(archive, password);
      return null;
    } on FerryxException catch (error) {
      return error;
    }
  }

  /// Asks the password of [archive]; answers whether one opened it.
  Future<bool> _askArchivePassword(String archive) => showArchivePasswordDialog(
    context,
    name: PathText.baseName(archive),
    submit: (password) => _tryArchivePassword(archive, password),
  );

  /// A panel's archive folder asked for its password: asked, then the
  /// folder opens; dismissed, the panel stays with the error saying why.
  Future<void> _passwordForPanel(PanelSide side, Location location) async {
    final archive = location.archive;
    if (archive == null) return;
    final opened = await _askArchivePassword(archive);
    if (!mounted) return;
    final panel = _cubitOf(side);
    if (opened) await panel.openAfterPassword();
    if (mounted) _focusOf(side).requestFocus();
  }

  /// Before an archive member is opened, viewed or copied out: its
  /// password, when it is encrypted and none was given. Answers whether
  /// to go on.
  Future<bool> _ensureArchivePassword(String archive) async {
    final info = await _archiveInfo(archive);
    if (info == null || !info.asksPassword || !mounted) return true;
    return _askArchivePassword(archive);
  }
}
