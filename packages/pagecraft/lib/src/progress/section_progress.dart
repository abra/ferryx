/// Reading progress through a book by the sizes of its sections:
/// foliate-js's `SectionProgress` (`progress.js`), so fractions, locations
/// and the time left match what the WebView reader reported and saved.
library;

import 'package:meta/meta.dart';

/// Progress at one place in a book.
@immutable
class ProgressDetails {
  const ProgressDetails({
    required this.fraction,
    required this.section,
    required this.sectionCount,
    required this.location,
    required this.nextLocation,
    required this.locationCount,
    required this.sectionTimeLeft,
    required this.totalTimeLeft,
  });

  /// Through the whole book, `[0, 1]`: the end of what is shown.
  final double fraction;
  final int section;
  final int sectionCount;

  /// Size-derived locations (`sizePerLocation` bytes each), the reader's
  /// "page" numbers for reflowable books.
  final int location;
  final int nextLocation;
  final int locationCount;

  /// Time left, in the units of `sizePerTimeUnit`.
  final double sectionTimeLeft;
  final double totalTimeLeft;
}

class SectionProgress {
  /// [sizes] are the sections' sizes; sections not in the reading order
  /// ([linear] false) and empty ones count as 0, as in foliate-js.
  SectionProgress(
    List<int> sizes, {
    List<bool>? linear,
    this.sizePerLocation = 1500,
    this.sizePerTimeUnit = 1600,
  }) : sizes = [
         for (var i = 0; i < sizes.length; i++)
           (linear == null || linear[i]) && sizes[i] > 0 ? sizes[i] : 0,
       ] {
    var sum = 0;
    for (final size in this.sizes) {
      sum += size;
    }
    sizeTotal = sum;
    var running = 0;
    _sectionFractions = [
      0,
      for (final size in this.sizes) (running += size) / sizeTotal,
    ];
  }

  final List<int> sizes;
  final int sizePerLocation;
  final int sizePerTimeUnit;
  late final int sizeTotal;
  late final List<double> _sectionFractions;

  /// The progress at [fractionInSection] of section [index], with
  /// [pageFraction] of the section shown (`getProgress`).
  ProgressDetails progress(
    int index,
    double fractionInSection, {
    double pageFraction = 0,
  }) {
    final sizeInSection = index >= 0 && index < sizes.length ? sizes[index] : 0;
    var sizeBefore = 0;
    for (var i = 0; i < index && i < sizes.length; i++) {
      sizeBefore += sizes[i];
    }
    final size = sizeBefore + fractionInSection * sizeInSection;
    final nextSize = size + pageFraction * sizeInSection;
    final remainingTotal = sizeTotal - size;
    final remainingSection = (1 - fractionInSection) * sizeInSection;
    return ProgressDetails(
      fraction: sizeTotal == 0 ? 0 : nextSize / sizeTotal,
      section: index,
      sectionCount: sizes.length,
      location: (size / sizePerLocation).floor(),
      nextLocation: (nextSize / sizePerLocation).floor(),
      locationCount: (sizeTotal / sizePerLocation).ceil(),
      sectionTimeLeft: remainingSection / sizePerTimeUnit,
      totalTimeLeft: remainingTotal / sizePerTimeUnit,
    );
  }

  /// The section and the fraction within it at [fraction] of the book:
  /// the inverse of [progress] (`getSection`).
  (int, double) section(double fraction) {
    if (fraction <= 0 || sizeTotal == 0) return (0, 0);
    if (fraction >= 1) return (sizes.length - 1, 1);
    final f = fraction + 2.220446049250313e-16;
    var index = _sectionFractions.indexWhere((x) => x > f) - 1;
    if (index < 0) return (0, 0);
    while (index < sizes.length && sizes[index] == 0) {
      index++;
    }
    if (index >= sizes.length) return (sizes.length - 1, 1);
    final fractionInSection =
        (f - _sectionFractions[index]) / (sizes[index] / sizeTotal);
    return (index, fractionInSection);
  }
}
