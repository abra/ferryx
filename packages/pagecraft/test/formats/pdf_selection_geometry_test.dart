import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/pdf.dart';

void main() {
  test('dragging below glyphs still finds insertion edges', () {
    final layer = _layer('abc');
    expect(layer.charIndexAt(19, 10), isNull);
    expect(layer.positionAt(1, 10), 0);
    expect(layer.positionAt(9, 10), 1);
    expect(layer.positionAt(19, 14), 2);
    expect(layer.positionAt(-80, 10), 0);
    expect(layer.positionAt(140, 10), 3);
  });

  test('dragging between lines picks the nearest line', () {
    final layer = _layer('abc\ndef');
    expect(layer.positionAt(9, 12), 1);
    expect(layer.positionAt(9, 18), 5);
    expect(layer.positionAt(200, 18), 7);
    expect(layer.positionAt(9, -30), 1);
    expect(layer.positionAt(9, 200), 5);
  });

  test('separate columns at the same height use horizontal proximity', () {
    final layer = PdfTextLayer(
      pageIndex: 0,
      text: 'ab\ncd',
      charBoxes: const [
        PdfBox(0, 0, 10, 10),
        PdfBox(10, 0, 20, 10),
        PdfBox(0, 0, 0, 0),
        PdfBox(200, 0, 210, 10),
        PdfBox(210, 0, 220, 10),
      ],
    );
    expect(layer.positionAt(1, 12), 0);
    expect(layer.positionAt(219, 12), 5);
  });

  test('caret affinity follows the selected side of a line break', () {
    final layer = _layer('abc\ndef');
    final before = layer.caretAt(3, upstream: true)!;
    final after = layer.caretAt(3)!;
    expect(before.box, const PdfBox(30, 0, 30, 10));
    expect(before.lineBox, const PdfBox(0, 0, 30, 10));
    expect(after.box, const PdfBox(0, 20, 0, 30));
    expect(after.lineBox, const PdfBox(0, 20, 30, 30));
    expect(layer.caretAt(0, upstream: true)!.box.left, 0);
    expect(layer.caretAt(layer.text.length)!.box.left, 30);
  });

  test('generated spaces preserve upstream and downstream caret edges', () {
    final layer = PdfTextLayer(
      pageIndex: 0,
      text: 'a b',
      charBoxes: const [
        PdfBox(0, 0, 10, 10),
        PdfBox(0, 0, 0, 0),
        PdfBox(20, 0, 30, 10),
      ],
    );
    expect(layer.caretAt(1, upstream: true)!.box.left, 10);
    expect(layer.caretAt(1)!.box.left, 20);
    expect(layer.caretAt(2, upstream: true)!.box.left, 10);
    expect(layer.caretAt(2)!.box.left, 20);
  });

  test('RTL edges follow the document glyphs', () {
    final layer = PdfTextLayer(
      pageIndex: 0,
      text: 'ابت',
      charBoxes: const [
        PdfBox(30, 0, 40, 10),
        PdfBox(20, 0, 30, 10),
        PdfBox(10, 0, 20, 10),
      ],
    );
    expect(layer.positionAt(39, 13), 0);
    expect(layer.positionAt(31, 13), 1);
    expect(layer.positionAt(21, 13), 2);
    expect(layer.positionAt(11, 13), 3);
    expect(layer.caretAt(0)!.box.left, 40);
    expect(layer.caretAt(3, upstream: true)!.box.left, 10);
    expect(layer.caretAt(0)!.isRtl, isTrue);
  });

  test('mixed RTL and Latin runs keep distinct caret affinities', () {
    final layer = PdfTextLayer(
      pageIndex: 0,
      text: 'אבab',
      charBoxes: const [
        PdfBox(30, 0, 40, 10),
        PdfBox(20, 0, 30, 10),
        PdfBox(0, 0, 10, 10),
        PdfBox(10, 0, 20, 10),
      ],
    );
    expect(layer.caretAt(2, upstream: true)!.box.left, 20);
    expect(layer.caretAt(2, upstream: true)!.isRtl, isTrue);
    expect(layer.caretAt(2)!.box.left, 0);
    expect(layer.caretAt(2)!.isRtl, isFalse);
  });

  test('drag positions and carets never split a grapheme', () {
    final layer = PdfTextLayer(
      pageIndex: 0,
      text: 'A😀e\u0301Z',
      charBoxes: const [
        PdfBox(0, 0, 10, 10),
        PdfBox(10, 0, 20, 10),
        PdfBox(0, 0, 0, 0),
        PdfBox(20, 0, 30, 10),
        PdfBox(22, -2, 27, 2),
        PdfBox(30, 0, 40, 10),
      ],
    );
    for (var x = -10.0; x <= 50; x++) {
      expect(layer.positionAt(x, 15), isIn([0, 1, 3, 5, 6]));
    }
    expect(layer.caretAt(2)!.box.left, 10);
    expect(layer.caretAt(2, upstream: true)!.box.left, 20);
    expect(layer.caretAt(4)!.box, const PdfBox(20, -2, 20, 10));
    expect(layer.caretAt(4, upstream: true)!.box.left, 30);
    expect(layer.textOf(layer.wordAt(4)!), 'e\u0301Z');
  });

  test('word selection includes supplementary-plane letters', () {
    final layer = _layer('𐐀𐐁 stop');
    expect(layer.wordAt(0), const PdfTextRange(0, 4));
    expect(layer.wordAt(1), const PdfTextRange(0, 4));
    expect(layer.wordAt(2), const PdfTextRange(0, 4));
    expect(layer.wordAt(3), const PdfTextRange(0, 4));
  });

  test('empty text and invalid positions have no caret', () {
    final empty = _layer('');
    expect(empty.positionAt(10, 10), isNull);
    expect(empty.caretAt(0), isNull);
    final layer = _layer('ab');
    expect(layer.caretAt(-1), isNull);
    expect(layer.caretAt(3), isNull);
    expect(layer.positionAt(double.nan, 0), isNull);
    expect(layer.positionAt(0, double.infinity), isNull);
  });
}

PdfTextLayer _layer(String text) {
  final boxes = <PdfBox>[];
  var line = 0;
  var column = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n') {
      boxes.add(const PdfBox(0, 0, 0, 0));
      line++;
      column = 0;
    } else {
      final x = column++ * 10.0;
      final y = line * 20.0;
      boxes.add(PdfBox(x, y, x + 10, y + 10));
    }
  }
  return PdfTextLayer(
    pageIndex: 0,
    text: text,
    charBoxes: boxes,
  );
}
