import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:preferences_service/preferences_service.dart';

import '../settings_rows.dart';

/// The built-in viewer's wrapping and separate text and book font sizes.
class ViewerPage extends StatelessWidget {
  const ViewerPage({required this.prefs, required this.service, super.key});

  final Preferences prefs;
  final PreferencesService service;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsPage(
      children: [
        SettingsGroup(
          children: [
            ToggleRow(
              label: l10n.viewerWrapLabel,
              value: prefs.viewerWrap,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(viewerWrap: v)),
            ),
            SliderRow(
              label: l10n.viewerFontSizeLabel,
              value: prefs.viewerFontSize,
              min: Preferences.minViewerFontSize,
              max: Preferences.maxViewerFontSize,
              divisions:
                  (Preferences.maxViewerFontSize -
                          Preferences.minViewerFontSize)
                      .round(),
              display: switch (context.metrics.lengthUnit) {
                AppLengthUnit.points => l10n.lengthPoints(
                  prefs.viewerFontSize.round(),
                ),
                AppLengthUnit.pixels => l10n.lengthPixels(
                  prefs.viewerFontSize.round(),
                ),
              },
              onChanged: (value) => service.update(
                (p) => p.copyWith(viewerFontSize: value.roundToDouble()),
              ),
            ),
            SliderRow(
              label: l10n.documentFontSizeLabel,
              value: prefs.documentFontSize,
              min: Preferences.minDocumentFontSize,
              max: Preferences.maxDocumentFontSize,
              divisions:
                  (Preferences.maxDocumentFontSize -
                          Preferences.minDocumentFontSize)
                      .round(),
              display: switch (context.metrics.lengthUnit) {
                AppLengthUnit.points => l10n.lengthPoints(
                  prefs.documentFontSize.round(),
                ),
                AppLengthUnit.pixels => l10n.lengthPixels(
                  prefs.documentFontSize.round(),
                ),
              },
              onChanged: (value) => service.update(
                (p) => p.copyWith(documentFontSize: value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
