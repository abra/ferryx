import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

const fixtures = 'test/fixtures/pdf';

const lines = [
  'The quick brown fox jumps over the lazy dog. It was',
  'a bright cold day in April, and the clocks were',
  'striking thirteen! Did anyone notice? Nobody did.',
  'Second paragraph starts here. A café au lait costs',
  '3.50 euros; the naïve waiter smiled.',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(preparePdfEngineForTests);

  group('PdfTextLayer.load', () {
    late PdfBook book;
    late PdfTextLayer layer;

    setUpAll(() async {
      book = await PdfBook.open('$fixtures/text_lines.pdf');
      layer = await PdfTextLayer.load(book, 0);
    });

    tearDownAll(() => book.close());

    test('reads the lines in order with a box per character', () {
      expect(layer.text, lines.join('\n'));
      expect(layer.charBoxes, hasLength(layer.text.length));
      expect(layer.lines, hasLength(5));
      expect(layer.textOf(layer.lines[3].range), lines[3]);
      expect(layer.isEmpty, isFalse);
    });

    test('boxes are display points: top-left origin, lines going down', () {
      final first = layer.charBoxes.first;
      // "T" at 72 pt from the left, 14 pt text at 720 pt from the bottom.
      expect(first.left, closeTo(72.3, 0.5));
      expect(first.top, closeTo(792 - 730.2, 0.5));
      expect(first.bottom, closeTo(792 - 717, 0.5));
      expect(
        layer.lines[1].box.top,
        greaterThan(layer.lines[0].box.bottom - 1),
      );
      expect(layer.lines[4].box.top, greaterThan(layer.lines[3].box.top));
    });

    test('finds the character and word under a point', () {
      final line = layer.lines.first;
      final quick = layer.text.indexOf('quick');
      final box = layer.charBoxes[quick + 2];
      final x = (box.left + box.right) / 2;
      final y = (line.box.top + line.box.bottom) / 2;
      expect(layer.charIndexAt(x, y), quick + 2);
      expect(layer.textOf(layer.wordAtPoint(x, y)!), 'quick');
      expect(layer.charIndexAt(x, line.box.bottom + 40), isNull);
      expect(layer.charIndexAt(65, y), 0, reason: 'nearest within a glyph');
      expect(layer.charIndexAt(5, y), isNull, reason: 'too far left');
      expect(layer.charIndexAt(500, y), isNull, reason: 'far past the line');
    });

    test('draws one box per line of a range', () {
      final start = layer.text.indexOf('lazy');
      final end = layer.text.indexOf('April') + 'April'.length;
      final boxes = layer.boxesOf(PdfTextRange(start, end));
      expect(boxes, hasLength(2));
      expect(boxes[0].right, closeTo(layer.lines[0].box.right, 0.01));
      expect(boxes[1].left, closeTo(layer.lines[1].box.left, 0.01));
      expect(boxes[1].right, lessThan(layer.lines[1].box.right));
    });

    test('a rotated page maps its boxes onto the displayed image', () async {
      final rotated = await PdfBook.open('$fixtures/text_outline.pdf');
      addTearDown(rotated.close);
      final page = await PdfTextLayer.load(rotated, 1);
      expect(page.text, 'Second page, rotated');
      final ink = page.boxesOf(PdfTextRange(0, page.text.length)).single;
      // Rendered at half size (one pixel = two points): the ink must sit inside the
      // mapped box, which runs down the right side of the landscape page.
      final info = await _resolve(
        PdfPageImage(book: rotated, pageIndex: 1, targetWidth: 396),
      );
      final dark = await _darkBounds(info.image);
      info.dispose();
      expect(dark, isNotNull);
      expect(dark!.left * 2, greaterThanOrEqualTo(ink.left - 1));
      expect(dark.right * 2, lessThanOrEqualTo(ink.right + 1));
      expect(dark.top * 2, greaterThanOrEqualTo(ink.top - 1));
      expect(dark.bottom * 2, lessThanOrEqualTo(ink.bottom + 1));
      expect(ink.width, lessThan(ink.height), reason: 'the line runs down');
    });

    test('a page without text is empty', () async {
      final plain = await PdfBook.open('$fixtures/many_pages.pdf');
      addTearDown(plain.close);
      final page = await PdfTextLayer.load(plain, 199);
      expect(page.text, 'Page 200');
    });
  });

  group('PdfTextLayer', () {
    PdfTextLayer layerOf(String text) => PdfTextLayer(
      pageIndex: 0,
      text: text,
      charBoxes: [
        for (var i = 0; i < text.length; i++)
          text[i].trim().isEmpty
              ? const PdfBox(0, 0, 0, 0)
              : PdfBox(i * 10.0, 0, i * 10.0 + 10, 10),
      ],
    );

    test('words include inner apostrophes and hyphens only', () {
      final layer = layerOf("don't stop-gap -x 'quoted' end-");
      expect(layer.textOf(layer.wordAt(1)!), "don't");
      expect(layer.textOf(layer.wordAt(8)!), 'stop-gap');
      expect(layer.textOf(layer.wordAt(16)!), 'x');
      expect(layer.textOf(layer.wordAt(19)!), 'quoted');
      expect(layer.textOf(layer.wordAt(27)!), 'end');
      expect(layer.wordAt(5), isNull, reason: 'a space');
      expect(layer.wordAt(15), isNull, reason: 'a leading hyphen');
      expect(layer.wordAt(-1), isNull);
      expect(layer.wordAt(99), isNull);
    });

    test('words span letters, digits and marks of any script', () {
      final layer = layerOf('Ёлка 2026 नमस्ते');
      expect(layer.textOf(layer.wordAt(0)!), 'Ёлка');
      expect(layer.textOf(layer.wordAt(6)!), '2026');
      expect(layer.textOf(layer.wordAt(12)!), 'नमस्ते');
    });

    test('the sentence around a word is its context', () {
      final layer = layerOf(lines.join('\n'));
      final clocks = layer.text.indexOf('clocks');
      final context = layer.contextOf(PdfTextRange(clocks, clocks + 6));
      expect(
        context.contextText,
        'It was a bright cold day in April, and the clocks were striking '
        'thirteen!',
      );
      expect(
        context.markedContextText,
        'It was a bright cold day in April, and the [[clocks]] were striking '
        'thirteen!',
      );
    });

    test('a selection across sentences keeps both', () {
      final layer = layerOf(lines.join('\n'));
      final start = layer.text.indexOf('Nobody');
      final end = layer.text.indexOf('starts');
      final context = layer.contextOf(PdfTextRange(start, end));
      expect(
        context.contextText,
        'Nobody did. Second paragraph starts here.',
      );
      expect(
        context.markedContextText,
        '[[Nobody did. Second paragraph ]]starts here.',
      );
    });

    test('a decimal point or a closing quote does not end a sentence', () {
      final layer = layerOf('It costs 3.50 euros. "Really?" she said. Yes.');
      final euros = layer.text.indexOf('euros');
      expect(
        layer.contextOf(PdfTextRange(euros, euros + 5)).contextText,
        'It costs 3.50 euros.',
      );
      final really = layer.text.indexOf('Really');
      expect(
        layer.contextOf(PdfTextRange(really, really + 6)).contextText,
        '"Really?"',
      );
    });

    test('first and last sentences of a page are bounded by the page', () {
      final layer = layerOf(lines.join('\n'));
      expect(
        layer.contextOf(const PdfTextRange(4, 9)).contextText,
        'The quick brown fox jumps over the lazy dog.',
      );
      final smiled = layer.text.indexOf('smiled');
      expect(
        layer.contextOf(PdfTextRange(smiled, smiled + 6)).contextText,
        'A café au lait costs 3.50 euros; the naïve waiter smiled.',
      );
    });

    test('an empty selection has no context', () {
      final layer = layerOf('Some text.');
      final context = layer.contextOf(const PdfTextRange(4, 5));
      expect(context.contextText, '');
      expect(context.markedContextText, '');
    });

    test(
      'a sentence cut by the context window falls back to the selection',
      () {
        final filler = List.filled(
          PdfTextLayer.contextSideChars + 10,
          'a',
        ).join();
        final layer = layerOf('$filler word $filler');
        final start = layer.text.indexOf('word');
        final context = layer.contextOf(PdfTextRange(start, start + 4));
        expect(context.contextText, 'word');
        expect(context.markedContextText, '[[word]]');
      },
    );

    test('finds saved text across line breaks and extra spaces', () {
      final layer = layerOf('lazy\ndog. It  was');
      expect(layer.rangeOfText('lazy dog.'), const PdfTextRange(0, 9));
      expect(layer.rangeOfText('It was'), const PdfTextRange(10, 17));
      expect(layer.rangeOfText('  '), isNull);
      expect(layer.rangeOfText('cat'), isNull);
    });

    test('searches with the shared rules', () {
      final layer = layerOf(lines.join('\n'));
      final matches = layer.search('cafe au');
      expect(matches.single.match, 'café au');
      expect(
        layer.textOf(PdfTextRange(matches.single.start, matches.single.end)),
        'café au',
      );
    });
  });
}

Future<ImageInfo> _resolve(ImageProvider provider) {
  final completer = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info);
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

Future<PdfBox?> _darkBounds(ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  int? left, top, right, bottom;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (data.getUint8((y * image.width + x) * 4) >= 0x80) continue;
      left = left == null || x < left ? x : left;
      right = right == null || x > right ? x : right;
      top ??= y;
      bottom = y;
    }
  }
  if (left == null) return null;
  return PdfBox(
    left.toDouble(),
    top!.toDouble(),
    right!.toDouble() + 1,
    bottom!.toDouble() + 1,
  );
}
