part of 'workspace_screen.dart';

/// Finder tags (macOS; the window has none where the core says the
/// desktop keeps none): the menu of ⌃⌘T, `:tag`, and the edits.
extension _TagActions on _WorkspaceScreenState {
  bool get _tagsSupported => widget.capabilities.finderTags;

  /// The targets whose tags change: on disk, a notice otherwise.
  List<FileEntry>? _tagTargets() {
    final tab = _tab;
    final targets = _targetsOrNotice();
    if (tab == null || targets.isEmpty) return null;
    if (!tab.location.isNative) {
      showAppNotice(context, _l10n.noticeNotInArchive);
      return null;
    }
    return targets;
  }

  /// ⌃⌘T: the seven colours and the folder's named tags, each checked
  /// when every target has it (a dash when some do), by the cursor's row;
  /// a pick turns it on for all, or off when all had it. "New Tag…" asks
  /// for a name and a colour.
  Future<void> _editTags() async {
    if (!_tagsSupported) return;
    final targets = _tagTargets();
    final tab = _tab;
    if (targets == null || tab == null) return;
    final choices = tagChoices(
      targets: targets,
      folderRows: tab.rows,
      localName: _l10n.tagColorName,
    );
    final picked = await showAppMenu<TagPick>(
      context: context,
      anchor: _rowAnchor(),
      entries: tagMenuEntries(context, choices),
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case TagToggle(:final choice):
        final (add, remove) = choice.edit;
        await _changeTags(targets, add: add, remove: remove);
      case TagNew():
        final tag = await showNewTagDialog(context);
        if (tag != null && mounted) await _changeTags(targets, add: [tag]);
    }
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }

  /// `:tag red,work` adds, `:tag -red` takes off; `:tag` alone opens the
  /// menu.
  Future<void> _vimTag(String arg) async {
    if (!_tagsSupported) {
      showAppNotice(context, _l10n.vimUnknownCommand('tag'));
      return;
    }
    if (arg.trim().isEmpty) {
      await _editTags();
      return;
    }
    final targets = _tagTargets();
    final tab = _tab;
    if (targets == null || tab == null) return;
    final (add, remove) = parseTagCommand(
      arg,
      localName: _l10n.tagColorName,
      folderRows: tab.rows,
    );
    await _changeTags(targets, add: add, remove: remove);
  }

  /// Applies the edit through the core and shows the new tags in both
  /// panels; what failed (a read-only volume…) says so in a notice.
  Future<void> _changeTags(
    List<FileEntry> targets, {
    List<FileTag> add = const [],
    List<String> remove = const [],
  }) => _guarded(() async {
    if (add.isEmpty && remove.isEmpty) return;
    final outcomes = await widget.files.setTags(
      [for (final t in targets) t.path],
      add: add,
      remove: remove,
    );
    final changed = {
      for (final o in outcomes)
        if (o.failure == null) o.path: o.tags,
    };
    _left.applyTags(changed);
    _right.applyTags(changed);
    final failures = [
      for (final o in outcomes)
        if (o.failure != null) o.failure!,
    ];
    if (failures.isNotEmpty && mounted) {
      showAppNotice(
        context,
        _l10n.tagsFailed(failures.length, _l10n.errorMessage(failures.first)),
      );
    }
  });
}
