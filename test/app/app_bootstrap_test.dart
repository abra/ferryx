import 'dart:async';

import 'package:ferryx/app/app_bootstrap.dart';
import 'package:ferryx/app/dependency_container.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';

class _Dependencies extends Mock implements DependenciesContainer {}

void main() {
  late Logger logger;
  late _Dependencies dependencies;

  setUp(() {
    logger = Logger();
    dependencies = _Dependencies();
    when(dependencies.disposeAfterBootstrapFailure).thenAnswer((_) async {});
  });

  test('a failed composition can be retried with the same logger', () async {
    var attempts = 0;
    final failure = StateError('preferences unavailable');
    final bootstrap = AppBootstrap(
      logger: logger,
      compose: ({required logger, windowFrame}) async {
        if (++attempts == 1) throw failure;
        return dependencies;
      },
    );
    final errors = <Object>[];
    final ready = <DependenciesContainer>[];
    await bootstrap.run(
      onReady: ready.add,
      onFailure: (error, _) => errors.add(error),
    );
    await bootstrap.run(
      onReady: ready.add,
      onFailure: (error, _) => errors.add(error),
    );
    expect(attempts, 2);
    expect(errors, [failure]);
    expect(ready, [dependencies]);
    expect(logger.destroyed, isFalse);
    verifyNever(dependencies.disposeAfterBootstrapFailure);
  });

  test(
    'onReady failure rolls back the attempt before offering retry',
    () async {
      final calls = <String>[];
      when(dependencies.disposeAfterBootstrapFailure).thenAnswer((_) async {
        calls.add('dispose');
      });
      final bootstrap = AppBootstrap(
        logger: logger,
        compose: ({required logger, windowFrame}) async => dependencies,
      );
      final failure = StateError('window unavailable');
      await bootstrap.run(
        onReady: (_) => throw failure,
        onFailure: (error, _) {
          expect(error, same(failure));
          calls.add('failure');
        },
      );
      expect(calls, ['dispose', 'failure']);
      expect(logger.destroyed, isFalse);
      await bootstrap.run(
        onReady: (_) => calls.add('ready'),
        onFailure: (_, _) => fail('retry failed'),
      );
      expect(calls, ['dispose', 'failure', 'ready']);
      verify(dependencies.disposeAfterBootstrapFailure).called(1);
    },
  );

  test('repeated retry clicks share one in-flight composition', () async {
    final pending = Completer<DependenciesContainer>();
    var attempts = 0;
    var ready = 0;
    final bootstrap = AppBootstrap(
      logger: logger,
      compose: ({required logger, windowFrame}) {
        attempts++;
        return pending.future;
      },
    );
    final first = bootstrap.run(
      onReady: (_) => ready++,
      onFailure: (_, _) => fail('unexpected failure'),
    );
    final second = bootstrap.run(
      onReady: (_) => fail('a duplicate attempt ran'),
      onFailure: (_, _) => fail('unexpected failure'),
    );
    expect(second, same(first));
    pending.complete(dependencies);
    await Future.wait([first, second]);
    expect(attempts, 1);
    expect(ready, 1);
  });

  test('a failing recovery callback still permits the next attempt', () async {
    final failure = StateError('recovery window unavailable');
    var attempts = 0;
    final bootstrap = AppBootstrap(
      logger: logger,
      compose: ({required logger, windowFrame}) async {
        if (++attempts == 1) throw StateError('initialization failed');
        return dependencies;
      },
    );
    await expectLater(
      bootstrap.run(
        onReady: (_) => fail('first attempt must fail'),
        onFailure: (_, _) => throw failure,
      ),
      throwsA(same(failure)),
    );
    var ready = false;
    await bootstrap.run(
      onReady: (_) => ready = true,
      onFailure: (_, _) => fail('retry failed'),
    );
    expect(ready, isTrue);
  });
}
