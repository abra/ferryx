import 'dart:async';
import 'dart:convert';

import 'package:domain_models/domain_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:terminal_feature/terminal_feature.dart';
import 'package:terminal_service/terminal_service.dart';

import 'fakes.dart';

class _MockService extends Mock implements TerminalService {}

class _MockPreferences extends Mock implements PreferencesService {}

/// What a command that floods the terminal costs the window: output comes
/// as the core sends it (64 KiB batches, two in flight until acknowledged),
/// the cubit parses at most a slice per turn of the event loop, and the
/// scrollback stays bounded.
void main() {
  setUpAll(() {
    registerFallbackValue(const TerminalStart(cols: 1, rows: 1));
  });

  test('yes | head -n 200000: every line parsed, the scrollback bounded, '
      'the event loop never held for long', () async {
    final service = _MockService();
    final preferences = _MockPreferences();
    final session = FakeSession();
    when(() => preferences.current).thenReturn(
      const Preferences(terminal: TerminalPreferences(scrollback: 10000)),
    );
    when(() => service.start(any())).thenAnswer((_) async => session);
    final cubit = TerminalSessionCubit(
      service: service,
      preferences: preferences,
      platform: TargetPlatform.macOS,
    );
    cubit.terminal.resize(120, 40);
    cubit.show('/');
    await Future<void>.delayed(Duration.zero);

    const lines = 200000;
    final all = utf8.encode('y\r\n' * lines);
    const batch = 64 * 1024;
    final batches = [
      for (var start = 0; start < all.length; start += batch)
        TerminalOutput(
          Uint8List.sublistView(
            all,
            start,
            start + batch < all.length ? start + batch : all.length,
          ),
        ),
    ];

    // A task in the event loop's queue, as a frame would be: the longest
    // wait between two of them is the longest the window could stall.
    final clock = Stopwatch()..start();
    var probing = true;
    var stall = 0;
    var turns = 0;
    unawaited(() async {
      var last = clock.elapsedMicroseconds;
      while (probing) {
        await Future<void>.delayed(Duration.zero);
        final now = clock.elapsedMicroseconds;
        if (now - last > stall) stall = now - last;
        last = now;
        turns++;
      }
    }());

    // The core: two batches in hand at most until one is acknowledged.
    var sent = 0;
    while (session.acks < batches.length) {
      if (sent < batches.length && sent - session.acks < 2) {
        session.emit(batches[sent++]);
      }
      await Future<void>.delayed(Duration.zero);
    }
    final total = clock.elapsedMilliseconds;
    probing = false;

    final buffer = cubit.terminal.buffer;
    // Bounded: the scrollback and the screen, not 200 000 lines.
    expect(buffer.height, lessThanOrEqualTo(10000 + 40));
    expect(buffer.lines[buffer.height - 41].toString().trim(), 'y');
    debugPrint(
      '${all.length} bytes in ${batches.length} batches: $total ms, the '
      'longest stall ${stall ~/ 1000} ms (debug JIT)',
    );
    // Each 64 KiB batch was parsed over four turns of the event loop at
    // least (16 KiB a turn), with other tasks, frames among them, between.
    expect(turns, greaterThanOrEqualTo(batches.length * 3));
    await cubit.close();
  });
}
