import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

import '../panel/panel_state.dart';

/// One hint of the strip: a command (its chord and label come from the
/// shortcut map and the strings), or a key that is not a command (Return
/// in a prompt, Esc out of a mode) with a word of its own.
sealed class PanelHint {
  const PanelHint();
}

final class CommandHint extends PanelHint {
  const CommandHint(this.command);

  final AppCommand command;
}

final class KeyHint extends PanelHint {
  const KeyHint(this.key, this.word);

  final LogicalKeyboardKey key;
  final HintWord word;
}

enum HintWord { done, cancel, back, keepMatches }

/// The keys worth knowing right now, for what is under the cursor or
/// selected: five at most, the plainest first. Pure, so it is tested.
List<PanelHint> hintsFor({
  required PanelTabState? tab,
  required bool vim,
  required bool hasRegister,
}) {
  if (tab == null) return const [CommandHint(AppCommand.switchPanel)];
  if (tab.renaming != null) {
    return const [
      KeyHint(LogicalKeyboardKey.enter, HintWord.done),
      KeyHint(LogicalKeyboardKey.escape, HintWord.cancel),
    ];
  }
  if (vim && tab.searching) {
    return const [
      KeyHint(LogicalKeyboardKey.enter, HintWord.keepMatches),
      KeyHint(LogicalKeyboardKey.escape, HintWord.back),
    ];
  }
  if (tab.quickSearch.isNotEmpty) {
    return [
      if (vim && tab.matches.isNotEmpty) ...const [
        CommandHint(AppCommand.vimSearchNext),
        CommandHint(AppCommand.vimSearchPrevious),
      ],
      const CommandHint(AppCommand.clearQuickSearch),
    ];
  }
  if (vim && tab.visual) {
    return const [
      CommandHint(AppCommand.vimYank),
      CommandHint(AppCommand.vimCut),
      CommandHint(AppCommand.moveToTrash),
      KeyHint(LogicalKeyboardKey.escape, HintWord.back),
    ];
  }
  if (tab.selected.isNotEmpty) {
    return const [
      CommandHint(AppCommand.copyTo),
      CommandHint(AppCommand.moveTo),
      CommandHint(AppCommand.moveToTrash),
      CommandHint(AppCommand.compress),
      CommandHint(AppCommand.deselectAll),
    ];
  }
  final focused = tab.focused;
  if (focused == null) {
    return const [
      CommandHint(AppCommand.pasteItems),
      CommandHint(AppCommand.newFolder),
      CommandHint(AppCommand.goParent),
      CommandHint(AppCommand.switchPanel),
    ];
  }
  final paste = hasRegister
      ? const [CommandHint(AppCommand.vimPaste)]
      : const <PanelHint>[];
  if (focused.isParent) {
    return [
      ...paste,
      const CommandHint(AppCommand.enterItem),
      const CommandHint(AppCommand.newFolder),
      const CommandHint(AppCommand.switchPanel),
    ];
  }
  if (focused.isDir) {
    return [
      ...paste,
      const CommandHint(AppCommand.enterItem),
      const CommandHint(AppCommand.toggleSelectionMoveDown),
      const CommandHint(AppCommand.copyTo),
      const CommandHint(AppCommand.switchPanel),
    ];
  }
  return [
    ...paste,
    const CommandHint(AppCommand.enterItem),
    const CommandHint(AppCommand.showPreview),
    const CommandHint(AppCommand.toggleSelectionMoveDown),
    const CommandHint(AppCommand.copyTo),
    const CommandHint(AppCommand.switchPanel),
  ];
}

/// The keys worth knowing while the terminal has them: where it goes from
/// here, and its own clear.
List<PanelHint> terminalHintsFor(TerminalPlace mode) =>
    mode == TerminalPlace.overlapped
    ? const [
        CommandHint(AppCommand.hideTerminal),
        CommandHint(AppCommand.togglePanelsOverTerminal),
        CommandHint(AppCommand.toggleTerminal),
        CommandHint(AppCommand.terminalClear),
      ]
    : const [
        CommandHint(AppCommand.togglePanelsOverTerminal),
        CommandHint(AppCommand.toggleTerminal),
        CommandHint(AppCommand.hideTerminal),
        CommandHint(AppCommand.terminalClear),
      ];

/// A quiet line under the panels: the keys for what is under the cursor
/// or selected, as caps and words in the secondary colour, the cheat
/// sheet's key at the end, and a way to hide the line. Hints that do not
/// fit the width are cut, never wrapped: the line stays one line.
class KeyHintStrip extends StatelessWidget {
  const KeyHintStrip({
    required this.hints,
    required this.shortcutMap,
    required this.vim,
    required this.onHide,
    super.key,
  });

  final List<PanelHint> hints;
  final ShortcutMap shortcutMap;
  final bool vim;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final metrics = context.metrics;
    final platform = Theme.of(context).platform;
    final entries = <AppKeyHint>[];
    for (final hint in hints) {
      switch (hint) {
        case CommandHint(:final command):
          // A command the user unbound has no key to show.
          final keys = shortcutMap.labelOf(command, platform, vim: vim);
          if (keys != null) {
            entries.add(AppKeyHint([keys], l10n.commandLabel(command)));
          }
        case KeyHint(:final key, :final word):
          entries.add(
            AppKeyHint(
              [Chord.keyLabel(key, platform)],
              switch (word) {
                HintWord.done => l10n.actionDone,
                HintWord.cancel => l10n.actionCancel,
                HintWord.back => l10n.hintBack,
                HintWord.keepMatches => l10n.hintKeepMatches,
              },
            ),
          );
      }
    }
    final sheet = shortcutMap.labelOf(
      AppCommand.cheatSheet,
      platform,
      vim: vim,
    );
    return Container(
      height: metrics.iconButtonSize.height + AppSpacing.xs,
      padding: EdgeInsets.only(
        left: metrics.rowInset + AppSpacing.sm,
        right: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.windowChrome,
        border: AppBorder(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            // One line: what does not fit is clipped at the end.
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: AppKeyHints(entries),
              ),
            ),
          ),
          if (sheet != null) ...[
            const SizedBox(width: AppSpacing.lg),
            AppKeyHints([
              AppKeyHint([sheet], l10n.commandLabel(AppCommand.cheatSheet)),
            ]),
          ],
          const SizedBox(width: AppSpacing.sm),
          AppIconButton(
            icon: AppIcons.close,
            tooltip: l10n.hintsHide,
            onPressed: onHide,
          ),
        ],
      ),
    );
  }
}
