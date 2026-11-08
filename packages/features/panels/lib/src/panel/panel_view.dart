import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shortcuts/shortcuts.dart';

import '../native/drop_plan.dart';
import '../native/panel_drag_hooks.dart';
import 'panel_cubit.dart';
import 'panel_footer.dart';
import 'panel_header.dart';
import 'panel_row.dart';
import 'panel_state.dart';
import 'rows_brief.dart';
import 'rows_list.dart';
import 'vim_command_line.dart';
import 'vim_keys.dart';

/// What a panel asks of the window around it.
class PanelHooks {
  const PanelHooks({
    required this.onActivate,
    required this.onOpenFile,
    required this.onContextMenu,
    required this.onPanelMenu,
    required this.onSwitchPanel,
    required this.onShowPreview,
    required this.onGoHome,
    required this.onGoRoot,
    required this.onVimYank,
    required this.onVimCut,
    required this.onVimPaste,
    required this.onVimCancelRegister,
    required this.onVimSetMark,
    required this.onVimGoMark,
    required this.onVimCommand,
    required this.onVimComplete,
    this.drag,
    this.onEscape,
    this.onArchivePassword,
  });

  /// The panel was clicked or took the keys: it is the active one now.
  final VoidCallback onActivate;

  /// Return on a file.
  final ValueChanged<OpenFileRequest> onOpenFile;

  /// A right click, or the menu key, on the focused row; the anchor is
  /// the row or the pointer.
  final void Function(Rect anchor) onContextMenu;
  final void Function(Rect anchor) onPanelMenu;
  final VoidCallback onSwitchPanel;
  final VoidCallback onShowPreview;
  final VoidCallback onGoHome;
  final VoidCallback onGoRoot;

  /// Vim: `yy` and `dd` take the targets to copy or move, `p` puts them
  /// here, `uy` lets them go.
  final VoidCallback onVimYank;
  final VoidCallback onVimCut;
  final VoidCallback onVimPaste;
  final VoidCallback onVimCancelRegister;

  /// Vim: `m` and `'` with a letter; `''` is the place before.
  final ValueChanged<String> onVimSetMark;
  final ValueChanged<String> onVimGoMark;

  /// Vim: a `:` line to run, and the completions of one being typed.
  final ValueChanged<String> onVimCommand;
  final Future<List<String>> Function(String line) onVimComplete;

  /// Rows dragged out of the panel and files dropped on it; the panel
  /// takes no part in drags without it.
  final PanelDragHooks? drag;

  /// Esc closes what floats over the panels (Quick Look) before anything
  /// in the panel; answers whether it closed something.
  final bool Function()? onEscape;

  /// An archive's folder asked for its password: the window asks the
  /// user and opens it again.
  final ValueChanged<Location>? onArchivePassword;
}

/// One file panel: header, tabs, rows and footer, with the panel's keys.
class PanelView extends StatefulWidget {
  const PanelView({
    required this.focusNode,
    required this.active,
    required this.layouts,
    required this.showTabBarAlways,
    required this.quickSearchModifier,
    required this.vimMode,
    required this.leftInset,
    required this.rightInset,
    required this.shortcutMap,
    required this.hooks,
    this.registerNote,
    this.windowDecor = WindowDecor.none,
    this.cursorRowKey,
    super.key,
  });

  final FocusNode focusNode;
  final bool active;
  final List<PanelLayout> layouts;
  final bool showTabBarAlways;
  final QuickSearchModifier quickSearchModifier;

  /// Vim keys are on: letters are commands, `/` searches, `:` is the
  /// command line, the footer names the mode.
  final bool vimMode;
  final double leftInset;
  final double rightInset;
  final ShortcutMap shortcutMap;
  final PanelHooks hooks;

  /// What the shelf holds (Add to Shelf, `yy`, `dd`), for the footer.
  final String? registerNote;

  /// The window's top row, which the header is part of.
  final WindowDecor windowDecor;

  /// Set on the cursor's row while it is in view, so the window can open
  /// a menu by it (the menu key, Open With).
  final GlobalKey? cursorRowKey;

  @override
  State<PanelView> createState() => _PanelViewState();
}

