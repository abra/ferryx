import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:preferences_service/preferences_service.dart';

import '../settings_rows.dart';

/// The built-in viewer's wrapping and font size.
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
              min: 9,
              max: 32,
              divisions: 23,
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
          ],
        ),
      ],
    );
  }
}
