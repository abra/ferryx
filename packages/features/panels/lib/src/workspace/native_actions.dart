part of 'workspace_screen.dart';

/// The largest archive member taken out for Quick Look or the share
/// picker; a larger one gets a notice instead of a long wait.
const int _nativeExtractLimit = 64 << 20;

/// What the window keeps for the desktop's own services: the panel Quick
/// Look follows and what it shows, each side's drop highlight, the
/// volumes a drag asked about.
class _NativeState {
  StreamSubscription<QuickLookEvent>? events;
  StreamSubscription<PanelState>? followed;
  StreamSubscription<WorkspaceState>? sides;

  /// The side Quick Look follows, while it is open.
  PanelSide? side;

  /// What the open panel was given, to tell a cursor move (the item
  /// changes) from another list (sent again).
  Location? location;
  List<FileEntry>? rows;
  Set<String>? selected;
  QuickLookPick pick = QuickLookPick.empty;

  /// The archive member shown, by its row's key.
  String? member;
  int index = -1;

  /// Bumped by every list sent, so a slow extraction cannot overtake a
  /// later move.
  int generation = 0;

  final highlights = {
    for (final side in PanelSide.values) side: ValueNotifier<DropSpot?>(null),
  };

  /// The volume of each folder a drag asked about, for this drag.
  final volumes = <String, int?>{};

  void forget() {
    followed?.cancel();
    sides?.cancel();
    followed = null;
    sides = null;
    side = null;
    location = null;
    rows = null;
    selected = null;
    pick = QuickLookPick.empty;
    member = null;
    index = -1;
    generation++;
  }

  void dispose() {
    events?.cancel();
    forget();
    for (final highlight in highlights.values) {
      highlight.dispose();
    }
  }
}

/// Quick Look, the share picker, and files dragged out of the panels and
/// dropped on them: the window's side of `PlatformServices`.
extension _NativeActions on _WorkspaceScreenState {
  PlatformServices get _platform => widget.platformServices;

  void _startNative() {
    _native.events = _platform.quickLookEvents.listen(_onQuickLookEvent);
  }

  /// Whether [command] runs on this desktop; a notice when it does not
  /// (only a `:` line can ask for a command that is hidden).
  bool _available(AppCommand command) {
    if (widget.shortcutMap.isAvailable(command)) return true;
    showAppNotice(context, _l10n.nativeUnavailable);
    return false;
  }

  /// Runs [action], turning the desktop's failure into a notice.
  Future<void> _platformGuarded(Future<void> Function() action) async {
    try {
      await action();
    } on PlatformException catch (error) {
      if (mounted) {
        _notice(FerryxException(FerryxErrorKind.io, error.message ?? ''));
      }
    } on MissingPluginException catch (error) {
      if (mounted) {
        _notice(FerryxException(FerryxErrorKind.unsupported, '$error'));
      }
    }
  }

  /// [entries] of the archive folder [location] taken out to a temporary
  /// folder, each with its path there; folders are skipped, and a member
  /// over the limit with a notice when [notify].
  Future<List<(FileEntry, String)>> _extracted(
    Location location,
    List<FileEntry> entries, {
    required bool notify,
  }) async {
    final out = <(FileEntry, String)>[];
    for (final entry in entries) {
      if (entry.isDir || entry.isParent) continue;
      if ((entry.size ?? 0) > _nativeExtractLimit) {
        if (notify && mounted) {
          showAppNotice(context, _l10n.quickLookTooLarge(entry.name));
        }
        continue;
      }
      try {
        final path = await widget.files.extractToTemp(
          location.archive!,
          // A flat view's row is in a folder of its own.
          location.join(entry.key).path,
        );
        out.add((entry, path));
      } on FerryxException catch (error) {
        if (notify && mounted) _notice(error);
      }
    }
    return out;
  }

  // ─── Quick Look ───

  bool get _quickLookOpen => _platform.quickLookOpen.value;

  /// ⌘Y: Quick Look on what the active panel points at, or closed.
  Future<void> _toggleQuickLook() async {
    if (!_available(AppCommand.quickLook)) return;
    if (_quickLookOpen) {
      await _closeQuickLook();
      return;
    }
    final side = _workspace.state.active;
    final tab = _cubitOf(side).state.active;
    if (tab == null) return;
    if (await _showQuickLookOf(tab, notify: true) && mounted) {
      _followQuickLook(side);
    }
  }

  /// Space: closes Quick Look while it is open, else the built-in preview.
  Future<void> _spacePreview() =>
      _quickLookOpen ? _closeQuickLook() : _preview();

  /// Esc closes Quick Look first.
  bool _escapeQuickLook() {
    if (!_quickLookOpen) return false;
    unawaited(_closeQuickLook());
    return true;
  }

