part of 'workspace_screen.dart';

/// The integrated terminal in the window: its place ([TerminalDock]), where
/// the keys go as it moves, its height under the panels, and the folder
/// kept in step with the active panel.
extension _TerminalActions on _WorkspaceScreenState {
  void _initTerminal() {
    final saved = widget.preferences.current.terminal;
    _dock = TerminalDockCubit(
      TerminalDock(
        mode: saved.place,
        lines: saved.lines,
      ),
    );
    final terminal = widget.terminal?.create();
    _terminal = terminal;
    if (terminal == null) return;
    // Esc on the edge puts back the height the keys found.
    _terminalEdgeFocus.addListener(() {
      if (_terminalEdgeFocus.hasFocus) _linesBeforeKeys = _dock.state.lines;
    });
    _terminalSubscriptions.addAll([
      // The shell follows the active panel, whichever side and tab.
      _left.stream.listen((_) => _followActiveFolder()),
      _right.stream.listen((_) => _followActiveFolder()),
      _workspace.stream.listen((_) => _followActiveFolder()),
      // A cd typed in the shell takes the active panel along.
      terminal.shellFolders.listen((folder) {
        if (mounted) unawaited(_active.open(Location.native(folder)));
      }),
    ]);
  }

  void _disposeTerminal() {
    _dockTimer?.cancel();
    _saveDock();
    for (final subscription in _terminalSubscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_terminal?.dispose());
    unawaited(_dock.close());
    _terminalFocus.dispose();
    _terminalEdgeFocus.dispose();
  }

  /// The active panel's folder on disk; `null` inside an archive or
  /// before it has one.
  String? _activeFolder() {
    final location = _active.state.active?.location;
    return location != null && location.isNative ? location.path : null;
  }

  void _followActiveFolder() {
    final folder = _activeFolder();
    if (folder == _followed) return;
    _followed = folder;
    _terminal?.followFolder(folder);
  }

  /// Once both panels have their folders: a terminal left open last time
  /// comes back.
  void _restoreTerminal() {
    if (!mounted || !_dock.state.shown) return;
    _followed = _activeFolder();
    _terminal?.show(_followed);
  }

  Map<AppCommand, VoidCallback> _terminalHandlers() => _terminal == null
      ? const {}
      : {
          AppCommand.showTerminal: _showTerminal,
          AppCommand.hideTerminal: _hideTerminal,
          AppCommand.togglePanelsOverTerminal: _togglePanelsOverTerminal,
          AppCommand.toggleTerminal: _toggleTerminalWindow,
        };

  /// Nimble Commander's ⌃⌥↑: reveals the terminal under the panels and
  /// gives it the keys; pressed again there, one line taller.
  void _showTerminal() {
    final dock = _dock.state;
    if (dock.mode == TerminalPlace.hidden) {
      _dock.show();
    } else if (_terminalFocus.hasFocus &&
        dock.mode == TerminalPlace.overlapped) {
      _dock.setLines(dock.lines + 1, maxLines: _terminalMaxLines());
    }
    _dockChanged(focusTerminal: true);
  }

  void _hideTerminal() {
    if (!_dock.state.shown) return;
    _dock.hide();
    _dockChanged(focusTerminal: false);
  }

  void _togglePanelsOverTerminal() {
    _dock.togglePanels();
    _dockChanged(focusTerminal: !_dock.state.panelsShown);
  }

  void _toggleTerminalWindow() {
    _dock.toggleFullWindow();
    final mode = _dock.state.mode;
    _dockChanged(
      focusTerminal:
          mode == TerminalPlace.fullWindow ||
          mode == TerminalPlace.panelsHidden,
    );
  }

  /// Tells the terminal whether it is on screen, moves the keys, and saves
  /// the place for the next run.
  void _dockChanged({required bool focusTerminal}) {
    final terminal = _terminal;
    if (terminal == null) return;
    if (_dock.state.shown) {
      _followed = _activeFolder();
      terminal.show(_followed);
    } else {
      terminal.hide();
    }
    if (focusTerminal && _dock.state.shown) {
      // Taken once the view is built, if it is not yet.
      _terminalFocus.requestFocus();
    } else {
      _focusOf(_workspace.state.active).requestFocus();
    }
    _saveDockSoon();
  }

  void _saveDockSoon() {
    _dockTimer?.cancel();
    _dockTimer = Timer(const Duration(milliseconds: 400), _saveDock);
  }

  void _saveDock() {
    _dockTimer?.cancel();
    final dock = _dock.state;
    final saved = widget.preferences.current.terminal;
    if (saved.lines == dock.lines && saved.place == dock.mode) return;
    unawaited(
      widget.preferences.update(
        (p) => p.copyWith(
          terminal: p.terminal.copyWith(lines: dock.lines, place: dock.mode),
        ),
      ),
    );
  }

  // ─── Height ───

  /// The least the panels keep over the terminal: a header, four rows and
  /// the footer.
  double _panelsMinHeight(BuildContext context) =>
      context.metrics.topBarHeight +
      4 * context.metrics.listRowHeight +
      PanelFooter.heightOf(context);

