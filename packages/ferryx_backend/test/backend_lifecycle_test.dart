import 'dart:io';

import 'package:ferryx_backend/ferryx_backend.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

final _library = File(
  '../../rust/target/debug/'
  '${Platform.isMacOS
      ? 'libferryx_api.dylib'
      : Platform.isWindows
      ? 'ferryx_api.dll'
      : 'libferryx_api.so'}',
);

void main() {
  test('failed initialization is retryable; concurrent and later attempts '
      'share the initialized bridge and event stream', () async {
    // The test runner has no Rust bridge symbols. Loading the wrong library
    // must not poison the process-wide initialization future.
    final missingBridge = ExternalLibrary.process(iKnowHowToUseIt: true);
    expect(
      missingBridge.ffiDynamicLibrary.providesSymbol(
        'frb_get_rust_content_hash',
      ),
      isFalse,
    );
    await expectLater(
      FerryxBackend.initialize(externalLibrary: missingBridge),
      throwsA(isA<ArgumentError>()),
    );

    final library = ExternalLibrary.open(_library.path);
    final first = FerryxBackend.initialize(externalLibrary: library);
    final concurrent = FerryxBackend.initialize(externalLibrary: library);
    expect(concurrent, same(first));
    final backend = await first;
    expect(await concurrent, same(backend));

    // Services can go away with a failed bootstrap and subscribe again.
    final subscription = backend.events.listen((_) {});
    await subscription.cancel();
    final retry = await FerryxBackend.initialize();
    expect(retry, same(backend));
    expect(retry.events, same(backend.events));
    final restored = retry.events.listen((_) {});
    await restored.cancel();
  }, skip: _library.existsSync() ? null : 'run `make core` first');
}
