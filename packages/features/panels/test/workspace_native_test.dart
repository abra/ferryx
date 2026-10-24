import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';
import 'package:operations_service/operations_service.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/native/drag_image.dart';
import 'package:panels_feature/src/native/drop_plan.dart';
import 'package:panels_feature/src/panel/rows_brief.dart';
import 'package:platform_services/platform_services.dart';
import 'package:platform_services/testing.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

class _Files extends Mock implements FileRepository {}

class _Operations extends Mock implements OperationsService {}

/// The window's side of Quick Look, the share picker and drag and drop,
/// against a fake desktop: what it asks for, and what it does with what
/// the desktop tells it.
void main() {
  const platform = TargetPlatform.macOS;
  const home = Location.native('/home');
  const other = Location.native('/other');
  const zip = Location.inArchive(archive: '/home/a.zip');
  final en = lookupFerryxLocalizations(const Locale('en'));

  late _Files files;
  late _Operations operations;
  late PreferencesService preferences;
  late FolderFrecency frecency;
  late FakePlatformServices desktop;
  late StreamController<String> changes;
  late List<OperationRequest> started;
  late List<Location> viewed;
  late Map<String, int?> volumes;

  FileEntry entry(
    String folder,
    String name, {
    bool dir = false,
    bool parent = false,
    int? size,
  }) => FileEntry(
    name: name,
    // An archive's members go by their path inside it.
    path: parent ? folder : (folder.isEmpty ? name : '$folder/$name'),
    kind: dir ? EntryKind.directory : EntryKind.file,
    isDir: dir,
    isParent: parent,
    size: size,
    extension: name.contains('.') ? name.split('.').last : '',
  );

  Listing listingOf(Location location) => Listing(
    location: location,
    watched: true,
    entries: switch (location) {
      home => [
        entry('/', '..', dir: true, parent: true),
        entry('/home', 'docs', dir: true),
        entry('/home', 'a.txt', size: 1),
        entry('/home', 'b.txt', size: 1),
        entry('/home', 'c.txt', size: 1),
      ],
      zip => [
        entry('/home', '..', dir: true, parent: true),
        entry('', 'inner', dir: true),
        entry('', 'm.txt', size: 10),
        entry('', 'big.bin', size: 100 << 20),
      ],
      _ => [
        entry('/', '..', dir: true, parent: true),
        entry('/other', 'x.txt', size: 1),
      ],
    },
  );

  setUpAll(() {
    registerFallbackValue(home);
    registerFallbackValue(const ListingOptions());
    registerFallbackValue(
      const OperationRequest(kind: OpKind.copy, sources: []),
    );
  });

  setUp(() async {
    files = _Files();
    operations = _Operations();
    desktop = FakePlatformServices();
    started = [];
    viewed = [];
    volumes = {'/home': 1, '/home/docs': 1, '/other': 1};
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    frecency = await FolderFrecency.load(InMemorySideStorage());
    final listings = <String, Location>{};
    changes = StreamController<String>.broadcast();
    when(() => files.directoryChanges).thenAnswer((_) => changes.stream);
    when(() => files.openListing(any(), any(), any())).thenAnswer((call) async {
      final location = call.positionalArguments[1] as Location;
      listings[call.positionalArguments[0] as String] = location;
      return listingOf(location);
    });
    when(() => files.refreshListing(any())).thenAnswer(
      (call) async => listingOf(listings[call.positionalArguments[0]]!),
    );
    when(() => files.resortListing(any(), any())).thenAnswer(
      (call) async => listingOf(listings[call.positionalArguments[0]]!),
    );
    when(() => files.closeListing(any())).thenAnswer((_) async {});
    when(() => files.isArchive(any())).thenReturn(false);
    when(() => files.volumeOf(any())).thenAnswer(
      (call) => volumes[call.positionalArguments[0]],
    );
    when(() => files.extractToTemp(any(), any())).thenAnswer(
      (call) async => '/tmp/x/${call.positionalArguments[1]}',
    );
    when(
      () => operations.progress,
    ).thenAnswer((_) => const Stream<OperationProgress>.empty());
    when(() => operations.current).thenReturn(const {});
    when(() => operations.start(any())).thenAnswer((call) async {
      started.add(call.positionalArguments.first as OperationRequest);
      return started.length;
    });
  });

  tearDown(() async {
    await desktop.dispose();
    await changes.close();
    await frecency.dispose();
    await preferences.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    Location left = home,
    Location right = other,
    Set<AppCommand> unavailable = const {},
  }) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final map = ShortcutMap.forUser(platform, unavailable: unavailable);
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
            folderSync: _MockFolderSync(),
            navigation: WorkspaceNavigation(
              openViewer: (context, location, {preview = false}) async =>
                  viewed.add(location),
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
            savedLeft: SavedPanel(tabs: [SavedTab(location: left)]),
            savedRight: SavedPanel(tabs: [SavedTab(location: right)]),
            savedActive: PanelSide.left,
            fallbackLocation: home,
            onSnapshot: (_) {},
            frecency: frecency,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> key(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool meta = false,
    bool shift = false,
    bool control = false,
  }) async {
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    if (control) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.sendKeyEvent(key);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  Future<void> down(WidgetTester tester, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
  }

  Future<void> quickLook(WidgetTester tester) =>
      key(tester, LogicalKeyboardKey.keyY, meta: true);

  /// A row's name in the panel on [side] (the footer names the focused
  /// row too).
  Finder rowNamed(String name, {int side = 0}) => find.descendant(
    of: find.byType(RowsBrief).at(side),
    matching: find.text(name),
  );

  const homeItems = ['/home/docs', '/home/a.txt', '/home/b.txt', '/home/c.txt'];

  group('Quick Look', () {
    testWidgets("⌘Y opens on the folder's items at the cursor and follows "
        'the cursor; Space closes it, not the preview', (tester) async {
      await pump(tester);
      await down(tester, 2);
      await quickLook(tester);
      expect(desktop.quickLooks, [QuickLookItems(homeItems, index: 1)]);

      await down(tester);
      expect(desktop.selections, [2]);
      expect(desktop.quickLooks, hasLength(1), reason: 'not sent again');
      await key(tester, LogicalKeyboardKey.arrowUp);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(desktop.selections, [2, 1, 0]);

      await key(tester, LogicalKeyboardKey.space);
      expect(desktop.quickLookOpen.value, isFalse);
      expect(desktop.closes, 1);
      expect(viewed, isEmpty);
      // Closed, it follows no more; Space is the preview again.
      await down(tester);
      expect(desktop.selections, [2, 1, 0]);
      await down(tester);
      await key(tester, LogicalKeyboardKey.space);
      expect(viewed, [home.join('b.txt')]);
    });

    testWidgets('a folder read again with the same items is not sent '
        'again; one with another item is', (tester) async {
      await pump(tester);
      await down(tester, 2);
      await quickLook(tester);
      expect(desktop.quickLooks, hasLength(1));
      // A size changed: the same paths.
      changes.add('left-1');
      await tester.pumpAndSettle();
      expect(desktop.quickLooks, hasLength(1));
      expect(desktop.selections, isEmpty);
      when(() => files.refreshListing(any())).thenAnswer(
        (_) async => listingOf(home).copyWith(
          entries: [...listingOf(home).entries, entry('/home', 'd.txt')],
        ),
      );
      changes.add('left-1');
      await tester.pumpAndSettle();
      expect(
        desktop.quickLooks.last,
        QuickLookItems([...homeItems, '/home/d.txt'], index: 1),
      );
    });

    testWidgets('⌘Y again and Esc close it; the panel keeps the keys', (
      tester,
    ) async {
      await pump(tester);
      await down(tester, 2);
      await quickLook(tester);
      await quickLook(tester);
      expect(desktop.quickLookOpen.value, isFalse);
      await quickLook(tester);
      expect(desktop.quickLookOpen.value, isTrue);
      await key(tester, LogicalKeyboardKey.escape);
      expect(desktop.quickLookOpen.value, isFalse);
      expect(desktop.closes, 2);
      await down(tester);
      await quickLook(tester);
      expect(desktop.quickLooks.last.index, 2);
    });

    testWidgets('↓ and ↑ on the panel move the cursor; its own close stops '
        'the following', (tester) async {
      await pump(tester);
      await down(tester);
      await quickLook(tester);
      expect(desktop.quickLooks.single.index, 0);
      desktop.userStepsQuickLook(1);
      await tester.pumpAndSettle();
      desktop.userStepsQuickLook(1);
      await tester.pumpAndSettle();
      expect(desktop.selections, [1, 2]);
      desktop.userClosesQuickLook();
      await tester.pumpAndSettle();
      await down(tester);
      expect(desktop.selections, [1, 2]);
      expect(desktop.closes, 0, reason: 'the desktop closed it');
    });

    testWidgets('several selected: the selection, at the cursor in it', (
      tester,
    ) async {
      await pump(tester);
      await down(tester, 2);
      await key(tester, LogicalKeyboardKey.insert); // a.txt, on to b.txt
      await down(tester);
      // c.txt, the last row: the cursor stays on it.
      await key(tester, LogicalKeyboardKey.insert);
      await quickLook(tester);
      expect(
        desktop.quickLooks.single,
        QuickLookItems(const ['/home/a.txt', '/home/c.txt'], index: 1),
      );
      // b.txt is not in the selection: the panel stays where it is.
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(desktop.selections, isEmpty);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(desktop.selections, [0]);
    });

    testWidgets('the keys moving to the other panel take Quick Look along', (
      tester,
    ) async {
      await pump(tester);
      await down(tester, 2);
      await quickLook(tester);
      await key(tester, LogicalKeyboardKey.tab);
      expect(
        desktop.quickLooks.last,
        QuickLookItems(const ['/other/x.txt'], index: 0),
      );
    });

    testWidgets('inside an archive the file is taken out first; a large one '
        'gets a notice', (tester) async {
      await pump(tester, left: zip);
      await down(tester, 2);
      await quickLook(tester);
      verify(() => files.extractToTemp('/home/a.zip', 'm.txt')).called(1);
      expect(desktop.quickLooks.single.paths, ['/tmp/x/m.txt']);
      // On to the large one: not taken out, the panel keeps m.txt.
      await down(tester);
      verifyNever(() => files.extractToTemp('/home/a.zip', 'big.bin'));
      expect(desktop.quickLooks, hasLength(1));
      await quickLook(tester);
      await quickLook(tester);
      expect(find.text(en.quickLookTooLarge('big.bin')), findsOneWidget);
    });

    testWidgets('an empty pick says so', (tester) async {
      await pump(tester, left: zip);
      await down(tester); // the folder "inner"
      await quickLook(tester);
      expect(desktop.quickLooks, isEmpty);
      expect(find.text(en.quickLookNothing), findsOneWidget);
    });
  });

  group('Share', () {
    testWidgets('⇧⌘S shares the targets, pointing at the cursor row', (
      tester,
    ) async {
      await pump(tester);
      await down(tester, 3);
      await key(tester, LogicalKeyboardKey.keyS, meta: true, shift: true);
      final share = desktop.shares.single;
      expect(share.paths, ['/home/b.txt']);
      final row = tester.getRect(rowNamed('b.txt'));
      expect(share.anchor.top, closeTo(row.top, 4));
      expect(share.anchor.bottom, closeTo(row.bottom, 4));
    });

    testWidgets("the row menu's Share… points where the menu opened", (
      tester,
    ) async {
      await pump(tester);
      final row = tester.getCenter(rowNamed('c.txt'));
      await tester.tapAt(row, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text(en.cmdQuickLook), findsOneWidget);
      await tester.tap(find.text(en.cmdShare));
      await tester.pumpAndSettle();
      final share = desktop.shares.single;
      expect(share.paths, ['/home/c.txt']);
      expect(share.anchor.topLeft, row);
    });

    testWidgets('inside an archive the files are taken out to share', (
      tester,
    ) async {
      await pump(tester, left: zip);
      await down(tester, 2);
      await key(tester, LogicalKeyboardKey.keyS, meta: true, shift: true);
      expect(desktop.shares.single.paths, ['/tmp/x/m.txt']);
    });

    testWidgets('without the capabilities the commands are nowhere', (
      tester,
    ) async {
      await pump(
        tester,
        unavailable: const {AppCommand.quickLook, AppCommand.share},
      );
      await down(tester, 2);
      await key(tester, LogicalKeyboardKey.keyS, meta: true, shift: true);
      await quickLook(tester);
      expect(desktop.shares, isEmpty);
      expect(desktop.quickLooks, isEmpty);
      await key(tester, LogicalKeyboardKey.enter, control: true);
      expect(find.text(en.cmdOpenWith), findsOneWidget, reason: 'the menu');
      expect(find.text(en.cmdShare), findsNothing);
      expect(find.text(en.cmdQuickLook), findsNothing);
    });
  });

  group('Dragging rows out', () {
    Future<TestGesture> press(WidgetTester tester, Offset at) =>
        tester.startGesture(
          at,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );

    testWidgets('starts past the threshold with the row under the pointer; '
        'the cursor moves there', (tester) async {
      await pump(tester);
      final gesture = await press(tester, tester.getCenter(rowNamed('b.txt')));
      await gesture.moveBy(const Offset(3, 0));
      await tester.pump();
      expect(desktop.drags, isEmpty, reason: 'within the threshold');
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final drag = desktop.drags.single;
      expect(drag.paths, ['/home/b.txt']);
      expect(drag.itemCount, 1);
      expect(drag.allowed, {FileDropOperation.copy, FileDropOperation.move});
      expect((drag.image as FileDragImage).entry.name, 'b.txt');
      final payload = PanelDragPayload.decode(drag.local)!;
      expect(payload.folder, home);
      expect(payload.side, PanelSide.left);
      // The cursor is on b.txt now: Quick Look opens there.
      await quickLook(tester);
      expect(desktop.quickLooks.single.index, 2);
    });

    testWidgets('a selected row takes the whole selection along', (
      tester,
    ) async {
      await pump(tester);
      await down(tester, 2);
      await key(tester, LogicalKeyboardKey.insert);
      await down(tester);
      await key(tester, LogicalKeyboardKey.insert);
      final gesture = await press(tester, tester.getCenter(rowNamed('c.txt')));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final drag = desktop.drags.single;
      expect(drag.paths, ['/home/a.txt', '/home/c.txt']);
      expect((drag.image as FileDragImage).count, 2);
    });

    testWidgets('a click with ⌘ that wobbles stays a click', (tester) async {
      await pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      for (final name in ['a.txt', 'c.txt']) {
        final gesture = await press(tester, tester.getCenter(rowNamed(name)));
        await gesture.moveBy(const Offset(2, 1));
        await gesture.up();
        // The row's tap waits out a double tap's chance.
        await tester.pump(kDoubleTapTimeout * 2);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(desktop.drags, isEmpty);
      // Both clicks selected their rows, as clicks with ⌘ do.
      await quickLook(tester);
      expect(desktop.quickLooks.single.paths, ['/home/a.txt', '/home/c.txt']);
    });

    testWidgets('`..` never drags', (tester) async {
      await pump(tester);
      final gesture = await press(tester, tester.getCenter(rowNamed('..')));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(desktop.drags, isEmpty);
    });

    testWidgets("an archive's members are only copied out, and only here", (
      tester,
    ) async {
      await pump(tester, left: zip);
      final gesture = await press(tester, tester.getCenter(rowNamed('m.txt')));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      final drag = desktop.drags.single;
      expect(drag.paths, isEmpty, reason: 'no file on disk to give away');
      expect(drag.allowed, {FileDropOperation.copy});
      expect(PanelDragPayload.decode(drag.local)!.paths, ['m.txt']);
    });
  });

  group('Dropping files', () {
    FileDropTarget targetAt(WidgetTester tester, Offset at) =>
        FileDropTarget.at(tester.element(find.byType(WorkspaceScreen)), at)!;

    FileDragInfo fromApp(
      List<String> paths, {
      Set<FileDropOperation> allowed = const {
        FileDropOperation.copy,
        FileDropOperation.move,
      },
    }) => FileDragInfo(allowed: allowed, paths: paths, itemCount: paths.length);

    RowsBrief rows(WidgetTester tester, int side) =>
        tester.widget<RowsBrief>(find.byType(RowsBrief).at(side));

    testWidgets('a folder row lights up and takes the files: a move on one '
        'volume', (tester) async {
      await pump(tester);
      final target = targetAt(tester, tester.getCenter(rowNamed('docs')));
      final drag = fromApp(['/other/x.txt']);
      expect(target.onOver(drag), FileDropOperation.move);
      await tester.pump();
      expect(rows(tester, 0).dropRow, 'docs');

      target.onDrop(drag, FileDropOperation.move);
      await tester.pumpAndSettle();
      expect(rows(tester, 0).dropRow, isNull);
      expect(started.single.kind, OpKind.move);
      expect(started.single.sources, ['/other/x.txt']);
      expect(started.single.destination, '/home/docs');
    });

    testWidgets('across volumes a copy; ⌥ (copy alone) wins over one volume', (
      tester,
    ) async {
      volumes['/Volumes/USB'] = 2;
      await pump(tester);
      final target = targetAt(tester, tester.getCenter(rowNamed('docs')));
      expect(
        target.onOver(fromApp(['/Volumes/USB/a.jpg'])),
        FileDropOperation.copy,
      );
      expect(
        target.onOver(
          fromApp(['/other/x.txt'], allowed: {FileDropOperation.copy}),
        ),
        FileDropOperation.copy,
      );
      target.onDrop(
        fromApp(['/Volumes/USB/a.jpg']),
        FileDropOperation.copy,
      );
      await tester.pumpAndSettle();
      expect(started.single.kind, OpKind.copy);
    });

    testWidgets("the panel's own folder: the files of another panel go in, "
        'its own rows do nothing', (tester) async {
      await pump(tester);
      final below =
          tester.getBottomLeft(find.byType(RowsBrief).at(1)) +
          const Offset(200, -40);
      final target = targetAt(tester, below);
      final fromLeft = FileDragInfo(
        allowed: const {FileDropOperation.copy, FileDropOperation.move},
        local: PanelDragPayload(
          side: PanelSide.left,
          folder: home,
          paths: const ['/home/a.txt'],
        ).encode(),
      );
      expect(target.onOver(fromLeft), FileDropOperation.move);
      await tester.pump();
      expect(rows(tester, 1).dropRow, isNull, reason: 'the panel, not a row');
      final fromRight = FileDragInfo(
        allowed: const {FileDropOperation.copy, FileDropOperation.move},
        local: PanelDragPayload(
          side: PanelSide.right,
          folder: other,
          paths: const ['/other/x.txt'],
        ).encode(),
      );
      expect(target.onOver(fromRight), FileDropOperation.none);
      target.onLeave();
      target.onDrop(fromLeft, FileDropOperation.move);
      await tester.pumpAndSettle();
      expect(started.single.destination, '/other');
    });

    testWidgets('a dragged selection lets go once dropped, as after F6', (
      tester,
    ) async {
      await pump(tester);
      await down(tester, 2);
      await key(tester, LogicalKeyboardKey.insert);
      await key(tester, LogicalKeyboardKey.insert);
      final target = targetAt(
        tester,
        tester.getCenter(rowNamed('x.txt', side: 1)),
      );
      final drag = FileDragInfo(
        allowed: const {FileDropOperation.copy, FileDropOperation.move},
        local: PanelDragPayload(
          side: PanelSide.left,
          folder: home,
          paths: const ['/home/a.txt', '/home/b.txt'],
        ).encode(),
      );
      target.onDrop(drag, target.onOver(drag));
      await tester.pumpAndSettle();
      expect(started.single.sources, ['/home/a.txt', '/home/b.txt']);
      await quickLook(tester);
      expect(
        desktop.quickLooks.single.paths,
        homeItems,
        reason: 'no selection left: the folder',
      );
    });

    testWidgets("an archive's members are extracted where they are dropped", (
      tester,
    ) async {
      await pump(tester, right: zip);
      final target = targetAt(tester, tester.getCenter(rowNamed('docs')));
      final drag = FileDragInfo(
        allowed: const {FileDropOperation.copy},
        local: PanelDragPayload(
          side: PanelSide.right,
          folder: zip,
          paths: const ['m.txt'],
        ).encode(),
      );
      expect(target.onOver(drag), FileDropOperation.copy);
      target.onDrop(drag, FileDropOperation.copy);
      await tester.pumpAndSettle();
      final request = started.single;
      expect(request.kind, OpKind.extract);
      expect(request.archive, '/home/a.zip');
      expect(request.sources, ['m.txt']);
      expect(request.destination, '/home/docs');
    });

    testWidgets('an archive refuses drops and stays dark', (tester) async {
      await pump(tester, right: zip);
      final target = targetAt(
        tester,
        tester.getCenter(rowNamed('m.txt', side: 1)),
      );
      expect(
        target.onOver(fromApp(['/other/x.txt'])),
        FileDropOperation.forbidden,
      );
      await tester.pump();
      expect(rows(tester, 1).dropRow, isNull);
      // `..` of the archive's root is the folder it is in: that one takes
      // them.
      final parent = targetAt(
        tester,
        tester.getCenter(rowNamed('..', side: 1)),
      );
      expect(parent.onOver(fromApp(['/other/x.txt'])), FileDropOperation.move);
    });

    testWidgets('a folder dropped into itself is refused with a notice', (
      tester,
    ) async {
      await pump(tester);
      final target = targetAt(tester, tester.getCenter(rowNamed('docs')));
      final drag = fromApp(['/home/docs']);
      expect(target.onOver(drag), FileDropOperation.forbidden);
      target.onDrop(drag, FileDropOperation.move);
      await tester.pumpAndSettle();
      expect(started, isEmpty);
      expect(find.text(en.dropIntoItself), findsOneWidget);
    });

    testWidgets('a drop that carries no files says so', (tester) async {
      await pump(tester);
      final target = targetAt(tester, tester.getCenter(rowNamed('docs')));
      target.onDrop(fromApp(const []), FileDropOperation.copy);
      await tester.pumpAndSettle();
      expect(started, isEmpty);
      expect(find.text(en.dropNoFiles), findsOneWidget);
    });

    testWidgets('without file drags the rows are neither sources nor targets', (
      tester,
    ) async {
      desktop = FakePlatformServices(capabilities: PlatformCapabilities.none);
      await pump(tester);
      expect(
        FileDropTarget.at(
          tester.element(find.byType(WorkspaceScreen)),
          tester.getCenter(rowNamed('docs')),
        ),
        isNull,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(rowNamed('a.txt')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(desktop.drags, isEmpty);
    });
  });

  test('the fake keeps what Quick Look shows', () async {
    final fake = FakePlatformServices();
    await fake.showQuickLook(QuickLookItems(const ['/a', '/b'], index: 1));
    await fake.selectQuickLookItem(0);
    expect(fake.shown, QuickLookItems(const ['/a', '/b']));
    await fake.closeQuickLook();
    expect(fake.shown, isNull);
    unawaited(fake.dispose());
  });
}

class _MockFolderSync extends Mock implements FolderSyncService {}
