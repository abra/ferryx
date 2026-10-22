import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';
import 'package:operations_service/operations_service.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

class _Files extends Mock implements FileRepository {}

class _Operations extends Mock implements OperationsService {}

/// The panel's side of a flat view, an encrypted archive and the keys of
/// rows that share a name.
void main() {
  const home = Location.native('/home');
  late _Files files;
  late _Operations operations;
  late PreferencesService preferences;
  late StreamController<String> changes;
  late StreamController<OperationProgress> progress;
  late PanelCubit cubit;

  /// The walks started, by generation, with the controller that feeds
  /// their batches.
  late Map<int, StreamController<FlatBatch>> walks;
  late int nextGeneration;

  /// What `sortFlatListing` answers: the order of the walked rows.
  late List<int> Function(List<FileEntry> walked) sortedOrder;
  late List<FileEntry> lastWalked;

  FileEntry file(String folder, String name, {int size = 1}) => FileEntry(
    name: name,
    path: folder.isEmpty ? '/home/$name' : '/home/$folder/$name',
    kind: EntryKind.file,
    isDir: false,
    size: size,
    folder: folder,
    extension: name.split('.').last,
  );

  const parentRow = FileEntry(
    name: '..',
    path: '/',
    kind: EntryKind.directory,
    isDir: true,
    isParent: true,
  );

  Listing plain() => const Listing(
    location: home,
    entries: [
      parentRow,
      FileEntry(
        name: 'a',
        path: '/home/a',
        kind: EntryKind.directory,
        isDir: true,
      ),
      FileEntry(
        name: 'b',
        path: '/home/b',
        kind: EntryKind.directory,
        isDir: true,
      ),
      FileEntry(
        name: 'same.txt',
        path: '/home/same.txt',
        kind: EntryKind.file,
        isDir: false,
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
    changes = StreamController<String>.broadcast();
    progress = StreamController<OperationProgress>.broadcast();
    walks = {};
    nextGeneration = 1;
    sortedOrder = (walked) => [for (var i = 0; i < walked.length; i++) i];
    lastWalked = const [];
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    when(() => files.directoryChanges).thenAnswer((_) => changes.stream);
    when(
      () => files.openListing(any(), any(), any()),
    ).thenAnswer((_) async => plain());
    when(() => files.refreshListing(any())).thenAnswer((_) async => plain());
    when(
      () => files.resortListing(any(), any()),
    ).thenAnswer((_) async => plain());
    when(() => files.closeListing(any())).thenAnswer((_) async {});
    when(() => files.isArchive(any())).thenReturn(false);
    when(() => files.openFlatListing(any(), any(), any())).thenAnswer((
      inv,
    ) async {
      final generation = nextGeneration++;
      final controller = StreamController<FlatBatch>();
      walks[generation] = controller;
      return FlatStart(
        listing: Listing(
          location: inv.positionalArguments[1] as Location,
          entries: const [],
          watched: true,
        ),
        generation: generation,
        batches: controller.stream,
      );
    });
    when(() => files.sortFlatListing(any(), any(), any())).thenAnswer(
      (_) async => sortedOrder(lastWalked),
    );
    when(() => operations.progress).thenAnswer((_) => progress.stream);
    cubit = PanelCubit(
      side: PanelSide.left,
      files: files,
      operations: operations,
      preferences: preferences,
      logger: Logger(),
    );
    await cubit.start(null, home);
  });

  tearDown(() async {
    await cubit.close();
    await changes.close();
    await progress.close();
    for (final walk in walks.values) {
      await walk.close();
    }
    await preferences.dispose();
  });

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  PanelTabState tab() => cubit.state.active!;

  List<String> keys() => [for (final r in tab().rows) r.key];

  /// Sends [rows] as one batch of walk [generation], then its end.
  Future<void> walk(int generation, List<FileEntry> rows) async {
    lastWalked = rows;
    walks[generation]!.add(
      FlatBatch(generation: generation, entries: rows, count: rows.length),
    );
    await settle();
    walks[generation]!.add(
      FlatBatch(generation: generation, done: true, count: rows.length),
    );
    await settle();
  }

  group('flat view', () {
    test('rows show as they come, then sorted; Esc-like leave goes back to '
        'the folder holding the cursor', () async {
      await cubit.toggleFlatView();
      expect(tab().isFlat, isTrue);
      expect(tab().flat!.walking, isTrue);
      expect(tab().rows, isEmpty);
      walks[1]!.add(
        FlatBatch(
          generation: 1,
          entries: [parentRow, file('b', 'same.txt')],
          count: 2,
        ),
      );
      await settle();
      expect(keys(), ['..', 'b/same.txt']);
      expect(tab().cursor, 0);
      final rows = [parentRow, file('b', 'same.txt'), file('', 'same.txt')];
      // By name, then by folder: the root's own first.
      sortedOrder = (_) => [0, 2, 1];
      await walk(1, rows.sublist(2));
      expect(tab().flat!.walking, isFalse);
      // The order, from the core, is applied to every row walked, in the
      // order the batches brought them.
      expect(keys(), ['..', 'same.txt', 'b/same.txt']);

      cubit.moveCursorTo(tab().indexOfName('b/same.txt'));
      await cubit.leaveFlatView();
      expect(tab().isFlat, isFalse);
      expect(tab().focused?.name, 'b');
      expect(tab().history, [home], reason: 'no new history entry');
    });

    test(
      'two rows of one name select apart and target their own paths',
      () async {
        await cubit.toggleFlatView();
        final rows = [parentRow, file('', 'same.txt'), file('a', 'same.txt')];
        lastWalked = rows;
        walks[1]!.add(FlatBatch(generation: 1, entries: rows, count: 3));
        await settle();
        walks[1]!.add(const FlatBatch(generation: 1, done: true, count: 3));
        await settle();
        cubit.toggleSelectionAt(2);
        expect(tab().selected, {'a/same.txt'});
        expect(tab().targets.map((t) => t.path), ['/home/a/same.txt']);
        cubit.selectAll();
        expect(tab().selected, {'same.txt', 'a/same.txt'});
        expect(
          tab().locationOf(tab().rows[2]),
          const Location.native('/home/a/same.txt'),
        );
      },
    );

    test('a walk again keeps the rows until it ends, and the cursor', () async {
      await cubit.toggleFlatView();
      final first = [parentRow, file('', 'x.txt'), file('a', 'y.txt')];
      lastWalked = first;
      walks[1]!.add(FlatBatch(generation: 1, entries: first, count: 3));
      await settle();
      walks[1]!.add(const FlatBatch(generation: 1, done: true, count: 3));
      await settle();
      cubit.moveCursorTo(2);
      changes.add(tab().id);
      await settle();
      expect(tab().flat!.refreshing, isTrue);
      final second = [parentRow, file('', 'new.txt'), file('a', 'y.txt')];
      walks[2]!.add(FlatBatch(generation: 2, entries: second, count: 3));
      await settle();
      expect(keys(), ['..', 'x.txt', 'a/y.txt'], reason: 'nothing flickers');
      lastWalked = second;
      walks[2]!.add(const FlatBatch(generation: 2, done: true, count: 3));
      await settle();
      expect(keys(), ['..', 'new.txt', 'a/y.txt']);
      expect(tab().focused?.key, 'a/y.txt');
      // A batch of the old walk is dropped.
      walks[1]!.add(
        FlatBatch(generation: 1, entries: [file('', 'old.txt')], count: 1),
      );
      await settle();
      expect(keys(), isNot(contains('old.txt')));
    });

    test('a sort asked while the walk goes on applies when it ends', () async {
      await cubit.toggleFlatView();
      await cubit.setSort(
        const SortOptions(field: SortField.size, descending: true),
      );
      expect(tab().sort.field, SortField.size);
      final rows = [file('', 'small', size: 1), file('a', 'big', size: 9)];
      sortedOrder = (_) => [1, 0];
      await walk(1, rows);
      expect(keys(), ['a/big', 'small']);
      final asked =
          verify(
                () => files.sortFlatListing(any(), 1, captureAny()),
              ).captured.last
              as ListingOptions;
      expect(asked.sort.field, SortField.size);
    });

    test('quick search matches names, under their folders', () async {
      await cubit.toggleFlatView();
      await walk(1, [file('docs', 'report.md'), file('', 'notes.txt')]);
      cubit.quickSearchType('rep');
      expect(tab().matches.keys, ['docs/report.md']);
      expect(tab().focused?.key, 'docs/report.md');
    });

    test('an operation that wrote under the tree walks it again', () async {
      await cubit.toggleFlatView();
      await walk(1, [file('a', 'one.txt')]);
      progress.add(
        const OperationProgress(
          id: 7,
          kind: OpKind.copy,
          state: OpState.done,
          sources: ['/elsewhere/x.txt'],
          destination: '/home/a',
        ),
      );
      await settle();
      expect(walks.keys, contains(2));
      expect(tab().flat!.refreshing, isTrue);
    });

    test('a tab closed while its walk starts takes the walk along', () async {
      await cubit.newTab();
      final id = tab().id;
      final opening = Completer<FlatStart>();
      when(
        () => files.openFlatListing(any(), any(), any()),
      ).thenAnswer((_) => opening.future);
      final toggled = cubit.toggleFlatView();
      await cubit.closeTab();
      final walk = StreamController<FlatBatch>();
      opening.complete(
        FlatStart(
          listing: const Listing(location: home, entries: []),
          generation: 9,
          batches: walk.stream,
        ),
      );
      await toggled;
      verify(() => files.closeListing(id)).called(greaterThanOrEqualTo(2));
      expect(cubit.state.tabs.any((t) => t.isFlat), isFalse);
      await walk.close();
    });

    test('another folder ends the flat view and its walk', () async {
      await cubit.toggleFlatView();
      await cubit.open(const Location.native('/'));
      expect(tab().isFlat, isFalse);
      // The walk's late batches go nowhere.
      walks[1]!.add(
        FlatBatch(generation: 1, entries: [file('', 'late')], count: 1),
      );
      await settle();
      expect(keys(), isNot(contains('late')));
    });
  });

  test('the key hints of a flat view name the way back first', () {
    const flatTab = PanelTabState(
      id: 't',
      location: home,
      sort: SortOptions(),
      flat: FlatView(generation: 1),
    );
    final hints = hintsFor(tab: flatTab, vim: false, hasRegister: false);
    expect(hints.first, isA<CommandHint>());
    expect((hints.first as CommandHint).command, AppCommand.toggleFlatView);
    expect(hints.length, lessThanOrEqualTo(5));
    const plainTab = PanelTabState(
      id: 't',
      location: home,
      sort: SortOptions(),
    );
    expect(
      hintsFor(
        tab: plainTab,
        vim: false,
        hasRegister: false,
      ).whereType<CommandHint>().map((h) => h.command),
      isNot(contains(AppCommand.toggleFlatView)),
    );
  });

  group('encrypted archives', () {
    const archive = Location.inArchive(archive: '/home/locked.7z');

    test(
      'a list that asks for a password keeps the tab and says where',
      () async {
        when(() => files.openListing(any(), archive, any())).thenThrow(
          const FerryxException(FerryxErrorKind.passwordRequired, 'locked'),
        );
        await cubit.open(archive);
        expect(tab().location, home);
        expect(tab().error?.kind, FerryxErrorKind.passwordRequired);
        expect(tab().passwordLocation, archive);
        when(() => files.openListing(any(), archive, any())).thenAnswer(
          (_) async => const Listing(location: archive, entries: []),
        );
        await cubit.openAfterPassword();
        expect(tab().location, archive);
        expect(tab().error, isNull);
        expect(tab().passwordLocation, isNull);
      },
    );
  });
}
