import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:preferences_service/preferences_service.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);

  late WorkspaceHarness h;
  late InMemoryPreferencesStorage storage;
  final l10n = lookupFerryxLocalizations(const Locale('en'));
  const initial = [
    Favorite(location: Location.native('/tmp')),
    Favorite(location: Location.native('/home/projects/ferryx')),
  ];

  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
    h.addFolder('/home/docs/child');
    h.addFolder('/work/right');
    await h.preferences.dispose();
    storage = InMemoryPreferencesStorage(
      const Preferences(favorites: initial),
    );
    h.preferences = await PreferencesService.create(storage: storage);
    when(() => h.files.volumes()).thenAnswer((_) async => const []);
    when(() => h.operations.currentJournal).thenReturn(JournalSummary.empty);
  });

  tearDown(() => h.tearDown());

  Future<List<Favorite>> saved(WidgetTester tester) async {
    // Preferences were created in setUp's real zone, as the harness needs.
    // Let its serialized persistence finish outside the widget fake clock.
    final preferences = await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
      return storage.load();
    });
    return preferences!.favorites;
  }

  Future<List<String>> savedPaths(WidgetTester tester) async => [
    for (final favorite in await saved(tester)) favorite.location.path,
  ];

  PanelCubit panel(WidgetTester tester, int index) =>
      tester.element(find.byType(PanelView).at(index)).read<PanelCubit>();

  Finder button(String label) => find.widgetWithText(OutlinedButton, label);

  Future<void> manageFromMenu(WidgetTester tester) async {
    await tester.tap(find.text(l10n.cmdManageFavorites));
    await h.settle(tester);
    expect(find.byType(AppDialog), findsOneWidget);
  }

  for (final scenario in [
    (panelMenu: false, focusFile: false),
    (panelMenu: true, focusFile: false),
    (panelMenu: true, focusFile: true),
  ]) {
    testWidgets(
      'Add is idempotent; ${scenario.panelMenu ? 'panel' : 'row'} menu removes '
      '${scenario.focusFile ? 'the current folder when a file is focused' : 'the focused folder'} only',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        await h.pump(tester);
        await h.press(tester, LogicalKeyboardKey.arrowDown); // child
        if (scenario.focusFile) {
          await h.press(tester, LogicalKeyboardKey.arrowDown); // a.txt
        }
        final target = scenario.focusFile ? '/home/docs' : '/home/docs/child';
        expect(
          panel(tester, 0).state.active!.focused!.name,
          scenario.focusFile ? 'a.txt' : 'child',
        );
        await h.press(tester, LogicalKeyboardKey.keyB, meta: true);
        expect(await savedPaths(tester), [
          '/tmp',
          '/home/projects/ferryx',
          target,
        ]);
        await h.press(tester, LogicalKeyboardKey.keyB, meta: true);
        expect(await savedPaths(tester), [
          '/tmp',
          '/home/projects/ferryx',
          target,
        ], reason: 'repeating Add neither removes nor duplicates a favorite');

        if (scenario.panelMenu) {
          await tester.tap(
            find.descendant(
              of: find.byType(PanelView).first,
              matching: find.byIcon(AppIcons.more),
            ),
          );
          await h.settle(tester);
        } else {
          await h.press(tester, LogicalKeyboardKey.enter, control: true);
        }
        await tester.tap(find.text(l10n.cmdRemoveFromFavorites));
        await h.settle(tester);
        expect(await saved(tester), initial);
        expect(
          h.started,
          isEmpty,
          reason: 'removing a favorite never deletes files',
        );
        expect(h.folders, contains('/home/docs/child'));
      },
    );
  }

  testWidgets(
    'Manage in the quick list adds the current folder; Remove persists the '
    'selected row and disables after the last favorite',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      await h.pump(tester);
      await h.press(tester, LogicalKeyboardKey.arrowDown); // child
      await h.press(tester, LogicalKeyboardKey.digit3, meta: true);
      await manageFromMenu(tester);
      await tester.tap(button(l10n.favoritesAddCurrent));
      await h.settle(tester);
      expect(await savedPaths(tester), [
        '/tmp',
        '/home/projects/ferryx',
        '/home/docs',
      ], reason: 'Manage adds its current folder, not the focused child');

      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is AppNavItem && widget.label == 'ferryx',
        ),
      );
      await h.settle(tester);
      // Repeated Remove uses the surviving selection without another row click.
      for (final step in [
        (label: 'ferryx', remaining: ['/tmp', '/home/docs']),
        (label: 'docs', remaining: ['/tmp']),
        (label: 'tmp', remaining: <String>[]),
      ]) {
        await tester.tap(button(l10n.actionRemove));
        await h.settle(tester);
        expect(
          await savedPaths(tester),
          step.remaining,
          reason: 'Remove acts on the selected ${step.label} favorite',
        );
        if (step.remaining.isNotEmpty) {
          final selected = tester
              .widgetList<AppNavItem>(find.byType(AppNavItem))
              .where((row) => row.selected)
              .toList();
          expect(
            selected,
            hasLength(1),
            reason: 'the surviving favorite remains selected',
          );
          expect(selected.single.label, step.remaining.last.split('/').last);
          expect(
            selected.single.focusNode!.hasPrimaryFocus,
            isTrue,
            reason: 'keys follow the surviving selection after removal',
          );
        }
      }
      expect(
        tester.widget<OutlinedButton>(button(l10n.actionRemove)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, l10n.actionDone),
            )
            .focusNode!
            .hasPrimaryFocus,
        isTrue,
      );
      expect(h.started, isEmpty);
      await h.press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(AppDialog), findsNothing);
      expect(await savedPaths(tester), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the visible row menu renames a favorite without changing its location',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      await h.pump(tester);
      await h.press(tester, LogicalKeyboardKey.digit3, meta: true);
      await manageFromMenu(tester);
      final row = find.byWidgetPredicate(
        (widget) => widget is AppNavItem && widget.label == 'ferryx',
      );
      await tester.tap(row);
      await h.settle(tester);
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(AppIcons.more)),
      );
      await h.settle(tester);
      await tester.tap(find.text(l10n.actionRename));
      await h.settle(tester);
      await tester.enterText(find.byType(TextField), 'Work project');
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionSave));
      await h.settle(tester);
      expect(await saved(tester), const [
        Favorite(location: Location.native('/tmp')),
        Favorite(
          location: Location.native('/home/projects/ferryx'),
          title: 'Work project',
        ),
      ]);
      expect(h.started, isEmpty);
    },
  );

  testWidgets(
    'Manage from F2 uses the right panel even while the left panel is active',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      await h.pump(tester, right: '/work/right');
      final workspace = tester
          .element(find.byType(KeyHintStrip))
          .read<WorkspaceCubit>();
      expect(workspace.state.active, PanelSide.left);
      await h.press(tester, LogicalKeyboardKey.f2);
      await manageFromMenu(tester);
      await tester.tap(button(l10n.favoritesAddCurrent));
      await h.settle(tester);
      expect(await savedPaths(tester), [
        '/tmp',
        '/home/projects/ferryx',
        '/work/right',
      ]);
      expect(workspace.state.active, PanelSide.right);
      expect(panel(tester, 0).state.active!.location.path, '/home/docs');
      expect(panel(tester, 1).state.active!.location.path, '/work/right');
      expect(h.started, isEmpty);
    },
  );
}