  Future<void> _closeQuickLook() async {
    _native.forget();
    await _platformGuarded(_platform.closeQuickLook);
    if (mounted) _focusOf(_workspace.state.active).requestFocus();
  }

  /// Sends what Quick Look takes from [tab] (taken out of an archive
  /// first); answers whether there was anything to show.
  Future<bool> _showQuickLookOf(
    PanelTabState tab, {
    required bool notify,
  }) async {
    final pick = quickLookPick(tab);
    final native = _native
      ..location = tab.location
      ..rows = tab.rows
      ..selected = tab.selected
      ..pick = pick
      ..member = tab.location.isNative ? null : tab.focused?.key
      ..index = pick.index;
    final generation = ++native.generation;
    final List<String> paths;
    var index = pick.index;
    if (tab.location.isNative) {
      paths = [for (final entry in pick.entries) entry.path];
    } else {
      final taken = await _extracted(
        tab.location,
        pick.entries,
        notify: notify,
      );
      paths = [for (final (_, path) in taken) path];
      final wanted = pick.entries.elementAtOrNull(pick.index)?.key;
      index = taken.indexWhere((t) => t.$1.key == wanted);
    }
    if (generation != native.generation || !mounted) return false;
    if (paths.isEmpty) {
      if (notify && pick.isEmpty) {
        showAppNotice(context, _l10n.quickLookNothing);
      }
      return false;
    }
    await _platformGuarded(
      () => _platform.showQuickLook(
        QuickLookItems(paths, index: index < 0 ? 0 : index),
      ),
    );
    return _quickLookOpen;
  }

  /// Keeps the panel on [side]'s cursor while it is open, and on the
  /// other side's once the keys move there.
  void _followQuickLook(PanelSide side) {
    final native = _native;
    native.side = side;
    native.followed?.cancel();
    native.followed = _cubitOf(side).stream.listen((state) {
      final tab = state.active;
      if (tab != null) unawaited(_quickLookFollow(tab));
    });
    native.sides ??= _workspace.stream.listen((workspace) {
      final active = workspace.active;
      if (!_quickLookOpen || active == _native.side) return;
      _followQuickLook(active);
      final tab = _cubitOf(active).state.active;
      if (tab != null) unawaited(_showQuickLookOf(tab, notify: false));
    });
  }

  /// The followed panel changed: the item when only its cursor moved, the
  /// whole list when the rows or the selection did.
  Future<void> _quickLookFollow(PanelTabState tab) async {
    final native = _native;
    if (!_quickLookOpen) return;
    final sameList =
        tab.location == native.location &&
        identical(tab.rows, native.rows) &&
        identical(tab.selected, native.selected);
    if (sameList && tab.location.isNative) {
      final index = native.pick.fromSelection
          ? quickLookIndexIn(native.pick.entries, tab.focused)
          : quickLookFolderIndex(tab);
      if (index < 0 || index == native.index) return;
      native.index = index;
      await _platformGuarded(() => _platform.selectQuickLookItem(index));
      return;
    }
    if (sameList && tab.focused?.key == native.member) return;
    await _showQuickLookOf(tab, notify: false);
  }

  void _onQuickLookEvent(QuickLookEvent event) {
    if (!mounted) return;
    switch (event) {
      case QuickLookClosed():
        _native.forget();
        _focusOf(_workspace.state.active).requestFocus();
      case QuickLookStep(:final delta):
        _cubitOf(_native.side ?? _workspace.state.active).moveCursor(delta);
    }
  }

  // ─── Share ───

  /// The share picker for the targets, pointing at [anchor]: where a menu
  /// was opened, else the cursor's row.
  Future<void> _share({Rect? anchor}) async {
    if (!_available(AppCommand.share)) return;
    final tab = _tab;
    final targets = _targetsOrNotice();
    if (tab == null || targets.isEmpty) return;
    final at = anchor ?? _rowAnchor();
    final List<String> paths;
    if (tab.location.isNative) {
      paths = [for (final entry in targets) entry.path];
    } else {
      final taken = await _extracted(tab.location, targets, notify: true);
      paths = [for (final (_, path) in taken) path];
    }
    if (paths.isEmpty || !mounted) return;
    await _platformGuarded(() => _platform.share(paths, anchor: at));
  }

  // ─── Drag and drop ───

  PanelDragHooks? _dragHooksFor(PanelSide side) {
    if (!_platform.capabilities.fileDrags) return null;
    return PanelDragHooks(
      onDragStart: (index, global) => _startDrag(side, index, global),
      onOver: (spot, drag) => _dropOver(side, spot, drag),
      onLeave: (spot) => _dropLeave(side, spot),
      onDrop: (spot, drag, operation) =>
          unawaited(_drop(side, spot, drag, operation)),
      highlight: _native.highlights[side]!,
    );
  }

