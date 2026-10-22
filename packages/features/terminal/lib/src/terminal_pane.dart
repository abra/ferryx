import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:xterm/xterm.dart';

import 'terminal_keys.dart';
import 'terminal_look.dart';
import 'terminal_session_cubit.dart';

/// Where the terminal sits in the window, as the workspace placed it.
class TerminalPlacement {
  const TerminalPlacement({
    this.panelsHidden = false,
    this.fullWindow = false,
    this.decor = WindowDecor.none,
  });

  /// The panels are hidden over the terminal (it takes their place).
  final bool panelsHidden;

  /// The terminal takes the whole window.
  final bool fullWindow;

  /// The window's buttons, when the terminal's bar is the window's top row.
  final WindowDecor decor;

  /// The bar is the window's top row: it keeps room for the window's
  /// buttons and moves the window.
  bool get topRow => panelsHidden || fullWindow;
}

/// The integrated terminal: a bar with its folder and its place in the
/// window, the emulator, and, once the shell has ended, a line offering a
/// new one. A part of the window the keys can be in ([AppFocusArea]).
///
/// The keys go to the shell, but for the terminal's own commands and the
/// window's chords no program is given ([TerminalKeys]).
class TerminalPane extends StatefulWidget {
  const TerminalPane({
    required this.cubit,
    required this.focusNode,
    required this.shortcutMap,
    required this.fontSize,
    required this.placement,
    required this.onHide,
    required this.onTogglePanels,
    required this.onToggleFullWindow,
    super.key,
  });

  final TerminalSessionCubit cubit;
  final FocusNode focusNode;
  final ShortcutMap shortcutMap;
  final double fontSize;
  final TerminalPlacement placement;
  final VoidCallback onHide;
  final VoidCallback onTogglePanels;
  final VoidCallback onToggleFullWindow;

  /// The height of one line of the terminal's text at [fontSize], for
  /// sizing the terminal by lines.
  static double lineHeightOf(BuildContext context, double fontSize) {
    final look = TerminalLook();
    return look.cellOf(look.styleOf(context, fontSize)).height;
  }

  /// The height the terminal takes besides its lines: its bar and the
  /// emulator's margins, when it sits under the panels.
  static double chromeHeightOf(BuildContext context) =>
      TerminalBar.heightOf(context, topRow: false) + 2 * AppSpacing.xs;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final _look = TerminalLook();
  final _scroll = ScrollController();
  final _view = GlobalKey<TerminalViewState>();
  TerminalKeys? _keys;

  TerminalSessionCubit get _cubit => widget.cubit;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  TerminalKeys _keysFor(TargetPlatform platform) {
    final keys = _keys;
    if (keys != null && keys.sameAs(widget.shortcutMap, platform)) return keys;
    return _keys = TerminalKeys(widget.shortcutMap, platform);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final command = _keysFor(Theme.of(context).platform).commandFor(
      event,
      keyboard,
    );
    if (command != null) {
      final at = node.context;
      if (at != null) invokeCommand(at, command);
      return KeyEventResult.handled;
    }
    final plain =
        !keyboard.isShiftPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed;
    if (_cubit.state.ended &&
        plain &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      unawaited(_cubit.restart());
      return KeyEventResult.handled;
    }
    // The logo key is never typed into a terminal; the system may want it.
    if (keyboard.isMetaPressed) return KeyEventResult.skipRemainingHandlers;
    return KeyEventResult.ignored;
  }

  Map<AppCommand, VoidCallback> _handlers() => {
    AppCommand.terminalCopy: () => unawaited(_copy()),
    AppCommand.terminalPaste: () => unawaited(_paste()),
    AppCommand.terminalSelectAll: _cubit.selectAll,
    AppCommand.terminalClear: _cubit.clear,
    AppCommand.terminalScrollPageUp: () => _scrollPage(-1),
    AppCommand.terminalScrollPageDown: () => _scrollPage(1),
    AppCommand.contextMenu: () => unawaited(_menu(_cursorAnchor())),
  };

