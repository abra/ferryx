import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortcuts/shortcuts.dart';

import 'panel_actions.dart';

/// Executable actions for one panel snapshot, independent of its short hints
/// and of whether a command has a keyboard binding.
class PanelActionsPicker extends StatefulWidget {
  const PanelActionsPicker({
    required this.actions,
    required this.selectionCount,
    required this.focusedName,
    required this.shortcutMap,
    required this.vim,
    super.key,
  });

  final List<PanelAction> actions;
  final int selectionCount;
  final String? focusedName;
  final ShortcutMap shortcutMap;
  final bool vim;

  @override
  State<PanelActionsPicker> createState() => _PanelActionsPickerState();
}

class _PanelActionsPickerState extends State<PanelActionsPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final english = lookupFerryxLocalizations(const Locale('en'));
    final platform = Theme.of(context).platform;
    final words = _query.toLowerCase().trim().split(RegExp(r'\s+'));
    final entries = <AppQuickPickerEntry<AppCommand>>[];
    final groups = <PanelActionTarget, List<PanelAction>>{};
    for (final action in widget.actions) {
      final command = action.labelCommand ?? action.command;
      final haystack =
          '${l10n.commandLabel(command)} '
                  '${english.commandLabel(command)}'
              .toLowerCase();
      if (!words.every(haystack.contains)) continue;
      final target =
          widget.selectionCount == 0 &&
              action.target == PanelActionTarget.targets
          ? PanelActionTarget.focusedItem
          : action.target;
      (groups[target] ??= []).add(action);
    }
    // A marked selection is the primary subject, even when the cursor has
    // advanced onto an unmarked row. Opening/renaming that row stays explicit.
    for (final target in PanelActionTarget.values) {
      final actions = groups[target];
      if (actions == null) continue;
      entries.add(
        AppQuickPickerHeader(switch (target) {
          PanelActionTarget.targets => l10n.contextActionsSelection(
            widget.selectionCount,
          ),
          PanelActionTarget.focusedItem => l10n.contextActionsFocused(
            widget.focusedName ?? '',
          ),
          PanelActionTarget.directory => l10n.contextActionsFolder,
        }),
      );
      for (final action in actions) {
        final keys = widget.shortcutMap.labelOf(
          action.command,
          platform,
          vim: widget.vim,
        );
        entries.add(
          AppQuickPickerItem(
            value: action.command,
            label: l10n.commandLabel(action.labelCommand ?? action.command),
            keys: [?keys],
          ),
        );
      }
    }
    String key(LogicalKeyboardKey key) => Chord.keyLabel(key, platform);
    return AppQuickPicker<AppCommand>(
      title: l10n.contextActions,
      hintText: l10n.contextActionsHint,
      noResultsText: l10n.paletteNoResults,
      entries: entries,
      hints: [
        if (entries.isNotEmpty) ...[
          (
            '${key(LogicalKeyboardKey.arrowUp)}'
                '${key(LogicalKeyboardKey.arrowDown)}',
            l10n.paletteKeySelect,
          ),
          (key(LogicalKeyboardKey.enter), l10n.paletteKeyRun),
        ],
        (key(LogicalKeyboardKey.escape), l10n.paletteKeyClose),
      ],
      onQueryChanged: (query) => setState(() => _query = query),
      onPick: (pick) => Navigator.of(context).pop(pick.value),
    );
  }
}
