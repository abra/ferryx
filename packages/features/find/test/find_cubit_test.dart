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

  test('results and completion can precede the start reply', () async {
    final reply = Completer<int>();
    when(() => service.start(request)).thenAnswer((_) => reply.future);
    final cubit = FindCubit(service: service);
    final starting = cubit.start(request);
    updates.add(FindUpdate(findId: 7, hits: [hit('early.md')]));
    updates.add(const FindUpdate(findId: 7, done: true, scanned: 3));
    await Future<void>.delayed(Duration.zero);
    reply.complete(7);
    await starting;
    expect(cubit.state.running, isFalse);
    expect(cubit.state.done, isTrue);
    expect(cubit.state.hits, [hit('early.md')]);
    expect(cubit.state.scanned, 3);
    await cubit.close();
    verifyNever(() => service.cancel(7));
  });

  for (final close in [false, true]) {
    test(
      '${close ? 'close' : 'stop'} during start cancels the eventual id',
      () async {
        final reply = Completer<int>();
        when(() => service.start(request)).thenAnswer((_) => reply.future);
        final cubit = FindCubit(service: service);
        final starting = cubit.start(request);
        await (close ? cubit.close() : cubit.stop());
        reply.complete(7);
        await starting;
        verify(() => service.cancel(7)).called(1);
        if (!close) {
          expect(cubit.state.running, isFalse);
          await cubit.close();
        }
      },
    );
  }

  test('restarting the same request ignores a late previous start', () async {
    final first = Completer<int>();
    final second = Completer<int>();
    var starts = 0;
    when(() => service.start(request))
        .thenAnswer((_) => starts++ == 0 ? first.future : second.future);
    final cubit = FindCubit(service: service);
    final a = cubit.start(request);
    await cubit.stop();
    final b = cubit.start(request);
    second.complete(8);
    await b;
    first.complete(7);
    await a;
    updates.add(FindUpdate(findId: 7, hits: [hit('stale.md')], done: true));
    updates.add(FindUpdate(findId: 8, hits: [hit('new.md')]));
    updates.add(const FindUpdate(findId: 8, done: true));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.findId, 8);
    expect(cubit.state.hits, [hit('new.md')]);
    expect(cubit.state.running, isFalse);
    verify(() => service.cancel(7)).called(1);
    await cubit.close();
  });

  test('a start failure leaves an error state and allows retry', () async {
    when(() => service.start(request)).thenThrow(
      const FerryxException(FerryxErrorKind.io, 'cannot start'),
    );
    final cubit = FindCubit(service: service);
    await cubit.start(request);
    expect(cubit.state.running, isFalse);
    expect(cubit.state.error, 'cannot start');
    when(() => service.start(request)).thenAnswer((_) async => 7);
    await cubit.start(request);
    expect(cubit.state.running, isTrue);
    expect(cubit.state.error, isNull);
    await cubit.close();
  });
}
