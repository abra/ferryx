import '../epubcfi/cfi_node.dart';
import 'content_document.dart';

/// A boundary in a section's [ContentDocument]: in a text node, before
/// character [offset] (UTF-16 code units, as CFIs count); at an element,
/// just before it (offset 0) or just after it and everything inside it
/// (offset 1). Elements are what a laid-out paragraph shows as one
/// character: an image, a line break, raised text.
class TextPoint {
  const TextPoint(this.node, this.offset);

  final int node;
  final int offset;

  @override
  bool operator ==(Object other) =>
      other is TextPoint && other.node == node && other.offset == offset;

  @override
  int get hashCode => Object.hash(node, offset);

  @override
  String toString() => 'TextPoint($node, $offset)';
}

/// The part of a section's document from [start] to [end], start first.
class TextPointRange {
  const TextPointRange(this.start, this.end);

  final TextPoint start;
  final TextPoint end;

  @override
  bool operator ==(Object other) =>
      other is TextPointRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TextPointRange($start, $end)';
}

/// Document order of [TextPoint]s, and their conversion to and from the
/// DOM boundaries CFIs are made of.
extension TextPoints on ContentDocument {
  /// Negative when [a] comes first, zero when they are the same boundary,
  /// positive when [b] does.
  int comparePoints(TextPoint a, TextPoint b) {
    final (an, ao) = _orderKey(a);
    final (bn, bo) = _orderKey(b);
    return an != bn ? an - bn : ao - bo;
  }

  /// Nodes are numbered in document order, an element before what it
  /// holds; "after an element" is "before the node after its subtree".
  (int, int) _orderKey(TextPoint point) {
    final node = point.node;
    if (node >= nodeCount) return (nodeCount, -1);
    if (isText(node)) return (node, point.offset);
    return point.offset == 0 ? (node, -1) : (subtreeEndOf(node), -1);
  }

  /// Whether [range] holds no character.
  bool isCollapsedRange(TextPointRange range) =>
      comparePoints(range.start, range.end) >= 0;

  /// Whether [a] and [b] share a character; ranges that only touch do
  /// not, as in `readflex_range.js`.
  bool rangesIntersect(TextPointRange a, TextPointRange b) =>
      !isCollapsedRange(a) &&
      !isCollapsedRange(b) &&
      comparePoints(a.start, b.end) < 0 &&
      comparePoints(a.end, b.start) > 0;

  /// Whether [outer] holds all of [inner].
  bool rangeContains(TextPointRange outer, TextPointRange inner) =>
      !isCollapsedRange(outer) &&
      !isCollapsedRange(inner) &&
      comparePoints(outer.start, inner.start) <= 0 &&
      comparePoints(outer.end, inner.end) >= 0;

  /// Calls [visit] with each text node holding characters of [range],
  /// in document order, and the part `[from, to)` of its text inside.
  void forEachTextIn(
    TextPointRange range,
    void Function(int node, int from, int to) visit,
  ) {
    final (startNode, startOffset) = _orderKey(range.start);
    final (endNode, endOffset) = _orderKey(range.end);
    for (var i = startNode; i <= endNode && i < nodeCount; i++) {
      if (!isText(i)) continue;
      // An offset of -1 stands for "before the node".
      if (i == endNode && endOffset < 0) break;
      final length = textOf(i).length;
      final from = i == startNode && startOffset > 0 ? startOffset : 0;
      final to = i == endNode ? endOffset.clamp(0, length) : length;
      if (to > from) visit(i, from, to);
    }
  }

  /// The text of [range] as DOM `Range.toString()` gives it: the text
  /// nodes' characters in it, nothing between blocks.
  String textOfRange(TextPointRange range) {
    final out = StringBuffer();
    forEachTextIn(
      range,
      (node, from, to) => out.write(textOf(node).substring(from, to)),
    );
    return out.toString();
  }

  /// [point] as a DOM boundary: a text node and an offset, or an element
  /// and a child index.
  CfiPoint cfiPointOf(TextPoint point) {
    final index = point.node;
    if (index >= nodeCount) {
      return CfiPoint(node(0), node(0).children.length);
    }
    if (isText(index)) return CfiPoint(node(index), point.offset);
    final parent = parentOf(index);
    if (parent < 0) {
      return CfiPoint(
        node(index),
        point.offset == 0 ? 0 : node(index).children.length,
      );
    }
    var position = 0;
    for (var s = previousSiblingOf(index); s >= 0; s = previousSiblingOf(s)) {
      position++;
    }
    return CfiPoint(node(parent), position + (point.offset == 0 ? 0 : 1));
  }

  /// The [TextPoint] of DOM boundary [point] of this document.
  TextPoint textPointOf(CfiPoint point) {
    final container = point.node as ContentNode;
    if (container.isText) return TextPoint(container.index, point.offset);
    final children = container.children;
    if (children.isEmpty) return TextPoint(container.index, 0);
    if (point.offset < children.length) {
      return TextPoint(children[point.offset].index, 0);
    }
    final last = children.last;
    return last.isText
        ? TextPoint(last.index, textOf(last.index).length)
        : TextPoint(last.index, 1);
  }

  /// [range] as a DOM range.
  CfiNodeRange cfiRangeOf(TextPointRange range) =>
      CfiNodeRange(cfiPointOf(range.start), cfiPointOf(range.end));

  /// The [TextPointRange] of DOM range [range] of this document.
  TextPointRange textRangeOf(CfiNodeRange range) =>
      TextPointRange(textPointOf(range.start), textPointOf(range.end));
}
