import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/article/article_anchor.dart';
import 'package:pagecraft/all_formats.dart';

/// The anchors the WebView article shell wrote for selections of
/// `fixtures/article/article.html` in Chromium, and the text each
/// restored (recorded by `article_anchor_fixtures.mjs` before its removal):
/// pagecraft writes the same anchors and restores the same text.
void main() {
  final html = File('test/fixtures/article/article.html').readAsStringSync();
  final fixtures =
      (jsonDecode(
                File('test/fixtures/article/anchors.json').readAsStringSync(),
              )
              as List)
          .cast<Map<String, Object?>>();
  // As the shell holds it: the article in its <main>.
  final doc = ContentDocument.parseHtml(
    '<!doctype html><html><head></head><body>'
    '<main id="article-content">$html</main></body></html>',
  );

  /// The range of [text]'s [occurrence] in the text nodes under the
  /// content, concatenated, as the fixture script selected it.
  TextPointRange rangeFor(String text, int occurrence) {
    final root = doc.elementIndexById(ArticleAnchor.contentId);
    final nodes = <(int node, int start)>[];
    final full = StringBuffer();
    for (final node in doc.descendantsOf(root)) {
      if (!doc.isText(node)) continue;
      nodes.add((node, full.length));
      full.write(doc.textOf(node));
    }
    var start = -1;
    for (var i = 0; i <= occurrence; i++) {
      start = full.toString().indexOf(text, start + 1);
    }
    expect(start, greaterThanOrEqualTo(0), reason: text);
    final end = start + text.length;
    final first = nodes.lastWhere((n) => n.$2 <= start);
    final last = nodes.firstWhere(
      (n) => end > n.$2 && end <= n.$2 + doc.textOf(n.$1).length,
    );
    return TextPointRange(
      TextPoint(first.$1, start - first.$2),
      TextPoint(last.$1, end - last.$2),
    );
  }

  group('as the shell wrote them', () {
    for (final entry in fixtures) {
      final text = entry['text']! as String;
      final occurrence = entry['occurrence']! as int;
      test('${jsonEncode(text)} #$occurrence', () {
        final anchor = ArticleAnchor.forRange(
          doc,
          rangeFor(text, occurrence),
          entry['selected']! as String,
        );
        expect(anchor?.encode(), entry['cfi']);
        final restored = ArticleAnchor.decode(
          entry['cfi']! as String,
        )!.rangeIn(doc);
        expect(doc.textOfRange(restored!), entry['restored']);
      });
    }
  });

  test('an anchor finds its text again when the text around it moved', () {
    final anchor = ArticleAnchor.decode(fixtures.first['cfi']! as String)!;
    final moved = ContentDocument.parseHtml(
      '<html><body><main id="article-content">'
      '<p id="block-1" data-rf-block-id="block-1">'
      '<span id="block-1-s0" data-rf-sentence="0">Since then the power bank '
      'keeps <em>devices</em> running.</span></p></main></body></html>',
    );
    expect(moved.textOfRange(anchor.rangeIn(moved)!), 'power bank keeps');
  });

  test('a sentence anchor: its block, index, text and the text around it', () {
    final sentence = doc.elementIndexById('block-1-s1');
    final anchor = ArticleAnchor.forSentence(doc, sentence)!;
    expect(anchor.blockId, 'block-1-s1', reason: 'its own id, as closest()');
    expect(anchor.sentenceIndex, 1);
    expect(
      anchor.sentenceText,
      'A second sentence follows here, with the word power again.',
    );
    expect(anchor.isRange, isFalse);
    expect(anchor.elementIn(doc), sentence);
    final decoded = ArticleAnchor.decode(anchor.encode())!;
    expect(decoded, anchor);
    expect(decoded.elementIn(doc), sentence);
  });

  test('what is not an anchor is none', () {
    for (final value in [
      null,
      '',
      'epubcfi(/6/4!/4/2)',
      '${ArticleAnchor.scheme}%7B',
      '${ArticleAnchor.scheme}%5B1%5D',
      '${ArticleAnchor.scheme}${encodeUriComponent('{"sentenceIndex":1}')}',
    ]) {
      expect(ArticleAnchor.decode(value), isNull, reason: '$value');
    }
  });

  test('encodeURIComponent as JavaScript writes it', () {
    expect(encodeUriComponent("a-_.!~*'()b"), "a-_.!~*'()b");
    expect(encodeUriComponent('{"a":1} %'), '%7B%22a%22%3A1%7D%20%25');
    expect(encodeUriComponent('Жё🙂'), '%D0%96%D1%91%F0%9F%99%82');
  });
}
