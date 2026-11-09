import 'dart:async';
import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:monitoring/monitoring.dart';
import 'package:network_service/network_service.dart';
import 'package:operations_service/operations_service.dart';
import 'package:platform_services/platform_services.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

import '../dialogs/archive_password_dialog.dart';
import '../dialogs/attributes_dialog.dart';
import '../dialogs/batch_rename_dialog.dart';
import '../dialogs/copy_move_dialog.dart';
import '../dialogs/extract_dialog.dart';
import '../dialogs/favorites_dialog.dart';
import '../dialogs/go_to_menus.dart';
import '../dialogs/jump_to_folder.dart';
import '../dialogs/names_editor_dialog.dart';
import '../dialogs/question_dialog.dart';
import '../dialogs/simple_dialogs.dart';
import '../dialogs/tag_dialog.dart';
import '../dialogs/undo_dialog.dart';
import '../native/drag_image.dart';
import '../native/drop_plan.dart';
import '../native/panel_drag_hooks.dart';
import '../native/quick_look_pick.dart';
import '../operations/operations_cards.dart';
import '../panel/panel_cubit.dart';
import '../panel/panel_footer.dart';
import '../panel/panel_side.dart';
import '../panel/panel_state.dart';
import '../panel/panel_view.dart';
import '../panel/saved_panel.dart';
import '../path_text.dart';
import 'context_menu.dart';
import 'folder_compare.dart';
import 'key_hints.dart';
import 'shelf.dart';
import 'shelf_strip.dart';
import 'tag_menu.dart';
import 'terminal_dock.dart';
import 'workspace_cubit.dart';
import 'workspace_operations_controller.dart';
import 'workspace_state.dart';
import 'workspace_terminal.dart';

part 'interface_actions.dart';
part 'native_actions.dart';
part 'operations_actions.dart';
part 'terminal_actions.dart';
part 'vim_actions.dart';
part 'workspace_actions.dart';
part 'archive_actions.dart';
part 'tag_actions.dart';
part 'network_actions.dart';

/// Where the window sends what it does not do itself.
class WorkspaceNavigation {
  const WorkspaceNavigation({
    required this.openViewer,
    required this.openFind,
    required this.openSettings,
    required this.openCheatSheet,
    required this.openSync,
    required this.openChecksums,
    required this.openDuplicates,
  });

  /// The built-in viewer on a file; [preview] opens it in Preview mode.
  final Future<void> Function(
    BuildContext context,
    Location location, {
    bool preview,
  })
  openViewer;

  /// Find Files under [root]; answers the path to go to, if any. [view]
  /// opens a hit in the viewer while the dialog stays.
  final Future<String?> Function(
    BuildContext context,
    String root, {
    required Future<void> Function(Location location) view,
  })
  openFind;
  final Future<void> Function(BuildContext context) openSettings;
  final Future<void> Function(BuildContext context) openCheatSheet;

  // ─── Operations stream ───

  /// Synchronize Folders between [left] and [right] (empty where a panel
  /// shows no folder on disk).
  final Future<void> Function(
    BuildContext context, {
    required String left,
    required String right,
  })
  openSync;

  /// Checksums of [paths], named relative to [base]; [algorithm] picked
  /// beforehand (`:checksum md5`).
  final Future<void> Function(
    BuildContext context, {
    required List<String> paths,
    required String base,
    ChecksumAlgorithm? algorithm,
  })
  openChecksums;

  /// Find Duplicates under [root], and [other] on request; answers the
  /// path of a file to show in the panel, if any.
  final Future<String?> Function(
    BuildContext context, {
    required String root,
    String? other,
  })
  openDuplicates;
}

// ─── Network ───

/// Servers in the window: their connections, and the dialogs that make
/// them, which the window around it owns (Connect to Server and the
/// questions a connection asks).
class WorkspaceNetwork {
  const WorkspaceNetwork({
    required this.service,
    required this.connectToServer,
    required this.connectServer,
    required this.connectProfile,
    required this.connectAddress,
  });

