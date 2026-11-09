import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// Expected values are what foliate-js's `progress.js` computes for the
/// same sections (run with node): sizes 100, 500 (not linear), 300, 0,
/// 600; 100 bytes a location, 160 a time unit.
void main() {
  final progress = SectionProgress(
    [100, 500, 300, 0, 600],
    linear: [true, false, true, true, true],
    sizePerLocation: 100,
    sizePerTimeUnit: 160,
  );

  test('sizes leave out sections outside the reading order', () {
    expect(progress.sizes, [100, 0, 300, 0, 600]);
    expect(progress.sizeTotal, 1000);
  });

  test('progress at a place matches progress.js', () {
    void expectProgress(
      int index,
      double fraction,
      double pageFraction, {
      required double total,
      required int location,
      required int next,
      required double sectionTime,
      required double totalTime,
    }) {
      final p = progress.progress(index, fraction, pageFraction: pageFraction);
      expect(p.fraction, closeTo(total, 1e-12));
      expect(p.section, index);
      expect(p.sectionCount, 5);
      expect(p.location, location);
      expect(p.nextLocation, next);
      expect(p.locationCount, 10);
      expect(p.sectionTimeLeft, closeTo(sectionTime, 1e-12));
      expect(p.totalTimeLeft, closeTo(totalTime, 1e-12));
    }

    expectProgress(
      0,
      0,
      0,
      total: 0,
      location: 0,
      next: 0,
      sectionTime: 0.625,
      totalTime: 6.25,
    );
    expectProgress(
      2,
      0.5,
      0.1,
      total: 0.28,
      location: 2,
      next: 2,
      sectionTime: 0.9375,
      totalTime: 4.6875,
    );
    expectProgress(
      4,
      1,
      0,
      total: 1,
      location: 10,
      next: 10,
      sectionTime: 0,
      totalTime: 0,
    );
    expectProgress(
      4,
      0.25,
      0.25,
      total: 0.7,
      location: 5,
      next: 7,
      sectionTime: 2.8125,
      totalTime: 2.8125,
    );
    expectProgress(
      3,
      0,
      0,
      total: 0.4,
      location: 4,
      next: 4,
      sectionTime: 0,
      totalTime: 3.75,
    );
  });

  test(
    'the section at a fraction matches progress.js, skipping empty ones',
    () {
      void expectSection(double fraction, int index, double inSection) {
        final (i, f) = progress.section(fraction);
        expect(i, index, reason: '$fraction');
        expect(f, closeTo(inSection, 1e-9), reason: '$fraction');
      }

      expectSection(0, 0, 0);
      expectSection(0.05, 0, 0.5);
      expectSection(0.1, 2, 0);
      expectSection(0.28, 2, 0.6);
      expectSection(0.4, 4, 0);
      expectSection(0.99, 4, 0.9833333333333337);
      expectSection(1, 4, 1);
      expectSection(-1, 0, 0);
      expectSection(2, 4, 1);
    },
  );

  test('an empty book is at its start', () {
    final empty = SectionProgress([0, 0]);
    expect(empty.progress(0, 0.5).fraction, 0);
    expect(empty.section(0.5), (0, 0));
  });
}
