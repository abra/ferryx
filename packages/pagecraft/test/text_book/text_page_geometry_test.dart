import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// Checked against the WebView paginator's own `pageColumnLayout`
/// (`test/fixtures/readflex_page_columns.json`, recorded before the
/// WebView reader's removal).
void main() {
  test('column layouts match readflex_page_columns.js', () {
    final cases =
        (jsonDecode(
                  File(
                    'test/fixtures/readflex_page_columns.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<List<Object?>>();
    expect(cases, hasLength(120));
    for (final [input as Map<String, Object?>, expected as Map<String, Object?>]
        in cases) {
      final actual = pageColumnLayout(
        landscape: input['landscape']! as bool,
        size: (input['size']! as num).toDouble(),
        gap: (input['gap']! as num).toDouble(),
        maxColumnCount: input['maxColumnCount']! as int,
        maxInlineSize: (input['maxInlineSize']! as num).toDouble(),
        measure: (input['measure'] as num?)?.toDouble(),
        safeInset: (input['safeInset']! as num).toDouble(),
      );
      expect(actual.columns, expected['columns'], reason: '$input');
      expect(actual.gap, closeTo((expected['gap']! as num).toDouble(), 1e-9));
      expect(
        actual.columnWidth,
        closeTo((expected['columnWidth']! as num).toDouble(), 1e-9),
        reason: '$input',
      );
    }
  });

  test('a phone page: margins as foliate-js widens them, one column', () {
    final geometry = TextPageGeometry.of(
      const Size(400, 800),
      const TextPageSettings(
        sideMarginPercent: 5,
        topMargin: 40,
        bottomMargin: 30,
      ),
    );
    // The gap equals the outer padding: -g / (g - 1) of the width.
    expect(geometry.gap, closeTo(0.05 / 0.95 * 400, 1e-9));
    expect(geometry.columns, 1);
    expect(geometry.columnWidth, closeTo(400 - geometry.gap, 1e-9));
    expect(geometry.columnLeft(0), geometry.gap / 2);
    expect(geometry.pageHeight, 730);
  });

  test('a landscape tablet with a measure shows a spread on Auto', () {
    final geometry = TextPageGeometry.of(
      const Size(1366, 1024),
      const TextPageSettings(maxColumnCount: 0, measure: 512),
    );
    expect(geometry.columns, 2);
    expect(geometry.columnWidth, 512);
    expect(geometry.columnLeft(1) - geometry.columnLeft(0), 512 + geometry.gap);
    final portrait = TextPageGeometry.of(
      const Size(1024, 1366),
      const TextPageSettings(maxColumnCount: 0, measure: 512),
    );
    expect(portrait.columns, 1);
  });
}
