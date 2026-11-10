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

class MockFiles extends Mock implements FileRepository {}

class MockOperations extends Mock implements OperationsService {}

class MockRename extends Mock implements RenameService {}

/// The whole window over a file system of folders in memory: both
/// panels, the global keys at the root as the app installs them, the
/// operations and renames recorded.
class WorkspaceHarness {
  WorkspaceHarness({this.platform = TargetPlatform.macOS});

  final TargetPlatform platform;
  final files = MockFiles();
  final operations = MockOperations();
  final rename = MockRename();
  final changes = StreamController<String>.broadcast();
  final progress = StreamController<OperationProgress>.broadcast();
  late PreferencesService preferences;
  late FolderFrecency frecency;
  final desktop = FakePlatformServices();
  final sideStorage = InMemorySideStorage();

  /// Folder path → its rows (no `..`).
  final folders = <String, List<FileEntry>>{};

  /// Listing id → what it shows.
  final listings = <String, Location>{};
  final started = <OperationRequest>[];

  /// Around the window, for pictures of it.
  final shotKey = GlobalKey(debugLabel: 'window');
  final notices = <String>[];
  var _nextOperation = 1;

  static const home = '/home';

  static void registerFallbacks() {
    registerFallbackValue(const Location.native('/'));
    registerFallbackValue(const ListingOptions());
    registerFallbackValue(
      const OperationRequest(kind: OpKind.copy, sources: []),
    );
    registerFallbackValue(<RenameOutcome>[]);
  }

  FileEntry file(String dir, String name, {int size = 1}) => FileEntry(
    name: name,
    path: dir == '/' ? '/$name' : '$dir/$name',
    kind: EntryKind.file,
    isDir: false,
    size: size,
    extension: name.contains('.') ? name.split('.').last : '',
  );

  FileEntry folder(String parent, String name) => FileEntry(
    name: name,
    path: parent == '/' ? '/$name' : '$parent/$name',
    kind: EntryKind.directory,
    isDir: true,
  );

  /// Adds [path] and every folder above it, each listed in its parent.
  void addFolder(String path, [List<String> fileNames = const []]) {
    folders.putIfAbsent(path, () => []);
    for (final name in fileNames) {
      folders[path]!.add(file(path, name));
    }
    final slash = path.lastIndexOf('/');
    if (slash < 0 || path == '/') return;
    final parent = slash == 0 ? '/' : path.substring(0, slash);
    final name = path.substring(slash + 1);
    addFolder(parent);
    if (!folders[parent]!.any((e) => e.name == name)) {
      folders[parent]!.add(folder(parent, name));
    }
  }

  void removeFolder(String path) {
    folders.removeWhere((key, _) => key == path || key.startsWith('$path/'));
    final slash = path.lastIndexOf('/');
    final parent = slash <= 0 ? '/' : path.substring(0, slash);
    folders[parent]?.removeWhere((e) => e.path == path);
  }

  Listing _list(Location location, ListingOptions options) {
    final rows = folders[location.path];
    if (rows == null) {
      throw FerryxException(FerryxErrorKind.notFound, location.path);
    }
    final sorted =
        [
          for (final row in rows)
            if (options.showHidden || !row.name.startsWith('.')) row,
        ]..sort((a, b) {
          if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
          return a.name.compareTo(b.name);
        });
    final parent = location.parent;
    return Listing(
      location: location,
      entries: [
        if (options.showParent && parent != null)
          FileEntry(
            name: '..',
            path: parent.path,
            kind: EntryKind.directory,
            isDir: true,
            isParent: true,
          ),
        ...sorted,
      ],
      watched: true,
    );
  }

  FileEntry? _entry(String path) {
    for (final rows in folders.values) {
      for (final row in rows) {
        if (row.path == path) return row;
      }
    }
    return null;
  }

