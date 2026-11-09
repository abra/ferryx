import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/djvu.dart';

DjvuTextLayer _layer() => DjvuTextLayer.fromJson(2, {
  'width': 600,
  'height': 900,
  'words': [
    {'text': 'A', 'x': 10, 'y': 20, 'width': 12, 'height': 24},
    {'text': 'café', 'x': 30, 'y': 20, 'width': 60, 'height': 24},
    {'text': '', 'x': 0, 'y': 0, 'width': 0, 'height': 0},
    {'text': '😀', 'x': 100, 'y': 20, 'width': 25, 'height': 24},
    {'text': 'reader.', 'x': 135, 'y': 20, 'width': 90, 'height': 24},
    {'text': 'Next', 'x': 10, 'y': 60, 'width': 60, 'height': 24},
    {'text': 'sentence.', 'x': 80, 'y': 60, 'width': 130, 'height': 24},
  ],
});

void main() {
  test('word offsets use Dart UTF-16 and preserve Unicode text', () {
    final layer = _layer();
    expect(layer.text, 'A café 😀 reader. Next sentence.');
    expect(layer.words, hasLength(6));
    final emoji = layer.words[2];
    expect(emoji.range.length, 2);
    for (final word in layer.words) {
      expect(layer.textOf(word.range), word.text);
      expect(layer.wordAt(word.start), word.range);
    }
    expect(layer.wordAt(1), isNull, reason: 'spaces have no word box');
    expect(layer.wordAt(-1), isNull);
    expect(layer.wordAt(layer.text.length), isNull);
    expect(layer.wordAtPoint(40, 30), layer.words[1].range);
    expect(layer.wordAtPoint(0, 0), isNull);
  });

  test(
    'search geometry covers exact word zones without invented glyph boxes',
    () {
      final layer = _layer();
      final range = layer.rangeOfText('CAFE 😀')!;
      expect(layer.textOf(range), 'café 😀');
      expect(layer.boxesOf(range), [
        const Rect.fromLTWH(30, 20, 60, 24),
        const Rect.fromLTWH(100, 20, 25, 24),
      ]);
      final context = layer.contextOf(layer.words[1].range);
      expect(context.contextText, 'A café 😀 reader.');
      expect(context.markedContextText, 'A [[café]] 😀 reader.');
    },
  );

  test('text anchors round trip and reject unrelated or reversed ranges', () {
    const range = DjvuTextRange(2, 6);
    final cfi = djvuTextCfi(2, range);
    final parsed = djvuTextAnchorFromCfi(cfi)!;
    expect(parsed.pageIndex, 2);
    expect(parsed.range, range);
    expect(djvuTextAnchorFromCfi('epubcfi(/6/2)'), isNull);
    expect(
      djvuTextAnchorFromCfi('epubcfi(/6/6!/2[pagecraft-djvu],/1:8,/1:2)'),
      isNull,
    );
    expect(
      resolveDjvuTextAnchor(_layer(), text: 'café', cfiRange: cfi),
      range,
    );
    expect(
      resolveDjvuTextAnchor(
        _layer(),
        text: 'café',
        cfiRange: djvuTextCfi(1, const DjvuTextRange(0, 1)),
      ),
      range,
      reason: 'a changed anchor falls back to matching saved text',
    );
    expect(resolveDjvuTextAnchor(_layer(), text: 'absent'), isNull);
  });

  test('clips word geometry and rejects invalid native dimensions', () {
    final layer = DjvuTextLayer.fromJson(0, {
      'width': 100,
      'height': 100,
      'words': [
        {'text': 'edge', 'x': -10, 'y': 90, 'width': 30, 'height': 20},
      ],
    });
    expect(layer.words.single.box, const Rect.fromLTWH(0, 90, 20, 10));
    for (final invalidWidth in [0, -1, double.infinity, double.nan]) {
      expect(
        () => DjvuTextLayer.fromJson(0, {
          'width': invalidWidth,
          'height': 100,
          'words': <Object>[],
        }),
        throwsA(isA<PagecraftException>()),
      );
    }
  });
}
