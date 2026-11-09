import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:duplicates_feature/duplicates_feature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operations_service/operations_service.dart';

class _Service extends Mock implements DuplicatesService {}

DuplicateFile file(String path, int day) =>
    DuplicateFile(path: path, modified: DateTime(2026, 1, day));

final _small = DuplicateGroup(
  size: 10,
  files: [file('/a/x/one.txt', 1), file('/a/one.txt', 3)],
);
final _big = DuplicateGroup(
  size: 1000,
  files: [
    file('/a/deep/er/big.bin', 2),
    file('/a/big.bin', 5),
    file('/b/big.bin', 1),
  ],
);

void main() {
  late _Service service;
  late StreamController<DuplicatesUpdate> updates;

  setUpAll(() {
    registerFallbackValue(const DuplicatesRequest(roots: []));
  });

  setUp(() {
    service = _Service();
    updates = StreamController<DuplicatesUpdate>.broadcast();
    when(() => service.updates).thenAnswer((_) => updates.stream);
    when(() => service.start(any())).thenAnswer((_) async => 2);
    when(() => service.cancel(any())).thenAnswer((_) async {});
  });

  tearDown(() => updates.close());

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  Future<DuplicatesCubit> started() async {
    final cubit = DuplicatesCubit(service: service);
    await cubit.start(const DuplicatesRequest(roots: ['/a', '/b']));
    updates.add(
      DuplicatesUpdate(
        taskId: 2,
        phase: DuplicatesPhase.hashing,
        groups: [_small],
      ),
    );
    updates.add(DuplicatesUpdate(taskId: 2, groups: [_big], done: true));
    await flush();
    return cubit;
  }

  test('keeps the groups with the most space to free first', () async {
    final cubit = await started();
    expect(cubit.state.running, isFalse);
    expect(cubit.state.groups.map((g) => g.size), [1000, 10]);
    expect(cubit.state.wasted, 2000 + 10);
    // A heading, then its files.
    expect(cubit.state.rows, hasLength(2 + 3 + 2));
    expect(cubit.state.rows.first, isA<GroupRow>());
    expect(cubit.state.fileAt(1)?.path, '/a/deep/er/big.bin');
    expect(cubit.state.fileAt(0), isNull);
    await cubit.close();
  });

  test('marks by hand: a click flips, several flip together', () async {
    final cubit = await started();
    cubit.toggleMarks([1]);
    expect(cubit.state.marked, {'/a/deep/er/big.bin'});
    // Some marked, some not: all become marked; then all unmarked.
    cubit.toggleMarks([1, 2]);
    expect(cubit.state.marked, {'/a/deep/er/big.bin', '/a/big.bin'});
    cubit.toggleMarks([1, 2]);
    expect(cubit.state.marked, isEmpty);
    // A heading marks nothing.
    cubit.toggleMarks([0]);
    expect(cubit.state.marked, isEmpty);
    await cubit.close();
  });

  test('marks by rule keep one copy of each group', () {
    expect(allButOne([_small, _big], KeepRule.newest), {
      '/a/x/one.txt',
      '/a/deep/er/big.bin',
      '/b/big.bin',
    });
    expect(allButOne([_small, _big], KeepRule.oldest), {
      '/a/one.txt',
      '/a/deep/er/big.bin',
      '/a/big.bin',
    });
    // The fewest folders deep, then the shortest.
    expect(allButOne([_small, _big], KeepRule.shortestPath), {
      '/a/x/one.txt',
      '/a/deep/er/big.bin',
      '/b/big.bin',
    });
  });

  test('folders show from the name of the deepest folder searched', () {
    const roots = ['/Users/me/Photos', '/Users/me/Photos/2025/', '/Volumes/B'];
    expect(shownFolder('/Users/me/Photos/a/b', roots), 'Photos/a/b');
    expect(shownFolder('/Users/me/Photos/2025/x', roots), '2025/x');
    expect(shownFolder('/Users/me/Photos', roots), 'Photos');
    expect(shownFolder('/Volumes/Backup/x', roots), '/Volumes/Backup/x');
    expect(shownFolder('/etc', ['/']), '/etc');
  });

  test('marked groups, bytes, and files that went to the trash', () async {
    final cubit = await started();
    cubit.markAllBut(KeepRule.newest);
    expect(cubit.state.markedBytes, 2 * 1000 + 10);
    expect(cubit.state.fullyMarkedGroups, 0);
    cubit.toggleMarks([2]);
    expect(cubit.state.fullyMarkedGroups, 1);

    cubit.removeFiles({'/a/x/one.txt', '/a/deep/er/big.bin'});
    // The small group is down to one file: no group any more.
    expect(cubit.state.groups.map((g) => g.size), [1000]);
    expect(cubit.state.groups.single.files, hasLength(2));
    expect(cubit.state.marked, {'/a/big.bin', '/b/big.bin'});
    cubit.unmarkAll();
    expect(cubit.state.marked, isEmpty);
    await cubit.close();
  });

  blocTest<DuplicatesCubit, DuplicatesState>(
    'a new search cancels the one under way; closing, the last',
    setUp: () {
      var next = 10;
      when(() => service.start(any())).thenAnswer((_) async => next++);
    },
    build: () => DuplicatesCubit(service: service),
    act: (cubit) async {
      await cubit.start(const DuplicatesRequest(roots: ['/a']));
      await cubit.start(const DuplicatesRequest(roots: ['/b']));
    },
    verify: (cubit) {
      verify(() => service.start(any())).called(2);
      verify(() => service.cancel(10)).called(1);
      verify(() => service.cancel(11)).called(1);
    },
  );

  test('early groups and done survive a delayed start reply', () async {
    final reply = Completer<int>();
    when(() => service.start(any())).thenAnswer((_) => reply.future);
    final cubit = DuplicatesCubit(service: service);
    final starting = cubit.start(const DuplicatesRequest(roots: ['/a']));
    updates.add(DuplicatesUpdate(taskId: 2, groups: [_small]));
    updates.add(DuplicatesUpdate(taskId: 2, groups: [_big], done: true));
    await flush();
    reply.complete(2);
    await starting;
    expect(cubit.state.running, isFalse);
    expect(cubit.state.groups.map((g) => g.size), [1000, 10]);
    await cubit.close();
    verifyNever(() => service.cancel(2));
  });

  test('closing while start is pending cancels its eventual task', () async {
    final reply = Completer<int>();
    when(() => service.start(any())).thenAnswer((_) => reply.future);
    final cubit = DuplicatesCubit(service: service);
    final starting = cubit.start(const DuplicatesRequest(roots: ['/a']));
    await cubit.close();
    reply.complete(2);
    await starting;
    verify(() => service.cancel(2)).called(1);
  });

  test('a start failure ends the running state', () async {
    when(() => service.start(any())).thenThrow(
      const FerryxException(FerryxErrorKind.io, 'cannot search'),
    );
    final cubit = DuplicatesCubit(service: service);
    await cubit.start(const DuplicatesRequest(roots: ['/a']));
    expect(cubit.state.running, isFalse);
    expect(cubit.state.error, 'cannot search');
    await cubit.close();
  });
}
