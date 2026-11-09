import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';
import 'package:operations_service/operations_service.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:preferences_service/preferences_service.dart';

class _Files extends Mock implements FileRepository {}

class _Operations extends Mock implements OperationsService {}

class _CountedFile extends FileEntry {
  const _CountedFile({
    required super.name,
    required super.path,
    required this.onKeyRead,
  }) : super(kind: EntryKind.file, isDir: false);

  final void Function() onKeyRead;

  @override
  String get key {
    onKeyRead();
    return super.key;
  }
}

/// A file system of names per folder, listed as the core would: sorted by
/// the options, the `..` row first.
class _FakeFs {
  final folders = <String, List<FileEntry>>{};
  final opened = <String, (Location, ListingOptions)>{};

  FileEntry file(String dir, String name, {int size = 1}) => FileEntry(
    name: name,
    path: '$dir/$name',
    kind: EntryKind.file,
    isDir: false,
    size: size,
    extension: name.contains('.') ? name.split('.').last : '',
  );

  FileEntry dir(String parent, String name) => FileEntry(
    name: name,
    path: parent == '/' ? '/$name' : '$parent/$name',
    kind: EntryKind.directory,
    isDir: true,
  );

  Listing list(Location location, ListingOptions options) {
    final entries = folders[location.path];
    if (entries == null) {
      throw FerryxException(FerryxErrorKind.notFound, location.path);
    }
    final rows = [...entries]
      ..sort((a, b) {
        if (options.sort.foldersFirst && a.isDir != b.isDir) {
          return a.isDir ? -1 : 1;
        }
        final order = switch (options.sort.field) {
          SortField.size => (a.size ?? 0).compareTo(b.size ?? 0),
          _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        };
        final tie = order == 0
            ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
            : order;
        return options.sort.descending ? -tie : tie;
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
        ...rows,
      ],
      freeBytes: 1000,
      watched: true,
    );
  }
}

