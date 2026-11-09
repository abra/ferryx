import 'dart:convert';

import '../document/content_document.dart';
import '../document/text_point.dart';
import '../text_book/highlight_merge.dart';
import '../text_book/text_selection_details.dart'
    show SavedTextHighlight, TextHighlightMerge;

part 'article_selection.dart';

/// A place in an article as the reader stores it: positions, bookmarks
/// and highlights are `readflex-html-position:` and the anchor's JSON,
/// written as the article shell wrote them (its keys in the same order,
/// `encodeURIComponent`'s escapes), so the anchors saved while articles
/// were read in the WebView keep resolving, and new ones compare equal to
/// old ones of the same place.
///
/// An anchor names a sentence — the import marks each one with an
/// `id` of `<block>-s<index>` and `data-rf-sentence` — by its block, index
/// and text with some text around it; a highlight's also names the root
/// it lies in ([rangeRootId]) and where in that root's text, white space
/// collapsed, its text is ([matchText] at [matchIndex], with
/// [matchPrefix] and [matchSuffix] to find it again when the text moved).
class ArticleAnchor {
  const ArticleAnchor({
    required this.blockId,
    required this.sentenceIndex,
    required this.sentenceText,
    this.prefix = '',
    this.suffix = '',
    this.rangeRootId,
    this.matchText,
    this.matchLength,
    this.matchPrefix,
    this.matchSuffix,
    this.matchIndex,
  });

  static const scheme = 'readflex-html-position:';

  /// The id of the element the article's content is in (the shell's
  /// `<main>`): the root of a highlight across blocks.
  static const contentId = 'article-content';

  final String blockId;

  /// Null for an anchor at a block that has no sentences of its own.
  final int? sentenceIndex;
  final String sentenceText;

  /// Up to 96 characters of the block's text before and after the
  /// sentence.
  final String prefix;
  final String suffix;

  final String? rangeRootId;
  final String? matchText;
  final int? matchLength;

  /// Up to 48 characters before and after the match in the root's text.
  final String? matchPrefix;
  final String? matchSuffix;
  final int? matchIndex;

  bool get isRange => matchText != null || matchLength != null;

