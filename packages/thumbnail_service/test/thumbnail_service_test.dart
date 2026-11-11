import 'dart:async';
import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thumbnail_service/thumbnail_service.dart';

// No repository call is expected when a test decoder is injected.
class _Files implements FileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ThumbnailRequest request(String name, {int revision = 1}) => ThumbnailRequest(
  location: Location.native('/$name.png'),
  entry: FileEntry(
    name: '$name.png',
    path: '/$name.png',
    kind: EntryKind.file,
    isDir: false,
    extension: 'png',
    size: 100,
    modified: DateTime.fromMillisecondsSinceEpoch(revision),
  ),
  targetWidth: 160,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'deduplicates work, bounds concurrency and cancels queued work',
    () async {
      final jobs = <Completer<Uint8List?>>[];
      final service = ThumbnailService(
        files: _Files(),
        loader: (_) {
          final job = Completer<Uint8List?>();
          jobs.add(job);
          return job.future;
        },
      );
      final a = service.acquire(request('a')),
          same = service.acquire(request('a'));
      final b = service.acquire(request('b')),
          c = service.acquire(request('c'));
      c.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(jobs.length, 2);
      jobs[0].complete(Uint8List.fromList([1]));
      jobs[1].complete(Uint8List.fromList([2]));
      expect(await a.bytes, [1]);
      expect(await same.bytes, [1]);
      expect(await b.bytes, [2]);
      expect(await c.bytes, isNull);
      expect(jobs.length, 2);
      await service.dispose();
      a.cancel();
    },
  );
  test('LRU budgets, metadata changes, failures and memory pressure', () async {
    var calls = 0;
    final service = ThumbnailService(
      files: _Files(),
      maxEntries: 2,
      maxBytes: 4,
      loader: (r) async {
        calls++;
        return r.location.name.startsWith('bad')
            ? null
            : Uint8List.fromList([1, 2]);
      },
    );
    Future<void> load(String name, {int revision = 1}) async {
      await service.acquire(request(name, revision: revision)).bytes;
    }

    await load('a');
    await load('b');
    await load('a');
    expect(calls, 2);
    await load('c');
    await load('b');
    expect(calls, 4);
    await load('bad');
    await load('bad');
    expect(calls, 5);
    await load('b', revision: 2);
    expect(calls, 6);
    service.didHaveMemoryPressure();
    await load('b', revision: 2);
    expect(calls, 7);
    await service.dispose();
  });
  test(
    'closing waits for active decode and never publishes retired results',
    () async {
      final job = Completer<Uint8List?>();
      final service = ThumbnailService(
        files: _Files(),
        loader: (_) => job.future,
      );
      final lease = service.acquire(request('a'));
      await Future<void>.delayed(Duration.zero);
      var closed = false;
      final closing = service.dispose().then((_) => closed = true);
      expect(closed, isFalse);
      job.complete(Uint8List(2));
      await closing;
      lease.cancel();
      expect(await service.acquire(request('a')).bytes, isNull);
    },
  );
}