class _PanelViewState extends State<PanelView> {
  /// The highlight of a panel without drags: never lit.
  static final _noDrop = ValueNotifier<DropSpot?>(null);

  final _vim = VimKeys();
  final _commandHistory = <String>[];
  bool _commandLine = false;

  PanelCubit get _cubit => context.read<PanelCubit>();

  PanelLayout _layoutOf(PanelTabState tab) {
    final layouts = widget.layouts.isEmpty
        ? PanelLayout.defaults
        : widget.layouts;
    return layouts[tab.layoutIndex.clamp(0, layouts.length - 1)];
  }

  /// Whether the names stand in columns (brief mode), where `h` and `l`
  /// move by a column.
  bool get _inColumns => switch (_cubit.state.active) {
    final tab? => _layoutOf(tab).mode == ViewMode.brief,
    null => false,
  };

  @override
  void initState() {
    super.initState();
    KeySequenceState.changes.addListener(_onSequence);
  }

  @override
  void didUpdateWidget(PanelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vimMode != widget.vimMode) {
      _vim.clear();
      _commandLine = false;
      _cubit.endVisual();
    }
  }

  @override
  void dispose() {
    KeySequenceState.changes.removeListener(_onSequence);
    super.dispose();
  }

  /// A prefix armed (`g`, `d`…) or let go shows in the footer.
  void _onSequence() {
    if (widget.vimMode && mounted) setState(() {});
  }

  // ─── Keys ───

  /// Letters typed go to the quick search; Backspace takes one back while
  /// a search is on; everything else goes on to the shortcuts. With Vim
  /// keys on, letters are commands unless the `/` prompt is open, digits
  /// count, and `f` `m` `'` take the key after them.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final tab = _cubit.state.active;
    if (tab == null || tab.renaming != null || _commandLine) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final plain =
        !keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed;
    final character = event.character;
    if (widget.vimMode && !tab.searching) {
      if (!plain) return KeyEventResult.ignored;
      final outcome = _vim.feed(key: event.logicalKey, character: character);
      switch (outcome) {
        case VimIgnored():
          return KeyEventResult.ignored;
        case VimConsumed():
          setState(() {});
          return KeyEventResult.handled;
        case VimFindChar(:final char, :final forward):
          setState(() {});
          _cubit.findRowStartingWith(
            char,
            forward: forward,
            count: _vim.takeCount(),
          );
          return KeyEventResult.handled;
        case VimSetMark(:final letter):
          setState(() {});
          widget.hooks.onVimSetMark(letter);
          return KeyEventResult.handled;
        case VimGoMark(:final letter):
          setState(() {});
          widget.hooks.onVimGoMark(letter);
          return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        tab.quickSearch.isNotEmpty &&
        plain) {
      _cubit.quickSearchBackspace();
      return KeyEventResult.handled;
    }
    if (widget.vimMode && tab.searching) {
      // The `/` prompt: Return keeps the matches, Esc clears them.
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _cubit.searchConfirm();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cubit.searchCancel();
        return KeyEventResult.handled;
      }
      // Backspace on an empty prompt leaves it, never the folder.
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        _cubit.searchCancel();
        return KeyEventResult.handled;
      }
    }
    if (character == null || character.isEmpty) return KeyEventResult.ignored;
    final rune = character.runes.first;
    if (rune < 0x20 || rune == 0x7f) return KeyEventResult.ignored;
    if (widget.vimMode) {
      if (!tab.searching) return KeyEventResult.ignored;
    } else if (!_quickSearchModifiersHeld(keyboard)) {
      return KeyEventResult.ignored;
    }
    // Space, `/` and `~` are keys of their own unless a search is on.
    if (tab.quickSearch.isEmpty &&
        !tab.searching &&
        (character == ' ' || character == '/' || character == '~')) {
      return KeyEventResult.ignored;
    }
    _cubit.quickSearchType(character);
    return KeyEventResult.handled;
  }

  bool _quickSearchModifiersHeld(HardwareKeyboard keyboard) {
    if (keyboard.isMetaPressed) return false;
    return switch (widget.quickSearchModifier) {
      QuickSearchModifier.disabled => false,
      QuickSearchModifier.none =>
        !keyboard.isControlPressed && !keyboard.isAltPressed,
      QuickSearchModifier.alt =>
        keyboard.isAltPressed &&
            !keyboard.isControlPressed &&
            !keyboard.isShiftPressed,
      QuickSearchModifier.controlAlt =>
        keyboard.isAltPressed && keyboard.isControlPressed,
      QuickSearchModifier.shiftAlt =>
        keyboard.isAltPressed && keyboard.isShiftPressed,
    };
  }

  /// A count typed before the command, or 1.
  int get _count => widget.vimMode ? _vim.takeCount() : 1;

  /// `{count}G` goes to row `count`; a plain `G` to the last row.
  void _moveLast({bool selecting = false}) {
    if (widget.vimMode && _vim.hasCount) {
      _cubit.moveCursorTo(_vim.takeCount() - 1, selecting: selecting);
    } else {
      _cubit.moveLast(selecting: selecting);
    }
  }

  void _moveFirst({bool selecting = false}) {
    if (widget.vimMode && _vim.hasCount) {
      _cubit.moveCursorTo(_vim.takeCount() - 1, selecting: selecting);
    } else {
      _cubit.moveFirst(selecting: selecting);
    }
  }

  /// `{count}gt` shows tab `count`.
  void _nextTab() {
    if (widget.vimMode && _vim.hasCount) {
      _cubit.showTab(_vim.takeCount() - 1);
    } else {
      _cubit.nextTab();
    }
  }

  /// Esc, with Vim keys on, steps back one thing at a time: what waits,
  /// the search prompt, the matches, Visual mode, the selection.
  void _escape() {
    if (widget.hooks.onEscape?.call() ?? false) return;
    final tab = _cubit.state.active;
    if (!widget.vimMode || tab == null) {
      // A flat view goes back to its folder once no search is on.
      if (tab != null && tab.quickSearch.isEmpty && tab.isFlat) {
        unawaited(_cubit.leaveFlatView());
      } else {
        _cubit.clearQuickSearch();
      }
      return;
    }
    if (_vim.count != null || _vim.pending != null) {
      setState(_vim.clear);
    } else if (tab.searching) {
      _cubit.searchCancel();
    } else if (tab.quickSearch.isNotEmpty) {
      _cubit.clearQuickSearch();
    } else if (tab.visual) {
      _cubit.endVisual();
    } else if (tab.selected.isNotEmpty) {
      _cubit.deselectAll();
    } else if (tab.isFlat) {
      unawaited(_cubit.leaveFlatView());
    }
  }

  void _pending(VimPending what) {
    if (!widget.vimMode) return;
    setState(() => _vim.pending = what);
  }

  void _repeatFind({required bool reverse}) {
    final find = _vim.repeatFind(reverse: reverse);
    if (find == null) return;
    _cubit.findRowStartingWith(
      find.char,
      forward: find.forward,
      count: _vim.takeCount(),
    );
  }

  int get _halfPage => (_cubit.geometry.rowsPerPage ~/ 2).clamp(1, 1 << 20);

  Map<AppCommand, VoidCallback> _handlers() => {
    AppCommand.moveUp: () => _cubit.moveCursor(-_count),
    AppCommand.moveDown: () => _cubit.moveCursor(_count),
    AppCommand.moveLeft: () => _cubit.moveColumn(-_count),
    AppCommand.moveRight: () => _cubit.moveColumn(_count),
    AppCommand.moveFirst: _moveFirst,
    AppCommand.moveLast: _moveLast,
    AppCommand.scrollFirst: _moveFirst,
    AppCommand.scrollLast: _moveLast,
    AppCommand.movePageUp: () => _cubit.movePage(-_count),
    AppCommand.movePageDown: () => _cubit.movePage(_count),
    AppCommand.scrollPageUp: () => _cubit.movePage(-_count),
    AppCommand.scrollPageDown: () => _cubit.movePage(_count),
    AppCommand.selectMoveUp: () => _cubit.moveCursor(-_count, selecting: true),
    AppCommand.selectMoveDown: () => _cubit.moveCursor(_count, selecting: true),
    AppCommand.selectMoveLeft: () =>
        _cubit.moveColumn(-_count, selecting: true),
    AppCommand.selectMoveRight: () =>
        _cubit.moveColumn(_count, selecting: true),
    AppCommand.selectMoveFirst: () => _moveFirst(selecting: true),
    AppCommand.selectMoveLast: () => _moveLast(selecting: true),
    AppCommand.selectMovePageUp: () =>
        _cubit.movePage(-_count, selecting: true),
    AppCommand.selectMovePageDown: () =>
        _cubit.movePage(_count, selecting: true),
    AppCommand.toggleSelection: _cubit.toggleSelection,
    AppCommand.toggleSelectionMoveDown: () {
      for (var i = _count; i > 0; i--) {
        _cubit.toggleSelectionAndMoveDown();
      }
    },
    AppCommand.enterItem: _enter,
    AppCommand.goParent: () => unawaited(_cubit.goParent()),
    AppCommand.goHomeKey: widget.hooks.onGoHome,
    AppCommand.goRootKey: widget.hooks.onGoRoot,
    AppCommand.switchPanel: widget.hooks.onSwitchPanel,
    AppCommand.showPreview: widget.hooks.onShowPreview,
    AppCommand.clearQuickSearch: _escape,
    for (var i = 0; i < 10; i++)
      AppCommand.values.byName('showTab${i + 1}'): () => _cubit.showTab(i),
    // Vim
    AppCommand.vimVisual: _cubit.toggleVisual,
    AppCommand.vimSearch: _cubit.searchOpen,
    AppCommand.vimSearchNext: () =>
        _cubit.searchStep(forward: true, count: _count),
    AppCommand.vimSearchPrevious: () =>
        _cubit.searchStep(forward: false, count: _count),
    AppCommand.vimCommandLine: _openCommandLine,
    AppCommand.vimCut: () => _operator(widget.hooks.onVimCut),
    AppCommand.vimYank: () => _operator(widget.hooks.onVimYank),
    AppCommand.vimPaste: widget.hooks.onVimPaste,
    AppCommand.vimCancelRegister: widget.hooks.onVimCancelRegister,
    AppCommand.vimFindChar: () => _pending(VimPending.findForward),
    AppCommand.vimFindCharBack: () => _pending(VimPending.findBackward),
    AppCommand.vimRepeatFind: () => _repeatFind(reverse: false),
    AppCommand.vimRepeatFindBack: () => _repeatFind(reverse: true),
    AppCommand.vimSetMark: () => _pending(VimPending.setMark),
    AppCommand.vimGoMark: () => _pending(VimPending.goMark),
    AppCommand.vimScreenTop: () =>
        _cubit.moveToScreen(ScrollAlign.top, count: _count),
    AppCommand.vimScreenMiddle: () => _cubit.moveToScreen(ScrollAlign.center),
    AppCommand.vimScreenBottom: () =>
        _cubit.moveToScreen(ScrollAlign.bottom, count: _count),
    AppCommand.vimScrollCenter: () => _cubit.scrollCursor(ScrollAlign.center),
    AppCommand.vimScrollTop: () => _cubit.scrollCursor(ScrollAlign.top),
    AppCommand.vimScrollBottom: () => _cubit.scrollCursor(ScrollAlign.bottom),
    AppCommand.vimHalfPageDown: () => _cubit.moveCursor(_halfPage * _count),
    AppCommand.vimHalfPageUp: () => _cubit.moveCursor(-_halfPage * _count),
    AppCommand.vimColumnNext: () => _cubit.moveColumn(_count),
    AppCommand.vimColumnPrevious: () => _cubit.moveColumn(-_count),
    AppCommand.vimLeft: () =>
        _inColumns ? _cubit.moveColumn(-_count) : unawaited(_cubit.goParent()),
    AppCommand.vimRight: () =>
        _inColumns ? _cubit.moveColumn(_count) : unawaited(_enter()),
    AppCommand.vimRenameAppend: () =>
        _cubit.startRenaming(caret: RenameCaret.end),
    AppCommand.vimRenamePrepend: () =>
        _cubit.startRenaming(caret: RenameCaret.start),
    AppCommand.vimSortReverse: () => unawaited(_cubit.sortReverse()),
    AppCommand.vimReselect: _cubit.reselectLast,
    AppCommand.nextTab: _nextTab,
  };

  /// `yy` and `dd` act on the targets and end Visual mode.
  void _operator(VoidCallback action) {
    action();
    _cubit.endVisual();
  }

  Future<void> _enter() async {
    final request = await _cubit.enter();
    if (request != null && mounted) widget.hooks.onOpenFile(request);
  }

  // ─── The command line ───

  void _openCommandLine() {
    if (!widget.vimMode) return;
    setState(() => _commandLine = true);
  }

  void _closeCommandLine() {
    if (!mounted) return;
    setState(() => _commandLine = false);
    widget.focusNode.requestFocus();
  }

  void _runCommandLine(String line) {
    _closeCommandLine();
    if (line.isEmpty) return;
    _commandHistory.remove(line);
    _commandHistory.add(line);
    if (_commandHistory.length > 50) _commandHistory.removeAt(0);
    widget.hooks.onVimCommand(line);
  }

  // ─── Mouse ───

  void _onTapDown(int index, {bool toggle = false, bool range = false}) {
    widget.hooks.onActivate();
    _cubit.clickRow(index, toggle: toggle, range: range);
  }

  void _onDoubleTap(int index) {
    widget.hooks.onActivate();
    _cubit.moveCursorTo(index, scroll: false);
    unawaited(_enter());
  }

  void _onSecondaryTapDown(int index, Offset global) {
    widget.hooks.onActivate();
    _cubit.moveCursorTo(index, scroll: false);
    widget.hooks.onContextMenu(Rect.fromLTWH(global.dx, global.dy, 0, 0));
  }

  Future<void> _onRenameCommit(String name) async {
    final error = await _cubit.commitRename(name);
    if (error != null && mounted) {
      showAppNotice(context, context.l10n.errorMessage(error));
    }
    widget.focusNode.requestFocus();
  }

  void _onRenameCancel() {
    _cubit.stopRenaming();
    widget.focusNode.requestFocus();
  }

  // ─── Menus ───

  Future<void> _sortMenu(Rect anchor) async {
    final tab = _cubit.state.active;
    if (tab == null) return;
    final picked = await showAppMenu<Object>(
      context: context,
      anchor: anchor,
      entries: sortMenuEntries(context, tab.sort, widget.shortcutMap),
    );
    if (picked == null || !mounted) return;
    final sort = tab.sort;
    switch (picked) {
      case SortField field:
        await _cubit.toggleSortField(field);
      case SortDirection direction:
        await _cubit.setSort(
          sort.copyWith(descending: direction == SortDirection.descending),
        );
      case AppCommand.toggleFoldersFirst:
        await _cubit.setSort(sort.copyWith(foldersFirst: !sort.foldersFirst));
      case AppCommand.toggleExtensionlessFolders:
        await _cubit.setSort(
          sort.copyWith(extensionlessFolders: !sort.extensionlessFolders),
        );
      case AppCommand.collationNatural:
        await _cubit.setSort(sort.copyWith(collation: Collation.natural));
      case AppCommand.collationCaseInsensitive:
        await _cubit.setSort(
          sort.copyWith(collation: Collation.caseInsensitive),
        );
      case AppCommand.collationCaseSensitive:
        await _cubit.setSort(sort.copyWith(collation: Collation.caseSensitive));
    }
  }

  Future<void> _layoutMenu(Rect anchor) async {
    final tab = _cubit.state.active;
    if (tab == null) return;
    final layouts = widget.layouts.isEmpty
        ? PanelLayout.defaults
        : widget.layouts;
    final platform = Theme.of(context).platform;
    final picked = await showAppMenu<int>(
      context: context,
      anchor: anchor,
      entries: [
        AppMenuSection(context.l10n.layoutMenuTitle),
        for (var i = 0; i < layouts.length; i++)
          AppMenuAction(
            value: i,
            label: context.l10n.viewModeName(layouts[i]),
            icon: layouts[i].mode == ViewMode.list
                ? AppIcons.layoutList
                : AppIcons.layoutBrief,
            shortcut: i < 5
                ? widget.shortcutMap.labelOf(
                    AppCommand.values.byName('viewMode${i + 1}'),
                    platform,
                  )
                : null,
            checked: tab.layoutIndex == i,
          ),
      ],
    );
    if (picked != null) _cubit.setLayout(picked);
  }

  Future<void> _tabsMenu(Rect anchor, PanelState state) async {
    final picked = await showAppMenu<String>(
      context: context,
      anchor: anchor,
      entries: [
        for (final t in state.tabs)
          AppMenuAction(
            value: t.id,
            label: t.location.display,
            icon: _tabIcon(t.location),
            checked: t.id == state.active?.id,
          ),
        if (state.closedTabs.isNotEmpty) ...[
          const AppMenuSeparator(),
          AppMenuSection(context.l10n.tabRecentlyClosed),
          for (var i = 0; i < state.closedTabs.length && i < 8; i++)
            AppMenuAction(
              value: 'closed:$i',
              label: state.closedTabs[i].display,
              icon: AppIcons.history,
            ),
        ],
      ],
    );
    if (picked == null || !mounted) return;
    if (picked.startsWith('closed:')) {
      final index = int.parse(picked.substring(7));
      await _cubit.newTab(location: state.closedTabs[index]);
      return;
    }
    final index = state.tabs.indexWhere((t) => t.id == picked);
    if (index >= 0) _cubit.showTab(index);
  }

  // ─── Build ───

  /// The footer's Vim line: the mode, what waits, the command line while
  /// it is open.
  VimLine? _vimLine(PanelTabState tab) {
    if (!widget.vimMode) return null;
    final platform = Theme.of(context).platform;
    final armed = KeySequenceState.pending;
    final pending = [
      _vim.pendingText,
      if (armed != null) Chord.keyLabel(armed, platform).toLowerCase(),
    ].join();
    return VimLine(
      mode: _commandLine
          ? VimMode.command
          : tab.searching
          ? VimMode.search
          : tab.visual
          ? VimMode.visual
          : VimMode.normal,
      pending: pending,
      commandLine: _commandLine
          ? VimCommandLine(
              shortcutMap: widget.shortcutMap,
              history: List.unmodifiable(_commandHistory),
              onRun: _runCommandLine,
              onCancel: _closeCommandLine,
              complete: widget.hooks.onVimComplete,
            )
          : null,
    );
  }

  /// A new error that is a password request: the window asks at once.
  static bool _asksPassword(PanelState previous, PanelState next) {
    final before = previous.active;
    final after = next.active;
    return after?.passwordLocation != null &&
        after?.error?.kind == FerryxErrorKind.passwordRequired &&
        (before?.id != after?.id || !identical(before?.error, after?.error));
  }

  /// The error strip's button: the password again for an archive that
  /// asked for one, the connection again for a server out of reach, else
  /// another read.
  VoidCallback _retryOf(PanelTabState tab) {
    final location = tab.passwordLocation;
    if (location != null &&
        tab.error?.kind == FerryxErrorKind.passwordRequired) {
      return () => widget.hooks.onArchivePassword?.call(location);
    }
    if (_reconnects(tab)) return () => unawaited(_cubit.reconnect());
    return () => unawaited(_cubit.refresh());
  }

  static bool _reconnects(PanelTabState tab) =>
      tab.location.isRemote && (tab.error?.kind.needsConnection ?? false);

  static IconData _tabIcon(Location location) => location.isRemote
      ? AppIcons.server
      : location.isNative
      ? AppIcons.folder
      : AppIcons.fileArchive;

  Future<void> _openCommandPalette() async {
    widget.hooks.onActivate();
    widget.focusNode.requestFocus();
    // Pointer clicks need not focus a toolbar button. Let the panel take
    // focus before the palette captures its commands and return location.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !widget.focusNode.hasFocus) return;
    invokeCommand(widget.focusNode.context!, AppCommand.commandPalette);
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<PanelCubit, PanelState>(
    listenWhen: _asksPassword,
    listener: (context, state) {
      final location = state.active?.passwordLocation;
      if (location != null) widget.hooks.onArchivePassword?.call(location);
    },
    builder: (context, state) {
      final tab = state.active;
      final l10n = context.l10n;
      if (tab == null) return const SizedBox.shrink();
      final layout = _layoutOf(tab);
      final showTabs = widget.showTabBarAlways || state.tabs.length > 1;
      final callbacks = RowCallbacks(
        onTapDown: _onTapDown,
        onDoubleTap: _onDoubleTap,
        onSecondaryTapDown: _onSecondaryTapDown,
        onRenameCommit: (name) => unawaited(_onRenameCommit(name)),
        onRenameCancel: _onRenameCancel,
        drag: widget.hooks.drag,
      );
      final rename = RenameSpec(
        caret: tab.renameCaret,
        shortcutMap: widget.shortcutMap,
      );
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) {
          widget.hooks.onActivate();
          if (!widget.focusNode.hasFocus && !_commandLine) {
            widget.focusNode.requestFocus();
          }
        },
        child: AppFocusArea(
          child: CommandHandlers(
            handlers: _handlers(),
            child: Focus(
              focusNode: widget.focusNode,
              onKeyEvent: _onKey,
              onFocusChange: (focused) {
                if (focused) widget.hooks.onActivate();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PanelHeader(
                    location: tab.location,
                    sort: tab.sort,
                    layout: layout,
                    active: widget.active,
                    leftInset: widget.leftInset,
                    rightInset: widget.rightInset,
                    onOpen: (location) {
                      widget.hooks.onActivate();
                      unawaited(_cubit.open(location));
                    },
                    onSortMenu: (anchor) => unawaited(_sortMenu(anchor)),
                    onLayoutMenu: (anchor) => unawaited(_layoutMenu(anchor)),
                    onPanelMenu: widget.hooks.onPanelMenu,
                    onCommandPalette: () => unawaited(_openCommandPalette()),
                    shortcutMap: widget.shortcutMap,
                    decor: widget.windowDecor,
                    edge: !showTabs || !AppTabStrip.joinsBarAbove(context),
                  ),
                  if (showTabs)
                    AppTabStrip(
                      tabs: [
                        for (final t in state.tabs)
                          AppTab(
                            id: t.id,
                            label: t.location.name,
                            tooltip: t.location.display,
                            icon: _tabIcon(t.location),
                          ),
                      ],
                      active: state.activeIndex,
                      onSelect: _cubit.showTab,
                      onClose: (index) => unawaited(_cubit.closeTab(index)),
                      onReorder: _cubit.moveTab,
                      onMenu: (index, anchor) =>
                          unawaited(_tabsMenu(anchor, state)),
                      onNewTab: () => unawaited(_cubit.newTab()),
                      closeTooltip: l10n.tabClose,
                      newTabTooltip: l10n.tabNew,
                      listTooltip: l10n.tabList,
                      newTabShortcut: widget.shortcutMap.labelOf(
                        AppCommand.newTab,
                        Theme.of(context).platform,
                      ),
                      // The menu key on a focused tab opens its menu by
                      // the tab; Esc puts the keys back on the rows.
                      wrapTab: (index, item) => Builder(
                        builder: (context) => CommandHandlers(
                          handlers: {
                            AppCommand.contextMenu: () => unawaited(
                              _tabsMenu(keyboardMenuAnchor(context), state),
                            ),
                          },
                          child: item,
                        ),
                      ),
                      onLeave: widget.focusNode.requestFocus,
                    ),
                  // The rows on the content colour, white or near black,
                  // as a table's in an AppKit window (Finder's list).
                  Expanded(
                    child: ColoredBox(
                      color: context.colors.surface,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: PanelDropZone(
                              hooks: widget.hooks.drag,
                              folder: tab.location,
                              child: ValueListenableBuilder<DropSpot?>(
                                valueListenable:
                                    widget.hooks.drag?.highlight ?? _noDrop,
                                builder: (context, spot, _) =>
                                    layout.mode == ViewMode.list
                                    ? RowsList(
                                        tab: tab,
                                        layout: layout,
                                        active: widget.active,
                                        callbacks: callbacks,
                                        rename: rename,
                                        cursorKey: widget.cursorRowKey,
                                        dropRow: spot?.row,
                                        onSort: (field) => unawaited(
                                          _cubit.toggleSortField(field),
                                        ),
                                        onGeometry: (g) => _cubit.geometry = g,
                                      )
                                    : RowsBrief(
                                        tab: tab,
                                        layout: layout,
                                        active: widget.active,
                                        callbacks: callbacks,
                                        rename: rename,
                                        cursorKey: widget.cursorRowKey,
                                        dropRow: spot?.row,
                                        onSort: (field) => unawaited(
                                          _cubit.toggleSortField(field),
                                        ),
                                        onGeometry: (g) => _cubit.geometry = g,
                                      ),
                              ),
                            ),
                          ),
                          if (tab.loading && tab.listing == null)
                            const Positioned.fill(child: _LoadingVeil()),
                        ],
                      ),
                    ),
                  ),
                  if (tab.error case final error?)
                    _ErrorArea(
                      text: errorStripOf(l10n, tab, error),
                      onRetry: _retryOf(tab),
                    ),
                  PanelFooter(
                    tab: tab,
                    active: widget.active,
                    vim: _vimLine(tab),
                    shelfNote: widget.registerNote,
                    onLeaveFlat: () => unawaited(_cubit.leaveFlatView()),
                    serverState: state.serverStateOf(tab),
                    onReconnect: () => unawaited(_cubit.reconnect()),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// What the strip under the rows says of [error] in [tab]: its title,
/// the line under it, its button's word, and whether it is a fault (a red
/// sign) or a state to act on (a server not connected yet, an archive
/// that waits for its password).
ErrorStripText errorStripOf(
  FerryxLocalizations l10n,
  PanelTabState tab,
  FerryxException error,
) {
  final archive = tab.passwordLocation?.archive;
  // The folder shown is fine: it is the archive that waits.
  if (error.kind == FerryxErrorKind.passwordRequired && archive != null) {
    return (
      title: l10n.archivePasswordTitle(Location.native(archive).name),
      message: l10n.archivePasswordMessage,
      action: l10n.archiveEnterPassword,
      fault: false,
    );
  }
  if (tab.location.isRemote && error.kind.needsConnection) {
    final notYet = error.kind == FerryxErrorKind.notConnected;
    return (
      title: l10n.errorMessage(FerryxException(error.kind, '')),
      message: tab.location.display,
      action: notYet ? l10n.networkConnect : l10n.networkReconnect,
      fault: !notYet,
    );
  }
  return (
    title: l10n.panelErrorTitle,
    message: l10n.errorMessage(error),
    action: l10n.actionRetry,
    fault: true,
  );
}

typedef ErrorStripText = ({
  String title,
  String message,
  String action,
  bool fault,
});

/// A folder that could not be read, or a state to act on: the message in
/// a strip under the rows that stay, with a button (the keys reach it; ⌘J
/// labels it).
class _ErrorArea extends StatelessWidget {
  const _ErrorArea({required this.text, required this.onRetry});

  final ErrorStripText text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.metrics.tableRowInset + AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: AppBorder(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          Icon(
            text.fault ? AppIcons.warning : AppIcons.info,
            size: AppIconSize.md,
            color: text.fault ? colors.danger : colors.textMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text.title, style: context.text.labelMedium),
                Text(
                  text.message,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          HintTarget(
            onActivate: onRetry,
            child: OutlinedButton(
              style: AppButtonStyles.small(context),
              onPressed: onRetry,
              child: Text(text.action),
            ),
          ),
        ],
      ),
    );
  }
}

/// A veil over the rows while a folder is first read, with the platform's
/// spinner; shown only once the read has taken a moment, so a quick one
/// never flashes it.
class _LoadingVeil extends StatefulWidget {
  const _LoadingVeil();

  static const delay = Duration(milliseconds: 300);

  @override
  State<_LoadingVeil> createState() => _LoadingVeilState();
}

class _LoadingVeilState extends State<_LoadingVeil> {
  Timer? _wait;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _wait = Timer(_LoadingVeil.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.expand();
    return ColoredBox(
      color: context.appColors.hoverFill,
      child: Center(
        child: Semantics(
          label: context.l10n.panelLoading,
          child: const AppSpinner(),
        ),
      ),
    );
  }
}

/// The row height, for the window to size things by.
double panelRowExtent(BuildContext context) => panelRowHeight(context);
