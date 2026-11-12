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
import '../operations/pending_deletion_card.dart';
import '../panel/panel_cubit.dart';
import '../panel/panel_side.dart';
import '../panel/panel_state.dart';
import '../panel/panel_terminal.dart';
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
import 'pending_deletions_controller.dart';
import 'workspace_preview.dart';
import 'workspace_preview_cubit.dart';
import 'workspace_state.dart';
import 'workspace_terminal.dart';
import 'saved_workspace.dart';

part 'interface_actions.dart';
part 'saved_workspace_actions.dart';
part 'native_actions.dart';
part 'operations_actions.dart';
part 'terminal_actions.dart';
part 'vim_actions.dart';
part 'workspace_actions.dart';
part 'archive_actions.dart';
part 'tag_actions.dart';
part 'network_actions.dart';
part 'preview_actions.dart';

/// Where the window sends what it does not do itself.
class WorkspaceNavigation {
  const WorkspaceNavigation({
    required this.openViewer,
    required this.openFind,
    required this.openSettings,
    this.openArchiverSettings,
    this.openComparison,
    this.openSavedSearches,
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
    Future<void> Function(FindRequest request)? results,
    FindRequest? initial,
  })
  openFind;
  final Future<(String, FindRequest)?> Function(
    BuildContext context,
    FindRequest? current,
  )?
  openSavedSearches;
  final Future<void> Function(BuildContext context) openSettings;
  final Future<void> Function(BuildContext context)? openArchiverSettings;
  final Future<void> Function(
    BuildContext context,
    Location left,
    Location right,
  )?
  openComparison;
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
    this.sideStorage,
    this.find,
    this.thumbnails,
    required this.platformServices,
    this.terminal,
    this.loadArchivers,
    this.preview,
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
  final SideStorage? sideStorage;
  final FindService? find;
  final ThumbnailProvider? thumbnails;

  /// The integrated terminal; none without it (the terminal's commands
  /// then do nothing).
  final WorkspaceTerminal? terminal;
  final ArchiverDiscovery? loadArchivers;

  /// The built-in viewer in the opposite pane or over the whole window.
  final WorkspacePreview? preview;

  /// What this desktop can do that others cannot, as the core reports
  /// it: the commands it lacks are hidden.
  final Capabilities capabilities;

  /// Servers; without it the panels stay on this computer.
  final WorkspaceNetwork? network;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  Future<SavedProfiles<SavedWorkspace>>? _savedWorkspaces;
  bool _restoringWorkspace = false;
  void _setRestoringWorkspace(bool restoring) {
    if (mounted) {
      setState(() => _restoringWorkspace = restoring);
    } else {
      _restoringWorkspace = restoring;
    }
  }

  late final WorkspaceCubit _workspace;
  late final PanelCubit _left;
  late final PanelCubit _right;
  final _leftFocus = FocusNode(debugLabel: 'left panel');
  final _rightFocus = FocusNode(debugLabel: 'right panel');
  final _leftPanel = GlobalKey(debugLabel: 'left panel view');
  final _rightPanel = GlobalKey(debugLabel: 'right panel view');
  final _leftCursor = GlobalKey(debugLabel: 'left cursor row');
  final _rightCursor = GlobalKey(debugLabel: 'right cursor row');
  final _splitterFocus = FocusNode(debugLabel: 'panel splitter');
  final _shelfFocus = FocusNode(debugLabel: 'shelf');
  StreamSubscription<String>? _changes;

  /// Asks the disk which shelf items are still there, once changes settle.
  Timer? _shelfCheck;
  late final WorkspaceOperationsController _operations;
  late final PendingDeletionsController _deletions;
  Timer? _snapshotTimer;
  double _splitBeforeKeys = 0.5;

  /// The panels' room along the line between them: their width side by
  /// side, their height one above the other.
  double _panelsExtent = 0;
  final _native = _NativeState();
  final _previewController = WorkspacePreviewCubit();
  final _previewFocus = FocusScopeNode(debugLabel: 'workspace preview');
  final _previewKey = GlobalKey(debugLabel: 'workspace preview view');

