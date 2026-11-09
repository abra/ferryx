import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  test('the ink of a line from the TrueType outlines', () {
    final font = File(
      'test/fixtures/fonts/NotoSans-Ascii.ttf',
    ).readAsBytesSync();
    final ink = fontInkOf(font)!;
    // fontTools: the tallest of b d f h k l and capitals, the deepest of
    // g j p q y, over 1000 units per em.
    expect(ink.ascent, closeTo(0.765, 1e-9));
    expect(ink.descent, closeTo(0.24, 1e-9));
  });

  test('the ink of the glyphs a text has', () {
    final ink = fontInkOf(
      File('test/fixtures/fonts/NotoSans-Ascii.ttf').readAsBytesSync(),
    )!;
    // fontTools: a 0.545/-0.01, c and e 0.546/-0.01, H 0.714, g -0.24.
    final ace = ink.extentOf('ace');
    expect(ace.ascent, closeTo(0.546, 1e-9));
    expect(ace.descent, closeTo(0.01, 1e-9));
    expect(ink.extentOf('Hg').ascent, closeTo(0.714, 1e-9));
    expect(ink.extentOf('Hg').descent, closeTo(0.24, 1e-9));
    expect(ink.extentOf('xHx', 1, 2).ascent, closeTo(0.714, 1e-9));
    expect(ink.extentOf('x').descent, 0, reason: 'nothing below');
    final hyphen = ink.extentOf('-');
    expect(hyphen.descent, 0, reason: 'above the baseline');
    expect(ink.extentOf('  \u00AD'), (ascent: 0.0, descent: 0.0));
    // Glyphs the font lacks are drawn by another: the font's tallest.
    expect(ink.extentOf('aЖ'), (ascent: ink.ascent, descent: ink.descent));
    expect(ink.extentOf('a😀'), (ascent: ink.ascent, descent: ink.descent));
    // Ink given by hand has no glyphs: always the tallest.
    const given = FontInk(ascent: 0.7, descent: 0.2);
    expect(given.extentOf('x'), (ascent: 0.7, descent: 0.2));
  });

  test('fonts it cannot read give nothing', () {
    expect(fontInkOf(Uint8List(0)), isNull);
    expect(fontInkOf(Uint8List.fromList(List.filled(64, 7))), isNull);
    final woff = File(
      'test/fixtures/fonts/NotoSans-Ascii.woff',
    ).readAsBytesSync();
    expect(fontInkOf(woff), isNull, reason: 'unpack it first');
    expect(fontInkOf(sfntOf(woff)!), isNotNull);
  });
}
