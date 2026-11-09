import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';
import 'package:pagecraft/src/formats/pdf/pdf_text_metrics.dart';
import 'package:pagecraft/testing.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' show PdfPageBaseExtensions;

import '../fixtures/pdf/unembedded_cyrillic_fixture.dart';

const _path = 'test/fixtures/pdf/unembedded_cyrillic.pdf';
const _lines = ['Проверка границ', 'Точный выбор слова'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(preparePdfEngineForTests);

  late PdfBook book;
  late PdfTextLayer layer;

  setUpAll(() async {
    book = await PdfBook.open(_path);
    layer = await PdfTextLayer.load(book, 0);
  });
  tearDownAll(() => book.close());

  test('device fixture bytes match the native regression document', () {
    final bytes = unembeddedCyrillicFixtureBytes();
    expect(bytes, File(_path).readAsBytesSync());
    expect(sha256.convert(bytes).toString(), unembeddedCyrillicFixtureSha256);
  });

  test(
    'the original unembedded font reproduces degenerate tight boxes',
    () async {
      final raw = await book.document.pages.first.loadStructuredText();
      expect(raw.fullText, _lines.join('\n'));
      expect(
        raw.charRects.first.height,
        lessThan(.1),
        reason: 'the OCR font has no usable tight Cyrillic glyph outline',
      );
    },
  );

  test('selection cells cover both visible raster lines', () async {
    final boxes = layer.boxesOf(PdfTextRange(0, layer.text.length));
    expect(boxes, hasLength(2));
    final image = (await book.document.pages.first.render(
      width: 240,
      height: 144,
    ))!;
    try {
      for (var index = 0; index < boxes.length; index++) {
        final box = boxes[index];
        expect(box.height, greaterThan(9));
        final ink = _inkBounds(
          image.pixels,
          image.width,
          index == 0 ? 28 : 52,
          index == 0 ? 52 : 80,
        );
        expect(ink, isNotNull);
        expect(box.top, lessThanOrEqualTo(ink!.top + 1));
        expect(box.bottom, greaterThanOrEqualTo(ink.bottom - 1));
      }
    } finally {
      image.dispose();
    }
  });

  test('visible Cyrillic glyphs can be pressed and adjusted', () {
    final word = layer.wordAtPoint(40, 40);
    expect(word, const PdfTextRange(0, 8));
    expect(layer.textOf(word!), 'Проверка');
    final start = layer.caretAt(word.start)!;
    final end = layer.caretAt(word.end, upstream: true)!;
    expect(start.box.height, greaterThan(9));
    expect(end.box.height, greaterThan(9));
    final inserted = layer.positionAt(end.box.left, end.lineBox.top + 3);
    expect(inserted, word.end);
  });

  test('font cells follow a rotated page with a nonzero crop origin', () async {
    final rotated = await PdfTextLayer.load(book, 1);
    expect(book.pages[1].width, 144);
    expect(book.pages[1].height, 240);
    final structured = await book.document.pages[1].loadStructuredText();
    expect(rotated.text, structured.fullText);
    expect(rotated.text.split('\n'), unorderedEquals(_lines));
    final bounds = rotated
        .boxesOf(PdfTextRange(0, rotated.text.length))
        .reduce((a, b) => a.union(b));
    final image = (await book.document.pages[1].render(
      width: 144,
      height: 240,
    ))!;
    try {
      final ink = _inkBounds(image.pixels, image.width, 0, image.height)!;
      expect(bounds.left, lessThanOrEqualTo(ink.left + 1));
      expect(bounds.top, lessThanOrEqualTo(ink.top + 1));
      expect(bounds.right, greaterThanOrEqualTo(ink.right - 1));
      expect(bounds.bottom, greaterThanOrEqualTo(ink.bottom - 1));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(book.pages[1].height));
    } finally {
      image.dispose();
    }
  });

  test('metrics preserve structured text offsets and stored anchors', () async {
    final structured = await book.document.pages.first.loadStructuredText();
    expect(layer.text, structured.fullText);
    expect(layer.charBoxes, hasLength(structured.charRects.length));
    final start = layer.text.indexOf('выбор');
    final range = PdfTextRange(start, start + 'выбор'.length);
    final cfi = pdfTextCfi(0, range);
    expect(pdfTextAnchorFromCfi(cfi)!.range, range);
    expect(resolvePdfTextAnchor(layer, text: 'выбор', cfiRange: cfi), range);
    expect(layer.textOf(range), 'выбор');
    for (var index = 0; index < layer.text.length; index++) {
      if (layer.text[index].trim().isEmpty) continue;
      expect(layer.charBoxes[index].left, structured.charRects[index].left);
      expect(layer.charBoxes[index].right, structured.charRects[index].right);
    }
  });

  test(
    'unexpected text refuses metrics instead of moving stored anchors',
    () async {
      final rects = await loadPdfTextSelectionRects(
        book.document,
        0,
        '${layer.text}x',
      );
      expect(rects, isNull);
    },
  );

  test(
    'collapsed whitespace does not shift the following glyph metrics',
    () async {
      final originalRects = (await loadPdfTextSelectionRects(
        book.document,
        0,
        layer.text,
      ))!;
      final text = layer.text.replaceAll(' ', '  ');
      final rects = (await loadPdfTextSelectionRects(book.document, 0, text))!;
      expect(rects, hasLength(text.length));
      final original = layer.text.indexOf('границ');
      final expanded = text.indexOf('границ');
      expect(
        rects[expanded]!.left,
        closeTo(originalRects[original]!.left, .01),
      );
      expect(rects[expanded]!.height, greaterThan(9));
    },
  );
}

PdfBox? _inkBounds(List<int> pixels, int width, int top, int bottom) {
  var left = width;
  var right = 0;
  var first = bottom;
  var last = top;
  for (var y = top; y < bottom; y++) {
    for (var x = 0; x < width; x++) {
      if (pixels[(y * width + x) * 4] >= 128) continue;
      left = math.min(left, x);
      right = math.max(right, x + 1);
      first = math.min(first, y);
      last = math.max(last, y + 1);
    }
  }
  return right <= left
      ? null
      : PdfBox(
          left.toDouble(),
          first.toDouble(),
          right.toDouble(),
          last.toDouble(),
        );
}
