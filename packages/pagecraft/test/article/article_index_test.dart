import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/article/article_document.dart';
import 'package:pagecraft/all_formats.dart';

/// An article as the import marks it: blocks with ids, sentences in
/// spans.
ContentDocument article() => ContentDocument.parseHtml(
  articleDocumentHtml(
    '<h1 id="block-0" data-rf-block-id="block-0">'
    '<span id="block-0-s0" data-rf-sentence="0">The   Title</span></h1>'
    '<p id="block-1" data-rf-block-id="block-1">'
    '<span id="block-1-s0" data-rf-sentence="0">One cat sat.</span> '
    '<span id="block-1-s1" data-rf-sentence="1">Two cats ran, Cat!</span></p>'
    '<figure><img src="images/a.png" alt=""/></figure>'
    '<h2 id="block-2" data-rf-block-id="block-2">'
    '<span id="block-2-s0" data-rf-sentence="0">Part two</span></h2>'
    '<p id="block-3" data-rf-block-id="block-3">'
    '<span id="block-3-s0" data-rf-sentence="0">A third cat.</span></p>',
  ),
);

void main() {
  selectionTests();
  group('the index', () {
    test('lists sentences in order and finds the one at a point', () {
      final doc = article();
      final index = ArticleIndex.of(doc);
      final ids = [for (final s in index.sentences) doc.attributeOf(s, 'id')];
      expect(ids, [
        'block-0-s0',
        'block-1-s0',
        'block-1-s1',
        'block-2-s0',
        'block-3-s0',
      ]);
      final inside = doc.elementIndexById('block-1-s1');
      expect(index.sentenceAt(TextPoint(inside + 1, 3)), inside);
      // The picture between blocks: the next sentence.
      final figure = doc
          .descendantsOf(0)
          .firstWhere(
            (n) => doc.isElement(n) && doc.localNameOf(n) == 'figure',
          );
      expect(index.sentenceAt(TextPoint(figure, 0)), index.sentences[3]);
    });

    test('names the heading a node is under', () {
      final doc = article();
      final index = ArticleIndex.of(doc);
      expect(index.headingBefore(0), isNull);
      expect(
        index.headingBefore(doc.elementIndexById('block-0-s0')),
        'The Title',
      );
      expect(
        index.headingBefore(doc.elementIndexById('block-1-s1')),
        'The Title',
      );
      expect(
        index.headingBefore(doc.elementIndexById('block-3-s0')),
        'Part two',
      );
    });

    test('estimates minutes left from the text before a sentence', () {
      final doc = article();
      final index = ArticleIndex.of(doc);
      // 'The Title' (9) 'One cat sat.' (12) ' ' 'Two cats ran, Cat!' (18)
      // 'Part two' (8) 'A third cat.' (12): runs of spaces count once.
      expect(index.textLength, 9 + 12 + 1 + 18 + 8 + 12);
      final third = doc.elementIndexById('block-3-s0');
      expect(
        index.minutesLeft(third, 0.5, atEnd: false),
        12 / ArticleIndex.charsPerMinute,
      );
      expect(
        index.minutesLeft(null, 0.5, atEnd: false),
        index.textLength * 0.5 / ArticleIndex.charsPerMinute,
      );
      expect(index.minutesLeft(third, 0.5, atEnd: true), 0);
    });
  });

  group('the search', () {
    test('finds every match in sentence order, with its heading', () async {
      final doc = article();
      final events = await searchArticle(
        ArticleIndex.of(doc),
        ' CAT ',
      ).toList();
      final hits = [
        for (final event in events)
          if (event is TextSearchResults)
            ...event.hits.cast<ArticleSearchHit>(),
      ];
      expect(hits.map((h) => '${h.pre}[${h.match}]${h.post}'), [
        'One [cat] sat.',
        'Two [cat]s ran, Cat!',
        'Two cats ran, [Cat]!',
        'A third [cat].',
      ]);
      expect(hits.map((h) => h.chapterTitle), [
        'The Title',
        'The Title',
        'The Title',
        'Part two',
      ]);
      expect(events.last, isA<TextSearchDone>());
      expect(events.whereType<TextSearchProgress>().last.fraction, 1);
      // Each hit resolves to its own text, as a highlight would.
      for (final hit in hits) {
        final anchor = ArticleAnchor.decode(hit.cfi)!;
        expect(anchor.matchText, hit.match);
        final range = anchor.rangeIn(doc)!;
        expect(doc.textOfRange(range), hit.match);
        expect(doc.comparePoints(hit.range!.start, range.start), 0);
      }
    });

    test('a blank query finds nothing', () async {
      final events = await searchArticle(
        ArticleIndex.of(article()),
        '  ',
      ).toList();
      expect(events.single, isA<TextSearchDone>());
    });

    test('runs in slices and stops when cancelled', () async {
      final html = StringBuffer();
      for (var i = 0; i < 400; i++) {
        html.write(
          '<p id="b$i" data-rf-block-id="b$i">'
          '<span id="b$i-s0" data-rf-sentence="0">cat number $i</span></p>',
        );
      }
      final index = ArticleIndex.of(
        ContentDocument.parseHtml(articleDocumentHtml(html.toString())),
      );
      final progress = await searchArticle(
        index,
        'cat',
        budget: Duration.zero,
      ).where((e) => e is TextSearchProgress).length;
      expect(progress, greaterThan(1));
      final seen = <TextSearchEvent>[];
      final subscription = searchArticle(
        index,
        'cat',
        budget: Duration.zero,
      ).listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      final before = seen.length;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seen.length, before);
      expect(seen.whereType<TextSearchDone>(), isEmpty);
    });
  });
}

