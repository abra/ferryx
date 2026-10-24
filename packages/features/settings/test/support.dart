import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preferences_service/preferences_service.dart';

/// A fresh service over memory, for one test.
Future<PreferencesService> testPreferences() =>
    PreferencesService.create(storage: InMemoryPreferencesStorage());

/// Pumps [child] under the macOS theme with the app's strings, in a
/// window wide enough for the settings panel.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  Locale? locale,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(AppPlatformStyle.macos),
      locale: locale,
      localizationsDelegates: FerryxSupportedLocales.delegates,
      supportedLocales: FerryxSupportedLocales.locales,
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

/// The strings as the tests read them.
FerryxLocalizations get en => lookupFerryxLocalizations(const Locale('en'));
FerryxLocalizations get ru => lookupFerryxLocalizations(const Locale('ru'));
