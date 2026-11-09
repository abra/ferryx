/// What the reader tells text actions about a selection besides its text:
/// its whole-word expansion and the sentence around it, as the WebView
/// reader's `readflex_selection_normalizer.js` and
/// `readflex_selection_context.js` compute them, on a section's
/// [ContentDocument].
library;

import '../document/content_document.dart';
import '../document/text_point.dart';
import '../text/selection_normalizer.dart';
import '../text/sentence_breaks.dart';

/// The sentence (or sentences) around a selection, and the same text with
/// the selection marked `[[like this]]`; both with whitespace collapsed.
typedef SelectionContext = ({String contextText, String markedContextText});

/// A selection grown to whole words.
typedef NormalizedSelection = ({
  TextPointRange range,
  String selectedText,
  String normalizedText,
  SelectionKind kind,
});

/// Selections longer than this are not segmented: their context is
/// themselves.
const _maxSegmentedChars = 4096;

/// How far the context reaches on each side of a selection.
const _sideChars = 2048;
const _sideNodes = 256;

/// Elements a sentence does not cross, as `blockSelector` in the JS.
const _blockNames = {
  'p', 'li', 'blockquote', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', //
  'pre', 'div', 'td', 'th', 'dt', 'dd', 'figcaption',
};

String _collapse(String text) => text.replaceAll(_spaces, ' ').trim();
final _spaces = RegExp(r'\s+');
final _space = RegExp(r'\s');

SelectionContext _selectedOnly(String selected) {
  final text = _collapse(selected);
  return (
    contextText: text,
    markedContextText: text.isEmpty ? '' : '[[$text]]',
  );
}

/// The sentences of `before + selected + after` that the selection
/// touches. A side that was cut short ([beforeClipped], [afterClipped]) is
/// not a sentence boundary: when the sentence would reach it, the
/// selection alone is the context.
SelectionContext sentenceContextForSelection(
  String before,
  String selected,
  String after, {
  bool beforeClipped = false,
  bool afterClipped = false,
}) {
  final fallback = _selectedOnly(selected);
  if (selected.trim().isEmpty || selected.length > _maxSegmentedChars) {
    return fallback;
  }
  // Source line breaks are HTML whitespace, not sentence boundaries.
  final prefix = before.replaceAll(_spaces, ' ');
  final selection = selected.replaceAll(_spaces, ' ');
  final suffix = after.replaceAll(_spaces, ' ');
  final text = prefix + selection + suffix;
  final start = prefix.length;
  final end = start + selection.length;
  final breaks = sentenceBreaks(text);
  final (sentenceStart, _) = sentenceAt(
    text,
    start + selection.length - selection.trimLeft().length,
    breaks,
  );
  final (_, sentenceEnd) = sentenceAt(
    text,
    start + selection.trimRight().length - 1,
    breaks,
  );
  if ((beforeClipped && sentenceStart == 0) ||
      (afterClipped && sentenceEnd == text.length)) {
    return fallback;
  }
  return (
    contextText: _collapse(text.substring(sentenceStart, sentenceEnd)),
    markedContextText: _collapse(
      '${text.substring(sentenceStart, start)}[[$selection]]'
      '${text.substring(end, sentenceEnd)}',
    ),
  );
}

/// The context of [range] in [doc]: the sentences around it inside its
/// block (a paragraph, a list item, a cell), read at most 2048 characters
/// and 256 nodes to each side. A selection across blocks is its own
/// context.
SelectionContext buildSelectionContext(
  ContentDocument doc,
  TextPointRange range,
) {
  if (doc.isCollapsedRange(range)) return _selectedOnly('');
  final selected = doc.textOfRange(range);
  if (selected.trim().isEmpty || selected.length > _maxSegmentedChars) {
    return _selectedOnly(selected);
  }
  final start = doc.cfiPointOf(range.start);
  final end = doc.cfiPointOf(range.end);
  final startNode = (start.node as ContentNode).index;
  final endNode = (end.node as ContentNode).index;
  final root = _contextRoot(doc, startNode);
  if (root != _contextRoot(doc, endNode)) return _selectedOnly(selected);
  final before = _readSide(doc, startNode, start.offset, root, before: true);
  final after = _readSide(doc, endNode, end.offset, root, before: false);
  return sentenceContextForSelection(
    before.text,
    selected,
    after.text,
    beforeClipped: before.clipped,
    afterClipped: after.clipped,
  );
}