void selectionTests() {
  group('a selection', () {
    test('carries its text, context and anchor as the shell made them', () {
      final doc = article();
      final sentence = doc.elementIndexById('block-1-s1');
      final text = sentence + 1;
      // "cats ran" in "Two cats ran, Cat!".
      final selection = ArticleSelection.of(
        doc,
        TextPointRange(TextPoint(text, 4), TextPoint(text, 12)),
      )!;
      expect(selection.text, 'cats ran');
      expect(selection.contextText, 'Two cats ran , Cat!');
      expect(selection.markedContextText, 'Two [[cats ran]] , Cat!');
      final anchor = ArticleAnchor.decode(selection.cfi)!;
      expect(anchor.rangeRootId, 'block-1-s1');
      expect(anchor.matchIndex, 4);
      expect(doc.textOfRange(anchor.rangeIn(doc)!), 'cats ran');
      expect(selection.highlightMerge, isNull);
    });

    test('across blocks, roots at the content and keeps its context', () {
      final doc = article();
      final first = doc.elementIndexById('block-1-s1') + 1;
      final last = doc.elementIndexById('block-3-s0') + 1;
      final selection = ArticleSelection.of(
        doc,
        TextPointRange(TextPoint(first, 9), TextPoint(last, 7)),
      )!;
      expect(selection.text, 'ran, Cat!Part twoA third');
      expect(selection.contextText, startsWith('Two cats ran, Cat!'));
      final anchor = ArticleAnchor.decode(selection.cfi)!;
      expect(anchor.rangeRootId, 'article-content');
      expect(
        doc.textOfRange(anchor.rangeIn(doc)!),
        'ran, Cat!Part twoA third',
      );
    });

    test('merges the saved highlights it shares text with', () {
      final doc = article();
      final text = doc.elementIndexById('block-1-s1') + 1;
      final saved = ArticleSelection.of(
        doc,
        TextPointRange(TextPoint(text, 0), TextPoint(text, 8)),
      )!;
      final selection = ArticleSelection.of(
        doc,
        TextPointRange(TextPoint(text, 4), TextPoint(text, 12)),
        highlights: [
          SavedTextHighlight(id: 'h1', cfi: saved.cfi, text: saved.text),
        ],
      )!;
      final merge = selection.highlightMerge!;
      expect(merge.highlightIds, ['h1']);
      expect(merge.text, 'Two cats ran');
      expect(
        doc.textOfRange(ArticleAnchor.decode(merge.cfi)!.rangeIn(doc)!),
        'Two cats ran',
      );
      // Inside a saved highlight: that highlight, as saved.
      final inside = ArticleSelection.of(
        doc,
        TextPointRange(TextPoint(text, 1), TextPoint(text, 3)),
        highlights: [
          SavedTextHighlight(id: 'h1', cfi: saved.cfi, text: saved.text),
        ],
      )!;
      expect(inside.highlightMerge!.cfi, saved.cfi);
      expect(inside.highlightMerge!.text, 'Two cats');
    });
  });
}
