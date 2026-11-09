import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// How the reader wants text pages cut from the screen, as it tells
/// foliate-js's paginator: the side margin as a share of the width (the
/// `gap` attribute), top and bottom margins, the column count (0 picks
/// one or two), the measure (`max-inline-size` set by the reader, the
/// longest line), and a horizontal safe-area inset to keep clear.
@immutable
class TextPageSettings {
  const TextPageSettings({
    this.sideMarginPercent = 6,
    this.topMargin = 48,
    this.bottomMargin = 48,
    this.maxColumnCount = 1,
    this.maxInlineSize = 720,
    this.measure,
    this.safeInlineInset = 0,
  });

  final double sideMarginPercent;
  final double topMargin;
  final double bottomMargin;

  /// Columns side by side; 0 lets the window decide (one, or a spread of
  /// two in a wide landscape window).
  final int maxColumnCount;

  /// foliate-js's column size when the reader sets no measure.
  final double maxInlineSize;

  /// The longest line, in logical pixels: columns keep it by widening
  /// the margins; null fills the page.
  final double? measure;

  final double safeInlineInset;

  @override
  bool operator ==(Object other) =>
      other is TextPageSettings &&
      other.sideMarginPercent == sideMarginPercent &&
      other.topMargin == topMargin &&
      other.bottomMargin == bottomMargin &&
      other.maxColumnCount == maxColumnCount &&
      other.maxInlineSize == maxInlineSize &&
      other.measure == measure &&
      other.safeInlineInset == safeInlineInset;

  @override
  int get hashCode => Object.hash(
    sideMarginPercent,
    topMargin,
    bottomMargin,
    maxColumnCount,
    maxInlineSize,
    measure,
    safeInlineInset,
  );
}

/// Where the columns of a page sit in a viewport: [columns] columns
/// [columnWidth] wide, [gap] apart, with half a gap outside the first and
/// the last, between the top and bottom margins.
@immutable
class TextPageGeometry {
  const TextPageGeometry({
    required this.viewport,
    required this.columns,
    required this.columnWidth,
    required this.gap,
    required this.topMargin,
    required this.bottomMargin,
  });

  /// The geometry [settings] give in a [viewport]; [landscape] is the
  /// window's orientation (a keyboard shortens the page, not the window).
  factory TextPageGeometry.of(
    Size viewport,
    TextPageSettings settings, {
    bool? landscape,
  }) {
    final g = settings.sideMarginPercent / 100;
    // foliate-js widens the column gap so that it equals the outer
    // padding: f⁻¹(x) = -x / (x - 1) of the share.
    final gap = -g / (g - 1) * viewport.width;
    final layout = pageColumnLayout(
      landscape: landscape ?? viewport.width > viewport.height,
      size: viewport.width,
      gap: gap,
      maxColumnCount: settings.maxColumnCount,
      maxInlineSize: settings.maxInlineSize,
      measure: settings.measure,
      safeInset: settings.safeInlineInset,
    );
    return TextPageGeometry(
      viewport: viewport,
      columns: layout.columns,
      columnWidth: math.max(1, layout.columnWidth),
      gap: layout.gap,
      topMargin: settings.topMargin,
      bottomMargin: settings.bottomMargin,
    );
  }

  final Size viewport;
  final int columns;
  final double columnWidth;
  final double gap;
  final double topMargin;
  final double bottomMargin;

  /// The height of a page's text.
  double get pageHeight =>
      math.max(1, viewport.height - topMargin - bottomMargin);

  /// The left edge of column [index] (0 is the leftmost).
  double columnLeft(int index) => gap / 2 + index * (columnWidth + gap);

  @override
  bool operator ==(Object other) =>
      other is TextPageGeometry &&
      other.viewport == viewport &&
      other.columns == columns &&
      other.columnWidth == columnWidth &&
      other.gap == gap &&
      other.topMargin == topMargin &&
      other.bottomMargin == bottomMargin;

  @override
  int get hashCode =>
      Object.hash(viewport, columns, columnWidth, gap, topMargin, bottomMargin);

  @override
  String toString() =>
      'TextPageGeometry($columns × ${columnWidth.toStringAsFixed(1)}, '
      'gap ${gap.toStringAsFixed(1)}, height ${pageHeight.toStringAsFixed(1)})';
}

/// Least share of the measure each page of an automatic spread keeps.
const autoSpreadMinMeasure = 0.625;

/// `pageColumnLayout` of `readflex_page_columns.js`: the columns, the gap
/// between them (twice the outer margin) and the column width for a page
/// [size] wide. Without a [measure] the columns fill the page.
({int columns, double gap, double columnWidth}) pageColumnLayout({
  required bool landscape,
  required double size,
  required double gap,
  required int maxColumnCount,
  required double maxInlineSize,
  double? measure,
  double safeInset = 0,
}) {
  final pageGap = math.max(gap, 2 * safeInset);
  final int columns;
  if (maxColumnCount > 0) {
    columns = maxColumnCount;
  } else if (measure == null) {
    columns = math.min(2, (size / maxInlineSize).ceil());
  } else {
    columns = landscape && size / 2 - pageGap >= measure * autoSpreadMinMeasure
        ? 2
        : 1;
  }
  final columnGap = measure == null
      ? pageGap
      : math.max(pageGap, size / columns - measure);
  return (
    columns: columns,
    gap: columnGap,
    columnWidth: size / columns - columnGap,
  );
}
