import '../document/content_document.dart';
import '../document/text_point.dart';
import 'article_anchor.dart';

/// What the reader looks up in an article as it scrolls, found in one
/// walk over it: its sentences in order (the import marks each with
/// `data-rf-sentence`), its headings, and how much text, white space
/// collapsed, comes before each sentence.
class ArticleIndex {
  ArticleIndex._(
    this.document,
    this.sentences,
    this._headings,
    this._headingTitles,
    this._sentenceOffsets,
    this.textLength,
  );

  factory ArticleIndex.of(ContentDocument doc) {
    final content = doc.elementIndexById(ArticleAnchor.contentId);
    final root = content == ContentDocument.none ? 0 : content;
    final sentences = <int>[];
    final headings = <int>[];
    final titles = <String>[];
    final offsets = <int, int>{};
    var length = 0;
    int? sentence;
    var sentenceEnd = -1;
    for (final node in doc.descendantsOf(root)) {
      if (node >= sentenceEnd) sentence = null;
      if (doc.isElement(node)) {
        if (doc.attributeOf(node, 'data-rf-sentence') != null) {
          sentences.add(node);
          sentence ??= node;
          if (sentence == node) sentenceEnd = doc.subtreeEndOf(node);
        }
        if (_headingNames.contains(doc.localNameOf(node).toLowerCase())) {
          headings.add(node);
          titles.add(normalizeArticleText(textContentOf(doc, node)));
        }
      } else if (doc.isText(node)) {
        final current = sentence;
        if (current != null) offsets.putIfAbsent(current, () => length);
        length += doc.textOf(node).replaceAll(_space, ' ').length;
      }
    }
    return ArticleIndex._(doc, sentences, headings, titles, offsets, length);
  }

  static const _headingNames = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};
  static final _space = RegExp(r'\s+');

  /// The rate the article shell estimated reading time with.
  static const charsPerMinute = 1200;

  final ContentDocument document;

  /// The sentence elements, in document order.
  final List<int> sentences;
  final List<int> _headings;
  final List<String> _headingTitles;
  final Map<int, int> _sentenceOffsets;

  /// The article's text length, white space runs counted as one.
  final int textLength;

  /// The sentence [point] is in; else the first one after it, or the
  /// last one before it.
  int? sentenceAt(TextPoint point) {
    for (
      var node = point.node;
      node != ContentDocument.none;
      node = document.parentOf(node)
    ) {
      if (document.isElement(node) &&
          document.attributeOf(node, 'data-rf-sentence') != null) {
        return node;
      }
    }
    if (sentences.isEmpty) return null;
    final next = _firstAfter(sentences, point.node);
    return next < sentences.length ? sentences[next] : sentences.last;
  }

  /// The text of the last heading that starts at or before [node]: the
  /// chapter it is in, or null before the first heading.
  String? headingBefore(int node) {
    final after = _firstAfter(_headings, node);
    for (var i = after - 1; i >= 0; i--) {
      final title = _headingTitles[i];
      if (title.isNotEmpty) return title;
    }
    return null;
  }

  /// The minutes left to read from [sentence] at the shell's rate, or
  /// from [fraction] of the text when [sentence] is unknown; none at the
  /// end.
  double minutesLeft(int? sentence, double fraction, {required bool atEnd}) {
    if (atEnd || textLength <= 0) return 0;
    final offset = sentence == null ? null : _sentenceOffsets[sentence];
    final remaining = offset == null
        ? textLength * (1 - fraction)
        : textLength - offset;
    return (remaining < 0 ? 0 : remaining) / charsPerMinute;
  }

  /// The index of the first of [sorted] greater than [value].
  static int _firstAfter(List<int> sorted, int value) {
    var low = 0;
    var high = sorted.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (sorted[mid] <= value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
