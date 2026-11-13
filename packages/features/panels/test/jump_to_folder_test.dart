import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/dialogs/jump_to_folder.dart';
import 'package:panels_feature/src/path_text.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);

  test('PathText.tilde writes the home folder as ~', () {
    expect(PathText.tilde('/home/me', home: '/home/me'), '~');
    expect(PathText.tilde('/home/me/src', home: '/home/me'), '~/src');
    expect(PathText.tilde('/home/meadow', home: '/home/me'), '/home/meadow');
    expect(PathText.tilde('/tmp', home: '/'), '/tmp');
  });

  group('FolderLabel', () {
    test('the name, and the folder it is in with ~ for home', () {
      expect(
        FolderLabel.of('/home/me/src/app', home: '/home/me'),
        const FolderLabel(name: 'app', parent: '~/src'),
      );
      expect(
        FolderLabel.of('/home/me/src', home: '/home/me'),
        const FolderLabel(name: 'src', parent: '~'),
      );
      expect(
        FolderLabel.of('/home/me', home: '/home/me'),
        const FolderLabel(name: 'me', parent: '/home'),
      );
      expect(
        FolderLabel.of('/home/meadow/x', home: '/home/me'),
        const FolderLabel(name: 'x', parent: '/home/meadow'),
      );
      expect(
        FolderLabel.of('/tmp', home: '/home/me'),
        const FolderLabel(name: 'tmp', parent: '/'),
      );
      expect(
        FolderLabel.of('/', home: '/home/me'),
        const FolderLabel(name: '/', parent: ''),
      );
    });

    test('the ranges of the path move into the name and the parent; the '
        'home\'s part lights the ~', () {
      // "/home/me/src/app": `me` at 6–8, `src` at 9–12, `ap` at 13–15.
      final label = FolderLabel.of(
        '/home/me/src/app',
        home: '/home/me',
        ranges: const [(6, 8), (9, 12), (13, 15)],
      );
      expect(label.nameRanges, [(0, 2)]);
      expect(label.parentRanges, [(0, 1), (2, 5)]);
      expect(label.parent.substring(2, 5), 'src');
      // A range across the separator lights both sides.
      final across = FolderLabel.of(
        '/tmp/abc',
        home: '/home/me',
        ranges: const [(2, 6)],
      );
      expect(across.parentRanges, [(2, 4)]);
      expect(across.nameRanges, [(0, 1)]);
    });
  });

  group('the panel counts the folders it shows', () {
    late WorkspaceHarness h;
    late List<String> visits;
    late PanelCubit cubit;

    setUp(() async {
      h = WorkspaceHarness();
      await h.setUp();
      h.addFolder('/home/docs/inner');
      visits = [];
      cubit = PanelCubit(
        side: PanelSide.left,
        files: h.files,
        operations: h.operations,
        preferences: h.preferences,
        logger: Logger(),
        onFolderShown: visits.add,
      );
    });

    tearDown(() async {
      await cubit.close();
      await h.tearDown();
    });

    test('a folder gone to counts; a start restoring tabs and a folder read '
        'again where it is do not', () async {
      await cubit.start(
        const SavedPanel(
          tabs: [SavedTab(location: Location.native('/home/docs'))],
        ),
        const Location.native('/home'),
      );
      expect(visits, isEmpty);
      await cubit.open(const Location.native('/home/docs/inner'));
      await cubit.goParent();
      // The same folder again, then read again: no visits.
      await cubit.open(const Location.native('/home/docs'));
      await cubit.refresh();
      // Back through the history: the same folder, then the inner one.
      await cubit.goBack();
      await cubit.goBack();
      expect(visits, ['/home/docs/inner', '/home/docs', '/home/docs/inner']);
    });

    test('a folder inside an archive is not counted', () async {
      when(() => h.files.openListing(any(), any(), any())).thenAnswer(
        (_) async => const Listing(
          location: Location.inArchive(archive: '/home/a.zip'),
          entries: [],
          watched: false,
        ),
      );
      await cubit.start(null, const Location.native('/home'));
      await cubit.open(const Location.inArchive(archive: '/home/a.zip'));
      expect(visits, isEmpty);
    });
  });

  group('the window', () {
    late WorkspaceHarness h;

    setUp(() async {
      h = WorkspaceHarness();
      await h.setUp();
    });

    tearDown(() => h.tearDown());

    PanelCubit panel(WidgetTester tester, int index) => tester
        .widgetList<PanelView>(find.byType(PanelView))
        .map(
          (view) => tester.element(find.byWidget(view)).read<PanelCubit>(),
        )
        .elementAt(index);

    Future<void> openJump(WidgetTester tester) =>
        h.press(tester, LogicalKeyboardKey.keyG, meta: true);

    testWidgets('⌘G lists the folders visited, the panel\'s own left out; '
        'Return opens the lit one in the active panel', (tester) async {
      h.frecency
        ..visit('/home/projects/ferryx')
        ..visit('/home/projects/ferryx')
        ..visit('/tmp')
        ..visit('/home/docs');
      await h.pump(tester);
      await openJump(tester);
      final picker = tester.widget<AppQuickPicker<String>>(
        find.byType(AppQuickPicker<String>),
      );
      expect(
        [
          for (final e
              in picker.entries.whereType<AppQuickPickerItem<String>>())
            e.value,
        ],
        ['/home/projects/ferryx', '/tmp'],
      );
      expect(find.text('~/projects'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'tm');
      await tester.pump();
      await h.press(tester, LogicalKeyboardKey.enter);
      expect(panel(tester, 0).state.active!.location.path, '/tmp');
      expect(find.byType(AppQuickPicker<String>), findsNothing);
    });

    testWidgets('⌘Return opens in a new tab, ⌥Return in the other panel', (
      tester,
    ) async {
      h.frecency
        ..visit('/home/projects/ferryx')
        ..visit('/home/projects/ferryx')
        ..visit('/home/docs');
      await h.pump(tester);
      await openJump(tester);
      await h.press(tester, LogicalKeyboardKey.enter, meta: true);
      final left = panel(tester, 0).state;
      expect(left.tabs.length, 2);
      expect(left.active!.location.path, '/home/projects/ferryx');
      await openJump(tester);
      expect(find.byType(AppQuickPicker<String>), findsOneWidget);
      // The folder shown is not offered; the one before it is.
      await h.press(tester, LogicalKeyboardKey.enter, alt: true);
      expect(panel(tester, 1).state.active!.location.path, '/home/docs');
    });

    testWidgets('a folder gone from the disk leaves the list with a notice', (
      tester,
    ) async {
      h.frecency.visit('/home/projects/ferryx');
      await h.pump(tester);
      h.removeFolder('/home/projects/ferryx');
      await openJump(tester);
      await h.press(tester, LogicalKeyboardKey.enter);
      expect(
        h.frecency.folders.map((f) => f.path),
        isNot(contains('/home/projects/ferryx')),
      );
      expect(find.textContaining('~/projects/ferryx'), findsOneWidget);
      expect(panel(tester, 0).state.active!.location.path, '/home/docs');
    });

    testWidgets('going to folders counts them for the next jump', (
      tester,
    ) async {
      await h.pump(tester);
      expect(h.frecency.folders, isEmpty, reason: 'a start is not a visit');
      await panel(tester, 0).open(const Location.native('/home/projects'));
      await tester.pumpAndSettle();
      expect(h.frecency.folders.map((f) => f.path), ['/home/projects']);
    });

    testWidgets('Vim: gj opens the list; :z words goes straight to the best '
        'folder, :z with none matching says so', (tester) async {
      await tester.runAsync(
        () => h.preferences.update((p) => p.copyWith(vimMode: true)),
      );
      h.frecency
        ..visit('/home/projects/ferryx')
        ..visit('/tmp');
      await h.pump(tester);
      await h.press(tester, LogicalKeyboardKey.keyG, character: 'g');
      await h.press(tester, LogicalKeyboardKey.keyJ, character: 'j');
      expect(find.byType(AppQuickPicker<String>), findsOneWidget);
      await h.press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(AppQuickPicker<String>), findsNothing);
      Future<void> command(String line) async {
        await h.press(
          tester,
          LogicalKeyboardKey.semicolon,
          shift: true,
          character: ':',
        );
        await tester.enterText(find.byType(EditableText), line);
        await h.press(tester, LogicalKeyboardKey.enter);
      }

      await command('z proj fe');
      expect(
        panel(tester, 0).state.active!.location.path,
        '/home/projects/ferryx',
      );
      await command('z nowhere');
      expect(find.textContaining('nowhere'), findsOneWidget);
      expect(
        panel(tester, 0).state.active!.location.path,
        '/home/projects/ferryx',
      );
    });
  });
}
