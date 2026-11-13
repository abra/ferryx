import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:preferences_service/preferences_service.dart';

import '../settings_rows.dart';
import 'program_dialog.dart';

/// The editors F4 picks from, by file mask.
class EditorsPage extends StatelessWidget {
  const EditorsPage({required this.prefs, required this.service, super.key});

  final Preferences prefs;
  final PreferencesService service;

  ProgramLabels _labels(FerryxLocalizations l10n) => ProgramLabels(
    title: l10n.editorEditTitle,
    addTitle: l10n.editorAddTitle,
    name: l10n.editorName,
    path: l10n.editorPath,
    extra: l10n.editorMask,
    extraHint: l10n.maskHint,
    inTerminal: l10n.editorInTerminal,
  );

  Future<void> _edit(BuildContext context, int? index) async {
    final l10n = context.l10n;
    final current = index == null ? null : prefs.editors[index];
    final draft = await showProgramDialog(
      context,
      labels: _labels(l10n),
      initial: current == null
          ? null
          : ProgramDraft(
              name: current.name,
              path: current.path,
              extra: current.mask,
              inTerminal: current.inTerminal,
            ),
    );
    if (draft == null) return;
    final editor = ExternalEditor(
      name: draft.name,
      path: draft.path,
      mask: draft.extra.isEmpty ? '*' : draft.extra,
      inTerminal: draft.inTerminal,
    );
    await service.update((p) {
      final editors = [...p.editors];
      if (index == null) {
        editors.add(editor);
      } else {
        editors[index] = editor;
      }
      return p.copyWith(editors: editors);
    });
  }

  Future<void> _remove(int index) => service.update(
    (p) => p.copyWith(editors: [...p.editors]..removeAt(index)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return SettingsPage(
      children: [
        Text(
          l10n.editorsIntro,
          style: context.text.bodyMedium?.copyWith(color: colors.textMuted),
        ),
        SettingsGroup(
          footer: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _edit(context, null),
                icon: const Icon(AppIcons.add, size: AppIconSize.sm),
                label: Text(l10n.editorsAdd),
              ),
            ],
          ),
          children: [
            if (prefs.editors.isEmpty)
              SettingsPlaceholderRow(l10n.editorsEmpty),
            for (var i = 0; i < prefs.editors.length; i++)
              ListEntryRow(
                key: ValueKey('editor-$i'),
                title: prefs.editors[i].name,
                subtitle: '${prefs.editors[i].mask} · ${prefs.editors[i].path}',
                icon: prefs.editors[i].inTerminal
                    ? AppIcons.terminal
                    : AppIcons.application,
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