  final NetworkService service;

  /// Connect to Server: the dialog; answers the connection made.
  final Future<ServerConnection?> Function(BuildContext context)
  connectToServer;

  /// The connection to a server (its key) opened again, with the way of
  /// logging in its saved server has; answers whether it is open. A
  /// failure has said why.
  final Future<bool> Function(BuildContext context, String server)
  connectServer;

  /// A saved server connected to; answers the connection made.
  final Future<ServerConnection?> Function(
    BuildContext context,
    ServerProfile server,
  )
  connectProfile;

  /// An address typed (`sftp://me@host/srv`) connected to; answers the
  /// connection made, its home the address's folder.
  final Future<ServerConnection?> Function(BuildContext context, String text)
  connectAddress;
}

/// What the window keeps between runs.
class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.left,
    required this.right,
    required this.active,
    required this.singlePane,
    required this.splitFraction,
  });

  final SavedPanel left;
  final SavedPanel right;
  final PanelSide active;
  final bool singlePane;
  final double splitFraction;
}

/// The main window: two panels, the edge between them, the operations
/// under way, and every file command.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    required this.files,
    required this.operations,
    required this.rename,
    required this.preferences,
    required this.logger,
    required this.shortcutMap,
    required this.windowDecor,
    required this.navigation,
    required this.savedLeft,
    required this.savedRight,
    required this.savedActive,
    required this.fallbackLocation,
    required this.onSnapshot,
    required this.frecency,
    required this.platformServices,
    this.terminal,
    required this.folderSync,
    this.capabilities = const Capabilities(),
    this.network,
    super.key,
  });

  final FileRepository files;
  final OperationsService operations;
  final RenameService rename;

  /// Quick Look, the share picker, files dragged to and from other
  /// applications, as far as this desktop has them.
  final PlatformServices platformServices;

  /// Compare Folders by contents goes through it.
  final FolderSyncService folderSync;
  final PreferencesService preferences;
  final Logger logger;
  final ShortcutMap shortcutMap;
  final WindowDecor windowDecor;
  final WorkspaceNavigation navigation;
  final SavedPanel? savedLeft;
  final SavedPanel? savedRight;
  final PanelSide savedActive;

  /// Where a panel opens when it has nothing saved: the home folder.
  final Location fallbackLocation;
  final ValueChanged<WorkspaceSnapshot> onSnapshot;

  /// The folders the panels showed, counted as they show them, for Jump
  /// to Folder.
  final FolderFrecency frecency;

  /// The integrated terminal; none without it (the terminal's commands
  /// then do nothing).
  final WorkspaceTerminal? terminal;

  /// What this desktop can do that others cannot, as the core reports
  /// it: the commands it lacks are hidden.
  final Capabilities capabilities;

  /// Servers; without it the panels stay on this computer.
  final WorkspaceNetwork? network;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late final WorkspaceCubit _workspace;
  late final PanelCubit _left;
  late final PanelCubit _right;
  final _leftFocus = FocusNode(debugLabel: 'left panel');
  final _rightFocus = FocusNode(debugLabel: 'right panel');
  final _leftCursor = GlobalKey(debugLabel: 'left cursor row');
  final _rightCursor = GlobalKey(debugLabel: 'right cursor row');
  final _splitterFocus = FocusNode(debugLabel: 'panel splitter');
  final _shelfFocus = FocusNode(debugLabel: 'shelf');
  StreamSubscription<String>? _changes;

  /// Asks the disk which shelf items are still there, once changes settle.
  Timer? _shelfCheck;
  late final WorkspaceOperationsController _operations;
  Timer? _snapshotTimer;
  double _splitBeforeKeys = 0.5;

  /// The panels' room along the line between them: their width side by
  /// side, their height one above the other.
  double _panelsExtent = 0;
  final _native = _NativeState();

  // ─── Terminal ───
  WorkspaceTerminalController? _terminal;
  late final TerminalDockCubit _dock;
  final _terminalFocus = FocusNode(debugLabel: 'terminal');
  final _terminalEdgeFocus = FocusNode(debugLabel: 'terminal edge');
  final _terminalSubscriptions = <StreamSubscription<Object?>>[];
  Timer? _dockTimer;
  String? _followed;
  int _linesBeforeKeys = TerminalDock.defaultLines;
  double _dragLines = 0;

  /// The height the panels and the terminal share.
  double _terminalArea = 0;

  @override
  void initState() {
    super.initState();
    final prefs = widget.preferences.current;
    _workspace = WorkspaceCubit(
      active: widget.savedActive,
      singlePane: prefs.singlePane,
      splitFraction: prefs.splitFraction,
      operationsShown: prefs.operationsVisible,
    );
    _left = _panel(PanelSide.left);
    _right = _panel(PanelSide.right);
    _initTerminal();
    unawaited(
      Future.wait([
        _left.start(widget.savedLeft, widget.fallbackLocation),
        _right.start(widget.savedRight, widget.fallbackLocation),
      ]).then((_) => _restoreTerminal()),
    );
    _operations = WorkspaceOperationsController(
      service: widget.operations,
      ask: _ask,
      onFinished: _scheduleShelfCheck,
    );
    _changes = widget.files.directoryChanges.listen(
      (_) => _scheduleShelfCheck(),
    );
    _startNative();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A terminal left over the panels' place keeps the keys.
      if (_terminal != null && !_dock.state.panelsShown) {
        _terminalFocus.requestFocus();
      } else {
        _focusOf(_workspace.state.active).requestFocus();
      }
    });
  }

  PanelCubit _panel(PanelSide side) => PanelCubit(
    side: side,
    files: widget.files,
    operations: widget.operations,
    preferences: widget.preferences,
    logger: widget.logger,
    onFolderShown: widget.frecency.visit,
    readTags: widget.capabilities.finderTags,
    network: widget.network?.service,
    connectServer: widget.network == null ? null : _reconnectServer,
  );

  /// A panel's server connected to again, the window's dialogs asking.
  Future<bool> _reconnectServer(String server) async {
    final network = widget.network;
    if (network == null || !mounted) return false;
    return network.connectServer(context, server);
  }

  @override
  void dispose() {
    _operations.dispose();
    _changes?.cancel();
    _shelfCheck?.cancel();
    _native.dispose();
    _snapshotTimer?.cancel();
    _snapshotNow();
    _disposeTerminal();
    _left.close();
    _right.close();
    _workspace.close();
    _leftFocus.dispose();
    _rightFocus.dispose();
    _splitterFocus.dispose();
    _shelfFocus.dispose();
    super.dispose();
  }

  // ─── Panels ───

  PanelCubit _cubitOf(PanelSide side) =>
      side == PanelSide.left ? _left : _right;

  PanelCubit get _active => _cubitOf(_workspace.state.active);

  PanelCubit get _opposite => _cubitOf(_workspace.state.active.opposite);

  FocusNode _focusOf(PanelSide side) =>
      side == PanelSide.left ? _leftFocus : _rightFocus;

  GlobalKey _cursorOf(PanelSide side) =>
      side == PanelSide.left ? _leftCursor : _rightCursor;

  void _activate(PanelSide side) {
    if (_workspace.state.active != side) {
      _workspace.activate(side);
      _scheduleSnapshot();
    }
  }

  void _focusPanel(PanelSide side) {
    _activate(side);
    _focusOf(side).requestFocus();
  }

  // ─── Persistence ───

  void _scheduleSnapshot() {
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer(const Duration(milliseconds: 400), _snapshotNow);
  }

  void _snapshotNow() {
    _snapshotTimer?.cancel();
    widget.onSnapshot(
      WorkspaceSnapshot(
        left: _left.saved(),
        right: _right.saved(),
        active: _workspace.state.active,
        singlePane: _workspace.state.singlePane,
        splitFraction: _workspace.state.splitFraction,
      ),
    );
  }

  // ─── Operations ───

  Future<Answer?> _ask(OperationQuestion question) async {
    // A question may already be waiting when the workspace is created.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return null;
    return showQuestionDialog(context, question: question);
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MultiBlocProvider(
      providers: [BlocProvider.value(value: _workspace)],
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        builder: (context, workspace) =>
            BlocBuilder<TerminalDockCubit, TerminalDock>(
              bloc: _dock,
              builder: (context, dock) => PreferenceBuilder<Preferences>(
                service: widget.preferences,
                select: (p) => p,
                builder: (context, prefs) {
                  final terminal = widget.terminal;
                  final controller = _terminal;
                  final terminalShown =
                      terminal != null && controller != null && dock.shown;
                  final fullWindow =
                      terminalShown && dock.mode == TerminalPlace.fullWindow;
                  return Scaffold(
                    backgroundColor: context.appColors.window,
                    body: CommandHandlers(
                      handlers: _globalHandlers(context),
                      child: Column(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, area) {
                                _terminalArea = area.maxHeight;
                                return _PanelsAndTerminal(
                                  dock: dock,
                                  terminalHeight: terminalShown
                                      ? _terminalHeight(
                                          context,
                                          area.maxHeight,
                                        )
                                      : 0,
                                  panels: CommandShortcuts(
                                    shortcuts: widget.shortcutMap.toShortcuts(
                                      Theme.of(context).platform,
                                      scopes: const {CommandScope.panel},
                                      // The window's `gn`, `cd`, `gj` before
                                      // the panel's own `n`, `d`, `j`.
                                      sequencesOf: const {CommandScope.global},
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final stacked = _panelsStacked(
                                          prefs,
                                          MediaQuery.sizeOf(context),
                                        );
                                        _panelsExtent = stacked
                                            ? constraints.maxHeight
                                            : constraints.maxWidth;
                                        return _Panels(
                                          workspace: workspace,
                                          stacked: stacked,
                                          prefs: prefs,
                                          cubitOf: _cubitOf,
                                          decor: widget.windowDecor,
                                          shortcutMap: widget.shortcutMap,
                                          splitterFocus: _splitterFocus,
                                          leftFocus: _leftFocus,
                                          rightFocus: _rightFocus,
                                          leftCursor: _leftCursor,
                                          rightCursor: _rightCursor,
                                          hooksFor: _hooksFor,
                                          registerNote: _shelfNote(
                                            l10n,
                                            workspace.shelf,
                                          ),
                                          splitterValue: l10n.textSizePercent(
                                            (workspace.splitFraction * 100)
                                                .round(),
                                          ),
                                          splitterHints: _splitterHints(
                                            context,
                                            stacked: stacked,
                                          ),
                                          onSplitterAction: _onSplitterAction,
                                          onSplitterDrag: (delta) {
                                            if (_panelsExtent > 0) {
                                              _workspace.moveSplit(
                                                delta / _panelsExtent,
                                              );
                                            }
                                          },
                                          onSplitterDragEnd: _scheduleSnapshot,
                                          extent: _panelsExtent,
                                        );
                                      },
                                    ),
                                  ),
                                  terminal: terminalShown
                                      ? terminal.builder(
                                          context,
                                          controller,
                                          WorkspaceTerminalView(
                                            focusNode: _terminalFocus,
                                            panelsHidden:
                                                dock.mode ==
                                                TerminalPlace.panelsHidden,
                                            fullWindow:
                                                dock.mode ==
                                                TerminalPlace.fullWindow,
                                            decor: widget.windowDecor,
                                            onHide: _hideTerminal,
                                            onTogglePanels:
                                                _togglePanelsOverTerminal,
                                            onToggleFullWindow:
                                                _toggleTerminalWindow,
                                          ),
                                        )
                                      : null,
                                  edge: terminalShown
                                      ? AppSplitter(
                                          focusNode: _terminalEdgeFocus,
                                          axis: Axis.vertical,
                                          line: AppSplitterLine.center,
                                          title: l10n.terminalHeightTitle,
                                          value: l10n.terminalLineCount(
                                            dock.lines,
                                          ),
                                          hints: _terminalEdgeHints(context),
                                          onAction: _onTerminalEdgeAction,
                                          onDragStart: _onTerminalEdgeDragStart,
                                          onDragUpdate: _onTerminalEdgeDrag,
                                          onDragEnd: _saveDockSoon,
                                        )
                                      : null,
                                  cards: workspace.operationsShown
                                      ? ListenableBuilder(
                                          listenable: _operations,
                                          builder: (context, _) =>
                                              OperationsCards(
                                                operations:
                                                    _operations.operations,
                                                titles: _operations.titles,
                                                onPause: (id) => unawaited(
                                                  widget.operations.pause(id),
                                                ),
                                                onResume: (id) => unawaited(
                                                  widget.operations.resume(id),
                                                ),
                                                onCancel: (id) => unawaited(
                                                  widget.operations.cancel(id),
                                                ),
                                                onDismiss: _operations.dismiss,
                                                onAnswer: (progress) =>
                                                    unawaited(
                                                      _operations.ask(
                                                        progress.id,
                                                      ),
                                                    ),
                                              ),
                                        )
                                      : null,
                                );
                              },
                            ),
                          ),
                          // The shelf, between the panels (and the terminal
                          // under them) and the hints: the panels give it
                          // room smoothly, at once under reduced motion. A
                          // terminal over the whole window covers it.
                          AnimatedSize(
                            duration: context.motion(AppMotion.medium),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: workspace.shelfShown && !fullWindow
                                ? AppFocusArea(
                                    child: BlocBuilder<PanelCubit, PanelState>(
                                      bloc: _cubitOf(workspace.active),
                                      builder: (context, panel) => ShelfStrip(
                                        shelf: workspace.shelf,
                                        focusNode: _shelfFocus,
                                        destination: _shelfDestination(
                                          panel.active,
                                        ),
                                        home: widget.files
                                            .standardFolders()
                                            .home,
                                        addKey: widget.shortcutMap.labelOf(
                                          AppCommand.addToShelf,
                                          Theme.of(context).platform,
                                          vim: prefs.vimMode,
                                        ),
                                        onReveal: (item) =>
                                            unawaited(_revealShelfItem(item)),
                                        onRemove: (item) =>
                                            _unshelve([item.path]),
                                        onClear: _clearShelf,
                                        onCopyHere: () =>
                                            unawaited(_putShelf(move: false)),
                                        onMoveHere: () =>
                                            unawaited(_putShelf(move: true)),
                                        onLeave: () => _focusOf(
                                          _workspace.state.active,
                                        ).requestFocus(),
                                      ),
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          // The keys for what is under the cursor or selected
                          // in the active panel, or the terminal's or the
                          // shelf's while they have the keys, until the user
                          // hides the line.
                          if (prefs.showKeyHints && !fullWindow)
                            _KeyHintsLine(
                              terminalFocus: _terminalFocus,
                              shelfFocus: _shelfFocus,
                              terminalHints: terminalShown
                                  ? terminalHintsFor(dock.mode)
                                  : null,
                              panel: _cubitOf(workspace.active),
                              vim: prefs.vimMode,
                              hasShelf: !workspace.shelf.isEmpty,
                              shortcutMap: widget.shortcutMap,
                              onHide: () => _hideKeyHints(context),
                              onHelp: () => unawaited(
                                widget.navigation.openCheatSheet(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
      ),
    );
  }

  void _hideKeyHints(BuildContext context) {
    unawaited(
      widget.preferences.update((p) => p.copyWith(showKeyHints: false)),
    );
    showAppNotice(context, context.l10n.hintsHidden);
  }

  PanelHooks _hooksFor(PanelSide side) => PanelHooks(
    onActivate: () => _activate(side),
    onOpenFile: (request) => unawaited(_openFile(request)),
    onContextMenu: (anchor) {
      _activate(side);
      unawaited(_rowMenu(anchor));
    },
    onPanelMenu: (anchor) {
      _activate(side);
      unawaited(_panelMenu(anchor));
    },
    onSwitchPanel: _switchPanel,
    onShowPreview: () => unawaited(_spacePreview()),
    onGoHome: () => unawaited(_goStandard((f) => f.home)),
    onGoRoot: () => unawaited(_goStandard((f) => f.root)),
    onVimYank: () => _vimTake(move: false),
    onVimCut: () => _vimTake(move: true),
    onVimPaste: () => unawaited(_vimPaste()),
    onVimCancelRegister: _vimCancelRegister,
    onVimSetMark: (letter) => unawaited(_vimSetMark(letter)),
    onVimGoMark: (letter) => unawaited(_vimGoMark(letter)),
    onVimCommand: (line) => unawaited(_runVimCommand(line)),
    onVimComplete: _vimComplete,
    drag: _dragHooksFor(side),
    onEscape: _escapeQuickLook,
    onArchivePassword: (location) =>
        unawaited(_passwordForPanel(side, location)),
  );

  List<AppKeyHint> _splitterHints(
    BuildContext context, {
    required bool stacked,
  }) {
    final l10n = context.l10n;
    final platform = Theme.of(context).platform;
    String key(LogicalKeyboardKey k) => Chord.keyLabel(k, platform);
    return [
      AppKeyHint(
        stacked
            ? [
                key(LogicalKeyboardKey.arrowUp),
                key(LogicalKeyboardKey.arrowDown),
              ]
            : [
                key(LogicalKeyboardKey.arrowLeft),
                key(LogicalKeyboardKey.arrowRight),
              ],
        l10n.splitterHintArrows,
      ),
      AppKeyHint([key(LogicalKeyboardKey.digit0)], l10n.splitterHintZero),
      AppKeyHint([key(LogicalKeyboardKey.enter)], l10n.splitterHintEnter),
      AppKeyHint([key(LogicalKeyboardKey.escape)], l10n.splitterHintEscape),
    ];
  }

  void _onSplitterAction(AppSplitterAction action) {
    const step = 0.02;
    switch (action) {
      case AppSplitterAction.left:
        _workspace.moveSplit(-step);
      case AppSplitterAction.right:
        _workspace.moveSplit(step);
      case AppSplitterAction.farLeft:
        _workspace.moveSplit(-step * 4);
      case AppSplitterAction.farRight:
        _workspace.moveSplit(step * 4);
      case AppSplitterAction.narrowest:
        _workspace.setSplit(WorkspaceCubit.minFraction);
      case AppSplitterAction.widest:
        _workspace.setSplit(WorkspaceCubit.maxFraction);
      case AppSplitterAction.reset:
        _workspace.setSplit(0.5);
      case AppSplitterAction.next:
      case AppSplitterAction.previous:
        break;
      case AppSplitterAction.done:
        _workspace.setResizing(false);
        _scheduleSnapshot();
        _focusOf(_workspace.state.active).requestFocus();
      case AppSplitterAction.cancel:
        _workspace.setSplit(_splitBeforeKeys);
        _workspace.setResizing(false);
        _focusOf(_workspace.state.active).requestFocus();
    }
  }
}

/// The hint line under the panels: the terminal's keys while it has the
/// keys, the shelf's while it has them, else those for the active panel's
/// cursor or selection.
class _KeyHintsLine extends StatelessWidget {
  const _KeyHintsLine({
    required this.terminalFocus,
    required this.shelfFocus,
    required this.terminalHints,
    required this.panel,
    required this.vim,
    required this.hasShelf,
    required this.shortcutMap,
    required this.onHide,
    required this.onHelp,
  });

  final FocusNode terminalFocus;
  final FocusNode shelfFocus;

  /// The terminal's keys while it is shown; null without it.
  final List<PanelHint>? terminalHints;
  final PanelCubit panel;
  final bool vim;
  final bool hasShelf;
  final ShortcutMap shortcutMap;
  final VoidCallback onHide;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      terminalFocus,
      shelfFocus,
      FocusManager.instance,
    ]),
    builder: (context, _) {
      if (terminalHints case final hints? when terminalFocus.hasFocus) {
        return KeyHintStrip(
          hints: hints,
          shortcutMap: shortcutMap,
          vim: false,
          onHide: onHide,
          onHelp: onHelp,
        );
      }
      // A text field, including Vim's command line, consumes sequences as text.
      final typing =
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorStateOfType<EditableTextState>() !=
          null;
      return BlocBuilder<PanelCubit, PanelState>(
        bloc: panel,
        builder: (context, state) => KeyHintStrip(
          hints: shelfFocus.hasFocus
              ? shelfHints
              : hintsFor(
                  tab: state.active,
                  vim: vim,
                  hasRegister: hasShelf,
                  hasMultipleTabs: state.tabs.length > 1 && !typing,
                ),
          shortcutMap: shortcutMap,
          vim: vim,
          onHide: onHide,
          onHelp: onHelp,
        ),
      );
    },
  );
}

/// The two panels side by side with the edge between them, or the active
/// one alone.
class _Panels extends StatelessWidget {
  const _Panels({
    required this.workspace,
    required this.stacked,
    required this.prefs,
    required this.cubitOf,
    required this.decor,
    required this.shortcutMap,
    required this.splitterFocus,
    required this.leftFocus,
    required this.rightFocus,
    required this.leftCursor,
    required this.rightCursor,
    required this.hooksFor,
    required this.registerNote,
    required this.splitterValue,
    required this.splitterHints,
    required this.onSplitterAction,
    required this.onSplitterDrag,
    required this.onSplitterDragEnd,
    required this.extent,
  });

  /// The line the splitter draws down the middle of its handle.
  static const double splitterLineWidth = 1;

  final WorkspaceState workspace;

  /// The left panel above the right one, not beside it.
  final bool stacked;
  final Preferences prefs;
  final PanelCubit Function(PanelSide side) cubitOf;
  final WindowDecor decor;
  final ShortcutMap shortcutMap;
  final FocusNode splitterFocus;
  final FocusNode leftFocus;
  final FocusNode rightFocus;
  final GlobalKey leftCursor;
  final GlobalKey rightCursor;
  final PanelHooks Function(PanelSide side) hooksFor;
  final String? registerNote;
  final String splitterValue;
  final List<AppKeyHint> splitterHints;
  final ValueChanged<AppSplitterAction> onSplitterAction;
  final ValueChanged<double> onSplitterDrag;
  final VoidCallback onSplitterDragEnd;

  /// The room along the line between the panels.
  final double extent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (workspace.singlePane) {
      final left = workspace.active == PanelSide.left;
      return _SidePanel(
        side: workspace.active,
        leading: true,
        trailing: true,
        cubit: cubitOf(workspace.active),
        focusNode: left ? leftFocus : rightFocus,
        cursorKey: left ? leftCursor : rightCursor,
        active: true,
        prefs: prefs,
        decor: decor,
        shortcutMap: shortcutMap,
        hooks: hooksFor(workspace.active),
        registerNote: registerNote,
      );
    }
    final first = (extent * workspace.splitFraction).roundToDouble();
    // One Flex either way, so the panels keep their state as it turns.
    return Stack(
      children: [
        Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: stacked ? null : first,
              height: stacked ? first : null,
              child: _SidePanel(
                side: PanelSide.left,
                // Above, it has the window's top row to itself.
                leading: true,
                trailing: stacked,
                cubit: cubitOf(PanelSide.left),
                focusNode: leftFocus,
                cursorKey: leftCursor,
                active: workspace.active == PanelSide.left,
                prefs: prefs,
                decor: decor,
                shortcutMap: shortcutMap,
                hooks: hooksFor(PanelSide.left),
                registerNote: registerNote,
              ),
            ),
            AppRule(
              axis: stacked ? Axis.horizontal : Axis.vertical,
              color: colors.line,
            ),
            Expanded(
              child: _SidePanel(
                side: PanelSide.right,
                // Below, its bar is not the window's: no buttons beside
                // it, and it does not move the window.
                leading: false,
                trailing: !stacked,
                cubit: cubitOf(PanelSide.right),
                focusNode: rightFocus,
                cursorKey: rightCursor,
                active: workspace.active == PanelSide.right,
                prefs: prefs,
                decor: stacked ? WindowDecor.none : decor,
                shortcutMap: shortcutMap,
                hooks: hooksFor(PanelSide.right),
                registerNote: registerNote,
              ),
            ),
          ],
        ),
        Positioned(
          left: stacked ? 0 : first - AppSizes.resizeHandleWidth / 2,
          top: stacked ? first - AppSizes.resizeHandleWidth / 2 : 0,
          right: stacked ? 0 : null,
          bottom: stacked ? null : 0,
          width: stacked
              ? null
              : AppSizes.resizeHandleWidth + splitterLineWidth,
          height: stacked
              ? AppSizes.resizeHandleWidth + splitterLineWidth
              : null,
          child: AppSplitter(
            focusNode: splitterFocus,
            axis: stacked ? Axis.vertical : Axis.horizontal,
            title: context.l10n.splitterTitle,
            value: splitterValue,
            hints: splitterHints,
            onAction: onSplitterAction,
            onDragStart: () {},
            onDragUpdate: onSplitterDrag,
            onDragEnd: onSplitterDragEnd,
            line: AppSplitterLine.center,
          ),
        ),
      ],
    );
  }
}

