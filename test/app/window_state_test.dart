import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ferryx/app/window_state.dart';

void main() {
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
