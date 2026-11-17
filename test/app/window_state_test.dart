import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ferryx/app/window_state.dart';
import 'package:preferences_service/preferences_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'flushing a maximized window keeps the last move before debounce',
    () async {
      const channel = MethodChannel('window_manager');
      var maximized = false;
      final normalRead = Completer<void>();
      final normalBounds = {
        'x': 42.0,
        'y': 61.0,
        'width': 1100.0,
        'height': 760.0,
      };
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        switch (call.method) {
          case 'isMaximized':
            return maximized;
          case 'isMinimized':
          case 'isFullScreen':
            return false;
          case 'getBounds':
            if (!maximized) {
              normalRead.complete();
              return normalBounds;
            }
            return {'x': 0.0, 'y': 0.0, 'width': 1920.0, 'height': 1080.0};
        }
        fail('Unexpected window method ${call.method}');
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final storage = InMemoryPreferencesStorage();
      final preferences = await PreferencesService.create(storage: storage);
      final saver = WindowStateSaver(preferences);
      addTearDown(preferences.dispose);
      addTearDown(saver.dispose);

      saver.onWindowMoved();
      await normalRead.future.timeout(const Duration(seconds: 1));
      expect(await storage.load(), isNull);
      maximized = true;
      saver.onWindowMaximize();
      await saver.flush();

      final saved = await storage.load();
      expect(saved?.windowMaximized, isTrue);
      expect(
        saved?.windowBounds,
        const WindowBounds(x: 42, y: 61, width: 1100, height: 760),
      );
    },
  );

  test(
    'an older window read cannot replace the more recent normal frame',
    () async {
      const channel = MethodChannel('window_manager');
      final older = Completer<Map<String, double>>();
      var reads = 0;
      var maximized = false;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        switch (call.method) {
          case 'isMaximized':
            return maximized;
          case 'isMinimized':
          case 'isFullScreen':
            return false;
          case 'getBounds':
            if (++reads == 1) return older.future;
            return {'x': 60.0, 'y': 30.0, 'width': 1050.0, 'height': 740.0};
        }
        fail('Unexpected window method ${call.method}');
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final storage = InMemoryPreferencesStorage();
      final preferences = await PreferencesService.create(storage: storage);
      final saver = WindowStateSaver(preferences);
      addTearDown(preferences.dispose);
      addTearDown(saver.dispose);

      saver.onWindowMoved();
      saver.onWindowMoved();
      await Future<void>.delayed(Duration.zero);
      maximized = true;
      older.complete({'x': 15.0, 'y': 20.0, 'width': 1000.0, 'height': 700.0});
      await Future<void>.delayed(Duration.zero);
      await saver.flush();

      expect((await storage.load())?.windowBounds?.x, 60);
    },
  );

  group('fitWindow', () {
    // A 1920×1080 main screen less a 25-pt menu bar, and a 1024×768 one
    // to its right less a 48-px taskbar.
    const main = Rect.fromLTWH(0, 25, 1920, 1055);
    const side = Rect.fromLTWH(1920, 0, 1024, 720);

    test('a first run opens at the first size, centred on the main screen', () {
      expect(
        fitWindow(wanted: null, workAreas: const [main, side]),
        const Rect.fromLTWH(320, 152.5, 1280, 800),
      );
    });

    test('a first run on a small screen fills its work area, the title bar '
        'below its top and the bottom above the taskbar', () {
      expect(
        fitWindow(
          wanted: null,
          workAreas: const [Rect.fromLTWH(0, 0, 1024, 720)],
        ),
        const Rect.fromLTWH(0, 0, 1024, 720),
      );
    });

    test('a remembered frame on a screen stays where it was', () {
      const frame = Rect.fromLTWH(100, 200, 1000, 700);
      expect(fitWindow(wanted: frame, workAreas: const [main, side]), frame);
      const there = Rect.fromLTWH(2000, 10, 900, 650);
      expect(fitWindow(wanted: there, workAreas: const [main, side]), there);
    });

    test('a frame over an edge moves in whole, its size kept', () {
      expect(
        fitWindow(
          wanted: const Rect.fromLTWH(1500, 0, 1000, 700),
          workAreas: const [main],
        ),
        const Rect.fromLTWH(920, 25, 1000, 700),
        reason: 'past the right edge and under the menu bar',
      );
    });

    test('a frame across two screens goes to the one it is mostly on, '
        'shrunk to fit it', () {
      expect(
        fitWindow(
          wanted: const Rect.fromLTWH(1700, 100, 1200, 800),
          workAreas: const [main, side],
        ),
        const Rect.fromLTWH(1920, 0, 1024, 720),
      );
    });

    test('a frame on a screen since unplugged opens centred on the main', () {
      expect(
        fitWindow(
          wanted: const Rect.fromLTWH(3500, 300, 1000, 700),
          workAreas: const [main, side],
        ),
        const Rect.fromLTWH(460, 202.5, 1000, 700),
      );
    });

    test('a work area under the minimum gets the minimum at its top left', () {
      expect(
        fitWindow(
          wanted: const Rect.fromLTWH(50, 50, 1000, 700),
          workAreas: const [Rect.fromLTWH(0, 30, 800, 560)],
        ),
        const Rect.fromLTWH(0, 30, 900, 600),
      );
      expect(
        fitWindow(
          wanted: null,
          workAreas: const [Rect.fromLTWH(0, 30, 800, 560)],
        ),
        const Rect.fromLTWH(0, 30, 900, 600),
      );
    });

    test('without screens: the remembered frame, at least the minimum; a '
        'first run as set up', () {
      expect(
        fitWindow(
          wanted: const Rect.fromLTWH(10, 20, 500, 400),
          workAreas: const [],
        ),
        const Rect.fromLTWH(10, 20, 900, 600),
      );
      expect(fitWindow(wanted: null, workAreas: const []), isNull);
    });
  });
}
