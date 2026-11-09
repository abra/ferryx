import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  // 0 <r>, 1 <p>, 2 "ab", 3 <img>, 4 "cd", 5 <sup>, 6 "1", 7 "ef", 8 <q>
  late ContentDocument doc;
  setUp(() {
    doc = ContentDocument.parseXml(
      '<r><p>ab<img/>cd<sup>1</sup>ef</p><q/></r>',
    );
  });

  test('the fixture numbers its nodes in document order', () {
    expect(doc.textOf(2), 'ab');
    expect(doc.localNameOf(3), 'img');
    expect(doc.localNameOf(5), 'sup');
    expect(doc.textOf(6), '1');
    expect(doc.localNameOf(8), 'q');
  });

  test('points order as DOM boundaries do', () {
    final ordered = [
      const TextPoint(2, 0),
      const TextPoint(2, 2),
      const TextPoint(3, 0), // before the image
      const TextPoint(3, 1), // after it
      const TextPoint(4, 1),
      const TextPoint(5, 0), // before <sup>
      const TextPoint(6, 1), // inside it
      const TextPoint(5, 1), // after it and its text
      const TextPoint(7, 2),
      const TextPoint(8, 0),
      const TextPoint(99, 0), // past the end
    ];
    for (var i = 0; i < ordered.length; i++) {
      for (var j = 0; j < ordered.length; j++) {
        expect(
          doc.comparePoints(ordered[i], ordered[j]).sign,
          (i - j).sign,
          reason: '${ordered[i]} vs ${ordered[j]}',
        );
      }
    }
    expect(
      doc.comparePoints(const TextPoint(5, 1), const TextPoint(7, 0)),
      lessThan(0),
      reason: 'after <sup> is before the text that follows it',
    );
  });

  test('ranges share characters only when they overlap', () {
    const ab = TextPointRange(TextPoint(2, 0), TextPoint(2, 2));
    const bc = TextPointRange(TextPoint(2, 1), TextPoint(4, 1));
    const cd = TextPointRange(TextPoint(4, 0), TextPoint(4, 2));
    const empty = TextPointRange(TextPoint(2, 1), TextPoint(2, 1));
    expect(doc.rangesIntersect(ab, bc), isTrue);
    expect(doc.rangesIntersect(bc, cd), isTrue);
    expect(doc.rangesIntersect(ab, cd), isFalse, reason: 'apart');
    expect(
      doc.rangesIntersect(
        ab,
        const TextPointRange(TextPoint(2, 2), TextPoint(4, 1)),
      ),
      isFalse,
      reason: 'touching',
    );
    expect(doc.rangesIntersect(ab, empty), isFalse);
    expect(doc.isCollapsedRange(empty), isTrue);
    expect(doc.rangeContains(bc, cd), isFalse);
    expect(
      doc.rangeContains(
        const TextPointRange(TextPoint(2, 0), TextPoint(7, 2)),
        bc,
      ),
      isTrue,
    );
  });

  test('range text is the text nodes inside, as Range.toString()', () {
    String text(TextPoint a, TextPoint b) =>
        doc.textOfRange(TextPointRange(a, b));
    expect(text(const TextPoint(2, 1), const TextPoint(7, 1)), 'bcd1e');
    expect(text(const TextPoint(3, 0), const TextPoint(5, 0)), 'cd');
    expect(text(const TextPoint(3, 1), const TextPoint(5, 1)), 'cd1');
    expect(text(const TextPoint(5, 1), const TextPoint(8, 0)), 'ef');
    expect(text(const TextPoint(7, 1), const TextPoint(2, 0)), '');
  });

  test('points convert to DOM boundaries and back', () {
    final p = doc.node(1);
    expect(doc.cfiPointOf(const TextPoint(2, 1)), CfiPoint(doc.node(2), 1));
    expect(doc.cfiPointOf(const TextPoint(3, 0)), CfiPoint(p, 1));
    expect(doc.cfiPointOf(const TextPoint(3, 1)), CfiPoint(p, 2));
    expect(doc.cfiPointOf(const TextPoint(5, 1)), CfiPoint(p, 4));
    for (final point in const [
      TextPoint(2, 0),
      TextPoint(2, 2),
      TextPoint(3, 0),
      TextPoint(4, 1),
      TextPoint(5, 0),
      TextPoint(6, 1),
      TextPoint(7, 2),
    ]) {
      final back = doc.textPointOf(doc.cfiPointOf(point));
      expect(doc.comparePoints(back, point), 0, reason: '$point → $back');
    }
    // The end of an element's children: after its last child.
    expect(doc.textPointOf(CfiPoint(p, 5)), const TextPoint(7, 2));
    expect(doc.textPointOf(CfiPoint(doc.node(0), 2)), const TextPoint(8, 1));
    expect(doc.textPointOf(CfiPoint(doc.node(8), 0)), const TextPoint(8, 0));
  });

  test('a range survives a trip through a CFI string', () {
    const range = TextPointRange(TextPoint(2, 1), TextPoint(7, 1));
    final cfi = cfiFromRange(doc.cfiRangeOf(range));
    final back = doc.textRangeOf(cfiToRange(doc, Cfi.parse(cfi.toString())));
    expect(doc.textOfRange(back), 'bcd1e');
  });
}
