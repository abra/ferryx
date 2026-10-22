import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

import '../settings_rows.dart';
import 'record_chord_dialog.dart';

/// Every command with its keys, by scope; a key is changed by recording
/// the next one pressed. A row takes the focus: Return changes its key,
/// Delete or Backspace removes it, the menu key or a right click opens
/// its menu.
class HotkeysPage extends StatefulWidget {
  const HotkeysPage({
    required this.prefs,
    required this.service,
    required this.platform,
    required this.vim,
    required this.shortcutMap,
    super.key,
  });

  final Preferences prefs;
  final PreferencesService service;
  final TargetPlatform platform;

  /// Keys read as Vim writes them (`j`, `gg`), as the panels take them.
  final bool vim;
  final ShortcutMap shortcutMap;

  @override
  State<HotkeysPage> createState() => _HotkeysPageState();
}

class _HotkeysPageState extends State<HotkeysPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _change(AppCommand command) async {
    final recorded = await showRecordChordDialog(
      context,
      command: command,
      map: widget.shortcutMap,
      platform: widget.platform,
      vim: widget.vim,
    );
    if (recorded == null) return;
    final chord = recorded.chord;
    final other = recorded.takenFrom;
    if (other != null) {
      await _override(other, [
        for (final c in widget.shortcutMap.chordsFor(other))
          if (c != chord) ChordCodec.encode(c),
      ]);
    }
    await _override(command, [ChordCodec.encode(chord)]);
  }

  Future<void> _override(AppCommand command, List<String>? chords) =>
      widget.service.update((p) {
        final overrides = {...p.shortcutOverrides};
        if (chords == null) {
          overrides.remove(command.name);
        } else {
          overrides[command.name] = chords;
        }
        return p.copyWith(shortcutOverrides: Map.unmodifiable(overrides));
      });

  Future<void> _resetAll() async {
    final l10n = context.l10n;
    final sure = await AppDialog.confirm(
      context,
      title: l10n.hotkeysReset,
      confirmLabel: l10n.actionReset,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!sure) return;
    await widget.service.update(
      (p) => p.copyWith(shortcutOverrides: const {}),
    );
  }

  Future<void> _menu(AppCommand command, Rect anchor) async {
    final l10n = context.l10n;
    final overridden = widget.prefs.shortcutOverrides.containsKey(command.name);
    final picked = await showAppMenu<String>(
      context: context,
      anchor: anchor,
      entries: [
        AppMenuAction(
          value: 'change',
          label: l10n.hotkeysChange,
          icon: AppIcons.edit,
        ),
        AppMenuAction(
          value: 'clear',
          label: l10n.hotkeysClear,
          icon: AppIcons.close,
          enabled: widget.shortcutMap.chordsFor(command).isNotEmpty,
        ),
        const AppMenuSeparator(),
        AppMenuAction(
          value: 'reset',
          label: l10n.hotkeysResetOne,
          icon: AppIcons.undo,
          enabled: overridden,
        ),
      ],
    );
    if (!mounted) return;
    switch (picked) {
      case 'change':
        await _change(command);
      case 'clear':
        await _override(command, const []);
      case 'reset':
        await _override(command, null);
    }
  }

  /// The command each command shares a chord with inside its scope, if
  /// any: both would answer the key where it is pressed.
  Map<AppCommand, AppCommand> _conflicts() {
    final found = <AppCommand, AppCommand>{};
    for (final scope in CommandScope.values) {
      final byChord = <Chord, AppCommand>{};
      for (final command in AppCommand.inScope(scope)) {
        for (final chord in widget.shortcutMap.chordsFor(command)) {
          final other = byChord[chord];
          if (other == null) {
            byChord[chord] = command;
          } else {
            found.putIfAbsent(command, () => other);
            found.putIfAbsent(other, () => command);
          }
        }
      }
    }
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final margin = context.metrics.contentMargin;
    final needle = _query.trim().toLowerCase();
    final conflicts = _conflicts();
    final items = <_HotkeyItem>[];
    for (final scope in CommandScope.values) {
      final commands = [
        for (final command in AppCommand.inScope(scope))
          if (needle.isEmpty ||
              l10n.commandLabel(command).toLowerCase().contains(needle))
            command,
      ];
      if (commands.isEmpty) continue;
      items.add(_HotkeyItem.caption(l10n.scopeLabel(scope)));
      for (final command in commands) {
        items.add(_HotkeyItem.command(command));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(margin, margin, margin, AppSpacing.sm),
          child: Row(
            spacing: AppSpacing.sm,
            children: [
              Expanded(
                child: AppSearchField(
                  hintText: l10n.hotkeysSearchHint,
                  controller: _search,
                  onChanged: (q) => setState(() => _query = q),
                ),
              ),
              OutlinedButton(
                onPressed: widget.prefs.shortcutOverrides.isEmpty
                    ? null
                    : _resetAll,
                child: Text(l10n.hotkeysReset),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(margin, 0, margin, margin),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final command = item.command;
              if (command == null) {
                // The label pads itself above: the first caption sits
                // under the search row by the row's own gap, the others a
                // margin under the rows before them.
                return Padding(
                  padding: EdgeInsets.only(
                    top: index == 0 ? 0 : margin - sectionLabelTopInset,
                  ),
                  child: AppSectionLabel(item.caption!, inset: false),
                );
              }
              final conflict = conflicts[command];
              return _HotkeyRow(
                key: ValueKey(command),
                command: command,
                chords: widget.shortcutMap.chordsFor(command),
                overridden: widget.prefs.shortcutOverrides.containsKey(
                  command.name,
                ),
                conflict: conflict == null ? null : l10n.commandLabel(conflict),
                platform: widget.platform,
                vim: widget.vim,
                menuChords: widget.shortcutMap.chordsFor(
                  AppCommand.contextMenu,
                ),
                onChange: () => _change(command),
                onClear: () => _override(command, const []),
                onMenu: (anchor) => _menu(command, anchor),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HotkeyItem {
  const _HotkeyItem.caption(this.caption) : command = null;

  const _HotkeyItem.command(this.command) : caption = null;

  final String? caption;
  final AppCommand? command;
}

/// One command: its name, its keys, and the marks that it was changed or
/// shares a key. A focusable row with one tab stop: Return changes the
/// key, Delete or Backspace removes it, the menu key and a right click
/// open the menu; ⌘J labels it.
class _HotkeyRow extends StatefulWidget {
  const _HotkeyRow({
    required this.command,
    required this.chords,
    required this.overridden,
    required this.conflict,
    required this.platform,
    required this.vim,
    required this.menuChords,
    required this.onChange,
    required this.onClear,
    required this.onMenu,
    super.key,
  });

  final AppCommand command;
  final List<Chord> chords;
  final bool overridden;

  /// The command that answers the same key in this scope, if one does.
  final String? conflict;
  final TargetPlatform platform;

  /// Keys read as Vim writes them (`j`, `gg`), as the panels take them.
  final bool vim;

  /// The chords that open a row's menu (`AppCommand.contextMenu`).
  final List<Chord> menuChords;
  final VoidCallback onChange;
  final VoidCallback onClear;
  final void Function(Rect anchor) onMenu;

  @override
  State<_HotkeyRow> createState() => _HotkeyRowState();
}

class _HotkeyRowState extends State<_HotkeyRow> {
  final _focus = FocusNode(debugLabel: 'hotkey row');

  /// The menu button takes no focus of its own: the row is the one tab
  /// stop, and the keys open the menu from the row.
  final _menuFocus = FocusNode(
    debugLabel: 'hotkey menu',
    canRequestFocus: false,
    skipTraversal: true,
  );
  bool _hovered = false;

  @override
  void dispose() {
    _focus.dispose();
    _menuFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final plain =
        !keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed;
    if (plain &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      widget.onChange();
      return KeyEventResult.handled;
    }
    if (plain &&
        (key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace)) {
      if (widget.chords.isNotEmpty) widget.onClear();
      return KeyEventResult.handled;
    }
    final chord = chordOfEvent(event, widget.platform);
    if (chord != null && widget.menuChords.contains(chord)) {
      widget.onMenu(keyboardMenuAnchor(context));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final metrics = context.metrics;
    final conflict = widget.conflict;
    final labelStyle = context.text.bodyMedium;
    return CommandHandlers(
      handlers: {
        AppCommand.contextMenu: () =>
            widget.onMenu(keyboardMenuAnchor(context)),
      },
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        onFocusChange: (_) => setState(() {}),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _focus.requestFocus,
            onSecondaryTapUp: (details) => widget.onMenu(
              details.globalPosition & Size.zero,
            ),
            child: HintTarget(
              onActivate: widget.onChange,
              child: FocusRing(
                focused: _focus.hasFocus,
                radius: metrics.radius.row,
                child: Container(
                  constraints: BoxConstraints(minHeight: metrics.listRowHeight),
                  padding: EdgeInsets.symmetric(horizontal: metrics.rowInset),
                  decoration: BoxDecoration(
                    color: _hovered && metrics.navHover
                        ? colors.hoverFill
                        : null,
                    borderRadius: BorderRadius.circular(metrics.radius.row),
                  ),
                  child: Row(
                    spacing: AppSpacing.sm,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.commandLabel(widget.command),
                          style: widget.overridden
                              ? labelStyle?.weight(FontWeight.w600)
                              : labelStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.overridden) const _ChangedDot(),
                      if (conflict != null)
                        AppTooltip(
                          message: l10n.hotkeysConflict(conflict),
                          child: Icon(
                            AppIcons.warning,
                            size: AppIconSize.sm,
                            color: colors.danger,
                          ),
                        ),
                      if (widget.chords.isEmpty)
                        Text(
                          l10n.hotkeysUnbound,
                          style: context.text.bodySmall?.copyWith(
                            color: colors.textMuted,
                          ),
                        )
                      else
                        AppKeyCaps([
                          for (final chord in widget.chords)
                            widget.vim
                                ? chord.vimLabel(widget.platform)
                                : chord.label(widget.platform),
                        ]),
                      Builder(
                        builder: (context) => AppIconButton(
                          icon: AppIcons.more,
                          tooltip: l10n.panelMenuTooltip,
                          focusNode: _menuFocus,
                          onPressed: () =>
                              widget.onMenu(keyboardMenuAnchor(context)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small mark in the accent after a command whose key was changed.
class _ChangedDot extends StatelessWidget {
  const _ChangedDot();

  @override
  Widget build(BuildContext context) => AppTooltip(
    message: context.l10n.hotkeysChanged,
    child: Container(
      width: AppSpacing.sm,
      height: AppSpacing.sm,
      decoration: BoxDecoration(
        color: context.appColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
    ),
  );
}
