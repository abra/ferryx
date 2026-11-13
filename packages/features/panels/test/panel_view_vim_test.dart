import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';
import 'package:operations_service/operations_service.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

class _Files extends Mock implements FileRepository {}

class _Operations extends Mock implements OperationsService {}

/// The keys as the panel gets them from the window: the Vim table over
/// the panel scope, the way the workspace installs it.
void main() {
  const home = Location.native('/home');
  const platform = TargetPlatform.macOS;
  late _Files files;
  late _Operations operations;
  late PreferencesService preferences;
  late PanelCubit cubit;
  late FocusNode focus;
  late List<String> events;

  final en = lookupFerryxLocalizations(const Locale('en'));

  // `..`, docs, a.txt, ab.txt, b.txt, c.md
  Listing listing() => Listing(
    location: home,
    entries: [
      const FileEntry(
        name: '..',
        path: '/',
        kind: EntryKind.directory,
        isDir: true,
        isParent: true,
      ),
      const FileEntry(
        name: 'docs',
        path: '/home/docs',
        kind: EntryKind.directory,
        isDir: true,
      ),
      for (final name in ['a.txt', 'ab.txt', 'b.txt', 'c.md'])
        FileEntry(
          name: name,
          path: '/home/$name',
          kind: EntryKind.file,
          isDir: false,
          size: 1,
          extension: name.split('.').last,
        ),
    ],
    watched: true,
  );

  setUpAll(() {
    registerFallbackValue(home);
    registerFallbackValue(const ListingOptions());
  });

  setUp(() async {
    files = _Files();
    operations = _Operations();
    events = [];
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    await preferences.update((p) => p.copyWith(vimMode: true));
    when(
      () => files.directoryChanges,
    ).thenAnswer((_) => const Stream<String>.empty());
    when(
      () => files.openListing(any(), any(), any()),
    ).thenAnswer((_) async => listing());
    when(() => files.refreshListing(any())).thenAnswer((_) async => listing());
    when(
      () => files.resortListing(any(), any()),
    ).thenAnswer((_) async => listing());
    when(() => files.closeListing(any())).thenAnswer((_) async {});
    when(() => files.isArchive(any())).thenReturn(false);
    when(
      () => operations.progress,
    ).thenAnswer((_) => const Stream<OperationProgress>.empty());
    cubit = PanelCubit(
      side: PanelSide.left,
      files: files,
      operations: operations,
      preferences: preferences,
      logger: Logger(),
    );
    await cubit.start(null, home);
    focus = FocusNode(debugLabel: 'panel');
  });

  tearDown(() async {
    focus.dispose();
    await cubit.close();
    await preferences.dispose();
  });

  PanelTabState tab() => cubit.state.active!;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final map = ShortcutMap.forUser(platform, vimMotions: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Scaffold(
          body: CommandShortcuts(
            shortcuts: map.toShortcuts(
              platform,
              scopes: const {CommandScope.panel},
            ),
            child: BlocProvider<PanelCubit>.value(
              value: cubit,
              child: PanelView(
                focusNode: focus,
                active: true,
                layouts: PanelLayout.defaults,
                showTabBarAlways: false,
                quickSearchModifier: QuickSearchModifier.none,
                vimMode: true,
                leftInset: 0,
                rightInset: 0,
                shortcutMap: map,
                hooks: PanelHooks(
                  onActivate: () {},
                  onOpenFile: (_) {},
                  onContextMenu: (_) {},
                  onPanelMenu: (_) {},
                  onSwitchPanel: () {},
                  onShowPreview: () {},
                  onGoHome: () {},
                  onGoRoot: () {},
                  onVimYank: () => events.add('yank'),
                  onVimCut: () => events.add('cut'),
                  onVimPaste: () => events.add('paste'),
                  onVimCancelRegister: () => events.add('cancel'),
                  onVimSetMark: (letter) => events.add('mark $letter'),
                  onVimGoMark: (letter) => events.add('go $letter'),
                  onVimCommand: (line) => events.add(':$line'),
                  onVimComplete: (_) async => const [],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
  }

  /// Types [keys] one by one; a capital or a symbol holds Shift.
  Future<void> type(WidgetTester tester, String keys) async {
    for (final rune in keys.runes) {
      final char = String.fromCharCode(rune);
      final (key, shift) = switch (char) {
        '/' => (LogicalKeyboardKey.slash, false),
        ':' => (LogicalKeyboardKey.semicolon, true),
        ';' => (LogicalKeyboardKey.semicolon, false),
        ',' => (LogicalKeyboardKey.comma, false),
        "'" => (LogicalKeyboardKey.quoteSingle, false),
        ' ' => (LogicalKeyboardKey.space, false),
        '\n' => (LogicalKeyboardKey.enter, false),
        '\x1b' => (LogicalKeyboardKey.escape, false),
        _ when RegExp(r'[0-9]').hasMatch(char) => (
          LogicalKeyboardKey.findKeyByKeyId(
            LogicalKeyboardKey.digit0.keyId + (rune - 0x30),
          )!,
          false,
        ),
        _ => (
          LogicalKeyboardKey.findKeyByKeyId(
            LogicalKeyboardKey.keyA.keyId +
                (char.toLowerCase().runes.first - 0x61),
          )!,
          char != char.toLowerCase(),
        ),
      };
      // As a Mac keyboard sends them; the simulator has no key code for the
      // quote elsewhere, and no physical key for it anywhere.
      if (shift) {
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.shiftLeft,
          platform: 'macos',
        );
      }
      await tester.sendKeyEvent(
        key,
        platform: 'macos',
        character: char,
        physicalKey: key == LogicalKeyboardKey.quoteSingle
            ? PhysicalKeyboardKey.quote
            : null,
      );
      if (shift) {
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.shiftLeft,
          platform: 'macos',
        );
      }
      await tester.pump();
    }
  }

  testWidgets('j k gg G move, with counts', (tester) async {
    await pump(tester);
    expect(find.text(en.vimModeNormal), findsOneWidget);
    await type(tester, 'j');
    expect(tab().cursor, 1);
    await type(tester, '3j');
    expect(tab().cursor, 4);
    await type(tester, 'k');
    expect(tab().cursor, 3);
    await type(tester, 'gg');
    expect(tab().cursor, 0);
    await type(tester, 'G');
    expect(tab().cursor, 5);
    await type(tester, '3G');
    expect(tab().cursor, 2);
    // A count shows in the footer while it waits; Esc drops it.
    await type(tester, '12');
    expect(find.text('12'), findsOneWidget);
    await type(tester, '\x1b');
    expect(find.text('12'), findsNothing);
    expect(tab().cursor, 2);
  });

  testWidgets('h and l move by a column where the names stand in columns, '
      'as vifm\'s ls-like view; in a table they go out and in; gl goes in '
      'either way', (tester) async {
    await pump(tester);
    // Short, low enough for the six rows to take two columns.
    cubit.setLayout(0);
    tester.view.physicalSize = const Size(1000, 230);
    await tester.pumpAndSettle();
    final perColumn = cubit.geometry.rowsPerColumn;
    expect(perColumn, inInclusiveRange(2, 5), reason: "two columns");
    await type(tester, 'l');
    expect(tab().cursor, perColumn);
    await type(tester, 'h');
    expect(tab().cursor, 0);
    await type(tester, 'j');
    await type(tester, 'gl');
    verify(
      () =>
          files.openListing(any(), const Location.native('/home/docs'), any()),
    ).called(1);

    // Full: a table.
    await cubit.start(null, home);
    cubit.setLayout(2);
    await tester.pumpAndSettle();
    clearInteractions(files);
    await type(tester, 'j');
    await type(tester, 'l');
    verify(
      () =>
          files.openListing(any(), const Location.native('/home/docs'), any()),
    ).called(1);
    // Out of docs, which l went into.
    await type(tester, 'h');
    verify(() => files.openListing(any(), home, any())).called(1);
  });

  testWidgets('v grows a selection; Esc ends it, then clears it', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'jv');
    expect(find.text(en.vimModeVisual), findsOneWidget);
    expect(tab().selected, {'docs'});
    await type(tester, 'jj');
    expect(tab().selected, {'docs', 'a.txt', 'ab.txt'});
    await type(tester, '\x1b');
    expect(find.text(en.vimModeNormal), findsOneWidget);
    expect(tab().selected, {'docs', 'a.txt', 'ab.txt'});
    await type(tester, '\x1b');
    expect(tab().selected, isEmpty);
    await type(tester, 'gv');
    expect(tab().selected, {'docs', 'a.txt', 'ab.txt'});
  });

  testWidgets('/ searches as letters are typed; n and N walk the matches', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, '/');
    expect(find.text(en.vimModeSearch), findsOneWidget);
    await type(tester, 'a');
    expect(tab().focused?.name, 'a.txt');
    expect(tab().matches.keys, ['a.txt', 'ab.txt']);
    // `j` is a letter of the search here, not a motion.
    await type(tester, 'j');
    expect(tab().quickSearch, 'aj');
    expect(tab().matches, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(tab().quickSearch, 'a');
    await type(tester, '\n');
    expect(find.text(en.vimModeNormal), findsOneWidget);
    expect(tab().matches.keys, ['a.txt', 'ab.txt']);
    await type(tester, 'n');
    expect(tab().cursor, 3);
    await type(tester, 'N');
    expect(tab().cursor, 2);
    await type(tester, '\x1b');
    expect(tab().matches, isEmpty);
    expect(tab().quickSearch, isEmpty);
  });

  testWidgets(': opens the command line, where panel keys are text', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'j:');
    expect(find.text(en.vimModeCommand), findsOneWidget);
    expect(find.byType(EditableText), findsOneWidget);
    expect(find.text(en.vimCommandHint), findsOneWidget);
    // Neither `j` nor Backspace reaches the panel from the field.
    await type(tester, 'j');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(tab().cursor, 1);
    expect(tab().location, home);
    await tester.enterText(find.byType(EditableText), '42');
    await type(tester, '\n');
    await tester.pumpAndSettle();
    expect(events, [':42']);
    expect(find.byType(EditableText), findsNothing);
    expect(find.text(en.vimModeNormal), findsOneWidget);
    expect(focus.hasFocus, isTrue);
    await type(tester, ':\x1b');
    expect(find.byType(EditableText), findsNothing);
    expect(events, [':42']);
  });

  testWidgets('f ; , m and \' take the key after them', (tester) async {
    await pump(tester);
    await type(tester, 'fb');
    expect(tab().cursor, 4);
    await type(tester, 'Fa');
    expect(tab().cursor, 3);
    await type(tester, ';');
    expect(tab().cursor, 2);
    // `,` turns the last find round: forward again.
    await type(tester, ',');
    expect(tab().cursor, 3);
    await type(tester, 'mq');
    expect(events, ['mark q']);
    await type(tester, "'q");
    expect(events, ['mark q', 'go q']);
    await type(tester, "''");
    expect(events.last, "go '");
  });

  testWidgets('yy dd p uy go to the window', (tester) async {
    await pump(tester);
    await type(tester, 'jyy');
    await type(tester, 'dd');
    await type(tester, 'p');
    await type(tester, 'uy');
    expect(events, ['yank', 'cut', 'paste', 'cancel']);
    // Space toggles and steps, as before; `x` toggles in place.
    await type(tester, ' ');
    expect(tab().selected, {'docs'});
    expect(tab().cursor, 2);
    await type(tester, 'x');
    expect(tab().selected, {'docs', 'a.txt'});
  });
}
