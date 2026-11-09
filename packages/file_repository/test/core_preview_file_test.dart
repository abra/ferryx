import 'dart:convert';
import 'dart:io';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' show FerryxBackend;
import 'package:file_repository/file_repository.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoring/monitoring.dart';

final _library = File(
  '../../rust/target/debug/'
  '${Platform.isMacOS
      ? 'libferryx_api.dylib'
      : Platform.isWindows
      ? 'ferryx_api.dll'
      : 'libferryx_api.so'}',
);

// A stored ZIP with books/book.epub containing "preview contents".
final _archive = base64Decode(
  'UEsDBBQAAAAAAAAAIVzTb6xcEAAAABAAAAAPAAAAYm9va3MvYm9vay5lcHVicHJldmlldyBj'
  'b250ZW50c1BLAQIUAxQAAAAAAAAAIVzTb6xcEAAAABAAAAAPAAAAAAAAAAAAAACAAQAAAABi'
  'b29rcy9ib29rLmVwdWJQSwUGAAAAAAEAAQA9AAAAPQAAAAAA',
);

void main() {
  final skip = _library.existsSync() ? null : 'run `make core` first';
  late FerryxBackend backend;
  late FileRepository files;
  late Directory directory;
  var disposed = false;
  final cancelled = isA<FerryxException>().having(
    (e) => e.kind,
    'kind',
    FerryxErrorKind.cancelled,
  );

  setUpAll(() async {
    if (skip != null) return;
    backend = await FerryxBackend.initialize(
      externalLibrary: ExternalLibrary.open(_library.path),
    );
  });

  setUp(() {
    if (skip != null) return;
    files = FileRepository(backend: backend, logger: Logger());
    directory = Directory.systemTemp.createTempSync('preview-lease-test');
    disposed = false;
  });

  tearDown(() async {
    if (skip != null) return;
    if (!disposed) await files.dispose();
    directory.deleteSync(recursive: true);
  });

  test(
    'native path is memoized and closing never deletes the source',
    () async {
      final source = File('${directory.path}/book.pdf')
        ..writeAsStringSync('source');
      final lease = files.preparePreview(Location.native(source.path));
      final first = lease.path;
      expect(identical(lease.path, first), isTrue);
      expect(await first, source.path);
      final closed = lease.close();
      expect(identical(lease.close(), closed), isTrue);
      await closed;
      expect(source.readAsStringSync(), 'source');
      await expectLater(lease.path, throwsA(cancelled));
    },
    skip: skip,
  );

  test(
    'archive staging is lazy and its private path lives until close',
    () async {
      final archive = File('${directory.path}/source.zip');
      final lease = files.preparePreview(
        Location.inArchive(archive: archive.path, path: 'books/book.epub'),
      );
      // Registration must not try to open a file that does not exist yet.
      archive.writeAsBytesSync(_archive);
      final staged = File(await lease.path);
      expect(staged.path, endsWith('book.epub'));
      expect(staged.readAsStringSync(), 'preview contents');
      await lease.close();
      expect(staged.parent.existsSync(), isFalse);
      expect(archive.existsSync(), isTrue);
    },
    skip: skip,
  );

  test('closing suppresses a worker result delivered after close', () async {
    final source = File('${directory.path}/book.pdf')
      ..writeAsStringSync('source');
    final lease = files.preparePreview(Location.native(source.path));
    final result = expectLater(lease.path, throwsA(cancelled));
    await lease.close();
    await result;
    expect(source.existsSync(), isTrue);
  }, skip: skip);

  test('repository disposal closes prepared and unused leases', () async {
    final archive = File('${directory.path}/source.zip')
      ..writeAsBytesSync(_archive);
    final staged = files.preparePreview(
      Location.inArchive(archive: archive.path, path: 'books/book.epub'),
    );
    final path = File(await staged.path);
    final unused = files.preparePreview(
      const Location.inArchive(archive: 'missing.zip', path: 'missing.pdf'),
    );
    await files.dispose();
    disposed = true;
    expect(path.parent.existsSync(), isFalse);
    await expectLater(unused.path, throwsA(cancelled));
    expect(
      () => files.preparePreview(Location.native(archive.path)),
      throwsStateError,
    );
    expect(archive.existsSync(), isTrue);
  }, skip: skip);
}
