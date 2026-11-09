import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:operations_service/operations_service.dart';

typedef Update = ({int id, String value, bool done});

Update update(int id, String value, {bool done = false}) =>
    (id: id, value: value, done: done);

void main() {
  late StreamController<Update> updates;
  late TaskSession<Update> session;
  late List<Update> received;
  late List<int> started;
  late List<int> cancelled;
  late List<Object> errors;
  late List<Object> cleanupErrors;

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    updates = StreamController<Update>.broadcast();
    received = [];
    started = [];
    cancelled = [];
    errors = [];
    cleanupErrors = [];
    session = TaskSession<Update>(
      updates: updates.stream,
      idOf: (event) => event.id,
      isDone: (event) => event.done,
      cancel: (id) async => cancelled.add(id),
      onStarted: started.add,
      onUpdate: received.add,
      onError: (error, _) => errors.add(error),
      onCleanupError: (error, _) => cleanupErrors.add(error),
    );
  });

  tearDown(() async {
    await session.close();
    await updates.close();
  });

  test('replays early results and done in order, only for its task', () async {
    final reply = Completer<int>();
    final starting = session.start(() => reply.future);
    updates.add(update(99, 'other', done: true));
    updates.add(update(7, 'first'));
    updates.add(update(7, 'last', done: true));
    await flush();
    expect(received, isEmpty);
    reply.complete(7);
    await starting;
    expect(started, [7]);
    expect(received.map((event) => event.value), ['first', 'last']);
    await session.close();
    expect(cancelled, isEmpty);
  });

  for (final close in [false, true]) {
    test('${close ? 'close' : 'stop'} cancels an id arriving later', () async {
      final reply = Completer<int>();
      final starting = session.start(() => reply.future);
      updates.add(update(7, 'before stop'));
      await flush();
      await (close ? session.close() : session.stop());
      reply.complete(7);
      await starting;
      updates.add(update(7, 'after stop', done: true));
      await flush();
      expect(cancelled, [7]);
      expect(started, isEmpty);
      expect(received, isEmpty);
    });
  }

  test('a late first start cannot replace the newer task', () async {
    final first = Completer<int>();
    final second = Completer<int>();
    final a = session.start(() => first.future);
    final b = session.start(() => second.future);
    updates.add(update(1, 'old result', done: true));
    updates.add(update(2, 'new result'));
    await flush();
    second.complete(2);
    await b;
    first.complete(1);
    await a;
    updates.add(update(2, 'new done', done: true));
    await flush();
    expect(started, [2]);
    expect(cancelled, [1]);
    expect(received.map((event) => event.value), ['new result', 'new done']);
  });

  test(
    'starting again cancels the active task and ignores its updates',
    () async {
      await session.start(() async => 1);
      await session.start(() async => 2);
      updates.add(update(1, 'late', done: true));
      updates.add(update(99, 'foreign'));
      updates.add(update(2, 'current'));
      await flush();
      expect(received.map((event) => event.value), ['current']);
      await session.stop();
      await session.close();
      expect(cancelled, [1, 2]);
    },
  );

  test('a stale start error does not fail the newer task', () async {
    final first = Completer<int>();
    final a = session.start(() => first.future);
    await session.start(() async => 2);
    first.completeError(StateError('old failure'));
    await a;
    updates.add(update(2, 'done', done: true));
    await flush();
    expect(errors, isEmpty);
    expect(received.single.value, 'done');
  });

  test(
    'reports synchronous and asynchronous start errors, then can retry',
    () async {
      final error = StateError('start failed');
      await session.start(() => throw error);
      await session.start(() async => throw error);
      expect(errors, [error, error]);
      await session.start(() async => 3);
      updates.add(update(3, 'retry', done: true));
      await flush();
      expect(received.single.value, 'retry');
    },
  );

  test(
    'a foreign event flood before the id fails explicitly and cancels',
    () async {
      final reply = Completer<int>();
      final starting = session.start(() => reply.future);
      for (var i = 0; i < TaskSession.maxEarlyEvents * 10; i++) {
        updates.add(update(99, '$i'));
      }
      await flush();
      expect(errors, hasLength(1));
      expect(received, isEmpty);
      reply.complete(7);
      await starting;
      expect(cancelled, [7]);
      await session.start(() async => 8);
      updates.add(update(8, 'retry', done: true));
      await flush();
      expect(received.single.value, 'retry');
    },
  );

  test('done at the early buffer limit is retained', () async {
    final reply = Completer<int>();
    final starting = session.start(() => reply.future);
    for (var i = 0; i < TaskSession.maxEarlyEvents; i++) {
      updates.add(update(7, '$i', done: i == TaskSession.maxEarlyEvents - 1));
    }
    await flush();
    reply.complete(7);
    await starting;
    expect(errors, isEmpty);
    expect(received, hasLength(TaskSession.maxEarlyEvents));
    expect(received.last.done, isTrue);
    await session.close();
    expect(cancelled, isEmpty);
  });

  test('a broken event stream fails and releases the active task', () async {
    await session.start(() async => 7);
    final error = StateError('stream failed');
    updates.addError(error);
    await flush();
    expect(errors, [error]);
    expect(cancelled, [7]);
  });

  test('closing stops future starts', () async {
    await session.close();
    await session.start(() => throw StateError('must not launch'));
    expect(errors, isEmpty);
    expect(started, isEmpty);
  });

  test(
    'a closed event stream fails a pending start and prevents another',
    () async {
      final reply = Completer<int>();
      final starting = session.start(() => reply.future);
      await updates.close();
      expect(errors, hasLength(1));
      reply.complete(7);
      await starting;
      expect(cancelled, [7]);
      var launched = false;
      await session.start(() async {
        launched = true;
        return 8;
      });
      expect(launched, isFalse);
      expect(errors, hasLength(2));
    },
  );

  test('cleanup errors are reported without failing a newer task', () async {
    await session.close();
    final failure = StateError('cancel failed');
    session = TaskSession<Update>(
      updates: updates.stream,
      idOf: (event) => event.id,
      isDone: (event) => event.done,
      cancel: (id) async => throw failure,
      onUpdate: received.add,
      onError: (error, _) => errors.add(error),
      onCleanupError: (error, _) => cleanupErrors.add(error),
    );
    await session.start(() async => 1);
    await session.start(() async => 2);
    updates.add(update(2, 'new result', done: true));
    await flush();
    expect(errors, isEmpty);
    expect(cleanupErrors, [failure]);
    expect(received.single.value, 'new result');
  });
}
