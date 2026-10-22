import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:monitoring/monitoring.dart';
import 'package:operations_service/operations_service.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

import '../dialogs/archive_password_dialog.dart';
import '../dialogs/attributes_dialog.dart';
import '../dialogs/batch_rename_dialog.dart';
import '../dialogs/copy_move_dialog.dart';
import '../dialogs/extract_dialog.dart';
import '../dialogs/favorites_dialog.dart';
import '../dialogs/go_to_menus.dart';
import '../dialogs/question_dialog.dart';
import '../dialogs/simple_dialogs.dart';
import '../dialogs/tag_dialog.dart';
import '../operations/operations_cards.dart';
import '../panel/panel_cubit.dart';
import '../panel/panel_footer.dart';
import '../panel/panel_side.dart';
import '../panel/panel_state.dart';
import '../panel/panel_view.dart';
import '../panel/saved_panel.dart';
import '../path_text.dart';
import 'context_menu.dart';
import 'key_hints.dart';
import 'tag_menu.dart';
import 'vim_register.dart';
import 'workspace_cubit.dart';
import 'workspace_state.dart';

part 'vim_actions.dart';
part 'workspace_actions.dart';
part 'archive_actions.dart';
part 'tag_actions.dart';

/// Where the window sends what it does not do itself.
class WorkspaceNavigation {
  const WorkspaceNavigation({
    required this.openViewer,
    required this.openFind,
    required this.openSettings,
    required this.openCheatSheet,
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
    this.capabilities = const Capabilities(),
    super.key,
  });

  final FileRepository files;
  final OperationsService operations;
  final RenameService rename;
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

