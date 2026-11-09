import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:checksums_feature/checksums_feature.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operations_service/operations_service.dart';

class _Service extends Mock implements ChecksumService {}

const _abc = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

void main() {
  late _Service service;
  late StreamController<ChecksumUpdate> updates;

  setUpAll(() {
    registerFallbackValue(
      const ChecksumRequest(
        paths: [],
        base: '',
        algorithm: ChecksumAlgorithm.md5,
      ),
    );
  });

  setUp(() {
    service = _Service();
    updates = StreamController<ChecksumUpdate>.broadcast();
    when(() => service.updates).thenAnswer((_) => updates.stream);
    var next = 3;
    when(() => service.start(any())).thenAnswer((_) async => next++);
    when(() => service.verify(any())).thenAnswer((_) async => 4);
    when(() => service.cancel(any())).thenAnswer((_) async {});
    when(
      () => service.save(any(), any(), overwrite: any(named: 'overwrite')),
    ).thenAnswer((_) async {});
  });

  tearDown(() => updates.close());

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  ChecksumsCubit cubit(List<String> paths, {ChecksumAlgorithm? algorithm}) =>
      ChecksumsCubit(
        service: service,
        paths: paths,
        base: '/home',
        algorithm: algorithm,
      );

  test('a checksum file is checked; other targets are hashed', () {
    expect(ChecksumsCubit.verifiable(['/home/SHA256SUMS']), isTrue);
    expect(ChecksumsCubit.verifiable(['/home/a.iso']), isFalse);
    expect(
      ChecksumsCubit.verifiable(['/home/SHA256SUMS', '/home/x']),
      isFalse,
    );
    final sums = cubit(['/home/x.md5']);
    expect(sums.state.mode, ChecksumMode.verify);
    expect(sums.state.algorithm, ChecksumAlgorithm.md5);
    final files = cubit([
      '/home/a',
      '/home/b',
    ], algorithm: ChecksumAlgorithm.sha1);
    expect(files.state.mode, ChecksumMode.calculate);
    expect(files.state.algorithm, ChecksumAlgorithm.sha1);
    expect(files.defaultFileName, 'home.sha1');
    expect(cubit(['/home/a.iso']).defaultFileName, 'a.iso.sha256');
  });

  test('gathers the files, then their outcomes by index', () async {
    final checksums = cubit(['/home/dir']);
    await checksums.start();
    final request =
        verify(() => service.start(captureAny())).captured.single
            as ChecksumRequest;
    expect(request.paths, ['/home/dir']);
    expect(request.base, '/home');
    expect(checksums.state.running, isTrue);

    updates.add(
      const ChecksumUpdate(
        taskId: 3,
        files: [
          ChecksumFile(index: 0, name: 'dir/a', path: '/home/dir/a', size: 3),
          ChecksumFile(index: 1, name: 'dir/b', path: '/home/dir/b', size: 3),
        ],
        filesTotal: 2,
        bytesTotal: 6,
      ),
    );
    await flush();
    expect(checksums.state.files, hasLength(2));
    expect(checksums.state.outcomeOf(0), isNull);

    updates.add(
      const ChecksumUpdate(
        taskId: 3,
        filesTotal: 2,
        filesDone: 2,
        outcomes: [
          ChecksumOutcome(index: 1, status: ChecksumStatus.ok, hash: _abc),
          ChecksumOutcome(
            index: 0,
            status: ChecksumStatus.error,
            error: FerryxException(
              FerryxErrorKind.permissionDenied,
              'denied',
            ),
          ),
        ],
        done: true,
      ),
    );
    await flush();
    expect(checksums.state.running, isFalse);
    expect(checksums.state.outcomeOf(1)?.hash, _abc);
    expect(checksums.state.lines, [
      const ChecksumLine(hash: _abc, name: 'dir/b'),
    ]);
    // A pasted hash finds its file, case and spaces aside; a short one
    // finds nothing.
    expect(checksums.state.matching(' ${_abc.toUpperCase()} '), [1]);
    expect(checksums.state.matching('ba78'), isEmpty);

    await checksums.save('dir.sha256');
    verify(
      () => service.save(
        '/home/dir.sha256',
        [const ChecksumLine(hash: _abc, name: 'dir/b')],
        overwrite: false,
      ),
    ).called(1);
    await checksums.close();
  });

  blocTest<ChecksumsCubit, ChecksumsState>(
    'a new algorithm starts over, and the old task is cancelled',
    build: () => cubit(['/home/a']),
    act: (checksums) async {
      await checksums.start();
      await checksums.setAlgorithm(ChecksumAlgorithm.blake3);
    },
    verify: (checksums) {
      // The first task when the algorithm changed, the second on close.
      verify(() => service.cancel(3)).called(1);
      verify(() => service.cancel(4)).called(1);
      verify(() => service.start(any())).called(2);
      expect(checksums.state.algorithm, ChecksumAlgorithm.blake3);
      expect(checksums.state.running, isTrue);
    },
  );

  test('checking counts the outcomes and the lines not understood', () async {
    final checksums = cubit(['/home/SHA1SUMS']);
    await checksums.start();
    verify(() => service.verify('/home/SHA1SUMS')).called(1);
    updates.add(
      const ChecksumUpdate(
        taskId: 4,
        algorithm: ChecksumAlgorithm.sha1,
        files: [
          ChecksumFile(index: 0, name: 'a', path: '/home/a', size: 1),
          ChecksumFile(index: 1, name: 'b', path: '/home/b', size: 1),
          ChecksumFile(index: 2, name: 'c', path: '/home/c', size: 1),
        ],
        outcomes: [
          ChecksumOutcome(index: 0, status: ChecksumStatus.ok, hash: 'x'),
          ChecksumOutcome(index: 1, status: ChecksumStatus.mismatch),
          ChecksumOutcome(index: 2, status: ChecksumStatus.missing),
        ],
        filesTotal: 3,
        badLines: 2,
        done: true,
      ),
    );
    await flush();
    expect(checksums.state.statusCounts, {
      ChecksumStatus.ok: 1,
      ChecksumStatus.mismatch: 1,
      ChecksumStatus.missing: 1,
    });
    expect(checksums.state.badLines, 2);
    await checksums.close();
  });

  test(
    'early verification outcomes and done survive a delayed start reply',
    () async {
      final reply = Completer<int>();
      when(() => service.verify(any())).thenAnswer((_) => reply.future);
      final checksums = cubit(['/home/SHA1SUMS']);
      final starting = checksums.start();
      updates.add(
        const ChecksumUpdate(
          taskId: 4,
          algorithm: ChecksumAlgorithm.sha1,
          files: [ChecksumFile(index: 0, name: 'a', path: '/home/a', size: 3)],
          filesTotal: 1,
        ),
      );
      updates.add(
        const ChecksumUpdate(
          taskId: 4,
          filesTotal: 1,
          outcomes: [
            ChecksumOutcome(index: 0, status: ChecksumStatus.ok, hash: 'abc'),
          ],
          done: true,
        ),
      );
      await flush();
      reply.complete(4);
      await starting;
      expect(checksums.state.running, isFalse);
      expect(checksums.state.files.single.name, 'a');
      expect(checksums.state.outcomeOf(0)?.hash, 'abc');
      await checksums.close();
      verifyNever(() => service.cancel(4));
    },
  );

  test(
    'an algorithm change owns its task when start replies arrive out of order',
    () async {
      final first = Completer<int>();
      final second = Completer<int>();
      var starts = 0;
      when(() => service.start(any()))
          .thenAnswer((_) => starts++ == 0 ? first.future : second.future);
      final checksums = cubit(['/home/a']);
      final a = checksums.start();
      final b = checksums.setAlgorithm(ChecksumAlgorithm.blake3);
      second.complete(4);
      await b;
      first.complete(3);
      await a;
      updates.add(const ChecksumUpdate(taskId: 3, error: 'stale', done: true));
      updates.add(const ChecksumUpdate(taskId: 4, done: true));
      await flush();
      expect(checksums.state.algorithm, ChecksumAlgorithm.blake3);
      expect(checksums.state.error, isNull);
      expect(checksums.state.running, isFalse);
      verify(() => service.cancel(3)).called(1);
      await checksums.close();
    },
  );

  test('a verification start failure ends the running state', () async {
    when(() => service.verify(any())).thenThrow(
      const FerryxException(FerryxErrorKind.io, 'cannot verify'),
    );
    final checksums = cubit(['/home/SHA1SUMS']);
    await checksums.start();
    expect(checksums.state.running, isFalse);
    expect(checksums.state.error, 'cannot verify');
    await checksums.close();
  });
}
