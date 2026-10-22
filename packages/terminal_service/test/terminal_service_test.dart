import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' show FerryxBackend;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_service/terminal_service.dart';

/// The host library `make core` builds.
final _library = File(
  '../../rust/target/debug/'
  '${Platform.isMacOS ? 'libferryx_api.dylib' : 'libferryx_api.so'}',
);

/// A session and what it said, read the way the terminal feature reads it.
class _Watch {
  _Watch(this.session) {
    _subscription = session.updates.listen((update) {
      switch (update) {
        case TerminalOutput(:final bytes):
          output.write(utf8.decode(bytes, allowMalformed: true));
          session.ack();
        case TerminalShellState():
          states.add(update);
        case TerminalExited(:final exitCode):
          exited = exitCode ?? -1;
      }
      _changed.add(null);
    });
  }

  final TerminalSession session;
  final output = StringBuffer();
  final states = <TerminalShellState>[];
  int? exited;
  final _changed = StreamController<void>.broadcast();
  late final StreamSubscription<TerminalUpdate> _subscription;

  Future<void> until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done()) {
      final left = deadline.difference(DateTime.now());
      if (left.isNegative) fail('timed out; output: $output');
      await _changed.stream.first.timeout(left, onTimeout: () {});
    }
  }

  Future<void> dispose() => _subscription.cancel();
}

void main() {
  final skip = Platform.isWindows
      ? 'ConPTY sessions are not run in tests'
      : (_library.existsSync() ? null : 'run `make core` first');

  late TerminalService service;

  setUpAll(() async {
    if (skip != null) return;
    await FerryxBackend.initialize(
      externalLibrary: ExternalLibrary.open(_library.path),
    );
  });

  setUp(() => service = TerminalService());
  tearDown(() => service.dispose());

  test('a shell through the bridge: output, state, folder, end', () async {
    final start = Directory.systemTemp.createTempSync('ferryx_term_a');
    final other = Directory.systemTemp.createTempSync('ferryx_term_b');
    addTearDown(() {
      start.deleteSync(recursive: true);
      other.deleteSync(recursive: true);
    });
    final session = await service.start(
      TerminalStart(shell: '/bin/sh', folder: start.path, cols: 80, rows: 24),
    );
    final watch = _Watch(session);
    addTearDown(watch.dispose);

    final home = start.resolveSymbolicLinksSync();
    await watch.until(
      () => watch.states.any((s) => s.idle == true && s.folder == home),
    );
    expect(session.state(), TerminalShellState(idle: true, folder: home));

    session.write(utf8.encode('echo dart-\$((20+1))\r'));
    await watch.until(() => watch.output.toString().contains('dart-21'));

    expect(await session.changeDirectory(other.path), isTrue);
    await watch.until(
      () =>
          watch.states.last ==
          TerminalShellState(idle: true, folder: other.path),
    );

    session.write(utf8.encode('exit 4\r'));
    await watch.until(() => watch.exited != null);
    expect(watch.exited, 4);
    // Typing into an ended shell is dropped quietly.
    session.write(utf8.encode('echo late\r'));
    await session.close();
  }, skip: skip);

  test('a shell that is not there is a typed error', () async {
    await expectLater(
      service.start(
        const TerminalStart(shell: '/no/such/shell', cols: 80, rows: 24),
      ),
      throwsA(
        isA<FerryxException>()
            .having((e) => e.kind, 'kind', FerryxErrorKind.notFound)
            .having((e) => e.path, 'path', '/no/such/shell'),
      ),
    );
  }, skip: skip);

  test('the default shell is a path', () {
    expect(service.defaultShell(), startsWith('/'));
  }, skip: skip);
}
