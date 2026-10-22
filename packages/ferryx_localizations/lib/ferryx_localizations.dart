/// Supported locales and UI copy.
///
/// Add a key to `lib/l10n/app_en.arb` and every other ARB, then run
/// `make l10n`. Bloc/Cubit state carries typed codes; only Views call
/// [FerryxLocalizations].
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/generated/ferryx_localizations.dart';

export 'src/command_labels.dart';
export 'src/formatting.dart';
export 'src/generated/ferryx_localizations.dart';
export 'src/tag_labels.dart';

/// Single source of truth for the locales the app ships.
abstract final class FerryxSupportedLocales {
  static const List<Locale> locales = [Locale('en'), Locale('ru')];

  static List<String> get codes =>
      locales.map((l) => l.languageCode).toList(growable: false);

  /// Delegates for `MaterialApp.localizationsDelegates`.
  static const List<LocalizationsDelegate<Object?>> delegates = [
    FerryxLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}

extension FerryxLocalizationsX on BuildContext {
  FerryxLocalizations get l10n => FerryxLocalizations.of(this);
}
