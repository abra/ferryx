part of 'article_anchor.dart';

/// What the reader's text actions take for a selection in an article,
/// as the article shell made it (`textSelectionPayload`): the text as
/// the document holds it, white space collapsed (the anchors match that
/// text), up to 200 characters of context on each side within its
/// sentence or block, its anchor, and what saving it as a highlight
/// merges.
class ArticleSelection {
  const ArticleSelection({
    required this.range,
    required this.text,
    required this.contextText,
    required this.markedContextText,
    required this.cfi,
    this.highlightMerge,
  });

  /// Null when [range] holds no text.
  static ArticleSelection? of(
    ContentDocument doc,
    TextPointRange range, {
    List<SavedTextHighlight> highlights = const [],
  }) {
    final text = normalizeArticleText(doc.textOfRange(range));
    if (text.isEmpty) return null;
    bool context(int element) =>
        doc.attributeOf(element, 'data-rf-sentence') != null ||
        _contextNames.contains(doc.localNameOf(element).toLowerCase());
    final root =
        _closest(doc, _elementAt(doc, range.start), context) ??
        doc.elementIndexById(ArticleAnchor.contentId);
    var prefix = '';
    var suffix = '';
    if (root != ContentDocument.none) {
      prefix = _last(
        normalizeArticleText(_textBetween(doc, root, end: range.start)),
        _contextChars,
      );
      suffix = _first(
        normalizeArticleText(_textBetween(doc, root, start: range.end)),
        _contextChars,
      );
    }
    return ArticleSelection(
      range: range,
      text: text,
      contextText: normalizeArticleText('$prefix $text $suffix'),
      markedContextText: normalizeArticleText('$prefix [[$text]] $suffix'),
      cfi: ArticleAnchor.forRange(doc, range, text)?.encode() ?? '',
      highlightMerge: _merge(doc, range, highlights),
    );
  }

  final TextPointRange range;
  final String text;
  final String contextText;

  /// [contextText] with the selection in `[[` and `]]`.
  final String markedContextText;

  /// The selection's anchor, or empty when it has none (no element with
  /// an id holds it).
  final String cfi;
  final TextHighlightMerge? highlightMerge;

  static const _contextChars = 200;
  static const _contextNames = {
    'p',
    'li',
    'blockquote',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'pre',
  };
}

/// `articleHighlightMerge`: every saved highlight sharing text with
/// [selection], merged into one anchored range; a saved highlight's own
/// anchor and text when the union is its range.
TextHighlightMerge? _merge(
  ContentDocument doc,
  TextPointRange selection,
  List<SavedTextHighlight> highlights,
) {
  final byId = <String, SavedTextHighlight>{};
  final entries = <HighlightRangeEntry>[];
  for (final highlight in highlights) {
    final range = ArticleAnchor.decode(highlight.cfi)?.rangeIn(doc);
    if (highlight.id.isEmpty || range == null) continue;
    byId[highlight.id] = highlight;
    entries.add((id: highlight.id, range: range));
  }
  final plan = planHighlightMerge(doc, selection, entries);
  if (plan == null) return null;
  final ids = [for (final entry in plan.absorbed) entry.id];
  final sameAs = plan.sameAs;
  if (sameAs != null) {
    final saved = byId[sameAs.id]!;
    final text = normalizeArticleText(saved.text);
    return TextHighlightMerge(
      cfi: saved.cfi,
      text: text.isNotEmpty
          ? text
          : normalizeArticleText(doc.textOfRange(plan.range)),
      highlightIds: ids,
    );
  }
  final text = normalizeArticleText(doc.textOfRange(plan.range));
  final anchor = ArticleAnchor.forRange(doc, plan.range, text);
  if (anchor == null) return null;
  return TextHighlightMerge(
    cfi: anchor.encode(),
    text: text,
    highlightIds: ids,
  );
}
