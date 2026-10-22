import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

import 'palette_cubit.dart';

/// Opens the command palette for the commands that can run where
/// [context] is: the focused widget's (a panel, the viewer, a dialog), so
/// the window's commands and that place's own, nothing no handler takes.
/// The command picked runs once the palette has closed and the focus is
/// back at [context], as a [CommandIntent] through the handlers' chain
/// there: what its key would do. [recents] remembers it for the next time.
Future<void> showCommandPalette(
  BuildContext context, {
  required ShortcutMap shortcutMap,
  required bool vim,
  RecentItems? recents,
}) async {
  final l10n = context.l10n;
  final platform = Theme.of(context).platform;
  final english = l10n.localeName.startsWith('en')
      ? null
      : lookupFerryxLocalizations(const Locale('en'));
  final commands = [
    for (final command in commandsAt(context))
      if (_offered(command, shortcutMap, vim: vim))
        PaletteCommand(
          command: command,
          label: l10n.commandLabel(command),
          englishLabel: switch (english?.commandLabel(command)) {
            final label? when label != l10n.commandLabel(command) => label,
            _ => null,
          },
          keys: [
            for (final chord in shortcutMap.chordsFor(command).take(2))
              vim ? chord.vimLabel(platform) : chord.label(platform),
          ],
        ),
  ];
  final names = AppCommand.values.asNameMap();
  final recent = [
    for (final name in recents?.items ?? const <String>[]) ?names[name],
  ];
  final picked = await showAppQuickPicker<AppCommand>(
    context,
    builder: (context) => BlocProvider(
      create: (_) => PaletteCubit(commands: commands, recent: recent),
      child: const PaletteView(),
    ),
  );
  if (picked == null) return;
  unawaited(recents?.record(picked.name));
  // The focus goes back in a microtask of the focus manager's; the frame
  // after has it where it was, so the command finds it there (a dialog
  // it opens gives the focus back to that place too).
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;
  Actions.maybeInvoke<CommandIntent>(context, CommandIntent(picked));
}

/// The palette itself does not list itself, nor Vim's keys while they are
/// off (the panel answers some of them all the same), nor what this
/// desktop lacks (Quick Look, Share), though a handler takes it.
bool _offered(
  AppCommand command,
  ShortcutMap shortcutMap, {
  required bool vim,
}) =>
    command != AppCommand.commandPalette &&
    (vim || !command.isVimOnly) &&
    shortcutMap.isAvailable(command);

/// The palette's list over [PaletteCubit]: a row per command with its
/// section (or its English name, when that is what matched) and its keys;
/// a pick closes the palette with the command.
class PaletteView extends StatelessWidget {
  const PaletteView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final platform = Theme.of(context).platform;
    String key(LogicalKeyboardKey key) => Chord.keyLabel(key, platform);
    void close() => Navigator.of(context).maybePop();
    return CommandHandlers(
      // Its own key again closes it, as a toggle.
      handlers: {AppCommand.commandPalette: close},
      child: BlocBuilder<PaletteCubit, PaletteState>(
        builder: (context, state) => AppQuickPicker<AppCommand>(
          entries: _entries(l10n, state.rows),
          hintText: l10n.paletteHint,
          noResultsText: l10n.paletteNoResults,
          hints: [
            (
              '${key(LogicalKeyboardKey.arrowUp)}'
                  '${key(LogicalKeyboardKey.arrowDown)}',
              l10n.paletteKeySelect,
            ),
            (key(LogicalKeyboardKey.enter), l10n.paletteKeyRun),
            (key(LogicalKeyboardKey.escape), l10n.paletteKeyClose),
          ],
          onQueryChanged: context.read<PaletteCubit>().setQuery,
          onPick: (pick) => Navigator.of(context).pop(pick.value),
        ),
      ),
    );
  }
}

/// The picker's rows for [rows]: a command's section beside it unless its
/// group's caption already names it, its English name instead when that is
/// what matched.
List<AppQuickPickerEntry<AppCommand>> _entries(
  FerryxLocalizations l10n,
  List<PaletteRow> rows,
) {
  final out = <AppQuickPickerEntry<AppCommand>>[];
  var underSection = false;
  for (final row in rows) {
    switch (row) {
      case PaletteGroupRow(:final section):
        underSection = section != null;
        out.add(
          AppQuickPickerHeader(
            section == null ? l10n.paletteRecent : l10n.sectionLabel(section),
          ),
        );
      case PaletteCommandRow(
        :final entry,
        :final labelRanges,
        :final englishRanges,
      ):
        out.add(
          AppQuickPickerItem(
            value: entry.command,
            label: entry.label,
            labelHighlights: labelRanges,
            detail: englishRanges != null
                ? entry.englishLabel
                : underSection
                ? null
                : l10n.sectionLabel(entry.section),
            detailHighlights: englishRanges ?? const [],
            keys: entry.keys,
          ),
        );
    }
  }
  return out;
}
