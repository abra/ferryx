import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:find_feature/find_feature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operations_service/operations_service.dart';

class _MockFindService extends Mock implements FindService {}

void main() {
  late _MockFindService service;
  late StreamController<FindUpdate> updates;

  const request = FindRequest(root: '/tmp', name: '*.md');
  FindHit hit(String name) =>
      FindHit(path: '/tmp/$name', isDir: false, size: 3);

  setUpAll(() {
    registerFallbackValue(const FindRequest(root: '/'));
  });

  setUp(() {
    service = _MockFindService();
    updates = StreamController<FindUpdate>.broadcast();
    when(() => service.updates).thenAnswer((_) => updates.stream);
    when(() => service.start(any())).thenAnswer((_) async => 7);
    when(() => service.cancel(any())).thenAnswer((_) async {});
  });

  tearDown(() => updates.close());

  blocTest<FindCubit, FindState>(
    'a search starts, gathers its hits and ends',
    build: () => FindCubit(service: service),
    act: (cubit) async {
      await cubit.start(request);
      updates.add(
        FindUpdate(findId: 7, hits: [hit('a.md')], current: '/tmp', scanned: 2),
      );
      updates.add(FindUpdate(findId: 9, hits: [hit('other.md')]));
      updates.add(FindUpdate(findId: 7, hits: [hit('b.md')], scanned: 5));
      updates.add(const FindUpdate(findId: 7, scanned: 6, done: true));
      await Future<void>.delayed(Duration.zero);
    },
    expect: () => [
      const FindState(request: request, running: true),
      const FindState(request: request, running: true, findId: 7),
      FindState(
        request: request,
        running: true,
        findId: 7,
        hits: [hit('a.md')],
        current: '/tmp',
        scanned: 2,
      ),
      FindState(
        request: request,
        running: true,
        findId: 7,
        hits: [hit('a.md'), hit('b.md')],
        current: '/tmp',
        scanned: 5,
      ),
      FindState(
        request: request,
        findId: 7,
        hits: [hit('a.md'), hit('b.md')],
        scanned: 6,
        done: true,
      ),
    ],
    verify: (_) {
      verify(() => service.start(request)).called(1);
      verifyNever(() => service.cancel(any()));
    },
  );

  blocTest<FindCubit, FindState>(
    'stop cancels the search and keeps what it found',
    build: () => FindCubit(service: service),
    act: (cubit) async {
      await cubit.start(request);
      updates.add(FindUpdate(findId: 7, hits: [hit('a.md')], scanned: 1));
      await Future<void>.delayed(Duration.zero);
      await cubit.stop();
      // Late news of the cancelled search changes nothing.
      updates.add(FindUpdate(findId: 7, hits: [hit('late.md')], scanned: 9));
      await Future<void>.delayed(Duration.zero);
    },
    skip: 2,
    expect: () => [
      FindState(
        request: request,
        running: true,
        findId: 7,
        hits: [hit('a.md')],
        scanned: 1,
      ),
      FindState(
        request: request,
        findId: 7,
        hits: [hit('a.md')],
        scanned: 1,
        done: true,
      ),
    ],
    verify: (_) => verify(() => service.cancel(7)).called(1),
  );

  blocTest<FindCubit, FindState>(
    'a search that cannot run reports why',
    build: () => FindCubit(service: service),
    act: (cubit) async {
      await cubit.start(request);
      updates.add(
        const FindUpdate(findId: 7, done: true, error: 'bad expression'),
      );
      await Future<void>.delayed(Duration.zero);
    },
    skip: 2,
    expect: () => [
      const FindState(
        request: request,
        findId: 7,
        done: true,
        error: 'bad expression',
      ),
    ],
  );

  blocTest<FindCubit, FindState>(
    'more hits than the cap stop the search',
    build: () => FindCubit(service: service),
    act: (cubit) async {
      await cubit.start(request);
      updates.add(
        FindUpdate(
          findId: 7,
          hits: [for (var i = 0; i <= FindCubit.maxHits; i++) hit('$i')],
        ),
      );
      await Future<void>.delayed(Duration.zero);
    },
    skip: 2,
    verify: (cubit) {
      expect(cubit.state.hits.length, FindCubit.maxHits);
      expect(cubit.state.capped, isTrue);
      expect(cubit.state.running, isFalse);
      verify(() => service.cancel(7)).called(1);
    },
  );

  test('closing a running search cancels it', () async {
    final cubit = FindCubit(service: service);
    await cubit.start(request);
    await cubit.close();
    verify(() => service.cancel(7)).called(1);
  });
}
