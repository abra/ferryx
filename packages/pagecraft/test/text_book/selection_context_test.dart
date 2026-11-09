import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// Ports of `selection_context.test.mjs` (the WebView reader's browser
/// tests) and the values its `sentenceContextForSelection` computes
/// (`test/fixtures/readflex_selection.json`).
void main() {
  ContentDocument html(String body) => ContentDocument.parseXml(
    '<html xmlns="http://www.w3.org/1999/xhtml"><body>$body</body></html>',
  );

  /// The range of characters `[start, end)` of [root]'s text.
  TextPointRange offsets(ContentDocument doc, int root, int start, int end) {
    TextPoint? from;
    var offset = 0;
    for (var i = root; i < doc.subtreeEndOf(root); i++) {
      if (!doc.isText(i)) continue;
      final length = doc.textOf(i).length;
      if (from == null && start >= offset && start < offset + length) {
        from = TextPoint(i, start - offset);
      }
      if (end > offset && end <= offset + length) {
        return TextPointRange(from!, TextPoint(i, end - offset));
      }
      offset += length;
    }
    throw StateError('outside the fixture');
  }

  int first(ContentDocument doc, String name) {
    for (var i = 0; i < doc.nodeCount; i++) {
      if (doc.isElement(i) && doc.localNameOf(i) == name) return i;
    }
    throw StateError(name);
  }

  test('sentence context matches the JS for the same sides', () {
    final fixture =
        jsonDecode(
              File('test/fixtures/readflex_selection.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    for (final row in (fixture['contexts']! as List).cast<List<Object?>>()) {
      final [
        before as String,
        selected as String,
        after as String,
        beforeClipped as bool,
        afterClipped as bool,
        expected as Map<String, Object?>,
      ] = row;
      final context = sentenceContextForSelection(
        before,
        selected,
        after,
        beforeClipped: beforeClipped,
        afterClipped: afterClipped,
      );
      expect(context.contextText, expected['contextText'], reason: selected);
      expect(
        context.markedContextText,
        expected['markedContextText'],
        reason: selected,
      );
    }
  });

  test('sentence context is invariant under inline markup and node splits', () {
    const selected = 'power';
    for (var index = 0; index < 8; index++) {
      final sentence = 'Sentence $index repeats power and power.';
      final text = 'Earlier power. $sentence Later power.';
      for (final chunk in [1, 2, 5, text.length]) {
        final body = StringBuffer('<p>');
        for (var offset = 0; offset < text.length; offset += chunk) {
          final tag = offset.isEven ? 'em' : 'span';
          final end = (offset + chunk).clamp(0, text.length);
          body.write('<$tag><b>${text.substring(offset, end)}</b></$tag>');
        }
        body.write('</p>');
        final doc = html(body.toString());
        final p = first(doc, 'p');
        for (final local in [
          sentence.indexOf(selected),
          sentence.lastIndexOf(selected),
        ]) {
          final start = 'Earlier power. '.length + local;
          final range = offsets(doc, p, start, start + selected.length);
          expect(doc.textOfRange(range), selected);
          expect(buildSelectionContext(doc, range), (
            contextText: sentence,
            markedContextText:
                '${sentence.substring(0, local)}[[$selected]]'
                '${sentence.substring(local + selected.length)}',
          ), reason: 'chunk $chunk');
        }
      }
    }
  });

  test('element boundaries give the same context as text offsets', () {
    final doc = html(
      '<p>Before. The <span><b>power</b> <em>bank</em></span> works. After.</p>',
    );
    final p = first(doc, 'p');
    final span = first(doc, 'span');
    final em = first(doc, 'em');
    final spanNode = doc.node(span);
    final inner = doc.textRangeOf(
      CfiNodeRange(
        CfiPoint(spanNode, 0),
        CfiPoint(spanNode, spanNode.children.length),
      ),
    );
    final outer = doc.textRangeOf(
      CfiNodeRange(CfiPoint(doc.node(p), 1), CfiPoint(doc.node(p), 2)),
    );
    final mixed = TextPointRange(inner.start, TextPoint(em + 1, 4));
    for (final range in [inner, outer, mixed]) {
      expect(buildSelectionContext(doc, range), (
        contextText: 'The power bank works.',
        markedContextText: 'The [[power bank]] works.',
      ), reason: '$range');
    }
  });

  test('context never crosses a neighbouring block', () {
    final doc = html(
      '<div><p>Unrelated prefix without punctuation</p>This <b>word</b> works.'
      '<p>Unrelated suffix without punctuation</p></div>',
    );
    final b = first(doc, 'b');
    final range = TextPointRange(TextPoint(b + 1, 0), TextPoint(b + 1, 4));
    expect(buildSelectionContext(doc, range), (
      contextText: 'This word works.',
      markedContextText: 'This [[word]] works.',
    ));
  });

  test('cross-paragraph and long selections are their own context', () {
    final doc = html(
      '<p>Unselected prefix. First selected sentence.</p>'
      '<p>${'Selected text. ' * 400}Last selected sentence. Unselected suffix.</p>',
    );
    final firstText = first(doc, 'p') + 1;
    final last = doc.nodeCount - 1;
    final end = TextPoint(
      last,
      doc.textOf(last).indexOf(' Unselected suffix.'),
    );
    for (final range in [
      TextPointRange(TextPoint(firstText, 'Unselected prefix. '.length), end),
      TextPointRange(TextPoint(last, 0), end),
    ]) {
      final expected = doc
          .textOfRange(range)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final context = buildSelectionContext(doc, range);
      expect(context.contextText, expected);
      expect(context.markedContextText, '[[$expected]]');
      expect(context.contextText, isNot(contains('Unselected')));
    }
  });

  test('context stays bounded in a very large block', () {
    final prefix = 'Earlier sentence. ' * 60000;
    final doc = html(
      '<p>${prefix}The power bank works. ${'Later sentence. ' * 60000}</p>',
    );
    final text = first(doc, 'p') + 1;
    final start = prefix.length + 'The '.length;
    final watch = Stopwatch()..start();
    final context = buildSelectionContext(
      doc,
      TextPointRange(TextPoint(text, start), TextPoint(text, start + 5)),
    );
    watch.stop();
    expect(context, (
      contextText: 'The power bank works.',
      markedContextText: 'The [[power bank]] works.'.replaceFirst(
        '[[power bank]]',
        '[[power]] bank',
      ),
    ));
    expect(watch.elapsedMilliseconds, lessThan(50));
  });

  test('a sentence cut by the 2048-character window is not invented', () {
    final doc = html('<p>${'word ' * 1000}target here.</p>');
    final text = first(doc, 'p') + 1;
    final start = 'word '.length * 1000;
    final context = buildSelectionContext(
      doc,
      TextPointRange(TextPoint(text, start), TextPoint(text, start + 6)),
    );
    expect(context, (contextText: 'target', markedContextText: '[[target]]'));
  });

  test('marked blocks and the body bound the context', () {
    final doc = html(
      '<section><span data-rf-sentence="0">One. Two here</span> three.</section>',
    );
    final span = first(doc, 'span');
    final range = TextPointRange(
      TextPoint(span + 1, 5),
      TextPoint(span + 1, 8),
    );
    expect(buildSelectionContext(doc, range).contextText, 'Two here');
    final loose = html('Loose text. In the body here.');
    final body = first(loose, 'body');
    final at = loose.textOf(body + 1).indexOf('body');
    expect(
      buildSelectionContext(
        loose,
        TextPointRange(TextPoint(body + 1, at), TextPoint(body + 1, at + 4)),
      ).markedContextText,
      'In the [[body]] here.',
    );
  });

  test('normalizing grows cut words at both ends', () {
    final doc = html('<p>The po<b>wer bank wo</b>rks well.</p>');
    final p = first(doc, 'p');
    final b = first(doc, 'b');
    final cut = TextPointRange(TextPoint(p + 1, 5), TextPoint(b + 1, 2));
    final normalized = normalizeSelectionRange(doc, cut)!;
    expect(normalized.selectedText, 'owe');
    expect(normalized.kind, SelectionKind.partialWord);
    expect(normalized.range.start, TextPoint(p + 1, 4));
    expect(normalized.range.end, TextPoint(b + 1, 3));
    expect(normalized.normalizedText, 'power');
    // An edge at a node's end is not grown into the next node, as in the
    // JS, even when the word goes on there.
    final atNodeEnd = TextPointRange(TextPoint(p + 1, 6), TextPoint(b + 1, 3));
    expect(normalizeSelectionRange(doc, atNodeEnd)!.kind, SelectionKind.exact);
    final span = TextPointRange(TextPoint(b + 1, 1), TextPoint(b + 1, 10));
    final grown = normalizeSelectionRange(doc, span)!;
    expect(grown.kind, SelectionKind.partialSpan);
    expect(grown.normalizedText, 'wer bank wo');
    final exact = TextPointRange(TextPoint(b + 1, 4), TextPoint(b + 1, 8));
    expect(normalizeSelectionRange(doc, exact)!.kind, SelectionKind.exact);
    expect(
      normalizeSelectionRange(doc, TextPointRange(exact.start, exact.start)),
      isNull,
    );
  });
}
