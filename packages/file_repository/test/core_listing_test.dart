import 'dart:io';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' show FerryxBackend;
import 'package:file_repository/file_repository.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoring/monitoring.dart';

/// The host library `make core` builds.
final _library = File(
  '../../rust/target/debug/'
  '${Platform.isMacOS
      ? 'libferryx_api.dylib'
      : Platform.isWindows
      ? 'ferryx_api.dll'
      : 'libferryx_api.so'}',
);

/// Rows in the folder; `FERRYX_LISTING_ROWS=100000` times a large one.
final _rows =
    int.tryParse(Platform.environment['FERRYX_LISTING_ROWS'] ?? '') ?? 3000;

void main() {
  final skip = _library.existsSync() ? null : 'run `make core` first';
  late FileRepository files;
  late Directory dir;

  setUpAll(() async {
    if (skip != null) return;
    final backend = await FerryxBackend.initialize(
      externalLibrary: ExternalLibrary.open(_library.path),
    );
    files = FileRepository(backend: backend, logger: Logger());
  });

  setUp(() {
    if (skip != null) return;
    dir = Directory.systemTemp.createTempSync('listing');
    for (var i = 0; i < _rows; i++) {
      File('${dir.path}/file ${'x' * (i % 13)} $i.txt').writeAsStringSync('');
    }
  });

  tearDown(() {
    if (skip != null) return;
    dir.deleteSync(recursive: true);
  });

  Future<T> timed<T>(String what, Future<T> Function() run) async {
    final clock = Stopwatch()..start();
    final result = await run();
    // ignore: avoid_print
    print('$what: ${clock.elapsedMilliseconds} ms');
    return result;
  }

  test('a read again and a resort keep the rows the panel has: only the '
      'changed ones are made anew', () async {
    final location = Location.native(dir.resolveSymbolicLinksSync());
    final listing = await timed(
      'open $_rows rows',
      () => files.openListing('t', location, const ListingOptions()),
    );
    expect(listing.entries.length, _rows + 1);

    final changed = files.directoryChanges.firstWhere((id) => id == 't');
    File('${location.path}/aaa new.txt').writeAsStringSync('n');
    await changed.timeout(const Duration(seconds: 10));
    final again = await timed(
      'read one change',
      () => files.refreshListing('t'),
    );
    expect(again.entries.length, _rows + 2);
    final added = again.entries.indexWhere((e) => e.name == 'aaa new.txt');
    expect(added, 1);
    final before = {for (final e in listing.entries) e.name: e};
    for (final row in again.entries) {
      if (row.name == 'aaa new.txt') continue;
      expect(identical(row, before[row.name]), isTrue, reason: row.name);
    }

    final resorted = await timed(
      'resort',
      () => files.resortListing(
        't',
        const ListingOptions(
          sort: SortOptions(field: SortField.name, descending: true),
        ),
      ),
    );
    expect(resorted.entries.first.isParent, isTrue);
    expect(resorted.entries.last.name, 'aaa new.txt');
    expect(identical(resorted.entries.last, again.entries[1]), isTrue);

    final whole = await timed(
      'read whole (⌘R)',
      () => files.refreshListing('t'),
    );
    expect(
      whole.entries.indexed.every(
        (r) => identical(r.$2, resorted.entries[r.$1]),
      ),
      isTrue,
    );
    await files.closeListing('t');
  }, skip: skip);
}
