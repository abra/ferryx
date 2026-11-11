import 'dart:async';

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

class _Find extends Mock implements FindService {}

void main() {
  const request = FindRequest(
    root: '/root',
    name: '*.txt',
    modifiedWithinDays: 7,
  );
  late _Files files;
  late _Find find;
  late PanelCubit panel;
  late PreferencesService preferences;
  late StreamController<FindUpdate> updates;
  var nextId = 0;

  setUpAll(() {
    registerFallbackValue(request);
    registerFallbackValue(const SortOptions());
    registerFallbackValue(const ListingOptions());
    registerFallbackValue(const Location.native('/'));
    registerFallbackValue(<FindHit>[]);
  });
  setUp(() async {
    files = _Files();
    find = _Find();
    updates = StreamController.broadcast();
    nextId = 0;
    final operations = _Operations();
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    when(() => files.directoryChanges).thenAnswer((_) => const Stream.empty());
    when(() => files.closeListing(any())).thenAnswer((_) async {});
    when(() => operations.progress).thenAnswer((_) => const Stream.empty());
    when(() => find.updates).thenAnswer((_) => updates.stream);
    when(() => find.start(any())).thenAnswer((_) async => ++nextId);
    when(() => find.cancel(any())).thenAnswer((_) async {});
    when(() => find.order(any(), any())).thenAnswer(
      (call) async =>
          List.generate((call.positionalArguments[0] as List).length, (i) => i),
    );
    panel = PanelCubit(
      side: PanelSide.left,
      files: files,
      find: find,
      operations: operations,
      preferences: preferences,
      logger: Logger(),
    );
  });
  tearDown(() async {
    await panel.close();
    await preferences.dispose();
    await updates.close();
  });

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'a failed folder navigation keeps search results and the live task',
    () async {
      await panel.newSearchTab(request, label: 'Notes');
      updates.add(
        FindUpdate(
          findId: 1,
          hits: [FindHit(path: '/root/one.txt', isDir: false, size: 1)],
        ),
      );
      await settle();
      final before = panel.state.active!;
      const target = Location.native('/root/missing');
      when(() => files.openListing(any(), target, any())).thenThrow(
        const FerryxException(FerryxErrorKind.notFound, '/root/missing'),
      );
      await panel.open(target);
      expect(panel.state.active!.search, before.search);
      expect(panel.state.active!.rows, before.rows);
      expect(panel.state.active!.failedLocation, target);
      verifyNever(() => find.cancel(1));
      updates.add(
        FindUpdate(
          findId: 1,
          hits: [FindHit(path: '/root/two.txt', isDir: false, size: 1)],
        ),
      );
      await settle();
      expect(
        panel.state.active!.rows.map((row) => row.name),
        containsAll(['one.txt', 'two.txt']),
      );
    },
  );

  FindHit hit(String path) => FindHit(path: path, isDir: false, size: 12);

  test('results keep distinct relative paths, reject paths outside the root '
      'and retain ordinary file command locations', () async {
    await panel.newSearchTab(request, label: 'Notes');
    updates.add(
      FindUpdate(
        findId: 1,
        hits: [
          hit('/root/one/shared.txt'),
          hit('/root/two/shared.txt'),
          hit('/root/one/shared.txt'),
          hit('/outside/no.txt'),
        ],
      ),
    );
    updates.add(const FindUpdate(findId: 1, done: true, scanned: 10));
    await settle();
    final tab = panel.state.active!;
    expect(tab.rows.map((row) => row.key), [
      'one/shared.txt',
      'two/shared.txt',
    ]);
    expect(
      tab.locationOf(tab.rows[1]),
      const Location.native('/root/two/shared.txt'),
    );
    expect(tab.search!.running, isFalse);
    expect(tab.search!.label, 'Notes');
    final restored = SavedPanel.decode(panel.saved().encode())!;
    expect(restored.tabs.single.search, request);
    expect(restored.tabs.single.searchLabel, 'Notes');
    verifyNever(() => files.openListing(any(), any(), any()));
  });

  test(
    'refresh keeps the shown results until the replacement query completes',
    () async {
      await panel.newSearchTab(request);
      updates.add(FindUpdate(findId: 1, hits: [hit('/root/old.txt')]));
      updates.add(const FindUpdate(findId: 1, done: true));
      await settle();
      await panel.refresh();
      expect(panel.state.active!.rows.single.name, 'old.txt');
      updates.add(FindUpdate(findId: 2, hits: [hit('/root/new.txt')]));
      await settle();
      expect(panel.state.active!.rows.single.name, 'old.txt');
      updates.add(const FindUpdate(findId: 2, done: true));
      await settle();
      expect(panel.state.active!.rows.single.name, 'new.txt');
    },
  );

  test(
    'closing a search tab cancels only its task and drops late events',
    () async {
      await panel.newSearchTab(request);
      await panel.newSearchTab(request);
      await panel.closeTab();
      verify(() => find.cancel(2)).called(1);
      updates.add(FindUpdate(findId: 2, hits: [hit('/root/late.txt')]));
      await settle();
      expect(panel.state.tabs.length, 1);
      expect(panel.state.active!.rows, isEmpty);
      verifyNever(() => find.cancel(1));
    },
  );

  test(
    'search cap stops native work and exposes that results are incomplete',
    () async {
      await panel.newSearchTab(request);
      updates.add(
        FindUpdate(
          findId: 1,
          hits: List.generate(10001, (i) => hit('/root/$i.txt')),
        ),
      );
      await settle();
      expect(panel.state.active!.rows.length, 10000);
      expect(panel.state.active!.search!.capped, isTrue);
      expect(panel.state.active!.search!.running, isFalse);
      verify(() => find.cancel(1)).called(1);
    },
  );

  test('an old sort cannot replace results from a newer query', () async {
    final sorting = Completer<List<int>>();
    when(() => find.order(any(), any())).thenAnswer((_) => sorting.future);
    await panel.newSearchTab(request);
    updates.add(FindUpdate(findId: 1, hits: [hit('/root/old.txt')]));
    updates.add(const FindUpdate(findId: 1, done: true));
    await settle();
    await panel.refresh();
    when(() => find.order(any(), any())).thenAnswer((_) async => [0]);
    updates.add(FindUpdate(findId: 2, hits: [hit('/root/new.txt')]));
    updates.add(const FindUpdate(findId: 2, done: true));
    await settle();
    sorting.complete([0]);
    await settle();
    expect(panel.state.active!.rows.single.name, 'new.txt');
  });
}