  int _terminalMaxLines() {
    final terminal = _terminal;
    if (terminal == null || _terminalArea <= 0) return TerminalDock.minLines;
    final room =
        _terminalArea -
        _panelsMinHeight(context) -
        terminal.chromeHeight(context);
    return math.max(
      TerminalDock.minLines,
      (room / terminal.lineHeight(context)).floor(),
    );
  }

  /// The terminal's height under the panels in an area [area] tall: its
  /// lines, as many as fit beside the panels' least, and its bar.
  double _terminalHeight(BuildContext context, double area) {
    final terminal = _terminal!;
    final line = terminal.lineHeight(context);
    final chrome = terminal.chromeHeight(context);
    final room = area - _panelsMinHeight(context) - chrome;
    final fit = math.max(TerminalDock.minLines, (room / line).floor());
    final lines = math.min(_dock.state.lines, fit);
    return math.min(area, (chrome + lines * line).roundToDouble());
  }

  void _onTerminalEdgeDragStart() => _dragLines = _dock.state.lines.toDouble();

  void _onTerminalEdgeDrag(double dy) {
    final terminal = _terminal;
    if (terminal == null) return;
    // Up makes the terminal taller.
    _dragLines -= dy / terminal.lineHeight(context);
    _dock.setLines(_dragLines.round(), maxLines: _terminalMaxLines());
  }

  void _onTerminalEdgeAction(AppSplitterAction action) {
    final lines = _dock.state.lines;
    final max = _terminalMaxLines();
    void set(int value) => _dock.setLines(value, maxLines: max);
    switch (action) {
      // The edge moves up: a taller terminal.
      case AppSplitterAction.left:
        set(lines + 1);
      case AppSplitterAction.right:
        set(lines - 1);
      case AppSplitterAction.farLeft:
        set(lines + 5);
      case AppSplitterAction.farRight:
        set(lines - 5);
      case AppSplitterAction.narrowest:
        set(max);
      case AppSplitterAction.widest:
        set(TerminalDock.minLines);
      case AppSplitterAction.reset:
        set(TerminalDock.defaultLines);
      case AppSplitterAction.next:
      case AppSplitterAction.previous:
        break;
      case AppSplitterAction.done:
        _saveDockSoon();
        _terminalFocus.requestFocus();
      case AppSplitterAction.cancel:
        set(_linesBeforeKeys);
        _terminalFocus.requestFocus();
    }
  }

  List<AppKeyHint> _terminalEdgeHints(BuildContext context) {
    final l10n = context.l10n;
    final platform = Theme.of(context).platform;
    String key(LogicalKeyboardKey k) => Chord.keyLabel(k, platform);
    return [
      AppKeyHint([
        key(LogicalKeyboardKey.arrowUp),
        key(LogicalKeyboardKey.arrowDown),
      ], l10n.terminalHeightHintArrows),
      AppKeyHint([
        key(LogicalKeyboardKey.digit0),
      ], l10n.terminalHeightHintZero),
      AppKeyHint([key(LogicalKeyboardKey.enter)], l10n.splitterHintEnter),
      AppKeyHint([key(LogicalKeyboardKey.escape)], l10n.splitterHintEscape),
    ];
  }
}

/// The panels and the integrated terminal sharing the window's height:
/// the terminal under the panels with a movable edge between them, or in
/// their place, or over the whole window.
class _PanelsAndTerminal extends StatelessWidget {
  const _PanelsAndTerminal({
    required this.dock,
    required this.terminalHeight,
    required this.panels,
    required this.terminal,
    required this.edge,
    required this.cards,
  });

  final TerminalDock dock;

  /// The terminal's height under the panels.
  final double terminalHeight;
  final Widget panels;

  /// `null` while the terminal is hidden or the window has none.
  final Widget? terminal;

  /// The movable edge between the panels and the terminal under them.
  final Widget? edge;

  /// The operations cards, over the panels' corner.
  final Widget? cards;

  @override
  Widget build(BuildContext context) {
    final terminal = this.terminal;
    final full = terminal != null && !dock.panelsShown;
    final under = terminal != null && !full ? terminalHeight : 0.0;
    return Stack(
      children: [
        if (!full)
          Positioned(
            key: const ValueKey('panels'),
            left: 0,
            top: 0,
            right: 0,
            bottom: under,
            child: panels,
          ),
        if (terminal != null)
          Positioned(
            key: const ValueKey('terminal'),
            left: 0,
            right: 0,
            bottom: 0,
            top: full ? 0 : null,
            height: full ? null : terminalHeight,
            child: terminal,
          ),
        if (terminal != null && !full && edge != null)
          Positioned(
            key: const ValueKey('terminal edge'),
            left: 0,
            right: 0,
            bottom: terminalHeight - AppSizes.resizeHandleWidth / 2,
            height: AppSizes.resizeHandleWidth,
            child: edge!,
          ),
        if (!full && cards != null)
          Positioned(
            key: const ValueKey('operations'),
            right: AppSpacing.md,
            bottom: AppSpacing.md + PanelFooter.heightOf(context) + under,
            child: cards!,
          ),
      ],
    );
  }
}