  /// The anchor [value] stores, or null when it is not one.
  static ArticleAnchor? decode(String? value) {
    if (value == null || !value.startsWith(scheme)) return null;
    final Object? json;
    try {
      json = jsonDecode(Uri.decodeComponent(value.substring(scheme.length)));
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final map = json;
    String? string(String key) => switch (map[key]) {
      final String s => s,
      _ => null,
    };
    int? integer(String key) => switch (map[key]) {
      final int n => n,
      final double n when n == n.roundToDouble() => n.toInt(),
      final String s => int.tryParse(s),
      _ => null,
    };
    final blockId = string('blockId');
    if (blockId == null) return null;
    return ArticleAnchor(
      blockId: blockId,
      sentenceIndex: integer('sentenceIndex'),
      sentenceText: string('sentenceText') ?? '',
      prefix: string('prefix') ?? '',
      suffix: string('suffix') ?? '',
      rangeRootId: string('rangeRootId'),
      matchText: string('matchText'),
      matchLength: integer('matchLength'),
      matchPrefix: string('matchPrefix'),
      matchSuffix: string('matchSuffix'),
      matchIndex: integer('matchIndex'),
    );
  }

  /// The stored form: as `encodePosition(anchor)` in the shell.
  String encode() {
    final json = <String, Object?>{
      'blockId': blockId,
      'sentenceIndex': sentenceIndex,
      'sentenceText': sentenceText,
      'prefix': prefix,
      'suffix': suffix,
      if (isRange) ...{
        'rangeRootId': rangeRootId,
        'matchText': matchText,
        'matchLength': matchLength,
        'matchPrefix': matchPrefix,
        'matchSuffix': matchSuffix,
        'matchIndex': matchIndex,
      },
    };
    return '$scheme${encodeUriComponent(jsonEncode(json))}';
  }

  /// The anchor of sentence element [sentence] (a `data-rf-sentence`
  /// span) in its block: a position or a bookmark.
  static ArticleAnchor? forSentence(ContentDocument doc, int sentence) {
    final index = int.tryParse(
      doc.attributeOf(sentence, 'data-rf-sentence') ?? '',
    );
    final block = _closest(
      doc,
      sentence,
      (e) =>
          doc.attributeOf(e, 'data-rf-block-id') != null ||
          doc.attributeOf(e, 'id') != null,
    );
    if (index == null || block == null) return null;
    final blockId =
        doc.attributeOf(block, 'data-rf-block-id') ??
        doc.attributeOf(block, 'id') ??
        '';
    if (blockId.isEmpty) return null;
    final blockText = normalizeArticleText(textContentOf(doc, block));
    final sentenceText = normalizeArticleText(textContentOf(doc, sentence));
    final at = sentenceText.isEmpty ? -1 : blockText.indexOf(sentenceText);
    return ArticleAnchor(
      blockId: blockId,
      sentenceIndex: index,
      sentenceText: sentenceText,
      prefix: at > 0 ? blockText.substring(_max(0, at - 96), at) : '',
      suffix: at >= 0
          ? blockText.substring(
              at + sentenceText.length,
              _min(blockText.length, at + sentenceText.length + 96),
            )
          : '',
    );
  }

  /// The anchor of [range], with [selectedText] as the reader sees it: a
  /// highlight's. Its root is the sentence holding it, else the block,
  /// else the nearest element with an id around both ends; null when
  /// none has one or the text is not found there.
  static ArticleAnchor? forRange(
    ContentDocument doc,
    TextPointRange range,
    String selectedText,
  ) {
    final startElement = _elementAt(doc, range.start);
    final endElement = _elementAt(doc, range.end, end: true);
    bool sentence(int e) => doc.attributeOf(e, 'data-rf-sentence') != null;
    bool block(int e) => doc.attributeOf(e, 'data-rf-block-id') != null;
    bool stable(int e) => doc.attributeOf(e, 'id') != null;
    final startSentence = _closest(doc, startElement, sentence);
    final endSentence = _closest(doc, endElement, sentence);
    final startBlock = _closest(doc, startElement, block);
    final endBlock = _closest(doc, endElement, block);
    final startStable = _closest(doc, startElement, stable);
    final endStable = _closest(doc, endElement, stable);
    final content = doc.elementIndexById(contentId);
    final root = startSentence != null && startSentence == endSentence
        ? startSentence
        : startBlock != null && startBlock == endBlock
        ? startBlock
        : startStable != null && startStable == endStable
        ? startStable
        : content == ContentDocument.none
        ? null
        : content;
    final rootId = root == null ? null : doc.attributeOf(root, 'id');
    if (root == null || rootId == null || rootId.isEmpty) return null;
    final position =
        (startSentence == null ? null : forSentence(doc, startSentence)) ??
        _textRootAnchor(doc, root);
    if (position == null) return null;
    final before = _textBetween(doc, root, end: range.start);
    final after = _textBetween(doc, root, start: range.end);
    final rootText = normalizeArticleText(textContentOf(doc, root));
    final matchText = normalizeArticleText(selectedText);
    final draft = ArticleAnchor(
      blockId: position.blockId,
      sentenceIndex: position.sentenceIndex,
      sentenceText: position.sentenceText,
      prefix: position.prefix,
      suffix: position.suffix,
      rangeRootId: rootId,
      matchText: matchText,
      matchLength: matchText.length,
      matchPrefix: _last(normalizeArticleText(before), 48),
      matchSuffix: _first(normalizeArticleText(after), 48),
      matchIndex: _normalizedStartOffset(before, selectedText),
    );
    final index =
        _exactMatchOffset(rootText, draft) ??
        _contextMatchOffset(rootText, draft);
    if (index == null) return null;
    return draft._withMatchIndex(index);
  }

  ArticleAnchor _withMatchIndex(int index) => ArticleAnchor(
    blockId: blockId,
    sentenceIndex: sentenceIndex,
    sentenceText: sentenceText,
    prefix: prefix,
    suffix: suffix,
    rangeRootId: rangeRootId,
    matchText: matchText,
    matchLength: matchLength,
    matchPrefix: matchPrefix,
    matchSuffix: matchSuffix,
    matchIndex: index,
  );

  /// The element a position or bookmark points at: its root, its
  /// sentence, its block, or the sentence with its text.
  int? elementIn(ContentDocument doc) {
    for (final id in [rangeRootId, ?_sentenceId, blockId]) {
      if (id == null || id.isEmpty) continue;
      final element = doc.elementIndexById(id);
      if (element != ContentDocument.none) return element;
    }
    return _sentenceWithText(doc, sentenceText);
  }

  String? get _sentenceId =>
      sentenceIndex == null ? null : '$blockId-s$sentenceIndex';

  /// The text a highlight marks, or null when it is no longer there.
  TextPointRange? rangeIn(ContentDocument doc) {
    final root = elementIn(doc);
    if (root == null) return null;
    final text = normalizeArticleText(textContentOf(doc, root));
    final match = normalizeArticleText(matchText);
    final length = match.isNotEmpty ? match.length : (matchLength ?? 0);
    if (text.isEmpty || length <= 0) return null;
    final offset =
        _contextMatchOffset(text, this) ?? _exactMatchOffset(text, this);
    if (offset == null) return null;
    return _rangeForNormalizedOffset(doc, root, offset, length);
  }

  @override
  bool operator ==(Object other) =>
      other is ArticleAnchor && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;

  @override
  String toString() => 'ArticleAnchor($blockId:$sentenceIndex)';
}

/// White space collapsed to single spaces and trimmed: the text anchors
/// compare.
String normalizeArticleText(String? value) =>
    (value ?? '').replaceAll(_whiteSpace, ' ').trim();

final _whiteSpace = RegExp(r'\s+');

/// Every text node's text under [element], in document order: the DOM's
/// `textContent`.
String textContentOf(ContentDocument doc, int element) {
  final out = StringBuffer();
  for (final node in doc.descendantsOf(element)) {
    if (doc.isText(node)) out.write(doc.textOf(node));
  }
  return out.toString();
}

/// JavaScript's `encodeURIComponent`: every character but `A-Z a-z 0-9
/// - _ . ! ~ * ' ( )` as its UTF-8 bytes in percent escapes.
String encodeUriComponent(String value) {
  final out = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final unreserved =
        (byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x61 && byte <= 0x7A) ||
        (byte >= 0x30 && byte <= 0x39) ||
        "-_.!~*'()".codeUnits.contains(byte);
    if (unreserved) {
      out.writeCharCode(byte);
    } else {
      out
        ..write('%')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return out.toString();
}

int _max(int a, int b) => a > b ? a : b;
int _min(int a, int b) => a < b ? a : b;

String _last(String text, int count) =>
    text.length <= count ? text : text.substring(text.length - count);

String _first(String text, int count) =>
    text.length <= count ? text : text.substring(0, count);

/// [element] or its nearest ancestor that [test] accepts.
int? _closest(ContentDocument doc, int? element, bool Function(int) test) {
  for (
    var e = element;
    e != null && e != ContentDocument.none;
    e = doc.parentOf(e)
  ) {
    if (doc.isElement(e) && test(e)) return e;
  }
  return null;
}

/// The element a boundary is in: a text node's parent, or the element.
int? _elementAt(ContentDocument doc, TextPoint point, {bool end = false}) {
  final node = point.node;
  if (node == ContentDocument.none) return null;
  return doc.isText(node) ? doc.parentOf(node) : node;
}

ArticleAnchor? _textRootAnchor(ContentDocument doc, int element) {
  final id = doc.attributeOf(element, 'id');
  if (id == null || id.isEmpty) return null;
  return ArticleAnchor(
    blockId: doc.attributeOf(element, 'data-rf-block-id') ?? id,
    sentenceIndex: null,
    sentenceText: normalizeArticleText(textContentOf(doc, element)),
  );
}

int? _sentenceWithText(ContentDocument doc, String text) {
  final wanted = normalizeArticleText(text);
  if (wanted.isEmpty) return null;
  for (var node = 0; node < doc.nodeCount; node++) {
    if (doc.isElement(node) &&
        doc.attributeOf(node, 'data-rf-sentence') != null &&
        normalizeArticleText(textContentOf(doc, node)) == wanted) {
      return node;
    }
  }
  return null;
}

/// The text of [root] before [end] (from its start) or after [start] (to
/// its end): a DOM range's `toString()`.
String _textBetween(
  ContentDocument doc,
  int root, {
  TextPoint? start,
  TextPoint? end,
}) {
  final out = StringBuffer();
  for (final node in doc.descendantsOf(root)) {
    if (!doc.isText(node)) continue;
    final text = doc.textOf(node);
    var from = 0;
    var to = text.length;
    if (end != null) {
      final order = _compareNode(doc, node, end);
      if (order > 0) break;
      if (order == 0) to = end.offset.clamp(0, text.length);
    }
    if (start != null) {
      final order = _compareNode(doc, node, start);
      if (order < 0) continue;
      if (order == 0) from = start.offset.clamp(0, text.length);
    }
    if (from < to) out.write(text.substring(from, to));
  }
  return out.toString();
}

/// Where text node [node] is against [point]: before it (negative), the
/// node it is in (zero), or after it (positive).
int _compareNode(ContentDocument doc, int node, TextPoint point) {
  if (point.node == node) return 0;
  final at = point.node;
  if (doc.isText(at)) return node < at ? -1 : 1;
  // Before an element (offset 0) or after it and its subtree (1).
  final boundary = point.offset == 0 ? at : doc.subtreeEndOf(at);
  return node < boundary ? -1 : 1;
}

/// `normalizedSelectionStartOffset`: where the selection starts in the
/// root's normalized text, from the text before it.
int? _normalizedStartOffset(String before, String selected) {
  final match = normalizeArticleText(selected);
  if (match.isEmpty) return null;
  final through = normalizeArticleText(before + selected);
  if (!through.toLowerCase().endsWith(match.toLowerCase())) return null;
  return through.length - match.length;
}

int? _exactMatchOffset(String text, ArticleAnchor anchor) {
  final index = anchor.matchIndex;
  final length = anchor.matchLength;
  if (index == null || length == null || index < 0 || length <= 0) {
    return null;
  }
  if (index + length > text.length) return null;
  final match = normalizeArticleText(anchor.matchText);
  final exact = text.substring(index, index + length);
  return match.isEmpty || exact.toLowerCase() == match.toLowerCase()
      ? index
      : null;
}

/// The best place for the anchor's text in [text]: near where it was,
/// after its prefix and before its suffix.
int? _contextMatchOffset(String text, ArticleAnchor anchor) {
  final match = normalizeArticleText(anchor.matchText);
  if (match.isEmpty) return null;
  final lowerText = text.toLowerCase();
  final lowerMatch = match.toLowerCase();
  final prefix = normalizeArticleText(anchor.matchPrefix).toLowerCase();
  final suffix = normalizeArticleText(anchor.matchSuffix).toLowerCase();
  final expected = anchor.matchIndex;
  int? best;
  var bestScore = double.negativeInfinity;
  var from = 0;
  while (from <= lowerText.length) {
    final index = lowerText.indexOf(lowerMatch, from);
    if (index < 0) break;
    var score = 0.0;
    if (expected != null && expected >= 0) {
      score -= (index - expected).abs() / 1000;
    }
    if (prefix.isNotEmpty &&
        normalizeArticleText(lowerText.substring(0, index)).endsWith(prefix)) {
      score += 3;
    }
    if (suffix.isNotEmpty &&
        normalizeArticleText(
          lowerText.substring(index + lowerMatch.length),
        ).startsWith(suffix)) {
      score += 3;
    }
    if (best == null || score > bestScore) {
      best = index;
      bestScore = score;
    }
    from = index + _max(1, lowerMatch.length);
  }
  return best;
}

/// `textRangeForNormalizedOffset`: the range of [length] characters from
/// [start] in [root]'s text with white space collapsed and trimmed.
TextPointRange? _rangeForNormalizedOffset(
  ContentDocument doc,
  int root,
  int start,
  int length,
) {
  if (start < 0 || length <= 0) return null;
  final mapping = <(int node, int start, int end)>[];
  var seenText = false;
  (int, int, int)? pendingSpace;
  for (final node in doc.descendantsOf(root)) {
    if (!doc.isText(node)) continue;
    final text = doc.textOf(node);
    for (var i = 0; i < text.length; i++) {
      if (_whiteSpace.hasMatch(text[i])) {
        if (seenText && pendingSpace == null) pendingSpace = (node, i, i + 1);
        continue;
      }
      if (pendingSpace != null && mapping.isNotEmpty) mapping.add(pendingSpace);
      pendingSpace = null;
      seenText = true;
      mapping.add((node, i, i + 1));
    }
  }
  final last = start + length - 1;
  if (start >= mapping.length || last >= mapping.length) return null;
  final (startNode, startOffset, _) = mapping[start];
  final (endNode, _, endOffset) = mapping[last];
  return TextPointRange(
    TextPoint(startNode, startOffset),
    TextPoint(endNode, endOffset),
  );
}