  // ─── Terminal ───
  WorkspaceTerminalController? _terminal;
  late final TerminalDockCubit _dock;
  final _terminalFocus = FocusNode(debugLabel: 'terminal');
  final _terminalScope = FocusScopeNode(debugLabel: 'terminal area');
  final _terminalKey = GlobalKey(debugLabel: 'terminal view');
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
    _deletions = PendingDeletionsController(onExecute: _executeDeletion);
    _changes = widget.files.directoryChanges.listen(
      (_) => _scheduleShelfCheck(),
    );
    _startNative();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A terminal left over the panels' place keeps the keys.
      if (_terminal != null &&
          (!_dock.state.panelsShown ||
              _dock.state.mode == TerminalPlace.panelTab &&
                  _dock.state.tabSelected)) {
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
    find: widget.find,
  );

  /// A panel's server connected to again, the window's dialogs asking.
  Future<bool> _reconnectServer(String server) async {
    final network = widget.network;
    if (network == null || !mounted) return false;
    return network.connectServer(context, server);
  }

  @override
  void dispose() {
    unawaited(
      _savedWorkspaces?.then(
        (catalog) => catalog.dispose(),
        // Loading already reports the error; disposal must consume it too.
        onError: (Object _, StackTrace _) {},
      ),
    );
    _deletions.dispose();
    _operations.dispose();
    _changes?.cancel();
    _shelfCheck?.cancel();
    _native.dispose();
    _snapshotTimer?.cancel();
    _snapshotNow();
    _disposeTerminal();
    unawaited(_previewController.close());
    _previewFocus.dispose();
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
    if (_previewController.state.source case final source?
        when source != side) {
      return;
    }
    if (_workspace.state.active != side) {
      _workspace.activate(side);
      _scheduleSnapshot();
    }
  }

  void _focusPanel(PanelSide side) {
    if (_previewController.state.source case final source?
        when source != side) {
      _focusPreview();
      return;
    }
    if (_previewController.state.fullWindow) {
      _focusPreviewFiles();
      return;
    }
    _activate(side);
    if (_dock.state.host == _terminalHost(side) &&
        _dock.state.mode == TerminalPlace.panelTab &&
        _dock.state.tabSelected) {
      _terminalFocus.requestFocus();
    } else {
      _focusOf(side).requestFocus();
    }
  }

  // ─── Persistence ───

  void _scheduleSnapshot() {
    if (_restoringWorkspace) return;
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer(const Duration(milliseconds: 400), _snapshotNow);
  }

