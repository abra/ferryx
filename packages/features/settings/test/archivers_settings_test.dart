import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:settings_feature/settings_feature.dart';

import 'support.dart';

void main() {
  const seven = ArchiveTool(
    name: '7-Zip',
    path: '/usr/local/bin/7zz',
    engine: ArchiverEngine.sevenZip,
  );
  late PreferencesService preferences;
  setUp(() async {
    preferences = await testPreferences();
  });
  tearDown(() {
    unawaited(preferences.dispose());
  });

  testWidgets(
    'each program has persistent, validated options and can reset them',
    (tester) async {
      await pumpScreen(
        tester,
        SettingsScreen(
          preferencesService: preferences,
          platform: TargetPlatform.macOS,
          version: 'test',
          initialSection: SettingsSection.archivers,
          loadArchivers: (manual, {refresh = false}) async => [seven],
          validateArchiverOptions: (engine, options) async {
            if (options.arguments.contains('--rm')) {
              throw const FerryxException(
                FerryxErrorKind.unsupported,
                'invalid option',
              );
            }
          },
          onClose: () {},
        ),
      );
      final configure = find.byWidgetPredicate(
        (w) =>
            w is AppIconButton &&
            w.tooltip == en.archiverOptionsTitle(seven.name),
      );
      await tester.tap(configure);
      await tester.pumpAndSettle();
      final choices = find.byType(AppPopupButton<int>);
      tester.widget<AppPopupButton<int>>(choices.at(0)).onChanged(7);
      tester.widget<AppPopupButton<int>>(choices.at(1)).onChanged(4);
      tester.widget<AppPopupButton<int>>(choices.at(2)).onChanged(1);
      await tester.pumpAndSettle();
      final arguments = find.descendant(
        of: find.byType(AppDialog),
        matching: find.byType(EditableText),
      );
      await tester.enterText(arguments, '--rm');
      await tester.tap(find.text(en.actionSave));
      await tester.pumpAndSettle();
      expect(find.text(en.archiverOptionsInvalid), findsOneWidget);
      expect(preferences.current.archivers.options, isEmpty);
      await tester.enterText(arguments, '-m0=lzma2\n-md=64m');
      await tester.tap(find.text(en.actionSave));
      await tester.pumpAndSettle();
      expect(
        preferences.current.archivers.optionsFor(seven.id),
        const ArchiverOptions(
          level: 7,
          threads: 4,
          solid: true,
          arguments: ['-m0=lzma2', '-md=64m'],
        ),
      );
      expect(find.textContaining(en.archiverCustomized), findsOneWidget);
      await tester.tap(configure);
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.actionReset));
      await tester.tap(find.text(en.actionSave));
      await tester.pumpAndSettle();
      expect(preferences.current.archivers.options, isEmpty);
    },
  );

  testWidgets(
    'detected tools can be disabled and refreshed; manual entries are checked, saved and removed',
    (tester) async {
      var scans = 0;
      await pumpScreen(
        tester,
        SettingsScreen(
          preferencesService: preferences,
          platform: TargetPlatform.macOS,
          version: 'test',
          initialSection: SettingsSection.archivers,
          loadArchivers: (manual, {refresh = false}) async {
            scans++;
            return [
              seven,
              ...manual.where((tool) => tool.path == '/custom/7zz'),
            ];
          },
          onClose: () {},
        ),
      );
      expect(find.text(seven.path), findsOneWidget);
      tester.widget<AppToggle>(find.byType(AppToggle)).onChanged!(false);
      await tester.pumpAndSettle();
      expect(preferences.current.archivers.disabled, [seven.id]);
      await tester.tap(find.text(en.archiversRescan));
      await tester.pumpAndSettle();
      expect(scans, greaterThan(1));
      await tester.tap(find.text(en.archiversAdd));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AppDialog),
        matching: find.byType(EditableText),
      );
      await tester.enterText(fields.at(0), 'Portable 7-Zip');
      await tester.enterText(fields.at(1), '/missing/7zz');
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.actionSave));
      await tester.pumpAndSettle();
      expect(find.text(en.archiversMissing), findsOneWidget);
      expect(preferences.current.archivers.manual, isEmpty);
      await tester.enterText(fields.at(1), '/custom/7zz');
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.actionSave));
      await tester.pumpAndSettle();
      expect(
        preferences.current.archivers.manual.single.name,
        'Portable 7-Zip',
      );
      expect(find.text('/custom/7zz'), findsOneWidget);
      final remove = find.byWidgetPredicate(
        (w) => w is AppIconButton && w.tooltip == en.actionRemove,
      );
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(preferences.current.archivers.manual, isEmpty);
    },
  );
}