  Future<void> _copy() async {
    final text = _cubit.selectedText();
    if (text != null) await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && mounted) _cubit.paste(text);
  }

  void _scrollPage(int direction) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    position.jumpTo(
      (position.pixels + direction * position.viewportDimension).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  /// Where a menu opened from the keyboard goes: by the cursor.
  Rect _cursorAnchor() {
    final view = _view.currentState;
    if (view == null || !view.mounted) return Rect.zero;
    return view.globalCursorRect;
  }

  Future<void> _menu(Rect anchor) async {
    final l10n = context.l10n;
    final platform = Theme.of(context).platform;
    String? key(AppCommand command) =>
        widget.shortcutMap.labelOf(command, platform);
    final running = _cubit.state.status == TerminalStatus.running;
    final picked = await showAppMenu<AppCommand>(
      context: context,
      anchor: anchor,
      entries: [
        AppMenuAction(
          value: AppCommand.terminalCopy,
          label: l10n.commandLabel(AppCommand.terminalCopy),
          icon: AppIcons.copy,
          shortcut: key(AppCommand.terminalCopy),
          enabled: _cubit.selection.selection != null,
        ),
        AppMenuAction(
          value: AppCommand.terminalPaste,
          label: l10n.commandLabel(AppCommand.terminalPaste),
          icon: AppIcons.paste,
          shortcut: key(AppCommand.terminalPaste),
          enabled: running,
        ),
        AppMenuAction(
          value: AppCommand.terminalSelectAll,
          label: l10n.commandLabel(AppCommand.terminalSelectAll),
          shortcut: key(AppCommand.terminalSelectAll),
        ),
        AppMenuAction(
          value: AppCommand.terminalClear,
          label: l10n.commandLabel(AppCommand.terminalClear),
          icon: AppIcons.clear,
          shortcut: key(AppCommand.terminalClear),
        ),
        const AppMenuSeparator(),
        AppMenuAction(
          value: AppCommand.hideTerminal,
          label: l10n.commandLabel(AppCommand.hideTerminal),
          icon: AppIcons.terminalHide,
          shortcut: key(AppCommand.hideTerminal),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == AppCommand.hideTerminal) {
      widget.onHide();
    } else {
      _handlers()[picked]?.call();
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<TerminalSessionCubit, TerminalSessionState>(
        bloc: _cubit,
        builder: (context, state) => AppFocusArea(
          child: CommandHandlers(
            handlers: _handlers(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TerminalBar(
                  title: state.title.isNotEmpty
                      ? state.title
                      : state.folder ?? context.l10n.terminalTitle,
                  placement: widget.placement,
                  shortcutMap: widget.shortcutMap,
                  onFocus: widget.focusNode.requestFocus,
                  onHide: widget.onHide,
                  onTogglePanels: widget.onTogglePanels,
                  onToggleFullWindow: widget.onToggleFullWindow,
                ),
                Expanded(
                  child: _Screen(
                    terminal: _cubit.terminal,
                    selection: _cubit.selection,
                    look: _look,
                    fontSize: widget.fontSize,
                    focusNode: widget.focusNode,
                    scroll: _scroll,
                    viewKey: _view,
                    onKey: _onKey,
                    onSecondaryTap: (position) =>
                        unawaited(_menu(position & Size.zero)),
                  ),
                ),
                if (state.ended)
                  TerminalEndNotice(
                    exitCode: state.exitCode,
                    failed: state.status == TerminalStatus.failed,
                    error: state.error == null
                        ? null
                        : context.l10n.errorMessage(state.error!),
                    onRestart: () {
                      widget.focusNode.requestFocus();
                      unawaited(_cubit.restart());
                    },
                  ),
              ],
            ),
          ),
        ),
      );
}

/// The emulator, in the theme's colours: the selection emphasized while
/// the keys are here.
class _Screen extends StatelessWidget {
  const _Screen({
    required this.terminal,
    required this.selection,
    required this.look,
    required this.fontSize,
    required this.focusNode,
    required this.scroll,
    required this.viewKey,
    required this.onKey,
    required this.onSecondaryTap,
  });

  final Terminal terminal;
  final TerminalController selection;
  final TerminalLook look;
  final double fontSize;
  final FocusNode focusNode;
  final ScrollController scroll;
  final GlobalKey<TerminalViewState> viewKey;
  final FocusOnKeyEventCallback onKey;
  final ValueChanged<Offset> onSecondaryTap;

  @override
  Widget build(BuildContext context) => TerminalView(
    terminal,
    key: viewKey,
    controller: selection,
    focusNode: focusNode,
    scrollController: scroll,
    theme: look.themeOf(context, active: AppFocusArea.activeOf(context)),
    textStyle: look.styleOf(context, fontSize),
    // The terminal's font size is a setting of its own.
    textScaler: TextScaler.noScaling,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    keyboardAppearance: Theme.of(context).brightness,
    // Its own keys go through [onKey], so the window's map rules them.
    shortcuts: const {},
    onKeyEvent: onKey,
    onSecondaryTapDown: (details, _) => onSecondaryTap(details.globalPosition),
  );
}

/// The terminal's bar: its folder (or the title a program set), and the
/// buttons for its place in the window. In the window's top row when the
/// panels are hidden, else a slim strip under them.
class TerminalBar extends StatelessWidget {
  const TerminalBar({
    required this.title,
    required this.placement,
    required this.shortcutMap,
    required this.onFocus,
    required this.onHide,
    required this.onTogglePanels,
    required this.onToggleFullWindow,
    super.key,
  });

  final String title;
  final TerminalPlacement placement;
  final ShortcutMap shortcutMap;
  final VoidCallback onFocus;
  final VoidCallback onHide;
  final VoidCallback onTogglePanels;
  final VoidCallback onToggleFullWindow;

  static double heightOf(BuildContext context, {required bool topRow}) => topRow
      ? context.metrics.topBarHeight
      : context.metrics.iconButtonSize.height + AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topRow = placement.topRow;
    final decor = placement.decor;
    final bar = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => onFocus(),
      child: Container(
        height: heightOf(context, topRow: topRow),
        decoration: BoxDecoration(
          color: colors.windowChrome,
          border: AppBorder(
            top: topRow ? BorderSide.none : BorderSide(color: colors.line),
            bottom: BorderSide(color: colors.line),
          ),
        ),
        child: AppTopBarRow(
          leftInset: (topRow ? decor.leadingInset : 0) + AppSpacing.md,
          rightInset: (topRow ? decor.trailingInset : 0) + AppSpacing.sm,
          title: Row(
            children: [
              Icon(
                AppIcons.terminal,
                size: AppIconSize.md,
                color: colors.textMuted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: AppMiddleEllipsis(
                  title,
                  style:
                      (topRow
                              ? context.text.titleSmall
                              : context.text.bodySmall)!
                          .copyWith(color: colors.textMuted),
                ),
              ),
            ],
          ),
          trailing: [
            _BarButton(
              command: AppCommand.togglePanelsOverTerminal,
              icon: placement.panelsHidden || placement.fullWindow
                  ? AppIcons.panelsShow
                  : AppIcons.panelsHide,
              shortcutMap: shortcutMap,
              onPressed: onTogglePanels,
            ),
            _BarButton(
              command: AppCommand.toggleTerminal,
              icon: placement.fullWindow
                  ? AppIcons.showAsWindow
                  : AppIcons.fillWindow,
              shortcutMap: shortcutMap,
              onPressed: onToggleFullWindow,
            ),
            _BarButton(
              command: AppCommand.hideTerminal,
              icon: AppIcons.terminalHide,
              shortcutMap: shortcutMap,
              onPressed: onHide,
            ),
          ],
        ),
      ),
    );
    return topRow ? decor.dragArea(bar) : bar;
  }
}

/// A button of the bar: a command, named with its key in the tooltip.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.command,
    required this.icon,
    required this.shortcutMap,
    required this.onPressed,
  });

  final AppCommand command;
  final IconData icon;
  final ShortcutMap shortcutMap;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AppIconButton(
    icon: icon,
    tooltip: context.l10n.commandLabel(command),
    shortcut: shortcutMap.labelOf(command, Theme.of(context).platform),
    onPressed: onPressed,
  );
}

/// The line under an ended shell: why it ended, and a new one (Return, or
/// the button).
class TerminalEndNotice extends StatelessWidget {
  const TerminalEndNotice({
    required this.exitCode,
    required this.failed,
    required this.error,
    required this.onRestart,
    super.key,
  });

  final int? exitCode;
  final bool failed;

  /// The words of the error when the shell could not start.
  final String? error;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final code = exitCode;
    final message = failed
        ? l10n.terminalStartFailed
        : (code == null || code == 0)
        ? l10n.terminalExited
        : l10n.terminalExitedWithCode(code);
    final detail = failed
        ? error
        : l10n.terminalRestartHint(
            Chord.keyLabel(
              LogicalKeyboardKey.enter,
              Theme.of(context).platform,
            ),
          );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: AppBorder(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          Icon(
            failed ? AppIcons.cancel : AppIcons.terminal,
            size: AppIconSize.md,
            color: failed ? colors.danger : colors.textMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: context.text.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: context.text.bodySmall?.copyWith(
                      color: colors.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          OutlinedButton(
            onPressed: onRestart,
            child: Text(l10n.terminalRestart),
          ),
        ],
      ),
    );
  }
}