  void _snapshotNow() {
    if (_restoringWorkspace) return;
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
        builder: (context, workspace) => BlocBuilder<WorkspacePreviewCubit, WorkspacePreviewState>(
          bloc: _previewController,
          builder: (context, preview) => ListenableBuilder(
            listenable: Listenable.merge([_previewFocus, _terminalScope]),
            builder: (context, _) => BlocBuilder<TerminalDockCubit, TerminalDock>(
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
                  final previewView = preview.shown && widget.preview != null
                      ? _WorkspacePreviewHost(
                          key: _previewKey,
                          preview: widget.preview!,
                          view: WorkspacePreviewView(
                            location: preview.location,
                            focusScope: _previewFocus,
                            fullWindow: preview.fullWindow,
                            startInPreview: preview.startInPreview,
                            decor: _previewDecor(prefs, preview),
                            onClose: _closePreview,
                            onFocusFiles: _focusPreviewFiles,
                            onToggleFullWindow: _togglePreviewWindow,
                          ),
                          shortcutMap: widget.shortcutMap,
                        )
                      : null;
                  final terminalView = terminalShown
                      ? KeyedSubtree(
                          key: _terminalKey,
                          child: FocusScope(
                            node: _terminalScope,
                            child: terminal.builder(
                              context,
                              controller,
                              WorkspaceTerminalView(
                                focusNode: _terminalFocus,
                                panelsHidden:
                                    dock.mode == TerminalPlace.panelsHidden,
                                fullWindow:
                                    dock.mode == TerminalPlace.fullWindow,
                                decor: widget.windowDecor,
                                inPanel:
                                    dock.host != TerminalHost.window &&
                                    dock.panelsShown,
                                asTab: dock.mode == TerminalPlace.panelTab,
                                placementActions: _terminalPlacementHandlers(),
                                onHide: _hideTerminal,
                                onTogglePanels: _togglePanelsOverTerminal,
                                onToggleFullWindow: _toggleTerminalWindow,
                              ),
                            ),
                          ),
                        )
                      : null;
                  final terminalEdge = terminalShown
                      ? AppSplitter(
                          focusNode: _terminalEdgeFocus,
                          axis: Axis.vertical,
                          line: AppSplitterLine.start,
                          title: l10n.terminalHeightTitle,
                          value: l10n.terminalLineCount(
                            dock.lines,
                          ),
                          hints: _terminalEdgeHints(
                            context,
                          ),
                          onAction: _onTerminalEdgeAction,
                          onDragStart: _onTerminalEdgeDragStart,
                          onDragUpdate: _onTerminalEdgeDrag,
                          onDragEnd: _saveDockSoon,
                        )
                      : null;
                  final panelTerminal = terminalShown && dock.inPanel
                      ? PanelTerminal(
                          child: terminalView!,
                          focusScope: _terminalScope,
                          asTab: dock.mode == TerminalPlace.panelTab,
                          selected: dock.tabSelected,
                          tabIndex: dock.tabPosition(
                            _cubitOf(_terminalSide).state.tabs.length,
                          ),
                          heightOf: (context, area) {
                            _terminalArea = area;
                            return _terminalHeight(context, area);
                          },
                          edge: terminalEdge!,
                          onSelectTab: (index) =>
                              _selectPanelTab(_terminalSide, index),
                          onCycleTab: (delta) =>
                              _cyclePanelTab(_terminalSide, delta),
                          onReorder: (index) {
                            _dock.moveTab(index);
                            _saveDockSoon();
                          },
                          onClose: _hideTerminal,
                          onMenu: (anchor) =>
                              unawaited(_terminalTabMenu(anchor)),
                        )
                      : null;
                  return Scaffold(
                    backgroundColor: context.appColors.window,
                    body: AbsorbPointer(
                      absorbing: _restoringWorkspace,
                      child: CommandHandlers(
                        handlers: _globalHandlers(context),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ExcludeFocus(
                              excluding:
                                  preview.fullWindow || _restoringWorkspace,
                              child: ExcludeSemantics(
                                excluding: preview.fullWindow,
                                child: Offstage(
                                  offstage: preview.fullWindow,
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
                                                shortcuts: widget.shortcutMap
                                                    .toShortcuts(
                                                      Theme.of(context)
                                                          .platform,
                                                      scopes: const {
                                                        CommandScope.panel,
                                                      },
                                                      // The window's `gn`, `cd`, `gj` before
                                                      // the panel's own `n`, `d`, `j`.
                                                      sequencesOf: const {
                                                        CommandScope.global,
                                                      },
                                                    ),
                                                child: LayoutBuilder(
                                                  builder: (context, constraints) {
                                                    final stacked =
                                                        _panelsStacked(
                                                          prefs,
                                                          MediaQuery.sizeOf(
                                                            context,
                                                          ),
                                                        );
                                                    _panelsExtent = stacked
                                                        ? constraints.maxHeight
                                                        : constraints.maxWidth;
                                                    final firstPercent =
                                                        (workspace.splitFraction *
                                                                100)
                                                            .round();
                                                    final secondPercent =
                                                        100 - firstPercent;
                                                    return _Panels(
                                                      retainPreviewOnExit:
                                                          !preview.shown,
                                                      retainTerminalOnExit:
                                                          !dock.shown,
                                                      thumbnails:
                                                          widget.thumbnails,
                                                      deletions: _deletions,
                                                      operations: _operations,
                                                      operationService:
                                                          widget.operations,
                                                      onCancelDeletion:
                                                          _cancelDeletion,
                                                      workspace: workspace,
                                                      stacked: stacked,
                                                      prefs: prefs,
                                                      cubitOf: _cubitOf,
                                                      decor: widget.windowDecor,
                                                      shortcutMap:
                                                          widget.shortcutMap,
                                                      splitterFocus:
                                                          _splitterFocus,
                                                      leftFocus: _leftFocus,
                                                      rightFocus: _rightFocus,
                                                      leftPanel: _leftPanel,
                                                      rightPanel: _rightPanel,
                                                      previewSide: preview
                                                          .source
                                                          ?.opposite,
                                                      preview:
                                                          preview.fullWindow
                                                          ? null
                                                          : previewView,
                                                      leftCursor: _leftCursor,
                                                      rightCursor: _rightCursor,
                                                      hooksFor: _hooksFor,
                                                      terminal: panelTerminal,
                                                      terminalSide:
                                                          _terminalSide,
                                                      registerNote: _shelfNote(
                                                        l10n,
                                                        workspace.shelf,
                                                      ),
                                                      splitterValue: stacked
                                                          ? l10n.panelSplitStacked(
                                                              firstPercent,
                                                              secondPercent,
                                                            )
                                                          : l10n.panelSplitSideBySide(
                                                              firstPercent,
                                                              secondPercent,
                                                            ),
                                                      splitterHints:
                                                          _splitterHints(
                                                            context,
                                                            stacked: stacked,
                                                          ),
                                                      onSplitterAction:
                                                          _onSplitterAction,
                                                      onSplitterDrag: (delta) {
                                                        if (_panelsExtent >
                                                            _Panels
                                                                .splitterLineWidth) {
                                                          _workspace.moveSplit(
                                                            delta /
                                                                (_panelsExtent -
                                                                    _Panels
                                                                        .splitterLineWidth),
                                                          );
                                                        }
                                                      },
                                                      onSplitterDragEnd:
                                                          _scheduleSnapshot,
                                                      onSplitterReset:
                                                          _equalizePanels,
                                                    );
                                                  },
                                                ),
                                              ),
                                              terminal:
                                                  terminalShown && !dock.inPanel
                                                  ? terminalView
                                                  : null,
                                              edge:
                                                  terminalShown && !dock.inPanel
                                                  ? terminalEdge
                                                  : null,
                                              cards: workspace.operationsShown
                                                  ? ListenableBuilder(
                                                      listenable: _operations,
                                                      builder: (context, _) =>
                                                          OperationsCards(
                                                            operations: _operations
                                                                .operationsFor(
                                                                  null,
                                                                ),
                                                            titles: _operations
                                                                .titles,
                                                            onPause: (id) =>
                                                                unawaited(
                                                                  widget
                                                                      .operations
                                                                      .pause(
                                                                        id,
                                                                      ),
                                                                ),
                                                            onResume: (id) =>
                                                                unawaited(
                                                                  widget
                                                                      .operations
                                                                      .resume(
                                                                        id,
                                                                      ),
                                                                ),
                                                            onCancel: (id) =>
                                                                unawaited(
                                                                  widget
                                                                      .operations
                                                                      .cancel(
                                                                        id,
                                                                      ),
                                                                ),
                                                            onDismiss:
                                                                _operations
                                                                    .dismiss,
                                                            onAnswer:
                                                                (
                                                                  progress,
                                                                ) => unawaited(
                                                                  _operations
                                                                      .ask(
                                                                        progress
                                                                            .id,
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
                                      AppPresence(
                                        resize: true,
                                        child:
                                            workspace.shelfShown && !fullWindow
                                            ? AppFocusArea(
                                                child:
                                                    BlocBuilder<
                                                      PanelCubit,
                                                      PanelState
                                                    >(
                                                      bloc: _cubitOf(
                                                        workspace.active,
                                                      ),
                                                      builder:
                                                          (
                                                            context,
                                                            panel,
                                                          ) => ShelfStrip(
                                                            shelf:
                                                                workspace.shelf,
                                                            focusNode:
                                                                _shelfFocus,
                                                            destination:
                                                                _shelfDestination(
                                                                  panel.active,
                                                                ),
                                                            home: widget.files
                                                                .standardFolders()
                                                                .home,
                                                            addKey: widget
                                                                .shortcutMap
                                                                .labelOf(
                                                                  AppCommand
                                                                      .addToShelf,
                                                                  Theme.of(
                                                                    context,
                                                                  ).platform,
                                                                  vim: prefs
                                                                      .vimMode,
                                                                ),
                                                            onReveal: (item) =>
                                                                unawaited(
                                                                  _revealShelfItem(
                                                                    item,
                                                                  ),
                                                                ),
                                                            onRemove: (item) =>
                                                                _unshelve([
                                                                  item.path,
                                                                ]),
                                                            onClear:
                                                                _clearShelf,
                                                            onCopyHere: () =>
                                                                unawaited(
                                                                  _putShelf(
                                                                    move: false,
                                                                  ),
                                                                ),
                                                            onMoveHere: () =>
                                                                unawaited(
                                                                  _putShelf(
                                                                    move: true,
                                                                  ),
                                                                ),
                                                            onLeave: () =>
                                                                _focusOf(
                                                                  _workspace
                                                                      .state
                                                                      .active,
                                                                ).requestFocus(),
                                                          ),
                                                    ),
                                              )
                                            : null,
                                      ),
                                      // The keys for what is under the cursor or selected
                                      // in the active panel, or the preview's, terminal's or
                                      // shelf's while they have the keys, until the user
                                      // hides the line.
                                      AppPresence(
                                        resize: true,
                                        child: prefs.showKeyHints && !fullWindow
                                            ? _KeyHintsLine(
                                                deletions: _deletions,
                                                previewFocus: _previewFocus,
                                                terminalFocus: _terminalFocus,
                                                shelfFocus: _shelfFocus,
                                                terminalHints: terminalShown
                                                    ? terminalHintsFor(
                                                        dock.mode,
                                                      )
                                                    : null,
                                                panel: _cubitOf(
                                                  workspace.active,
                                                ),
                                                vim: prefs.vimMode,
                                                hasShelf:
                                                    !workspace.shelf.isEmpty,
                                                shortcutMap: widget.shortcutMap,
                                                onHide: () =>
                                                    _hideKeyHints(context),
                                                onHelp: () => unawaited(
                                                  widget.navigation
                                                      .openCheatSheet(
                                                        context,
                                                      ),
                                                ),
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            AppPresence(
                              retainOnExit: !preview.shown,
                              animateInitially: true,
                              child: preview.fullWindow ? previewView : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
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
    onEscape: _escapePreview,
    onCancelPendingDeletion: () => _deletions.cancelFrom(side),
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
/// keys, the preview's or shelf's while they have them, else the active panel's
/// cursor or selection.
class _KeyHintsLine extends StatelessWidget {
  const _KeyHintsLine({
    required this.deletions,
    required this.previewFocus,
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
  final FocusNode previewFocus;
  final PendingDeletionsController deletions;
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
      deletions,
      previewFocus,
      terminalFocus,
      shelfFocus,
      FocusManager.instance,
      panel.screenItems,
    ]),
    builder: (context, _) {
      if (previewFocus.hasFocus) {
        return KeyHintStrip(
          hints: previewHints,
          shortcutMap: shortcutMap,
          vim: false,
          onHide: onHide,
          onHelp: onHelp,
        );
      }
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
              : [
                  if (deletions.hasPending &&
                      !typing &&
                      state.active?.renaming == null)
                    const KeyHint(LogicalKeyboardKey.escape, HintWord.cancel),
                  ...hintsFor(
                    tab: state.active,
                    vim: vim,
                    hasRegister: hasShelf,
                    hasMultipleTabs: state.tabs.length > 1 && !typing,
                    screenItems: panel.geometry.rowsPerPage,
                  ),
                ],
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
    required this.retainPreviewOnExit,
    required this.retainTerminalOnExit,
    required this.deletions,
    required this.operations,
    required this.operationService,
    required this.onCancelDeletion,
    required this.workspace,
    this.terminal,
    this.thumbnails,
    this.terminalSide = PanelSide.left,
    required this.stacked,
    required this.prefs,
    required this.cubitOf,
    required this.decor,
    required this.shortcutMap,
    required this.splitterFocus,
    required this.leftFocus,
    required this.rightFocus,
    required this.leftPanel,
    required this.rightPanel,
    required this.previewSide,
    required this.preview,
    required this.leftCursor,
    required this.rightCursor,
    required this.hooksFor,
    required this.registerNote,
    required this.splitterValue,
    required this.splitterHints,
    required this.onSplitterAction,
    required this.onSplitterDrag,
    required this.onSplitterDragEnd,
    required this.onSplitterReset,
  });

  /// The line the splitter draws down the middle of its handle.
  static const double splitterLineWidth = 1;

  final bool retainPreviewOnExit;
  final bool retainTerminalOnExit;
  final WorkspaceState workspace;
  final PendingDeletionsController deletions;
  final WorkspaceOperationsController operations;
  final OperationsService operationService;
  final ValueChanged<PanelSide> onCancelDeletion;
  final PanelTerminal? terminal;
  final ThumbnailProvider? thumbnails;
  final PanelSide terminalSide;

  /// The left panel above the right one, not beside it.
  final bool stacked;
  final Preferences prefs;
  final PanelCubit Function(PanelSide side) cubitOf;
  final WindowDecor decor;
  final ShortcutMap shortcutMap;
  final FocusNode splitterFocus;
  final FocusNode leftFocus;
  final FocusNode rightFocus;
  final GlobalKey leftPanel;
  final GlobalKey rightPanel;
  final PanelSide? previewSide;
  final Widget? preview;
  final GlobalKey leftCursor;
  final GlobalKey rightCursor;
  final PanelHooks Function(PanelSide side) hooksFor;
  final String? registerNote;
  final String splitterValue;
  final List<AppKeyHint> splitterHints;
  final ValueChanged<AppSplitterAction> onSplitterAction;
  final ValueChanged<double> onSplitterDrag;
  final VoidCallback onSplitterDragEnd;
  final VoidCallback onSplitterReset;

  @override
  Widget build(BuildContext context) {
    final single = workspace.singlePane && previewSide == null;
    final singleLeft = single && workspace.active == PanelSide.left;
    final singleRight = single && workspace.active == PanelSide.right;
    return AppSplitView(
      axis: stacked ? Axis.vertical : Axis.horizontal,
      fraction: workspace.splitFraction,
      expandedPane: single
          ? (singleLeft ? AppSplitPane.first : AppSplitPane.second)
          : null,
      first: _PanelOperationsHost(
        side: PanelSide.left,
        deletions: deletions,
        operations: operations,
        operationService: operationService,
        showOperations: workspace.operationsShown,
        onCancel: () => onCancelDeletion(PanelSide.left),
        child: _PreviewPanelSlot(
          retainOnExit: retainPreviewOnExit,
          preview: previewSide == PanelSide.left ? preview : null,
          child: _SidePanel(
            retainTerminalOnExit: retainTerminalOnExit,
            thumbnails: thumbnails,
            key: leftPanel,
            side: PanelSide.left,
            terminal: terminalSide == PanelSide.left ? terminal : null,
            leading: true,
            trailing: stacked || singleLeft,
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
      ),
      second: _PanelOperationsHost(
        side: PanelSide.right,
        deletions: deletions,
        operations: operations,
        operationService: operationService,
        showOperations: workspace.operationsShown,
        onCancel: () => onCancelDeletion(PanelSide.right),
        child: _PreviewPanelSlot(
          retainOnExit: retainPreviewOnExit,
          preview: previewSide == PanelSide.right ? preview : null,
          child: _SidePanel(
            retainTerminalOnExit: retainTerminalOnExit,
            thumbnails: thumbnails,
            key: rightPanel,
            side: PanelSide.right,
            terminal: terminalSide == PanelSide.right ? terminal : null,
            leading: singleRight,
            trailing: !stacked || singleRight,
            cubit: cubitOf(PanelSide.right),
            focusNode: rightFocus,
            cursorKey: rightCursor,
            active: workspace.active == PanelSide.right,
            prefs: prefs,
            decor: stacked && !singleRight ? WindowDecor.none : decor,
            shortcutMap: shortcutMap,
            hooks: hooksFor(PanelSide.right),
            registerNote: registerNote,
          ),
        ),
      ),
      handle: AppSplitter(
        focusNode: splitterFocus,
        axis: stacked ? Axis.vertical : Axis.horizontal,
        title: context.l10n.splitterTitle,
        value: splitterValue,
        hints: splitterHints,
        onAction: onSplitterAction,
        onDragStart: () {},
        onDragUpdate: onSplitterDrag,
        onDragEnd: onSplitterDragEnd,
        onReset: onSplitterReset,
        resetLabel: context.l10n.splitterReset,
        resetHint: context.l10n.splitterResetHint,
        line: AppSplitterLine.center,
      ),
    );
  }
}

/// Composition for one side: updates cards without rebuilding its file/viewer
/// subtree. Pending deletion is visible even when ordinary progress is hidden.
class _PanelOperationsHost extends StatelessWidget {
  const _PanelOperationsHost({
    required this.side,
    required this.deletions,
    required this.operations,
    required this.operationService,
    required this.showOperations,
    required this.onCancel,
    required this.child,
  });

  final PanelSide side;
  final PendingDeletionsController deletions;
  final WorkspaceOperationsController operations;
  final OperationsService operationService;
  final bool showOperations;
  final VoidCallback onCancel;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([deletions, operations]),
    child: child,
    builder: (context, child) {
      final pending = deletions.pendingFor(side);
      final running = showOperations
          ? operations.operationsFor(side)
          : const <OperationProgress>[];
      return Stack(
        fit: StackFit.expand,
        children: [
          child!,
          Positioned.fill(
            top: context.metrics.topBarHeight,
            bottom: AppStatusBar.heightOf(context),
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.bottomRight,
              child: AppPresence(
                resize: true,
                alignment: Alignment.bottomRight,
                animateInitially: true,
                child: pending != null || running.isNotEmpty
                    ? SizedBox(
                        width: OperationsCards.cardWidth + AppSpacing.md * 2,
                        child: SingleChildScrollView(
                          reverse: true,
                          // Keep the floating plate's shadow inside the viewport.
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: AppSpacing.sm,
                            children: [
                              if (running.isNotEmpty)
                                OperationsCards(
                                  operations: running,
                                  titles: operations.titles,
                                  onPause: (id) =>
                                      unawaited(operationService.pause(id)),
                                  onResume: (id) =>
                                      unawaited(operationService.resume(id)),
                                  onCancel: (id) =>
                                      unawaited(operationService.cancel(id)),
                                  onDismiss: operations.dismiss,
                                  onAnswer: (progress) =>
                                      unawaited(operations.ask(progress.id)),
                                ),
                              if (pending != null)
                                PendingDeletionCard(
                                  key: ValueKey(pending.id),
                                  deletion: pending,
                                  remaining: deletions.remaining(pending),
                                  onCancel: onCancel,
                                ),
                            ],
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      );
    },
  );
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
    required this.retainTerminalOnExit,
    this.terminal,
    this.thumbnails,
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
    super.key,
  });

  final PanelSide side;
  final bool retainTerminalOnExit;
  final PanelTerminal? terminal;
  final ThumbnailProvider? thumbnails;

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
  Widget build(BuildContext context) {
    return BlocProvider<PanelCubit>.value(
      value: cubit,
      child: PanelView(
        thumbnails: thumbnails,
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
        terminal: terminal,
        retainTerminalOnExit: retainTerminalOnExit,
      ),
    );
  }
}

/// Keep the covered panel mounted: its scroll, tabs and selection survive.
class _PreviewPanelSlot extends StatelessWidget {
  const _PreviewPanelSlot({
    required this.child,
    required this.preview,
    required this.retainOnExit,
  });

  final Widget child;
  final Widget? preview;
  final bool retainOnExit;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeFocus(
        excluding: preview != null,
        child: ExcludeSemantics(
          excluding: preview != null,
          child: Offstage(offstage: preview != null, child: child),
        ),
      ),
      AppPresence(
        retainOnExit: retainOnExit,
        animateInitially: true,
        child: preview,
      ),
    ],
  );
}

class _WorkspacePreviewHost extends StatelessWidget {
  const _WorkspacePreviewHost({
    required this.preview,
    required this.view,
    required this.shortcutMap,
    super.key,
  });

  final WorkspacePreview preview;
  final WorkspacePreviewView view;
  final ShortcutMap shortcutMap;

  @override
  Widget build(BuildContext context) => CommandShortcuts(
    shortcuts: {
      for (final entry
          in shortcutMap
              .toShortcuts(
                Theme.of(context).platform,
                scopes: const {CommandScope.panel},
              )
              .entries)
        if (entry.value is CommandIntent &&
            const {
              AppCommand.switchPanel,
              AppCommand.showPreview,
            }.contains((entry.value as CommandIntent).command))
          entry.key: entry.value,
      const SingleActivator(LogicalKeyboardKey.escape): const CommandIntent(
        AppCommand.dismiss,
      ),
    },
    child: CommandHandlers(
      handlers: {
        AppCommand.switchPanel: view.onFocusFiles,
        AppCommand.showPreview: view.onClose,
        AppCommand.dismiss: view.onClose,
      },
      child: preview.builder(context, view),
    ),
  );
}
