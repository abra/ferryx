import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preferences_service/preferences_service.dart';

void main() {
  group('Preferences JSON', () {
    test('round-trips every field', () {
      const prefs = Preferences(
        themeMode: AppThemeMode.dark,
        localeCode: 'ru',
        textScale: 1.2,
        shortcutOverrides: {
          'copyTo': ['primary+keyC'],
        },
        windowBounds: WindowBounds(x: 1, y: 2, width: 900, height: 700),
        windowMaximized: true,
        splitFraction: 0.4,
        singlePane: true,
        panelArrangement: PanelArrangement.stacked,
        panelState: {'left': '{}'},
        showHiddenFiles: true,
        showParentEntry: false,
        foldersFirst: false,
        collation: Collation.caseSensitive,
        quickSearchWhere: QuickSearchWhere.fuzzy,
        quickSearchModifier: QuickSearchModifier.alt,
        quickSearchOnlyMatching: true,
        favorites: [
          Favorite(location: Location.native('/tmp'), title: 'Temp'),
          Favorite(
            location: Location.inArchive(archive: '/a.zip', path: 'd'),
          ),
        ],
        editors: [
          ExternalEditor(name: 'Vim', path: '/usr/bin/vim', inTerminal: true),
        ],
        tools: [
          ExternalTool(title: 'Open', path: '/usr/bin/open', parameters: '%p'),
        ],
        confirmTrash: true,
        verifyCopies: true,
        viewerWrap: false,
        viewerFontSize: 15,
        showTabBarAlways: true,
        vimMode: true,
        vimMarks: {'a': 'native:/tmp'},
        terminal: TerminalPreferences(
          shell: '/bin/bash',
          fontFamily: 'Geist Mono',
          fontSize: 14,
          scrollback: 20000,
          lines: 20,
          place: TerminalPlace.fullWindow,
        ),
      );
      expect(Preferences.fromJson(prefs.toJson()), prefs);
    });

    test('the terminal block keeps its numbers in range', () {
      expect(
        TerminalPreferences.fromJson({
          'shell': '  /bin/zsh ',
          'fontSize': 200,
          'scrollback': 5,
          'lines': -3,
          'place': 'sideways',
        }),
        const TerminalPreferences(
          shell: '/bin/zsh',
          fontSize: TerminalPreferences.maxFontSize,
          scrollback: TerminalPreferences.minScrollback,
          lines: TerminalPreferences.minLines,
        ),
      );
      expect(
        TerminalPreferences.fromJson('nonsense'),
        const TerminalPreferences(),
      );
      expect(
        TerminalPreferences.fromJson({'fontSize': double.nan}).fontSize,
        const TerminalPreferences().fontSize,
      );
      // An older file has no terminal block at all.
      expect(Preferences.fromJson({}).terminal, const TerminalPreferences());
    });

    test('terminal font preferences accept old files and normalize names', () {
      expect(TerminalPreferences.fromJson({}).fontFamily, isEmpty);
      for (final invalid in [null, 42, false, <String>[]]) {
        expect(
          TerminalPreferences.fromJson({'fontFamily': invalid}).fontFamily,
          isEmpty,
        );
      }
      expect(
        TerminalPreferences.fromJson({'fontFamily': '  Menlo  '}).fontFamily,
        'Menlo',
      );
      expect(
        TerminalPreferences.fromJson({'fontFamily': '   '}).fontFamily,
        isEmpty,
      );
    });

    test('damaged values fall back to defaults', () {
      final prefs = Preferences.fromJson({
        'themeMode': 'purple',
        'textScale': 'big',
        'splitFraction': 5,
        'layouts': [
          1,
          {'name': 'x'},
        ],
        'favorites': [
          {'location': 'nowhere'},
        ],
        'shortcutOverrides': {'copyTo': 'keyC'},
      });
      const defaults = Preferences();
      expect(prefs.themeMode, defaults.themeMode);
      expect(prefs.textScale, defaults.textScale);
      expect(prefs.splitFraction, 0.9);
      expect(prefs.layouts, PanelLayout.defaults);
      expect(prefs.favorites, isEmpty);
      expect(prefs.shortcutOverrides, isEmpty);
    });
  });

  group('PreferencesService', () {
    test(
      'a font change is saved, restored and can return to the default',
      () async {
        final storage = InMemoryPreferencesStorage();
        final service = await PreferencesService.create(storage: storage);
        final seen = <String>[];
        final subscription = service.stream.listen(
          (p) => seen.add(p.terminal.fontFamily),
        );
        await service.update(
          (p) => p.copyWith(terminal: p.terminal.copyWith(fontFamily: 'Menlo')),
        );
        final restored = await PreferencesService.create(storage: storage);
        expect(restored.current.terminal.fontFamily, 'Menlo');
        await service.update(
          (p) => p.copyWith(terminal: p.terminal.copyWith(fontFamily: '')),
        );
        expect(service.current.terminal.fontFamily, isEmpty);
        expect(seen, ['Menlo', '']);
        await subscription.cancel();
        await restored.dispose();
        await service.dispose();
      },
    );

    test('broadcasts and saves every change in order', () async {
      final storage = InMemoryPreferencesStorage();
      final service = await PreferencesService.create(storage: storage);
      final seen = <bool>[];
      final subscription = service.stream.listen((p) => seen.add(p.singlePane));
      await service.update((p) => p.copyWith(singlePane: true));
      await service.update((p) => p.copyWith(singlePane: true));
      await service.update((p) => p.copyWith(singlePane: false));
      expect(seen, [true, false]);
      expect(storage.saves, 2);
      await subscription.cancel();
      await service.dispose();
    });
  });
}