  /// What this desktop can do that others cannot, as the core reports
  /// it: the commands it lacks are hidden.
  final Capabilities capabilities;

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
  StreamSubscription<OperationProgress>? _progress;
  Timer? _snapshotTimer;
  final _dismissTimers = <int, Timer>{};
  final _shownOperations = <int>{};
  final _askedQuestions = <int>{};
  double _splitBeforeKeys = 0.5;
  double _panelsWidth = 0;

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
    unawaited(_left.start(widget.savedLeft, widget.fallbackLocation));
    unawaited(_right.start(widget.savedRight, widget.fallbackLocation));
    _progress = widget.operations.progress.listen(_onProgress);
    for (final progress in widget.operations.current.values) {
      _shownOperations.add(progress.id);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusOf(_workspace.state.active).requestFocus();
    });
  }

  PanelCubit _panel(PanelSide side) => PanelCubit(
    side: side,
    files: widget.files,
    operations: widget.operations,
    preferences: widget.preferences,
    logger: widget.logger,
    readTags: widget.capabilities.finderTags,
  );

  @override
  void dispose() {
    _progress?.cancel();
    _snapshotTimer?.cancel();
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    _snapshotNow();
    _left.close();
    _right.close();
    _workspace.close();
    _leftFocus.dispose();
    _rightFocus.dispose();
    _splitterFocus.dispose();
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

  void _onProgress(OperationProgress progress) {
    if (progress.kind == OpKind.calcSizes) return;
    final question = progress.question;
    if (progress.state == OpState.waiting &&
        question != null &&
        !_askedQuestions.contains(question.id)) {
      _askedQuestions.add(question.id);
      unawaited(_ask(progress.id, question));
    }
    if (!mounted) return;
    setState(() => _shownOperations.add(progress.id));
    if (progress.state.isFinished) {
      _dismissTimers[progress.id]?.cancel();
      final keep =
          progress.errors.isNotEmpty || progress.state == OpState.failed;
      if (!keep) {
        _dismissTimers[progress.id] = Timer(
          const Duration(seconds: 3),
          () => _dismissOperation(progress.id),
        );
      }
    }
  }

  Future<void> _ask(int operationId, OperationQuestion question) async {
    final answer = await showQuestionDialog(context, question: question);
    await widget.operations.answer(
      operationId,
      question.id,
      answer ?? Answer.abort,
    );
  }

  void _dismissOperation(int id) {
    _dismissTimers.remove(id)?.cancel();
    if (!mounted) return;
    setState(() => _shownOperations.remove(id));
    unawaited(widget.operations.forget(id));
  }

  List<OperationProgress> get _operations => [
    for (final id in _shownOperations) ?widget.operations.current[id],
  ]..sort((a, b) => a.id.compareTo(b.id));

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MultiBlocProvider(
      providers: [BlocProvider.value(value: _workspace)],
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        builder: (context, workspace) => PreferenceBuilder<Preferences>(
          service: widget.preferences,
          select: (p) => p,
          builder: (context, prefs) => Scaffold(
            backgroundColor: context.appColors.window,
            body: CommandHandlers(
              handlers: _globalHandlers(context),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CommandShortcuts(
                            shortcuts: widget.shortcutMap.toShortcuts(
                              Theme.of(context).platform,
                              scopes: const {CommandScope.panel},
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                _panelsWidth = constraints.maxWidth;
                                return _Panels(
                                  workspace: workspace,
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
                                  registerNote: _registerNote(
                                    l10n,
                                    workspace.register,
                                  ),
                                  splitterValue: l10n.textSizePercent(
                                    (workspace.splitFraction * 100).round(),
                                  ),
                                  splitterHints: _splitterHints(context),
                                  onSplitterAction: _onSplitterAction,
                                  onSplitterDrag: (delta) {
                                    if (_panelsWidth > 0) {
                                      _workspace.moveSplit(
                                        delta / _panelsWidth,
                                      );
                                    }
                                  },
                                  onSplitterDragEnd: _scheduleSnapshot,
                                  width: constraints.maxWidth,
                                );
                              },
                            ),
                          ),
                        ),
                        if (workspace.operationsShown)
                          Positioned(
                            right: AppSpacing.md,
                            bottom:
                                AppSpacing.md + PanelFooter.heightOf(context),
                            child: OperationsCards(
                              operations: _operations,
                              onPause: (id) =>
                                  unawaited(widget.operations.pause(id)),
                              onResume: (id) =>
                                  unawaited(widget.operations.resume(id)),
                              onCancel: (id) =>
                                  unawaited(widget.operations.cancel(id)),
                              onDismiss: _dismissOperation,
                              onAnswer: (progress) {
                                final question = progress.question;
                                if (question != null) {
                                  _askedQuestions.add(question.id);
                                  unawaited(_ask(progress.id, question));
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  // The keys for what is under the cursor or selected in the
                  // active panel, until the user hides the line.
                  if (prefs.showKeyHints)
                    BlocBuilder<PanelCubit, PanelState>(
                      bloc: _cubitOf(workspace.active),
                      builder: (context, panel) => KeyHintStrip(
                        hints: hintsFor(
                          tab: panel.active,
                          vim: prefs.vimMode,
                          hasRegister: workspace.register != null,
                        ),
                        shortcutMap: widget.shortcutMap,
                        vim: prefs.vimMode,
                        onHide: () {
                          unawaited(
                            widget.preferences.update(
                              (p) => p.copyWith(showKeyHints: false),
                            ),
                          );
                          showAppNotice(context, l10n.hintsHidden);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    onShowPreview: () => unawaited(_preview()),
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
    onArchivePassword: (location) =>
        unawaited(_passwordForPanel(side, location)),
  );

  List<AppKeyHint> _splitterHints(BuildContext context) {
    final l10n = context.l10n;
    final platform = Theme.of(context).platform;
    String key(LogicalKeyboardKey k) => Chord.keyLabel(k, platform);
    return [
      AppKeyHint(
        [key(LogicalKeyboardKey.arrowLeft), key(LogicalKeyboardKey.arrowRight)],
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

/// The two panels side by side with the edge between them, or the active
/// one alone.
class _Panels extends StatelessWidget {
  const _Panels({
    required this.workspace,
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
    required this.width,
  });

  /// The line the splitter draws down the middle of its handle.
  static const double splitterLineWidth = 1;

  final WorkspaceState workspace;
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
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (workspace.singlePane) {
      final left = workspace.active == PanelSide.left;
      return _SidePanel(
        side: workspace.active,
        only: true,
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
    final leftWidth = (width * workspace.splitFraction).roundToDouble();
    return Stack(
      children: [
        Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: _SidePanel(
                side: PanelSide.left,
                only: false,
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
            AppRule(axis: Axis.vertical, color: colors.line),
            Expanded(
              child: _SidePanel(
                side: PanelSide.right,
                only: false,
                cubit: cubitOf(PanelSide.right),
                focusNode: rightFocus,
                cursorKey: rightCursor,
                active: workspace.active == PanelSide.right,
                prefs: prefs,
                decor: decor,
                shortcutMap: shortcutMap,
                hooks: hooksFor(PanelSide.right),
                registerNote: registerNote,
              ),
            ),
          ],
        ),
        Positioned(
          left: leftWidth - AppSizes.resizeHandleWidth / 2,
          top: 0,
          bottom: 0,
          width: AppSizes.resizeHandleWidth + splitterLineWidth,
          child: AppSplitter(
            focusNode: splitterFocus,
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

/// One side's panel with its own cubit in scope. Keyed by its side, so a
/// switch to single-pane mode keeps the panel's subtree alive.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.side,
    required this.only,
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

  /// The only panel shown: it takes both window insets.
  final bool only;
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
      leftInset:
          (side == PanelSide.left || only ? decor.leadingInset : 0) +
          AppSpacing.md,
      rightInset:
          (side == PanelSide.right || only ? decor.trailingInset : 0) +
          AppSpacing.sm,
      shortcutMap: shortcutMap,
      hooks: hooks,
      windowDecor: decor,
      cursorRowKey: cursorKey,
    ),
  );
}