/// [range] grown to whole words where an edge cuts one inside a text
/// node; null for an empty range.
NormalizedSelection? normalizeSelectionRange(
  ContentDocument doc,
  TextPointRange range,
) {
  if (doc.isCollapsedRange(range)) return null;
  var start = range.start;
  var end = range.end;
  var kind = SelectionKind.exact;
  if (doc.isText(start.node)) {
    final grown = normalizeTextRange(
      doc.textOf(start.node),
      start.offset,
      start.offset,
    ).normalizedStart;
    if (grown != start.offset) {
      start = TextPoint(start.node, grown);
      kind = SelectionKind.partialWord;
    }
  }
  if (doc.isText(end.node)) {
    final grown = normalizeTextRange(
      doc.textOf(end.node),
      end.offset,
      end.offset,
    ).normalizedEnd;
    if (grown != end.offset) {
      end = TextPoint(end.node, grown);
      kind = SelectionKind.partialWord;
    }
  }
  final selectedText = doc.textOfRange(range);
  final normalized = TextPointRange(start, end);
  if (kind != SelectionKind.exact && _space.hasMatch(selectedText.trim())) {
    kind = SelectionKind.partialSpan;
  }
  return (
    range: normalized,
    selectedText: selectedText,
    normalizedText: doc.textOfRange(normalized),
    kind: kind,
  );
}

bool _isBlock(ContentDocument doc, int element) =>
    _blockNames.contains(doc.localNameOf(element)) ||
    doc.attributeOf(element, 'data-rf-sentence') != null;

/// The block holding [node], or the body.
int _contextRoot(ContentDocument doc, int node) {
  var element = doc.isText(node) ? doc.parentOf(node) : node;
  while (element >= 0) {
    if (_isBlock(doc, element)) return element;
    element = doc.parentOf(element);
  }
  for (final child in doc.childrenOf(0)) {
    if (!doc.isText(child) && doc.localNameOf(child) == 'body') return child;
  }
  return 0;
}

/// The text of [root] before (or after) DOM boundary [container],
/// [offset], up to the nearest block edge, as `readContextSide` walks it
/// with a tree walker: nodes are numbered in document order, so the
/// walker's previous and next node are the neighbouring indices.
({String text, bool clipped}) _readSide(
  ContentDocument doc,
  int container,
  int offset,
  int root, {
  required bool before,
}) {
  final rootEnd = doc.subtreeEndOf(root);
  final chunks = <String>[];
  var remaining = _sideChars;
  var visited = 0;
  ({String text, bool clipped}) finish(bool clipped) => (
    text: (before ? chunks.reversed : chunks).join(),
    clipped: clipped,
  );
  void take(String data, int start, int end) {
    final length = end - start;
    chunks.add(
      before
          ? data.substring(
              start > end - remaining ? start : end - remaining,
              end,
            )
          : data.substring(
              start,
              end < start + remaining ? end : start + remaining,
            ),
    );
    remaining -= length < remaining ? length : remaining;
  }

  int? advance(int node) {
    final next = before ? node - 1 : node + 1;
    return next >= root && next < rootEnd ? next : null;
  }

  int? node;
  if (doc.isText(container)) {
    final data = doc.textOf(container);
    final start = before ? 0 : offset;
    final end = before ? offset : data.length;
    final clipped = end - start > remaining;
    take(data, start, end);
    if (clipped) return finish(true);
    node = advance(container);
  } else {
    final children = doc.childrenOf(container).toList();
    if (offset < children.length) {
      final child = children[offset];
      node = before ? advance(child) : child;
    } else {
      // Past the last child: from the deepest last descendant.
      var current = container;
      while (visited < _sideNodes && doc.lastChildOf(current) >= 0) {
        current = doc.lastChildOf(current);
        visited++;
      }
      if (visited == _sideNodes) return finish(true);
      node = before ? current : advance(current);
      if (node == container) node = advance(container);
    }
  }
  while (node != null &&
      node != root &&
      remaining > 0 &&
      visited < _sideNodes) {
    visited++;
    if (doc.isText(node)) {
      // Walking back reaches the last text of a previous block before
      // that block's element.
      if (_contextRoot(doc, node) != root) return finish(false);
      final data = doc.textOf(node);
      final clipped = data.length > remaining;
      take(data, 0, data.length);
      if (clipped) return finish(true);
    } else if (_isBlock(doc, node)) {
      return finish(false);
    }
    node = advance(node);
  }
  return finish(node != null && node != root);
}
