import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoLocalizations;
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final (locale, cancel, copy) in const [
    (Locale('en'), 'Cancel', 'Copy'),
    (Locale('ru'), 'Отмена', 'Копировать'),
  ]) {
    testWidgets('app and design delegates resolve ${locale.languageCode}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: FerryxSupportedLocales.locales,
          localizationsDelegates: FerryxSupportedLocales.delegates,
          home: Builder(
            builder: (context) => Text(context.l10n.actionCancel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.text(cancel));
      expect(context.l10n.localeName, locale.languageCode);
      expect(MaterialLocalizations.of(context).copyButtonLabel, copy);
      expect(CupertinoLocalizations.of(context).copyButtonLabel, copy);
      expect(tester.takeException(), isNull);
    });
  }
}
