import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:preferences_service/preferences_service.dart';

import '../settings_rows.dart';
import 'program_dialog.dart';

/// The programs the Tools menu runs on the panels' items.
class ToolsPage extends StatelessWidget {
  const ToolsPage({required this.prefs, required this.service, super.key});

  final Preferences prefs;
  final PreferencesService service;

  ProgramLabels _labels(FerryxLocalizations l10n) => ProgramLabels(
    title: l10n.toolEditTitle,
    addTitle: l10n.toolAddTitle,
    name: l10n.toolTitle,
    path: l10n.toolPath,
    extra: l10n.toolParameters,
    extraHint: '%p',
    inTerminal: l10n.toolInTerminal,
  );

  Future<void> _edit(BuildContext context, int? index) async {
    final l10n = context.l10n;
    final current = index == null ? null : prefs.tools[index];
    final draft = await showProgramDialog(
      context,
      labels: _labels(l10n),
      initial: current == null
          ? null
          : ProgramDraft(
              name: current.title,
              path: current.path,
              extra: current.parameters,
              inTerminal: current.inTerminal,
            ),
    );
    if (draft == null) return;
    final tool = ExternalTool(
      title: draft.name,
      path: draft.path,
      parameters: draft.extra,
      inTerminal: draft.inTerminal,
      shortcut: current?.shortcut,
    );
    await service.update((p) {
      final tools = [...p.tools];
      if (index == null) {
        tools.add(tool);
      } else {
        tools[index] = tool;
      }
      return p.copyWith(tools: tools);
    });
  }

  Future<void> _remove(int index) =>
      service.update((p) => p.copyWith(tools: [...p.tools]..removeAt(index)));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return SettingsPage(
      children: [
        Text(
          l10n.toolsIntro,
          style: context.text.bodyMedium?.copyWith(color: colors.textMuted),
        ),
        SettingsGroup(
          footer: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _edit(context, null),
                icon: const Icon(AppIcons.add, size: AppIconSize.sm),
                label: Text(l10n.toolsAdd),
              ),
            ],
          ),
          children: [
            if (prefs.tools.isEmpty) SettingsPlaceholderRow(l10n.toolsEmpty),
            for (var i = 0; i < prefs.tools.length; i++)
              ListEntryRow(
                key: ValueKey('tool-$i'),
                title: prefs.tools[i].title,
                subtitle: '${prefs.tools[i].path} ${prefs.tools[i].parameters}',
                icon: prefs.tools[i].inTerminal
                    ? AppIcons.terminal
                    : AppIcons.wrench,
                editTooltip: l10n.hotkeysChange,
                removeTooltip: l10n.actionRemove,
                onEdit: () => _edit(context, i),
                onRemove: () => _remove(i),
              ),
          ],
        ),
      ],
    );
  }
}