  /// Prepares the window's services; call it from `setUp`, not inside a
  /// widget test: a preference changed in the test's fake time and then
  /// read by the window never settles.
  Future<void> setUp({bool vim = false}) async {
    addFolder('$home/docs', ['a.txt', 'b.txt', 'c.md']);
    addFolder('$home/projects/ferryx');
    addFolder('/tmp');
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    await preferences.update((p) => p.copyWith(vimMode: vim));
    frecency = await FolderFrecency.load(
      sideStorage,
      writeDelay: const Duration(milliseconds: 1),
    );
    when(() => files.directoryChanges).thenAnswer((_) => changes.stream);
    when(() => files.openListing(any(), any(), any())).thenAnswer((call) async {
      final id = call.positionalArguments[0] as String;
      final location = call.positionalArguments[1] as Location;
      final listing = _list(
        location,
        call.positionalArguments[2] as ListingOptions,
      );
      listings[id] = location;
      return listing;
    });
    when(() => files.refreshListing(any())).thenAnswer((call) async {
      final id = call.positionalArguments[0] as String;
      return _list(listings[id]!, ListingOptions(showParent: true));
    });
    when(() => files.resortListing(any(), any())).thenAnswer((call) async {
      final id = call.positionalArguments[0] as String;
      return _list(
        listings[id]!,
        call.positionalArguments[1] as ListingOptions,
      );
    });
    when(() => files.closeListing(any())).thenAnswer((_) async {});
    when(() => files.isArchive(any())).thenReturn(false);
    when(() => files.isDirectory(any())).thenAnswer(
      (call) => folders.containsKey(call.positionalArguments[0] as String),
    );
    when(() => files.stat(any())).thenAnswer((call) async {
      final path = call.positionalArguments[0] as String;
      final entry = _entry(path);
      if (entry == null) throw FerryxException(FerryxErrorKind.notFound, path);
      return entry;
    });
    when(
      () => files.peek(any(), showHidden: any(named: 'showHidden')),
    ).thenAnswer((call) async {
      final location = call.positionalArguments[0] as Location;
      final hidden = call.namedArguments[#showHidden] as bool? ?? false;
      return [
        for (final row in folders[location.path] ?? const <FileEntry>[])
          if (hidden || !row.name.startsWith('.')) row,
      ];
    });
    when(() => files.standardFolders()).thenReturn(
      const StandardFolders(
        home: home,
        desktop: '$home/Desktop',
        documents: '$home/docs',
        downloads: '$home/Downloads',
        applications: '/Applications',
        utilities: '/Applications/Utilities',
        library: '$home/Library',
        root: '/',
        temporary: '/tmp',
        userName: 'me',
      ),
    );
    when(() => operations.progress).thenAnswer((_) => progress.stream);
    when(() => operations.current).thenReturn(const {});
    when(() => operations.forget(any())).thenAnswer((_) async {});
    when(() => operations.start(any())).thenAnswer((call) async {
      started.add(call.positionalArguments[0] as OperationRequest);
      return _nextOperation++;
    });
  }

  Future<void> tearDown() async {
    await frecency.dispose();
    await desktop.dispose();
    // Not awaited: a panel's cubit closes in the test's fake time, so its
    // listener may still be on the stream, and a broadcast close would
    // wait for it forever once a test changed a preference.
    unawaited(preferences.dispose());
    await changes.close();
    await progress.close();
  }

  ShortcutMap get shortcutMap =>
      ShortcutMap.forUser(platform, vimMotions: preferences.current.vimMode);

  /// Pumps the window, the left panel in [left], the right in [right].
  Future<void> pump(
    WidgetTester tester, {
    String left = '$home/docs',
    String right = '/tmp',
    Size size = const Size(1200, 800),
    Locale locale = const Locale('en'),
    double textScale = 1,
    Brightness brightness = Brightness.light,
    AppPlatformStyle style = AppPlatformStyle.macos,
    WindowDecor decor = WindowDecor.none,
    Map<AppCommand, VoidCallback> commandHandlers = const {},
    WorkspacePreview? preview,
    WorkspaceTerminal? terminal,
    ArchiverDiscovery? loadArchivers,
    ValueChanged<WorkspaceSnapshot>? onSnapshot,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final map = shortcutMap;
    SavedPanel saved(String path) => SavedPanel(
      tabs: [SavedTab(location: Location.native(path), layoutIndex: 2)],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light(style)
            : AppTheme.dark(style),
        locale: locale,
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: CommandShortcuts(
            shortcuts: map.toShortcuts(
              platform,
              scopes: const {CommandScope.global},
            ),
            child: CommandHandlers(
              handlers: commandHandlers,
              child: WindowDecorScope(
                decor: decor,
                child: RepaintBoundary(key: shotKey, child: child),
              ),
            ),
          ),
        ),
        home: WorkspaceScreen(
          files: files,
          operations: operations,
          rename: rename,
          preferences: preferences,
          logger: Logger(),
          shortcutMap: map,
          windowDecor: decor,
          platformServices: desktop,
          folderSync: _MockFolderSync(),
          preview: preview,
          terminal: terminal,
          loadArchivers: loadArchivers,
          navigation: WorkspaceNavigation(
            openViewer: (context, location, {preview = false}) async {},
            openFind: (context, root, {required view}) async => null,
            openSettings: (context) async {},
            openCheatSheet: (context) async {},
            openSync: (_, {required left, required right}) async {},
            openChecksums: (
              _, {
              required paths,
              required base,
              algorithm,
            }) async {},
            openDuplicates: (_, {required root, other}) async => null,
          ),
          savedLeft: saved(left),
          savedRight: saved(right),
          savedActive: PanelSide.left,
          fallbackLocation: const Location.native(home),
          onSnapshot: onSnapshot ?? (_) {},
          frecency: frecency,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Presses [key] with the modifiers asked for, as a Mac keyboard sends
  /// it.
  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool meta = false,
    bool shift = false,
    bool alt = false,
    bool control = false,
    String? character,
  }) async {
    final held = [
      if (meta) LogicalKeyboardKey.metaLeft,
      if (control) LogicalKeyboardKey.controlLeft,
      if (alt) LogicalKeyboardKey.altLeft,
      if (shift) LogicalKeyboardKey.shiftLeft,
    ];
    for (final modifier in held) {
      await tester.sendKeyDownEvent(modifier, platform: 'macos');
    }
    await tester.sendKeyEvent(key, platform: 'macos', character: character);
    for (final modifier in held.reversed) {
      await tester.sendKeyUpEvent(modifier, platform: 'macos');
    }
    await settle(tester);
  }

  /// Lets routes and notices finish moving, within a bound: a caret
  /// blinking in a field never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Types [text] key by key (letters and spaces), as the panel takes it.
  Future<void> type(WidgetTester tester, String text) async {
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final key = char == ' '
          ? LogicalKeyboardKey.space
          : LogicalKeyboardKey.findKeyByKeyId(
              LogicalKeyboardKey.keyA.keyId +
                  (char.toLowerCase().runes.first - 0x61),
            )!;
      await press(
        tester,
        key,
        shift: char != char.toLowerCase(),
        character: char,
      );
    }
  }
}

class _MockFolderSync extends Mock implements FolderSyncService {}