  /// Row [index] of [side] dragged out: the selection when the row is in
  /// it, else the row alone, with the cursor moved onto it (Finder's way).
  void _startDrag(PanelSide side, int index, Offset global) {
    final cubit = _cubitOf(side);
    final before = cubit.state.active;
    if (before == null || index < 0 || index >= before.rows.length) return;
    final row = before.rows[index];
    if (row.isParent) return;
    _focusPanel(side);
    final selection = before.selected.contains(row.key);
    if (!selection) cubit.moveCursorTo(index, scroll: false);
    final tab = cubit.state.active ?? before;
    final entries = selection ? tab.targets : [row];
    final native = tab.location.isNative;
    final paths = [for (final entry in entries) entry.path];
    final request = FileDragRequest(
      position: global,
      image: FileDragImage(entry: row, count: entries.length),
      imageSize: FileDragImage.size,
      itemCount: entries.length,
      paths: native ? paths : const [],
      local: PanelDragPayload(
        side: side,
        folder: tab.location,
        paths: paths,
      ).encode(),
      allowed: native
          ? const {FileDropOperation.copy, FileDropOperation.move}
          : const {FileDropOperation.copy},
    );
    unawaited(
      _platformGuarded(() => _platform.startFileDrag(context, request)),
    );
  }

  FileDropOperation _dropOver(
    PanelSide side,
    DropSpot spot,
    FileDragInfo drag,
  ) {
    final source = DragSource.of(drag);
    final operation = planDrop(
      destination: spot.folder,
      source: source,
      allowed: drag.allowed,
      sameVolume: _sameVolume(source, spot.folder),
    );
    _lightDrop(side, dropAccepts(operation) ? spot : null);
    return operation;
  }

  void _dropLeave(PanelSide side, DropSpot spot) {
    final highlight = _native.highlights[side]!;
    if (highlight.value == spot) highlight.value = null;
  }

  /// Lights [spot] on [side] and nothing elsewhere.
  void _lightDrop(PanelSide side, DropSpot? spot) {
    for (final entry in _native.highlights.entries) {
      entry.value.value = entry.key == side ? spot : null;
    }
  }

  /// Whether [source] is on the volume of [destination]; `null` when
  /// either cannot be told (another application's drag not read yet).
  bool? _sameVolume(DragSource source, Location destination) {
    final folder = source.folder;
    if (folder == null || !folder.isNative || !destination.isNative) {
      return null;
    }
    final volumes = _native.volumes;
    if (volumes.length > 64) volumes.clear();
    final from = volumes.putIfAbsent(
      folder.path,
      () => widget.files.volumeOf(folder.path),
    );
    final to = volumes.putIfAbsent(
      destination.path,
      () => widget.files.volumeOf(destination.path),
    );
    return from == null || to == null ? null : from == to;
  }

  /// The files dropped at [spot] with [operation], the drag's last
  /// feedback: copied, moved or taken out of an archive by the operations
  /// runner, with its questions and progress card.
  Future<void> _drop(
    PanelSide side,
    DropSpot spot,
    FileDragInfo drag,
    FileDropOperation operation,
  ) async {
    _lightDrop(side, null);
    final source = DragSource.of(drag);
    final plan = planDrop(
      destination: spot.folder,
      source: source,
      allowed: drag.allowed,
      sameVolume: _sameVolume(source, spot.folder),
    );
    _native.volumes.clear();
    if (source.paths.isEmpty) {
      showAppNotice(context, _l10n.dropNoFiles);
      return;
    }
    if (plan == FileDropOperation.forbidden && spot.folder.isNative) {
      // Found only now that every path is known: a folder into itself.
      showAppNotice(context, _l10n.dropIntoItself);
      return;
    }
    if (!dropAccepts(plan) || !dropAccepts(operation)) return;
    await _guarded(() async {
      final OperationRequest request;
      if (source.fromArchive) {
        request = OperationRequest(
          kind: OpKind.extract,
          sources: source.paths,
          archive: source.folder!.archive,
          destination: spot.folder.path,
        );
      } else {
        request = OperationRequest(
          kind: operation == FileDropOperation.move ? OpKind.move : OpKind.copy,
          sources: source.paths,
          destination: spot.folder.path,
          preserveAttributes: _prefs.preserveAttributes,
          verify: _prefs.verifyCopies,
        );
      }
      await widget.operations.start(request);
      // The selection dragged has gone where it went, as after F5 or F6.
      final payload = source.payload;
      if (payload == null) return;
      final from = _cubitOf(payload.side);
      final tab = from.state.active;
      if (tab == null ||
          tab.location != payload.folder ||
          tab.selected.isEmpty) {
        return;
      }
      final dragged = payload.paths.toSet();
      if (tab.targets.every((t) => dragged.contains(t.path))) {
        from.clearSelection();
      }
    });
  }
}
