import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:preferences_service/preferences_service.dart';

import '../settings_rows.dart';

/// Appearance, language, text size, confirmations, copying defaults.
class GeneralPage extends StatelessWidget {
  const GeneralPage({required this.prefs, required this.service, super.key});

  final Preferences prefs;
  final PreferencesService service;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsPage(
      children: [
        SettingsGroup(
          children: [
            SegmentRow<AppThemeMode>(
              label: l10n.themeLabel,
              value: prefs.themeMode,
              options: [
                (AppThemeMode.system, l10n.themeSystem),
                (AppThemeMode.light, l10n.themeLight),
                (AppThemeMode.dark, l10n.themeDark),
              ],
              onChanged: (mode) =>
                  service.update((p) => p.copyWith(themeMode: mode)),
            ),
            ChoiceRow<String?>(
              label: l10n.languageLabel,
              value: prefs.localeCode,
              items: [
                (null, l10n.languageSystem),
                ('en', l10n.languageEnglish),
                ('ru', l10n.languageRussian),
              ],
              onChanged: (code) => service.update(
                (p) => code == null
                    ? p.copyWith(clearLocale: true)
                    : p.copyWith(localeCode: code),
              ),
            ),
            SliderRow(
              label: l10n.textSizeLabel,
              value: prefs.textScale,
              min: 0.8,
              max: 1.6,
              divisions: 8,
              display: l10n.textSizePercent((prefs.textScale * 100).round()),
              onChanged: (value) => service.update(
                (p) => p.copyWith(textScale: (value * 10).round() / 10),
              ),
            ),
            ToggleRow(
              label: l10n.generalKeyHintsLabel,
              note: l10n.generalKeyHintsNote,
              value: prefs.showKeyHints,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(showKeyHints: v)),
            ),
          ],
        ),
        SettingsGroup(
          title: l10n.confirmationsLabel,
          children: [
            ToggleRow(
              label: l10n.confirmTrashLabel,
              value: prefs.confirmTrash,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(confirmTrash: v)),
            ),
            ToggleRow(
              label: l10n.confirmDeleteLabel,
              value: prefs.confirmDelete,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(confirmDelete: v)),
            ),
          ],
        ),
        SettingsGroup(
          title: l10n.copyDefaultsLabel,
          children: [
            ToggleRow(
              label: l10n.optionPreserveAttributes,
              value: prefs.preserveAttributes,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(preserveAttributes: v)),
            ),
            ToggleRow(
              label: l10n.optionVerify,
              value: prefs.verifyCopies,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(verifyCopies: v)),
            ),
          ],
        ),
        // ─── Operations stream ───
        SettingsGroup(
          title: l10n.compareGroupLabel,
          children: [
            ToggleRow(
              label: l10n.compareContentsSetting,
              value: prefs.compareOptions.quickContents,
              onChanged: (v) => service.update(
                (p) => p.copyWith(
                  compareOptions: p.compareOptions.copyWith(quickContents: v),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