/// Whether the panels stand one above the other: as [prefs] has them, or,
/// by the window's shape, where the window is taller than it is wide.
bool _panelsStacked(Preferences prefs, Size window) =>
    switch (prefs.panelArrangement) {
      PanelArrangement.sideBySide => false,
      PanelArrangement.stacked => true,
      PanelArrangement.byWindowShape => window.height > window.width,
    };

/// One side's panel with its own cubit in scope. Keyed by its side, so a
/// switch to single-pane mode keeps the panel's subtree alive.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.side,
    required this.leading,
    required this.trailing,
    required this.cubit,
    required this.focusNode,
    required this.cursorKey,
    required this.active,
    required this.prefs,
    required this.decor,
    required this.shortcutMap,
    required this.hooks,
    required this.registerNote,
  });

  final PanelSide side;

  /// The panel's bar meets the window's buttons at its start, at its end.
  final bool leading;
  final bool trailing;
  final PanelCubit cubit;
  final FocusNode focusNode;
  final GlobalKey cursorKey;
  final bool active;
  final Preferences prefs;
  final WindowDecor decor;
  final ShortcutMap shortcutMap;
  final PanelHooks hooks;
  final String? registerNote;

  @override
  Widget build(BuildContext context) => BlocProvider<PanelCubit>.value(
    value: cubit,
    child: PanelView(
      key: ValueKey(side),
      focusNode: focusNode,
      active: active,
      layouts: prefs.layouts,
      showTabBarAlways: prefs.showTabBarAlways,
      quickSearchModifier: prefs.quickSearchModifier,
      vimMode: prefs.vimMode,
      registerNote: registerNote,
      // The window's buttons, then the bar's own margin at each edge.
      leftInset: (leading ? decor.leadingInset : 0) + AppSpacing.md,
      rightInset: (trailing ? decor.trailingInset : 0) + AppSpacing.sm,
      shortcutMap: shortcutMap,
      hooks: hooks,
      windowDecor: decor,
      cursorRowKey: cursorKey,
    ),
  );
}
