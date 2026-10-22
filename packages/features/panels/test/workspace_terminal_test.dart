import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';
import 'package:operations_service/operations_service.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:platform_services/testing.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

class _Files extends Mock implements FileRepository {}

class _Operations extends Mock implements OperationsService {}

/// The terminal as the window sees it, recording what it is told.
class _FakeTerminal implements WorkspaceTerminalController {
  final calls = <String>[];
  final folders = StreamController<String>.broadcast();
  var disposed = false;

  @override
  void show(String? folder) => calls.add('show $folder');

  @override
  void hide() => calls.add('hide');

  @override
  void followFolder(String? folder) => calls.add('follow $folder');

  @override
  Stream<String> get shellFolders => folders.stream;

  var busy = false;

  @override
  bool run(String command) {
    calls.add('run $command');
    return !busy;
  }

  @override
  double lineHeight(BuildContext context) => 16;

  @override
  double chromeHeight(BuildContext context) => 40;

  @override
  Future<void> dispose() async {
    disposed = true;
    await folders.close();
  }
}

/// The window with a terminal, its keys pressed as a Mac keyboard would.
void main() {
  const home = Location.native('/home');
  const platform = TargetPlatform.macOS;
  late _Files files;
  late _Operations operations;
  late PreferencesService preferences;
  late FolderFrecency frecency;
  late FakePlatformServices desktop;
  late _FakeTerminal terminal;
  late List<WorkspaceTerminalView> views;

  final en = lookupFerryxLocalizations(const Locale('en'));

  Listing listing(Location location) => Listing(
    location: location,
    entries: [
      FileEntry(
        name: 'docs',
        path: '${location.path}/docs',
        kind: EntryKind.directory,
        isDir: true,
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
    terminal = _FakeTerminal();
    views = [];
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    // A folder the shell takes the panel to counts as a visit; its write
    // runs within the test's frames.
    frecency = await FolderFrecency.load(
      InMemorySideStorage(),
      writeDelay: const Duration(milliseconds: 1),
    );
    desktop = FakePlatformServices();
    when(
      () => files.directoryChanges,
    ).thenAnswer((_) => const Stream<String>.empty());
    when(() => files.openListing(any(), any(), any())).thenAnswer(
      (call) async => listing(call.positionalArguments[1] as Location),
    );
    when(() => files.closeListing(any())).thenAnswer((_) async {});
    when(() => files.isArchive(any())).thenReturn(false);
    when(
      () => operations.progress,
    ).thenAnswer((_) => const Stream<OperationProgress>.empty());
    when(() => operations.current).thenReturn(const {});
  });

  tearDown(() async {
    await frecency.dispose();
    await desktop.dispose();
  });

  // The service lives in memory; its writes run in each test's fake time,
  // so it is not awaited after them.

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final map = ShortcutMap.forUser(
      platform,
      vimMotions: preferences.current.vimMode,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: CommandShortcuts(
          shortcuts: map.toShortcuts(
            platform,
            scopes: const {CommandScope.global},
          ),
          child: WorkspaceScreen(
            files: files,
            operations: operations,
            rename: const RenameService(),
            preferences: preferences,
            logger: Logger(),
            shortcutMap: map,
            windowDecor: WindowDecor.none,
            platformServices: desktop,
            frecency: frecency,
            folderSync: _MockFolderSync(),
            navigation: WorkspaceNavigation(
              openViewer: (_, _, {preview = false}) async {},
              openFind: (_, _, {required view}) async => null,
              openSettings: (_) async {},
              openCheatSheet: (_) async {},
              openSync: (_, {required left, required right}) async {},
              openChecksums: (
                _, {
                required paths,
                required base,
                algorithm,
              }) async {},
              openDuplicates: (_, {required root, other}) async => null,
            ),
            savedLeft: null,
            savedRight: null,
            savedActive: PanelSide.left,
            fallbackLocation: home,
            onSnapshot: (_) {},
            terminal: WorkspaceTerminal(
              create: () => terminal,
              builder: (context, controller, view) {
                views.add(view);
                return Focus(
                  focusNode: view.focusNode,
                  child: const ColoredBox(
                    key: ValueKey('fake terminal'),
                    color: Color(0xFF000000),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool meta = false,
    bool control = false,
    bool alt = false,
  }) async {
    final held = [
      if (meta) LogicalKeyboardKey.metaLeft,
      if (control) LogicalKeyboardKey.controlLeft,
      if (alt) LogicalKeyboardKey.altLeft,
    ];
    for (final k in held) {
      await tester.sendKeyDownEvent(k);
    }
    await tester.sendKeyEvent(key);
    for (final k in held.reversed) {
      await tester.sendKeyUpEvent(k);
    }
    await tester.pumpAndSettle();
  }

  Future<void> showTerminal(WidgetTester tester) => chord(
    tester,
    LogicalKeyboardKey.arrowUp,
    control: true,
    alt: true,
  );

  final terminalView = find.byKey(const ValueKey('fake terminal'));
  bool terminalFocused() => views.last.focusNode.hasFocus;

  testWidgets('hidden at first; Control-Option-Up shows it under the panels '
      'with the keys, in the active panel\'s folder', (tester) async {
    await pump(tester);
    expect(terminalView, findsNothing);
    expect(find.byType(PanelView), findsNWidgets(2));
    await showTerminal(tester);
    expect(terminalView, findsOneWidget);
    expect(find.byType(PanelView), findsNWidgets(2));
    expect(terminal.calls, contains('show /home'));
    expect(terminalFocused(), isTrue);
    // Its height: its chrome and twelve lines, under the panels.
    expect(tester.getSize(terminalView).height, 40 + 12 * 16);
    expect(
      tester.getBottomLeft(find.byType(PanelView).first).dy,
      tester.getTopLeft(terminalView).dy,
    );
    // Remembered for the next run.
    await tester.pump(const Duration(milliseconds: 500));
    expect(preferences.current.terminal.place, TerminalPlace.overlapped);
  });

  testWidgets('pressed again where the keys are, a line taller', (
    tester,
  ) async {
    await pump(tester);
    await showTerminal(tester);
    await showTerminal(tester);
    expect(tester.getSize(terminalView).height, 40 + 13 * 16);
    await tester.pump(const Duration(milliseconds: 500));
    expect(preferences.current.terminal.lines, 13);
  });

  testWidgets('the key hints follow the keys into the terminal', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(en.cmdHideTerminal), findsNothing);
    await showTerminal(tester);
    expect(find.text(en.cmdHideTerminal), findsOneWidget);
    expect(find.text(en.cmdTerminalClear), findsOneWidget);
  });

  testWidgets('Control-Option-O hides the panels over the terminal and '
      'brings them back with the keys', (tester) async {
    await pump(tester);
    await showTerminal(tester);
    await chord(tester, LogicalKeyboardKey.keyO, control: true, alt: true);
    expect(find.byType(PanelView), findsNothing);
    expect(terminalView, findsOneWidget);
    expect(views.last.panelsHidden, isTrue);
    expect(terminalFocused(), isTrue);
    expect(tester.getTopLeft(terminalView).dy, 0);
    await chord(tester, LogicalKeyboardKey.keyO, control: true, alt: true);
    expect(find.byType(PanelView), findsNWidgets(2));
    expect(terminalFocused(), isFalse);
  });

  testWidgets('Option-Command-O takes the whole window, key hints too, and '
      'goes back to where it was', (tester) async {
    await pump(tester);
    expect(find.byType(KeyHintStrip), findsOneWidget);
    await chord(tester, LogicalKeyboardKey.keyO, meta: true, alt: true);
    expect(views.last.fullWindow, isTrue);
    expect(find.byType(KeyHintStrip), findsNothing);
    expect(find.byType(PanelView), findsNothing);
    expect(terminalFocused(), isTrue);
    expect(tester.getSize(terminalView), const Size(1200, 800));
    await chord(tester, LogicalKeyboardKey.keyO, meta: true, alt: true);
    expect(terminalView, findsNothing, reason: 'it was hidden before');
    expect(find.byType(KeyHintStrip), findsOneWidget);
    expect(terminal.calls.last, 'hide');
  });

  testWidgets('Control-Option-Down hides it and gives the panel the keys', (
    tester,
  ) async {
    await pump(tester);
    await showTerminal(tester);
    await chord(tester, LogicalKeyboardKey.arrowDown, control: true, alt: true);
    expect(terminalView, findsNothing);
    expect(terminal.calls.last, 'hide');
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'left panel',
    );
  });

  testWidgets('the shell follows the active panel; a cd in the shell takes '
      'the panel along', (tester) async {
    await pump(tester);
    await showTerminal(tester);
    terminal.calls.clear();
    // The right panel becomes the active one.
    await chord(tester, LogicalKeyboardKey.arrowRight, meta: true);
    terminal.folders.add('/tmp/elsewhere');
    await tester.pumpAndSettle();
    verify(
      () => files.openListing(
        any(),
        const Location.native('/tmp/elsewhere'),
        any(),
      ),
    ).called(1);
    expect(terminal.calls, contains('follow /tmp/elsewhere'));
  });

  testWidgets('the edge between them sizes the terminal by lines, with the '
      'pointer or the keys', (tester) async {
    await pump(tester);
    await showTerminal(tester);
    final edge = find.byWidgetPredicate(
      (w) => w is AppSplitter && w.axis == Axis.vertical,
    );
    expect(edge, findsOneWidget);
    await tester.drag(edge, const Offset(0, -64));
    await tester.pumpAndSettle();
    expect(tester.getSize(terminalView).height, 40 + 16 * 16);
    final splitter = tester.widget<AppSplitter>(edge);
    splitter.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.getSize(terminalView).height, 40 + 14 * 16);
    // Esc puts back the height the keys found.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.getSize(terminalView).height, 40 + 16 * 16);
    expect(terminalFocused(), isTrue);
  });

  testWidgets('a terminal left open comes back at the next start', (
    tester,
  ) async {
    // Set at once; the write itself is not waited for in fake time.
    unawaited(
      preferences.update(
        (p) => p.copyWith(
          terminal: const TerminalPreferences(
            place: TerminalPlace.overlapped,
            lines: 8,
          ),
        ),
      ),
    );
    await pump(tester);
    expect(terminalView, findsOneWidget);
    expect(tester.getSize(terminalView).height, 40 + 8 * 16);
    expect(terminal.calls, contains('show /home'));
  });

  testWidgets('Vim\'s :term shows the terminal and runs a command there', (
    tester,
  ) async {
    unawaited(preferences.update((p) => p.copyWith(vimMode: true)));
    await pump(tester);
    Future<void> command(String line) async {
      // `:` as a Mac keyboard sends it, then the line and Return.
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.shiftLeft,
        platform: 'macos',
      );
      await tester.sendKeyEvent(
        LogicalKeyboardKey.semicolon,
        platform: 'macos',
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.shiftLeft,
        platform: 'macos',
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), line);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    await command('term make test');
    expect(terminalView, findsOneWidget);
    expect(terminalFocused(), isTrue);
    expect(terminal.calls, contains('run make test'));
    // A program runs there: the window says so rather than typing over it.
    await chord(tester, LogicalKeyboardKey.arrowDown, control: true, alt: true);
    terminal.busy = true;
    await command('term ls');
    expect(find.text(en.terminalBusy), findsOneWidget);
  });

  testWidgets('the window disposes its terminal', (tester) async {
    await pump(tester);
    await tester.pumpWidget(const SizedBox());
    expect(terminal.disposed, isTrue);
  });
}

class _MockFolderSync extends Mock implements FolderSyncService {}
