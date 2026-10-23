part of 'workspace_screen.dart';

/// The Operations stream's commands: Compare Folders over the two panels,
/// undo and redo through the journal, and the dialogs of Synchronize
/// Folders, Checksums and Find Duplicates (opened through the
/// navigation, as features of their own).
extension _OperationsActions on _WorkspaceScreenState {
  Map<AppCommand, VoidCallback> _operationsHandlers() => {
    AppCommand.compareFolders: () => unawaited(_compareFolders()),
    AppCommand.synchronizeFolders: () => unawaited(_synchronizeFolders()),
    AppCommand.undo: () => unawaited(_walkJournal(redo: false)),
    AppCommand.redo: () => unawaited(_walkJournal(redo: true)),
    AppCommand.checksums: () => unawaited(_checksums()),
    AppCommand.findDuplicates: () => unawaited(_findDuplicates()),
  };

  // ─── Compare Folders ───

  /// Selects in both panels what differs (Total Commander's Compare
  /// Directories): what is on one side only, and of two files of one name
  /// the newer. With [contents] (or the preference), files of one size
  /// are compared byte for byte in the core, as an operation; its result
  /// adds to the selection once it ends.
  Future<void> _compareFolders({bool? contents}) async {
    final leftTab = _left.state.active;
    final rightTab = _right.state.active;
    final leftListing = leftTab?.listing;
    final rightListing = rightTab?.listing;
    if (leftTab == null ||
        rightTab == null ||
        leftListing == null ||
        rightListing == null) {
      showAppNotice(context, _l10n.compareNeedsFolders);
      return;
    }
    if (leftTab.location == rightTab.location) {
      showAppNotice(context, _l10n.compareSameFolder);
      return;
    }
    // Names pair across two folders; a flat view's rows are in many.
    if (leftTab.isFlat || rightTab.isFlat) {
      showAppNotice(context, _l10n.noticeNotInFlat);
      return;
    }
    final wanted = contents ?? _prefs.compareOptions.quickContents;
    final onDisk = leftTab.location.isNative && rightTab.location.isNative;
    final comparison = compareFolderEntries(
      left: leftListing.entries,
      right: rightListing.entries,
      caseSensitive: leftTab.sort.collation == Collation.caseSensitive,
      byContents: wanted && onDisk,
    );
    _left.selectOnly(comparison.left);
    _right.selectOnly(comparison.right);
    if (comparison.candidates.isEmpty) {
      _compareNotice(comparison);
      if (wanted && !onDisk) {
        showAppNotice(context, _l10n.compareContentsNotHere);
      }
      return;
    }
    final count = comparison.candidates.length;
    showAppNotice(context, _l10n.compareContentsStarted(count));
    await _guarded(() async {
      final id = await widget.folderSync.compareContents([
        for (final c in comparison.candidates)
          ContentPair(left: c.left.path, right: c.right.path),
      ]);
      final report = await _whenFinished(id);
      if (report.state == OpState.cancelled) return;
      final differing = await widget.folderSync.takeContentDifferences(id);
      if (!mounted) return;
      // The panels moved on meanwhile: the result is for other folders.
      if (_left.state.active?.location != leftTab.location ||
          _right.state.active?.location != rightTab.location) {
        return;
      }
      final full = comparison.withDiffering(differing);
      _left.selectWhere((row) => full.left.contains(row.name), select: true);
      _right.selectWhere(
        (row) => full.right.contains(row.name),
        select: true,
      );
      _compareNotice(full);
    });
  }

  void _compareNotice(FolderComparison comparison) {
    if (comparison.left.isEmpty && comparison.right.isEmpty) {
      showAppNotice(context, _l10n.compareSame);
      return;
    }
    showAppNotice(
      context,
      _l10n.compareSelected(
        _l10n.count(comparison.left.length),
        _l10n.count(comparison.right.length),
      ),
    );
  }

  /// The last report of the operation [id], once it ended.
  Future<OperationProgress> _whenFinished(int id) {
    final known = widget.operations.current[id];
    if (known != null && known.state.isFinished) return Future.value(known);
    return widget.operations.progress.firstWhere(
      (p) => p.id == id && p.state.isFinished,
    );
  }

  // ─── Synchronize Folders ───

  Future<void> _synchronizeFolders() async {
    if (_onServer()) return;
    String folderOf(PanelCubit panel) {
      final location = panel.state.active?.location;
      return location != null && location.isNative ? location.path : '';
    }

    await widget.navigation.openSync(
      context,
      left: folderOf(_left),
      right: folderOf(_right),
    );
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }

  // ─── Undo and redo ───

  /// Undoes ([redo]: redoes) the journal's next step: at once when it
  /// goes as it was; else after a dialog that names what cannot be done,
  /// or offers to forget a step none of which can. The operation's card
  /// is titled by the step and is all the feedback.
  Future<void> _walkJournal({required bool redo}) async {
    final operations = widget.operations;
    final UndoCheck? check;
    try {
      check = await operations.checkStep(redo: redo);
    } on FerryxException catch (error) {
      if (mounted) _notice(error);
      return;
    }
    if (!mounted) return;
    if (check == null) {
      showAppNotice(context, redo ? _l10n.redoNothing : _l10n.undoNothing);
      return;
    }
    if (!check.clean) {
      final choice = await showUndoDialog(context, check: check, redo: redo);
      if (!mounted || choice == null) return;
      if (choice == UndoChoice.forget) {
        await _guarded(() async {
          await operations.forgetStep(check!.step.id, redo: redo);
          if (mounted) showAppNotice(context, _l10n.undoForgotten);
        });
        return;
      }
    }
    final step = _l10n.stepLabel(check.step);
    final title = redo ? _l10n.redoCardTitle(step) : _l10n.undoCardTitle(step);
    try {
      final id = redo
          ? await operations.redo(check.step.id)
          : await operations.undo(check.step.id);
      // The card says what was undone; no notice besides.
      _operationTitles[id] = title;
    } on FerryxException catch (error) {
      if (!mounted) return;
      if (error.kind == FerryxErrorKind.notFound) {
        showAppNotice(context, _l10n.undoMoved);
      } else {
        _notice(error);
      }
    }
  }

  // ─── Checksums and duplicates ───

  /// Checksums of the targets (folders walked), or the check of a
  /// checksum file; [algorithm] as `:checksum md5` asks.
  Future<void> _checksums({ChecksumAlgorithm? algorithm}) async {
    final tab = _tab;
    final targets = _targetsOrNotice();
    if (tab == null || targets.isEmpty) return;
    final paths = _nativePaths(targets);
    if (paths == null) return;
    await widget.navigation.openChecksums(
      context,
      paths: paths,
      base: tab.location.path,
      algorithm: algorithm,
    );
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }

  /// Find Duplicates under the active folder, the other panel's on offer;
  /// a file the dialog asks to show is revealed in the active panel.
  Future<void> _findDuplicates() async {
    if (_onServer()) return;
    final tab = _tab;
    final root = tab?.location.isNative == true
        ? tab!.location.path
        : widget.files.standardFolders().home;
    final other = _opposite.state.active?.location;
    final path = await widget.navigation.openDuplicates(
      context,
      root: root,
      other: other != null && other.isNative && other.path != root
          ? other.path
          : null,
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
