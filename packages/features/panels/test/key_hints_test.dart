import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:shortcuts/shortcuts.dart';

void main() {
  const home = Location.native('/home');
  const parent = FileEntry(
    name: '..',
    path: '/',
    kind: EntryKind.directory,
    isDir: true,
    isParent: true,
  );
  const folder = FileEntry(
    name: 'docs',
    path: '/home/docs',
    kind: EntryKind.directory,
    isDir: true,
  );
  const file = FileEntry(
    name: 'a.txt',
    path: '/home/a.txt',
    kind: EntryKind.file,
    isDir: false,
    size: 1,
    extension: 'txt',
  );
  PanelTabState tab({
    List<FileEntry> rows = const [parent, folder, file],
    int cursor = 0,
    Set<String> selected = const {},
    String quickSearch = '',
    Map<String, List<(int, int)>> matches = const {},
    bool searching = false,
    int? visualAnchor,
    int? renaming,
  }) => PanelTabState(
    id: 't',
    location: home,
    sort: const SortOptions(),
    rows: rows,
    cursor: cursor,
    selected: selected,
    quickSearch: quickSearch,
    matches: matches,
    searching: searching,
    visualAnchor: visualAnchor,
    renaming: renaming,
  );

  List<AppCommand> commands(List<PanelHint> hints) => [
    for (final hint in hints)
      if (hint is CommandHint) hint.command,
  ];

  test('with nothing in the panel: how to get to the other one', () {
    expect(
      commands(
        hintsFor(
          tab: null,
          vim: false,
          hasRegister: false,
          hasMultipleTabs: true,
        ),
      ),
      [AppCommand.switchPanel],
    );
  });

  test('multiple tabs lead browsing hints, including an empty folder', () {
    for (final current in [
      tab(cursor: 0),
      tab(cursor: 1),
      tab(cursor: 2),
      tab(rows: const [], cursor: -1),
    ]) {
      final hints = hintsFor(
        tab: current,
        vim: true,
        hasRegister: true,
        hasMultipleTabs: true,
      );
      expect(commands(hints).take(2), [
        AppCommand.previousTab,
        AppCommand.nextTab,
      ]);
      expect(hints.length, lessThanOrEqualTo(5));
      final single = commands(
        hintsFor(tab: current, vim: true, hasRegister: true),
      );
      expect(single, isNot(contains(AppCommand.previousTab)));
      expect(single, isNot(contains(AppCommand.nextTab)));
    }
  });

  test('a file, a folder and .. each get their own keys', () {
    expect(
      commands(hintsFor(tab: tab(cursor: 2), vim: false, hasRegister: false)),
      [
        AppCommand.enterItem,
        AppCommand.showPreview,
        AppCommand.toggleSelectionMoveDown,
        AppCommand.copyTo,
        AppCommand.switchPanel,
      ],
    );
    expect(
      commands(hintsFor(tab: tab(cursor: 1), vim: false, hasRegister: false)),
      contains(AppCommand.enterItem),
    );
    expect(
      commands(hintsFor(tab: tab(cursor: 0), vim: false, hasRegister: false)),
      isNot(contains(AppCommand.showPreview)),
    );
  });

  test('a selection is what to do with it; Vim adds the register', () {
    final hints = hintsFor(
      tab: tab(selected: {'a.txt'}),
      vim: false,
      hasRegister: false,
      hasMultipleTabs: true,
    );
    expect(commands(hints), [
      AppCommand.copyTo,
      AppCommand.moveTo,
      AppCommand.moveToTrash,
      AppCommand.compress,
      AppCommand.clearQuickSearch,
    ]);
    expect(
      commands(hintsFor(tab: tab(cursor: 2), vim: true, hasRegister: true))
          .first,
      AppCommand.vimPaste,
    );
  });

  test(
    'ordinary browsing offers the shelf instead of an unbound Vim paste',
    () {
      final hints = hintsFor(
        tab: tab(cursor: 2),
        vim: false,
        hasRegister: true,
      );
      expect(commands(hints).first, AppCommand.toggleShelf);
      final selected = hintsFor(
        tab: tab(selected: {'a.txt'}),
        vim: false,
        hasRegister: false,
      );
      expect(
        (selected.last as CommandHint).labelCommand,
        AppCommand.deselectAll,
      );
      expect(
        ShortcutMap.defaults(TargetPlatform.macOS)
            .primaryChord(AppCommand.toggleSelectionMoveDown),
        const Chord(LogicalKeyboardKey.space, alt: true),
      );
    },
  );

  test('modes: renaming, the search prompt, matches, Visual', () {
    final renaming = hintsFor(
      tab: tab(renaming: 2),
      vim: false,
      hasRegister: false,
      hasMultipleTabs: true,
    );
    expect(renaming, hasLength(2));
    expect((renaming.first as KeyHint).key, LogicalKeyboardKey.enter);
    final prompt = hintsFor(
      tab: tab(searching: true),
      vim: true,
      hasRegister: false,
      hasMultipleTabs: true,
    );
    expect((prompt.first as KeyHint).word, HintWord.keepMatches);
    final matches = hintsFor(
      tab: tab(
        quickSearch: 'a',
        matches: {
          'a.txt': [(0, 1)],
        },
      ),
      vim: true,
      hasRegister: false,
      hasMultipleTabs: true,
    );
    expect(commands(matches), [
      AppCommand.vimSearchNext,
      AppCommand.vimSearchPrevious,
      AppCommand.clearQuickSearch,
    ]);
    final visual = hintsFor(
      tab: tab(cursor: 1, visualAnchor: 1, selected: {'docs'}),
      vim: true,
      hasRegister: false,
      hasMultipleTabs: true,
    );
    expect(commands(visual), [
      AppCommand.vimYank,
      AppCommand.vimCut,
      AppCommand.moveToTrash,
    ]);
    expect((visual.last as KeyHint).word, HintWord.back);
  });

  test('block hints appear for large Vim lists after tabs; editing and marks keep priority', () {
    final large = tab(rows: [for (var i = 0; i < 100; i++) file]);
    for (final tabs in [false, true]) {
      final hints = commands(
        hintsFor(
          tab: large,
          vim: true,
          hasRegister: false,
          hasMultipleTabs: tabs,
          screenItems: 40,
        ),
      );
      expect(hints.take(tabs ? 4 : 2), [
        if (tabs) ...[AppCommand.previousTab, AppCommand.nextTab],
        AppCommand.vimBlockPrevious,
        AppCommand.vimBlockNext,
      ]);
    }
    for (final (vim, screen) in [(false, 40), (true, 100)]) {
      expect(
        commands(
          hintsFor(
            tab: large,
            vim: vim,
            hasRegister: false,
            screenItems: screen,
          ),
        ),
        isNot(contains(AppCommand.vimBlockNext)),
      );
    }
    for (final current in [
      large.copyWith(renaming: 1),
      large.copyWith(searching: true),
      large.copyWith(selected: {'a.txt'}),
      large.copyWith(quickSearch: 'a'),
    ]) {
      expect(
        commands(
          hintsFor(
            tab: current,
            vim: true,
            hasRegister: false,
            screenItems: 40,
          ),
        ),
        isNot(contains(AppCommand.vimBlockNext)),
      );
    }
  });

  test('an empty folder says how to fill it', () {
    expect(
      commands(
        hintsFor(
          tab: tab(rows: const [], cursor: -1),
          vim: false,
          hasRegister: false,
        ),
      ),
      [
        AppCommand.pasteItems,
        AppCommand.newFolder,
        AppCommand.goParent,
        AppCommand.switchPanel,
      ],
    );
  });

  testWidgets(
    'help remains clickable and keyboard accessible without a binding',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          localizationsDelegates: FerryxSupportedLocales.delegates,
          supportedLocales: FerryxSupportedLocales.locales,
          home: Material(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: KeyHintStrip(
                hints: const [],
                shortcutMap: ShortcutMap.forUser(TargetPlatform.macOS)
                    .rebind(AppCommand.cheatSheet, []),
                vim: false,
                onHide: () {},
                onHelp: () => opened++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Shortcuts'));
      expect(opened, 1);
      Focus.of(tester.element(find.text('Shortcuts'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, 2);
    },
  );

  testWidgets('tab hints use the mode, language and user bindings', (
    tester,
  ) async {
    const platform = TargetPlatform.macOS;
    final ru = lookupFerryxLocalizations(const Locale('ru'));
    final hints = hintsFor(
      tab: tab(cursor: 2),
      vim: false,
      hasRegister: false,
      hasMultipleTabs: true,
    );
    Finder keyCap(String label) => find.byWidgetPredicate(
      (w) => w is AppKeyCap && w.label == label,
    );
    for (final vim in [false, true]) {
      final defaults = ShortcutMap.forUser(platform, vimMotions: vim);
      for (final rebound in [false, true]) {
        final map = rebound
            ? defaults
                  .rebind(AppCommand.nextTab, [
                    Chord(LogicalKeyboardKey.keyN, primary: true, alt: true),
                  ])
                  .rebind(AppCommand.previousTab, [])
            : defaults;
        await tester.pumpWidget(
          MaterialApp(
            theme: vim
                ? AppTheme.dark(AppPlatformStyle.macos)
                : AppTheme.light(AppPlatformStyle.macos),
            locale: const Locale('ru'),
            localizationsDelegates: FerryxSupportedLocales.delegates,
            supportedLocales: FerryxSupportedLocales.locales,
            home: Material(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: KeyHintStrip(
                  hints: hints,
                  shortcutMap: map,
                  vim: vim,
                  onHide: () {},
                  onHelp: () {},
                ),
              ),
            ),
          ),
        );
        final next = rebound ? '⌥⌘N' : (vim ? 'gt' : '⇧⌘]');
        final previous = vim ? 'gT' : '⇧⌘[';
        expect(find.text(ru.cmdNextTab), findsOneWidget);
        expect(keyCap(next), findsOneWidget);
        expect(keyCap(previous), rebound ? findsNothing : findsOneWidget);
        expect(
          find.text(ru.cmdPreviousTab),
          rebound ? findsNothing : findsOneWidget,
        );
        final cap = tester.widget<AppKeyCap>(keyCap(next));
        expect(cap.typed, vim && !rebound);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('files say Open with the enter binding; folders keep Enter', (
    tester,
  ) async {
    const platform = TargetPlatform.macOS;
    for (final language in ['en', 'ru']) {
      final locale = Locale(language);
      final l10n = lookupFerryxLocalizations(locale);
      for (final vim in [false, true]) {
        final defaults = ShortcutMap.forUser(
          platform,
          vimMotions: vim,
        ).rebind(AppCommand.openItem, []);
        for (final (cursor, rebound) in [
          (2, false),
          (2, true),
          (1, false),
          (0, false),
        ]) {
          final map = rebound
              ? defaults.rebind(AppCommand.enterItem, [
                  Chord(LogicalKeyboardKey.keyO, primary: true, alt: true),
                ])
              : defaults;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(AppPlatformStyle.macos),
              locale: locale,
              localizationsDelegates: FerryxSupportedLocales.delegates,
              supportedLocales: FerryxSupportedLocales.locales,
              home: Material(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: KeyHintStrip(
                    hints: hintsFor(
                      tab: tab(cursor: cursor),
                      vim: vim,
                      hasRegister: false,
                    ),
                    shortcutMap: map,
                    vim: vim,
                    onHide: () {},
                    onHelp: () {},
                  ),
                ),
              ),
            ),
          );
          final hint = tester.widget<AppKeyHints>(find.byType(AppKeyHints));
          expect(hint.hints.first.keys, [
            rebound
                ? '⌥⌘O'
                : vim
                ? 'gl'
                : Chord.keyLabel(LogicalKeyboardKey.enter, platform),
          ]);
          expect(hint.hints.first.typed, vim && !rebound);
          expect(
            hint.hints.first.label,
            cursor == 2 ? l10n.cmdOpenItem : l10n.cmdEnterItem,
          );
          expect(tester.takeException(), isNull);
        }
      }
    }
  });
}
