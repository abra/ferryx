import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoLocalizations;
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('clipboard notices keep list counts in English and Russian', () {
    final en = lookupFerryxLocalizations(const Locale('en'));
    final ru = lookupFerryxLocalizations(const Locale('ru'));
    expect(en.noticeNamesCopied(1), 'Name copied');
    expect(ru.noticeNamesCopied(1), 'Скопировано 1 имя');
    expect(ru.noticePathsCopied(1), 'Скопирован 1 путь');
    for (final (count, names, paths) in const [
      (2, 'Скопировано 2 имени', 'Скопировано 2 пути'),
      (5, 'Скопировано 5 имён', 'Скопировано 5 путей'),
      (21, 'Скопировано 21 имя', 'Скопирован 21 путь'),
      (101, 'Скопировано 101 имя', 'Скопирован 101 путь'),
    ]) {
      expect(en.noticeNamesCopied(count), '$count names copied');
      expect(en.noticePathsCopied(count), '$count paths copied');
      expect(ru.noticeNamesCopied(count), names);
      expect(ru.noticePathsCopied(count), paths);
    }
  });

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