void main() {
  late _Files files;
  late _Operations operations;
  late PreferencesService preferences;
  late StreamController<String> changes;
  late _FakeFs fs;
  late PanelCubit cubit;

  const home = Location.native('/home');

  setUpAll(() {
    registerFallbackValue(home);
    registerFallbackValue(const ListingOptions());
    registerFallbackValue(
      const OperationRequest(kind: OpKind.calcSizes, sources: []),
    );
  });

  setUp(() async {
    files = _Files();
    operations = _Operations();
    changes = StreamController<String>.broadcast();
    fs = _FakeFs();
    fs.folders['/'] = [fs.dir('/', 'home')];
    fs.folders['/home'] = [
      fs.dir('/home', 'docs'),
      fs.file('/home', 'b.txt', size: 5),
      fs.file('/home', 'a.txt', size: 9),
      fs.file('/home', 'c.md', size: 2),
    ];
    fs.folders['/home/docs'] = [fs.file('/home/docs', 'x.txt')];
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    when(() => files.directoryChanges).thenAnswer((_) => changes.stream);
    when(() => files.openListing(any(), any(), any())).thenAnswer((inv) async {
      final id = inv.positionalArguments[0] as String;
      final location = inv.positionalArguments[1] as Location;
      final options = inv.positionalArguments[2] as ListingOptions;
      fs.opened[id] = (location, options);
      return fs.list(location, options);
    });
    when(() => files.refreshListing(any())).thenAnswer((inv) async {
      final id = inv.positionalArguments[0] as String;
      final (location, options) = fs.opened[id]!;
      return fs.list(location, options);
    });
    when(() => files.resortListing(any(), any())).thenAnswer((inv) async {
      final id = inv.positionalArguments[0] as String;
      final options = inv.positionalArguments[1] as ListingOptions;
      final (location, _) = fs.opened[id]!;
      fs.opened[id] = (location, options);
      return fs.list(location, options);
    });
    when(() => files.closeListing(any())).thenAnswer((_) async {});
    when(() => files.isArchive(any())).thenReturn(false);
    when(() => operations.progress).thenAnswer(
      (_) => const Stream<OperationProgress>.empty(),
    );
    when(() => operations.start(any())).thenAnswer((_) async => 1);
    cubit = PanelCubit(
      side: PanelSide.left,
      files: files,
      operations: operations,
      preferences: preferences,
      logger: Logger(),
    );
  });

  tearDown(() async {
    await cubit.close();
    await changes.close();
    await preferences.dispose();
  });

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<String> names() => [for (final r in cubit.state.active!.rows) r.name];

  test('start opens the saved tabs with the cursor on the first row', () async {
    await cubit.start(
      const SavedPanel(
        tabs: [
          SavedTab(location: home),
          SavedTab(location: Location.native('/')),
        ],
        activeIndex: 1,
      ),
      home,
    );
    expect(cubit.state.tabs.length, 2);
    expect(cubit.state.activeIndex, 1);
    expect(cubit.state.tabs[0].location, home);
    expect(cubit.state.tabs[0].rows.map((r) => r.name), [
      '..',
      'docs',
      'a.txt',
      'b.txt',
      'c.md',
    ]);
    expect(cubit.state.tabs[0].cursor, 0);
    expect(cubit.state.tabs[1].history, [const Location.native('/')]);
  });

  test('a folder that cannot be read falls back, then the root', () async {
    await cubit.start(
      const SavedPanel(tabs: [SavedTab(location: Location.native('/gone'))]),
      home,
    );
    expect(cubit.state.active!.location, home);
    expect(cubit.state.active!.error, isNull);
  });

  group('navigation', () {
    setUp(() => cubit.start(null, home));

    test(
      'open pushes history and goParent puts the cursor on the folder left',
      () async {
        await cubit.open(const Location.native('/home/docs'));
        final tab = cubit.state.active!;
        expect(tab.location, const Location.native('/home/docs'));
        expect(tab.history, [home, const Location.native('/home/docs')]);
        expect(tab.historyIndex, 1);
        await cubit.goParent();
        expect(cubit.state.active!.location, home);
        expect(cubit.state.active!.focused?.name, 'docs');
        expect(cubit.state.active!.history.length, 3);
      },
    );

    test('a folder entered starts on its first row, whatever row the cursor '
        'was on and whatever the folder holds', () async {
      fs.folders['/home/docs']!.add(fs.dir('/home/docs', 'docs'));
      cubit.moveCursorTo(1);
      expect(cubit.state.active!.focused?.name, 'docs');
      await cubit.enter();
      expect(cubit.state.active!.location, const Location.native('/home/docs'));
      expect(
        cubit.state.active!.cursor,
        0,
        reason: 'not on its own `docs`, nor on row 1 as before',
      );
      await cubit.goParent();
      cubit.moveCursorTo(4);
      await cubit.open(const Location.native('/home/docs'));
      expect(cubit.state.active!.cursor, 0, reason: 'nor clamped to row 4');
      // The same folder read again keeps the cursor on its row.
      cubit.moveCursorTo(1);
      final focused = cubit.state.active!.focused?.name;
      await cubit.refresh();
      expect(cubit.state.active!.focused?.name, focused);
    });

    test('goBack and goForward walk the history without growing it', () async {
      await cubit.open(const Location.native('/home/docs'));
      await cubit.goBack();
      expect(cubit.state.active!.location, home);
      expect(cubit.state.active!.canGoForward, isTrue);
      await cubit.goForward();
      expect(cubit.state.active!.location, const Location.native('/home/docs'));
      expect(cubit.state.active!.history.length, 2);
      await cubit.goForward();
      expect(cubit.state.active!.historyIndex, 1);
    });

    test(
      'enter opens a folder, answers a file to open, climbs on ..',
      () async {
        cubit.moveCursorTo(1);
        expect(await cubit.enter(), isNull);
        expect(
          cubit.state.active!.location,
          const Location.native('/home/docs'),
        );
        cubit.moveCursorTo(1);
        final request = await cubit.enter();
        expect(request, isNotNull);
        expect(request!.entry.name, 'x.txt');
        expect(request.location, const Location.native('/home/docs/x.txt'));
        cubit.moveCursorTo(0);
        expect(await cubit.enter(), isNull);
        expect(cubit.state.active!.location, home);
      },
    );

    test(
      'toggleSortField resorts through the repository and keeps the cursor',
      () async {
        cubit.moveCursorTo(3);
        expect(cubit.state.active!.focused?.name, 'b.txt');
        await cubit.toggleSortField(SortField.size);
        expect(names(), ['..', 'docs', 'a.txt', 'b.txt', 'c.md']);
        expect(cubit.state.active!.sort.field, SortField.size);
        expect(cubit.state.active!.sort.descending, isTrue);
        expect(cubit.state.active!.focused?.name, 'b.txt');
        await cubit.toggleSortField(SortField.size);
        expect(names(), ['..', 'docs', 'c.md', 'b.txt', 'a.txt']);
        expect(cubit.state.active!.focused?.name, 'b.txt');
        verify(() => files.resortListing('left-1', any())).called(2);
      },
    );
  });

  group('cursor and selection', () {
    setUp(() => cubit.start(null, home));

    test('moveCursor clamps to the rows', () {
      cubit.moveCursor(-5);
      expect(cubit.state.active!.cursor, 0);
      cubit.moveCursor(100);
      expect(cubit.state.active!.cursor, 4);
      cubit.moveFirst();
      expect(cubit.state.active!.cursor, 0);
      cubit.moveLast();
      expect(cubit.state.active!.cursor, 4);
    });

    test('a shift run selects from the row the cursor was on, never ..', () {
      cubit.moveCursor(1, selecting: true);
      expect(cubit.state.active!.selected, isEmpty);
      expect(cubit.state.active!.cursor, 1);
      expect(cubit.state.active!.rangeSelecting, isTrue);
      cubit.moveCursor(1, selecting: true);
      cubit.moveCursor(1, selecting: true);
      expect(cubit.state.active!.selected, {'docs', 'a.txt'});
      expect(cubit.state.active!.cursor, 3);
      cubit.moveCursor(-1);
      expect(cubit.state.active!.rangeSelecting, isNull);
      expect(cubit.state.active!.selected, {'docs', 'a.txt'});
      // From a selected row the run deselects.
      cubit.moveCursorTo(1);
      cubit.moveCursor(1, selecting: true);
      expect(cubit.state.active!.rangeSelecting, isFalse);
      expect(cubit.state.active!.selected, {'a.txt'});
    });

    test('a range to the end takes every row up to the target', () {
      cubit.moveCursorTo(2);
      cubit.moveLast(selecting: true);
      expect(cubit.state.active!.selected, {'a.txt', 'b.txt'});
      expect(cubit.state.active!.cursor, 4);
    });

    test('a click with the modifier flips one row and moves the cursor', () {
      cubit.clickRow(2, toggle: true);
      expect(cubit.state.active!.selected, {'a.txt'});
      expect(cubit.state.active!.cursor, 2);
      cubit.clickRow(2, toggle: true);
      expect(cubit.state.active!.selected, isEmpty);
      cubit.clickRow(0, toggle: true);
      expect(cubit.state.active!.selected, isEmpty);
      cubit.clickRow(3);
      expect(cubit.state.active!.cursor, 3);
      expect(cubit.state.active!.selected, isEmpty);
    });

    test('a shift click takes the rows between the cursor and the click', () {
      cubit.moveCursorTo(1);
      cubit.clickRow(3, range: true);
      expect(cubit.state.active!.selected, {'docs', 'a.txt', 'b.txt'});
      expect(cubit.state.active!.rangeSelecting, isNull);
    });

    test('toggleSelectionAndMoveDown marks the row and steps', () {
      cubit.moveCursorTo(1);
      cubit.toggleSelectionAndMoveDown();
      expect(cubit.state.active!.selected, {'docs'});
      expect(cubit.state.active!.cursor, 2);
      cubit.toggleSelection();
      expect(cubit.state.active!.selected, {'docs', 'a.txt'});
    });

    test('selectAll, invert, by mask and by extension', () {
      cubit.selectAll();
      expect(cubit.state.active!.selected, {'docs', 'a.txt', 'b.txt', 'c.md'});
      cubit.invertSelection();
      expect(cubit.state.active!.selected, isEmpty);
      cubit.selectWhere((r) => r.name.endsWith('.txt'), select: true);
      expect(cubit.state.active!.selected, {'a.txt', 'b.txt'});
      cubit.moveCursorTo(2);
      cubit.selectByExtension(select: false);
      expect(cubit.state.active!.selected, isEmpty);
      cubit.moveCursorTo(4);
      cubit.selectByExtension(select: true);
      expect(cubit.state.active!.selected, {'c.md'});
      cubit.deselectAll();
      expect(cubit.state.active!.selected, isEmpty);
      expect(cubit.state.active!.targets.map((t) => t.name), ['c.md']);
    });
  });

  group('quick search', () {
    setUp(() => cubit.start(null, home));

    test('typing moves the cursor to the first match and underlines it', () {
      cubit.quickSearchType('b');
      final tab = cubit.state.active!;
      expect(tab.quickSearch, 'b');
      expect(tab.focused?.name, 'b.txt');
      expect(tab.matches, {
        'b.txt': [(0, 1)],
      });
      expect(names().length, 5);
      cubit.quickSearchType('.');
      expect(cubit.state.active!.matches.keys, ['b.txt']);
      cubit.quickSearchBackspace();
      expect(cubit.state.active!.quickSearch, 'b');
      cubit.clearQuickSearch();
      expect(cubit.state.active!.quickSearch, isEmpty);
      expect(cubit.state.active!.matches, isEmpty);
    });

    test('a query typed on tries only the last matches; after a refresh or '
        'with a shorter query every row is tried again', () async {
      cubit.quickSearchType('t');
      expect(
        cubit.state.active!.matches.keys,
        unorderedEquals(['a.txt', 'b.txt']),
      );
      // A new file comes in while the search is on.
      fs.folders['/home']!.add(fs.file('/home', 'tt.md'));
      changes.add('left-1');
      await settle();
      expect(
        cubit.state.active!.matches.keys,
        unorderedEquals(['a.txt', 'b.txt', 'tt.md']),
      );
      cubit.quickSearchType('t');
      expect(cubit.state.active!.matches.keys, ['tt.md']);
      cubit.quickSearchBackspace();
      expect(
        cubit.state.active!.matches.keys,
        unorderedEquals(['a.txt', 'b.txt', 'tt.md']),
      );
    });

    test('with only matching rows shown the rows shrink', () async {
      await preferences.update(
        (p) => p.copyWith(quickSearchOnlyMatching: true),
      );
      await settle();
      cubit.quickSearchType('txt');
      expect(names(), ['..', 'a.txt', 'b.txt']);
      expect(cubit.state.active!.focused?.name, 'a.txt');
      cubit.clearQuickSearch();
      expect(names().length, 5);
    });
  });

  group('tabs', () {
    setUp(() => cubit.start(null, home));

    test('newTab opens after the active one and shows it', () async {
      await cubit.newTab(location: const Location.native('/home/docs'));
      expect(cubit.state.tabs.length, 2);
      expect(cubit.state.activeIndex, 1);
      expect(cubit.state.active!.location, const Location.native('/home/docs'));
      cubit.showTab(0);
      await cubit.newTab();
      expect(cubit.state.tabs.map((t) => t.location.path), [
        '/home',
        '/home',
        '/home/docs',
      ]);
      expect(cubit.state.activeIndex, 1);
    });

    test('closeTab keeps the last tab and remembers what closed', () async {
      await cubit.closeTab();
      expect(cubit.state.tabs.length, 1);
      await cubit.newTab(location: const Location.native('/home/docs'));
      final closedId = cubit.state.active!.id;
      await cubit.closeTab();
      expect(cubit.state.tabs.length, 1);
      expect(cubit.state.activeIndex, 0);
      expect(cubit.state.closedTabs, [const Location.native('/home/docs')]);
      verify(() => files.closeListing(closedId)).called(1);
      await cubit.reopenClosedTab();
      expect(cubit.state.closedTabs, isEmpty);
      expect(cubit.state.active!.location, const Location.native('/home/docs'));
    });

    test('next, previous and moveTab keep the active tab', () async {
      await cubit.newTab(location: const Location.native('/home/docs'));
      await cubit.newTab(location: const Location.native('/'));
      expect(cubit.state.activeIndex, 2);
      cubit.nextTab();
      expect(cubit.state.activeIndex, 0);
      cubit.previousTab();
      expect(cubit.state.activeIndex, 2);
      final activeId = cubit.state.active!.id;
      cubit.moveTab(2, 0);
      expect(cubit.state.activeIndex, 0);
      expect(cubit.state.active!.id, activeId);
      expect(cubit.state.tabs.map((t) => t.location.path), [
        '/',
        '/home',
        '/home/docs',
      ]);
    });

    test('a folder that changes under a tab not shown is read once the '
        'tab shows, not on every change', () async {
      final first = cubit.state.active!.id;
      await cubit.newTab(location: const Location.native('/home/docs'));
      clearInteractions(files);
      fs.folders['/home']!.add(fs.file('/home', 'new.txt'));
      changes
        ..add(first)
        ..add(first);
      await settle();
      verifyNever(() => files.refreshListing(any()));
      cubit.showTab(0);
      await settle();
      verify(() => files.refreshListing(first)).called(1);
      expect(cubit.state.active!.rows.map((e) => e.name), contains('new.txt'));
      cubit.showTab(1);
      cubit.showTab(0);
      await settle();
      verifyNever(() => files.refreshListing(any()));
    });

    test('changes during a read again read once more after it, not once '
        'each', () async {
      final id = cubit.state.active!.id;
      final gate = Completer<void>();
      var reads = 0;
      when(() => files.refreshListing(any())).thenAnswer((inv) async {
        reads++;
        if (reads == 1) await gate.future;
        final (location, options) = fs.opened[id]!;
        return fs.list(location, options);
      });
      changes.add(id);
      await settle();
      fs.folders['/home']!.add(fs.file('/home', 'late.txt'));
      changes
        ..add(id)
        ..add(id)
        ..add(id);
      await settle();
      expect(reads, 1);
      gate.complete();
      await settle();
      expect(reads, 2);
      expect(cubit.state.active!.rows.map((e) => e.name), contains('late.txt'));
      // Done: the next change reads again at once.
      changes.add(id);
      await settle();
      expect(reads, 3);
    });

    test('saved round-trips through SavedPanel', () async {
      await cubit.newTab(location: const Location.native('/home/docs'));
      await cubit.toggleSortField(SortField.size);
      cubit.setLayout(3);
      await cubit.closeTab(0);
      final saved = SavedPanel.decode(cubit.saved().encode())!;
      expect(saved.tabs.map((t) => t.location), [
        const Location.native('/home/docs'),
      ]);
      expect(saved.tabs.first.sort.field, SortField.size);
      expect(saved.tabs.first.layoutIndex, 3);
      expect(saved.activeIndex, 0);
      expect(saved.closedTabs, [home]);
    });
  });

  group('vim', () {
    // `..`, docs, a.txt, ab.txt, b.txt, c.md
    setUp(() {
      fs.folders['/home']!.add(fs.file('/home', 'ab.txt'));
      return cubit.start(null, home);
    });

    test('visual mode grows and shrinks the selection with the cursor', () {
      cubit.moveCursorTo(1);
      cubit.toggleVisual();
      expect(cubit.state.active!.visual, isTrue);
      expect(cubit.state.active!.selected, {'docs'});
      cubit.moveCursor(2);
      expect(cubit.state.active!.selected, {'docs', 'a.txt', 'ab.txt'});
      cubit.moveCursor(-1);
      expect(cubit.state.active!.selected, {'docs', 'a.txt'});
      // Back past the anchor: the rows the other way.
      cubit.moveCursorTo(0);
      expect(cubit.state.active!.selected, {'docs'});
      cubit.moveCursorTo(2);
      cubit.endVisual();
      expect(cubit.state.active!.visual, isFalse);
      expect(cubit.state.active!.selected, {'docs', 'a.txt'});
      cubit.moveCursor(1);
      expect(cubit.state.active!.selected, {'docs', 'a.txt'});
    });

    test('visual mode selects over what was selected before', () {
      cubit.clickRow(5, toggle: true);
      cubit.moveCursorTo(1);
      cubit.toggleVisual();
      cubit.moveCursor(1);
      expect(cubit.state.active!.selected, {'c.md', 'docs', 'a.txt'});
      cubit.toggleVisual();
      expect(cubit.state.active!.visual, isFalse);
    });

    test('gv brings back the selection last cleared', () {
      cubit.clickRow(2, toggle: true);
      cubit.clickRow(4, toggle: true);
      cubit.deselectAll();
      expect(cubit.state.active!.selected, isEmpty);
      expect(cubit.state.active!.lastSelection, {'a.txt', 'b.txt'});
      cubit.reselectLast();
      expect(cubit.state.active!.selected, {'a.txt', 'b.txt'});
    });

    test(
      'gv survives navigation and restores only names in the current folder',
      () async {
        cubit.clickRow(2, toggle: true);
        cubit.clickRow(4, toggle: true);
        expect(cubit.state.active!.selectedBytes, 14);
        cubit.deselectAll();
        fs.folders['/home/docs'] = [fs.file('/home/docs', 'a.txt', size: 20)];
        await cubit.open(const Location.native('/home/docs'));
        expect(cubit.state.active!.lastSelection, {'a.txt', 'b.txt'});
        cubit.reselectLast();
        expect(cubit.state.active!.selected, {'a.txt'});
        expect(cubit.state.active!.selectedBytes, 20);
      },
    );

    test('the search prompt keeps its matches for n and N', () {
      cubit.searchOpen();
      expect(cubit.state.active!.searching, isTrue);
      cubit.quickSearchType('a');
      expect(cubit.state.active!.focused?.name, 'a.txt');
      cubit.searchConfirm();
      expect(cubit.state.active!.searching, isFalse);
      expect(cubit.state.active!.matches.keys, ['a.txt', 'ab.txt']);
      cubit.searchStep(forward: true);
      expect(cubit.state.active!.cursor, 3);
      cubit.searchStep(forward: true);
      expect(cubit.state.active!.cursor, 2);
      cubit.searchStep(forward: false);
      expect(cubit.state.active!.cursor, 3);
      cubit.searchStep(forward: false, count: 2);
      expect(cubit.state.active!.cursor, 3);
      cubit.searchOpen();
      cubit.searchCancel();
      expect(cubit.state.active!.searching, isFalse);
      expect(cubit.state.active!.quickSearch, isEmpty);
      expect(cubit.state.active!.matches, isEmpty);
    });

    test('search counts wrap from matched and unmatched cursor rows', () {
      cubit.quickSearchType('a');
      for (final (cursor, forward, count, expected) in [
        (2, true, 4, 2),
        (3, true, 9999, 2),
        (2, false, 9999, 3),
        (4, true, 2, 3),
        (1, false, 2, 2),
        (0, false, 1, 3),
        (5, true, 1, 2),
        (4, false, 1, 3),
      ]) {
        cubit.moveCursorTo(cursor);
        cubit.searchStep(forward: forward, count: count);
        expect(
          cubit.state.active!.cursor,
          expected,
          reason: 'cursor=$cursor forward=$forward count=$count',
        );
      }
      for (final count in [0, -1]) {
        final before = cubit.state;
        cubit.searchStep(forward: true, count: count);
        expect(cubit.state, same(before));
      }
    });

    test(
      'search counts scan at most once; nearby matches keep short scans',
      () async {
        const length = 20000;
        var reads = 0;
        var checking = false;
        fs.folders['/home'] = [
          for (var i = 0; i < length; i++)
            _CountedFile(
              name: i == length ~/ 2 ? 'match' : 'file-$i',
              path: '/home/$i',
              onKeyRead: () {
                if (!checking) return;
                if (++reads > length * 2) {
                  throw StateError('search count repeated the listing scan');
                }
              },
            ),
        ];
        await cubit.refresh();
        cubit.quickSearchType('match');
        final cursor = cubit.state.active!.cursor;
        checking = true;
        for (final forward in [true, false]) {
          reads = 0;
          cubit.searchStep(forward: forward, count: 9999);
          expect(cubit.state.active!.cursor, cursor);
          expect(reads, lessThanOrEqualTo(length));
        }
        checking = false;
        cubit.clearQuickSearch();
        cubit.quickSearchType('file');
        reads = 0;
        checking = true;
        final before = cubit.state.active!.cursor;
        cubit.searchStep(forward: true);
        expect(cubit.state.active!.cursor, before + 1);
        expect(reads, 1);
      },
    );

    test('f and F find the row whose name starts with the letter', () {
      cubit.findRowStartingWith('b', forward: true);
      expect(cubit.state.active!.cursor, 4);
      cubit.findRowStartingWith('a', forward: false);
      expect(cubit.state.active!.cursor, 3);
      cubit.findRowStartingWith('z', forward: true);
      expect(cubit.state.active!.cursor, 3);
      cubit.moveCursorTo(4);
      cubit.findRowStartingWith('A', forward: false, count: 2);
      expect(cubit.state.active!.cursor, 2);
      // A count past the last match goes nowhere.
      cubit.findRowStartingWith('a', forward: false, count: 5);
      expect(cubit.state.active!.cursor, 2);
    });

    test('H, M and L go by what the view reports', () {
      cubit.geometry = const PanelGeometry(rowsPerPage: 3, firstVisibleRow: 1);
      cubit.moveToScreen(ScrollAlign.top);
      expect(cubit.state.active!.cursor, 1);
      cubit.moveToScreen(ScrollAlign.bottom);
      expect(cubit.state.active!.cursor, 3);
      cubit.moveToScreen(ScrollAlign.center);
      expect(cubit.state.active!.cursor, 2);
      cubit.moveToScreen(ScrollAlign.top, count: 2);
      expect(cubit.state.active!.cursor, 2);
      cubit.moveToScreen(ScrollAlign.bottom, count: 9);
      expect(cubit.state.active!.cursor, 1);
    });

    test('zz asks the view to centre the cursor until it moves', () {
      final before = cubit.state.active!.scrollRequest;
      cubit.scrollCursor(ScrollAlign.center);
      expect(cubit.state.active!.scrollAlign, ScrollAlign.center);
      expect(cubit.state.active!.scrollRequest, before + 1);
      cubit.moveCursor(1);
      expect(cubit.state.active!.scrollAlign, ScrollAlign.reveal);
    });

    test('sortReverse turns the order; A and I place the caret', () async {
      expect(cubit.state.active!.sort.descending, isFalse);
      await cubit.sortReverse();
      expect(cubit.state.active!.sort.descending, isTrue);
      cubit.moveCursorTo(1);
      cubit.toggleVisual();
      cubit.startRenaming(caret: RenameCaret.end);
      expect(cubit.state.active!.renaming, 1);
      expect(cubit.state.active!.renameCaret, RenameCaret.end);
      expect(cubit.state.active!.visual, isFalse);
    });

    test('another folder ends visual mode and the prompt', () async {
      cubit.moveCursorTo(1);
      cubit.toggleVisual();
      cubit.searchOpen();
      await cubit.goInto();
      final tab = cubit.state.active!;
      expect(tab.location, const Location.native('/home/docs'));
      expect(tab.visual, isFalse);
      expect(tab.searching, isFalse);
      expect(tab.selected, isEmpty);
    });
  });

  blocTest<PanelCubit, PanelState>(
    'a change on disk refreshes the tab and keeps the selection by name',
    build: () => cubit,
    act: (cubit) async {
      await cubit.start(null, home);
      cubit.clickRow(2, toggle: true);
      cubit.moveCursorTo(3);
      fs.folders['/home']!.add(fs.file('/home', 'aa.txt'));
      changes.add('left-1');
      await settle();
    },
    verify: (cubit) {
      final tab = cubit.state.active!;
      expect(tab.rows.map((r) => r.name), [
        '..',
        'docs',
        'a.txt',
        'aa.txt',
        'b.txt',
        'c.md',
      ]);
      expect(tab.selected, {'a.txt'});
      expect(tab.focused?.name, 'b.txt');
    },
  );
}
