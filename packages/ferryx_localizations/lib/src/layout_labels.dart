import 'package:domain_models/domain_models.dart';

import 'generated/ferryx_localizations.dart';

/// View modes in words.
extension LayoutLabels on FerryxLocalizations {
  /// [layout]'s name: a mode the app starts with by its name in this
  /// language while it keeps that name, any other as the user typed it.
  String viewModeName(PanelLayout layout) =>
      switch (PanelLayout.defaults.indexWhere((d) => d.name == layout.name)) {
        0 => layoutShort,
        1 => layoutMedium,
        2 => layoutFull,
        3 => layoutWide,
        4 => layoutDetails,
        _ => layout.name,
      };
}
