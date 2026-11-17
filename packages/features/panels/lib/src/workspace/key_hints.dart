import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
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
  run,
  complete,
  previousCommand,
  nextCommand,
  // ─── Interface ───
  reveal,
  remove,
}

const commandLineHints = [
  KeyHint(LogicalKeyboardKey.enter, HintWord.run),
  KeyHint(LogicalKeyboardKey.tab, HintWord.complete),
  KeyHint(LogicalKeyboardKey.arrowUp, HintWord.previousCommand),
  KeyHint(LogicalKeyboardKey.arrowDown, HintWord.nextCommand),
  KeyHint(LogicalKeyboardKey.escape, HintWord.cancel),
];

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
  bool deletionPending = false,
  int screenItems = 20,
}) {
  final proposed = _hintsFor(
    tab: tab,
    vim: vim,
    hasRegister: hasRegister,
    hasMultipleTabs: hasMultipleTabs,
    screenItems: screenItems,
  );
  final location = tab?.location;
  final hints = [
    for (final hint in proposed.where(
      (hint) =>
          !deletionPending ||
          hint is! CommandHint ||
          hint.command != AppCommand.moveToTrash,
    ))
      if (location == null || hint is! CommandHint)
        hint
      else if (location.isNative)
        hint
      else if (hint.command == AppCommand.copyTo)
        CommandHint(
          hint.command,
          labelCommand: location.isRemote ? null : AppCommand.extractTo,
        )
      else if (location.isRemote && hint.command == AppCommand.moveToTrash)
        const CommandHint(AppCommand.deletePermanently)
      else if (!const {
            AppCommand.vimYank,
            AppCommand.vimCut,
            AppCommand.vimPaste,
            AppCommand.compress,
            AppCommand.checksums,
          }.contains(hint.command) &&
          (location.isRemote ||
              !const {
                AppCommand.moveTo,
                AppCommand.moveToTrash,
                AppCommand.pasteItems,
                AppCommand.newFolder,
              }.contains(hint.command)))
        hint,
  ];
  // A flat view names its way back first.
  if (tab != null &&
      tab.isFlat &&
      tab.renaming == null &&
      !(vim && tab.searching)) {
    return [const CommandHint(AppCommand.toggleFlatView), ...hints];
  }
  return hints;
}

List<PanelHint> _hintsFor({
  required PanelTabState? tab,
  required bool vim,
  required bool hasRegister,
  required bool hasMultipleTabs,
  required int screenItems,
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
  if (tab.error != null) {
    return const [
      CommandHint(
        AppCommand.clearQuickSearch,
        labelCommand: AppCommand.dismiss,
      ),
      CommandHint(AppCommand.commandPalette),
    ];
  }
  if (tab.quickSearch.isNotEmpty) {
    return [
      if (vim && tab.matches.isNotEmpty) ...const [
        CommandHint(AppCommand.vimSearchNext),
        CommandHint(AppCommand.vimSearchPrevious),
      ],
      const CommandHint(AppCommand.clearQuickSearch),
      if (tab.matches.isNotEmpty) ...[
        CommandHint(
          AppCommand.enterItem,
          labelCommand: tab.focused?.isDir == false
              ? AppCommand.openItem
              : null,
        ),
        if (tab.focused?.isDir == false)
          const CommandHint(AppCommand.showPreview),
        const CommandHint(AppCommand.toggleSelectionMoveDown),
      ],
      if (tab.selected.isNotEmpty) ...const [
        CommandHint(AppCommand.copyItemName),
        CommandHint(AppCommand.copyItemPath),
      ],
    ];
  }
  if (vim && tab.visual) {
    return const [
      CommandHint(AppCommand.copyItemName),
      CommandHint(AppCommand.copyItemPath),
      CommandHint(AppCommand.vimYank),
      CommandHint(AppCommand.vimCut),
      CommandHint(AppCommand.moveToTrash),
      KeyHint(LogicalKeyboardKey.escape, HintWord.back),
    ];
  }
  if (tab.selected.isNotEmpty) {
    return const [
      CommandHint(AppCommand.copyItemName),
      CommandHint(AppCommand.copyItemPath),
      CommandHint(AppCommand.copyTo),
      CommandHint(AppCommand.moveTo),
      CommandHint(AppCommand.moveToTrash),
      CommandHint(AppCommand.compress),
      CommandHint(
        AppCommand.clearQuickSearch,
        labelCommand: AppCommand.deselectAll,
      ),
    ];
  }
  final browsing = _browsingHints(tab, hasRegister: hasRegister, vim: vim);
  final navigation = [
    if (hasMultipleTabs) ...const [
      CommandHint(AppCommand.previousTab),
      CommandHint(AppCommand.nextTab),
    ],
    if (vim && screenItems > 0 && tab.itemCount > screenItems) ...const [
      CommandHint(AppCommand.vimBlockPrevious),
      CommandHint(AppCommand.vimBlockNext),
    ],
  ];
  return navigation.isEmpty ? browsing : [...navigation, ...browsing];
}

List<PanelHint> _browsingHints(
  PanelTabState tab, {
  required bool hasRegister,
  required bool vim,
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
      ? [CommandHint(vim ? AppCommand.vimPaste : AppCommand.toggleShelf)]
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
    this.editingHints,
    this.onActions,
    super.key,
  });

  final List<PanelHint> hints;
  final ShortcutMap shortcutMap;
  final bool vim;
  final VoidCallback onHide;
  final VoidCallback onHelp;
  final List<AppKeyHint>? editingHints;

  /// Opens executable actions, including commands without a key binding.
  /// Omitted in editors that commit or cancel on focus loss.
  final VoidCallback? onActions;

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
                HintWord.run => l10n.paletteKeyRun,
                HintWord.complete => l10n.hintComplete,
                HintWord.previousCommand => l10n.hintPreviousCommand,
                HintWord.nextCommand => l10n.hintNextCommand,
                HintWord.reveal => l10n.shelfHintReveal,
                HintWord.remove => l10n.shelfHintRemove,
              },
            ),
          );
      }
    }
    if (editingHints case final editing?) {
      entries
        ..clear()
        ..addAll(editing);
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
      child: Visibility(
        visible: ModalRoute.of(context)?.isCurrent != false,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: Row(
          children: [
            Expanded(
              child: AppKeyHints(entries, singleLine: true),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (onActions != null) ...[
              TextButton(
                onPressed: onActions,
                style: AppButtonStyles.bar(context),
                child: Text(l10n.contextActions),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
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
      ),
    );
  }
}
