import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
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
  const CommandHint(this.command, {this.labelCommand});

  final AppCommand command;

  /// A contextual label; the key still comes from [command].
  final AppCommand? labelCommand;
}

final class KeyHint extends PanelHint {
  const KeyHint(this.key, this.word);

  final LogicalKeyboardKey key;
  final HintWord word;
}

enum HintWord {
  done,
  cancel,
  back,
  keepMatches,
  // ─── Interface ───
  reveal,
  remove,
}

/// The keys of the shelf's strip while it has them.
const shelfHints = [
  KeyHint(LogicalKeyboardKey.enter, HintWord.reveal),
  KeyHint(LogicalKeyboardKey.backspace, HintWord.remove),
  KeyHint(LogicalKeyboardKey.escape, HintWord.back),
];

/// Shared navigation for every neighboring preview, including an empty one.
const previewHints = [
  CommandHint(AppCommand.switchPanel),
  CommandHint(AppCommand.dismiss),
  CommandHint(
    AppCommand.internalViewer,
    labelCommand: AppCommand.viewerToggleFullWindow,
  ),
];

/// The keys worth knowing right now, for what is under the cursor or
/// selected. Tab navigation leads ordinary browsing when available;
/// editing, searching and selection keep their own hints.
List<PanelHint> hintsFor({
  required PanelTabState? tab,
  required bool vim,
  required bool hasRegister,
  bool hasMultipleTabs = false,
}) {
  final hints = _hintsFor(
    tab: tab,
    vim: vim,
    hasRegister: hasRegister,
    hasMultipleTabs: hasMultipleTabs,
  );
  // A flat view names its way back first.
  if (tab != null &&
      tab.isFlat &&
      tab.renaming == null &&
      !(vim && tab.searching)) {
    return [const CommandHint(AppCommand.toggleFlatView), ...hints.take(4)];
  }
  return hints;
}

List<PanelHint> _hintsFor({
  required PanelTabState? tab,
  required bool vim,
  required bool hasRegister,
  required bool hasMultipleTabs,
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
  final browsing = _browsingHints(tab, hasRegister: hasRegister);
  return hasMultipleTabs
      ? [
          const CommandHint(AppCommand.previousTab),
          const CommandHint(AppCommand.nextTab),
          ...browsing.take(3),
        ]
      : browsing;
}

List<PanelHint> _browsingHints(
  PanelTabState tab, {
  required bool hasRegister,
}) {
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
    const CommandHint(AppCommand.enterItem, labelCommand: AppCommand.openItem),
    // A checksum file is checked with the Checksums command.
    if (ChecksumAlgorithm.ofSumsFile(focused.name) != null)
      const CommandHint(AppCommand.checksums),
    const CommandHint(AppCommand.showPreview),
    const CommandHint(AppCommand.toggleSelectionMoveDown),
    const CommandHint(AppCommand.copyTo),
    const CommandHint(AppCommand.switchPanel),
  ];
}

/// The keys worth knowing while the terminal has them: where it goes from
/// here, and its own clear.
List<PanelHint> terminalHintsFor(TerminalPlace mode) =>
    (mode == TerminalPlace.overlapped || mode == TerminalPlace.panelTab)
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
/// sheet at the end, and a way to hide the line. Only complete hints that
/// fit are shown; the line never wraps.
class KeyHintStrip extends StatelessWidget {
  const KeyHintStrip({
    required this.hints,
    required this.shortcutMap,
    required this.vim,
    required this.onHide,
    required this.onHelp,
    super.key,
  });

  final List<PanelHint> hints;
  final ShortcutMap shortcutMap;
  final bool vim;
  final VoidCallback onHide;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final metrics = context.metrics;
    final platform = Theme.of(context).platform;
    final entries = <AppKeyHint>[];
    for (final hint in hints) {
      switch (hint) {
        case CommandHint(:final command, :final labelCommand):
          // A command the user unbound has no key to show.
          final keys = shortcutMap.labelOf(command, platform, vim: vim);
          if (keys != null) {
            entries.add(
              AppKeyHint(
                [keys],
                l10n.commandLabel(labelCommand ?? command),
                // Vim's keys are typed: `l` must not read as a bar.
                typed:
                    vim &&
                    (shortcutMap.letterChord(command)?.isVimKey ?? false),
              ),
            );
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
                HintWord.reveal => l10n.shelfHintReveal,
                HintWord.remove => l10n.shelfHintRemove,
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
    return AppStatusBar(
      padding: EdgeInsets.only(
        left: metrics.tableRowInset + AppSpacing.sm,
        right: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: AppKeyHints(entries, singleLine: true),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppTooltip(
            message: l10n.cmdCheatSheet,
            shortcut: sheet,
            child: TextButton(
              onPressed: onHelp,
              style: AppButtonStyles.bar(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpacing.xs,
                children: [
                  const Icon(AppIcons.keyboard, size: AppIconSize.sm),
                  Text(l10n.hintsHelp),
                  if (sheet != null) AppKeyCap(sheet),
                ],
              ),
            ),
          ),
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
