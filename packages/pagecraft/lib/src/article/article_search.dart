import 'dart:async';

import '../document/content_document.dart';
import '../document/text_point.dart';
import '../text_book/text_book_search.dart';
import 'article_anchor.dart';
import 'article_index.dart';

/// A match in an article: its anchor (its sentence's, with where the
/// match is in the sentence's text) as the search result's CFI, the
/// heading it is under, and the text it covers, to mark.
class ArticleSearchHit extends TextSearchHit {
  const ArticleSearchHit({
    required super.cfi,
    required super.pre,
    required super.match,
    required super.post,
    required this.chapterTitle,
    required this.range,
  });

  final String? chapterTitle;

  /// Null past the first [articleSearchMarkLimit] hits.
  final TextPointRange? range;
}

/// How many hits of an article search get their text range, to mark.
const articleSearchMarkLimit = 1000;

/// Searches the article [index] is of for [query] as the article shell
/// did: each sentence's text, white space collapsed, lower-cased, in
/// document order, a slice of sentences at a time between frames;
/// results in batches of 25 ([TextSearchResults] of section 0), then the
/// share of sentences searched, then [TextSearchDone]. A blank query
/// finds nothing. Cancelling the subscription stops it.
Stream<TextSearchEvent> searchArticle(
  ArticleIndex index,
  String query, {
  Duration budget = const Duration(milliseconds: 8),
}) {
  final needle = normalizeArticleText(query).toLowerCase();
  late final StreamController<TextSearchEvent> out;
  var cancelled = false;
  Future<void> run() async {
    final doc = index.document;
    final sentences = index.sentences;
    var batch = <TextSearchHit>[];
    var marked = 0;
    var next = 0;
    final clock = Stopwatch()..start();
    while (needle.isNotEmpty && next < sentences.length && !cancelled) {
      clock.reset();
      while (next < sentences.length && clock.elapsed <= budget) {
        final sentence = sentences[next++];
        String? title;
        for (final (anchor, excerpt) in _matchesIn(doc, sentence, needle)) {
          title ??= index.headingBefore(sentence) ?? '';
          batch.add(
            ArticleSearchHit(
              cfi: anchor.encode(),
              pre: excerpt.pre,
              match: excerpt.match,
              post: excerpt.post,
              chapterTitle: title.isEmpty ? null : title,
              range: marked++ < articleSearchMarkLimit
                  ? anchor.rangeIn(doc)
                  : null,
            ),
          );
          if (batch.length >= 25) {
            out.add(TextSearchResults(0, batch));
            batch = [];
          }
        }
      }
      if (batch.isNotEmpty) {
        out.add(TextSearchResults(0, batch));
        batch = [];
      }
      out.add(TextSearchProgress(next / sentences.length));
      if (next < sentences.length) await Future<void>.delayed(Duration.zero);
    }
    if (!cancelled) {
      out.add(const TextSearchDone());
      await out.close();
    }
  }

  out = StreamController<TextSearchEvent>(
    onListen: () => unawaited(run()),
    onCancel: () => cancelled = true,
  );
  return out.stream;
}

/// Each match of [needle] in [sentence]'s text: its anchor, and the
/// excerpt around it (the shell's `searchMatchAnchor` and
/// `searchExcerpt`).
Iterable<(ArticleAnchor, ({String pre, String match, String post}))> _matchesIn(
  ContentDocument doc,
  int sentence,
  String needle,
) sync* {
  final anchor = ArticleAnchor.forSentence(doc, sentence);
  if (anchor == null) return;
  final text = normalizeArticleText(textContentOf(doc, sentence));
  final lower = text.toLowerCase();
  final length = needle.length;
  var from = 0;
  while (true) {
    final at = lower.indexOf(needle, from);
    if (at < 0) return;
    final end = (at + length).clamp(0, text.length);
    final match = text.substring(at, end);
    yield (
      ArticleAnchor(
        blockId: anchor.blockId,
        sentenceIndex: anchor.sentenceIndex,
        sentenceText: anchor.sentenceText,
        prefix: anchor.prefix,
        suffix: anchor.suffix,
        matchText: match,
        matchLength: length,
        matchPrefix: text.substring((at - 48).clamp(0, at), at),
        matchSuffix: text.substring(end, (end + 48).clamp(end, text.length)),
        matchIndex: at,
      ),
      (
        pre: text.substring((at - 56).clamp(0, at), at),
        match: match,
        post: text.substring(end, (end + 64).clamp(end, text.length)),
      ),
    );
    from = at + (length > 0 ? length : 1);
  }
}
