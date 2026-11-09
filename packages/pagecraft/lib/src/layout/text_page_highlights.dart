import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../document/content_document.dart';
import '../document/text_point.dart';
import 'column_layout.dart';
import 'column_pages.dart';
import 'text_source_map.dart';

/// A tint over part of a section's text: a saved highlight, the preview
/// of one, a search hit.
///
/// Highlights are painted under the text with [color] (its alpha
/// included), in list order: later ones on top, and the topmost answers
/// a tap. On solid text and background this looks the same as the
/// WebView reader's translucent tint with `multiply` (light themes) or
/// `lighten` (dark themes) over the text, without blend modes.
@immutable
class TextHighlight {
  const TextHighlight({
    required this.id,
    required this.range,
    required this.color,
    this.verticalOffset = 0,
  });

  final String id;

  /// Where it is in the section's document.
  final TextPointRange range;
  final Color color;

  /// How far down the tint is moved, in logical pixels.
  final double verticalOffset;

  @override
  bool operator ==(Object other) =>
      other is TextHighlight &&
      other.id == id &&
      other.range == range &&
      other.color == color &&
      other.verticalOffset == verticalOffset;

  @override
  int get hashCode => Object.hash(id, range, color, verticalOffset);

  @override
  String toString() => 'TextHighlight($id, $range)';
}

/// The part of [highlight] in one paragraph: text offsets `[start, end)`
/// of [item]'s paragraph, and the boxes they cover in the column.
class PlacedHighlight {
  PlacedHighlight(this.highlight, this.item, this.start, this.end);

  final TextHighlight highlight;
  final ColumnText item;
  final int start;
  final int end;

  /// The boxes of the highlighted text, in column coordinates.
  late final List<Rect> rects = [
    for (final box in item.paragraph.boxesFor(start, end))
      box.toRect().shift(
        item.rect.topLeft + Offset(0, highlight.verticalOffset),
      ),
  ];
}

/// Where [highlights] fall on [page] of [column], laid out from [doc]:
/// one [PlacedHighlight] per highlight and paragraph shown on the page,
/// in paint order.
List<PlacedHighlight> placeHighlights(
  ContentDocument doc,
  ColumnLayout column,
  ColumnPage page,
  List<TextHighlight> highlights,
) {
  if (highlights.isEmpty) return const [];
  final placed = <PlacedHighlight>[];
  final shown = [
    for (final item in column.items)
      if (item is ColumnText &&
          item.rect.bottom > page.top &&
          item.rect.top < page.bottom &&
          item.paragraph.box.text.isNotEmpty)
        item,
  ];
  for (final highlight in highlights) {
    final range = highlight.range;
    if (doc.isCollapsedRange(range)) continue;
    for (final item in shown) {
      final map = item.paragraph.box.sourceMap;
      final length = item.paragraph.box.text.length;
      final firstSource = map.toSource(0);
      final lastSource = map.toSourceEnd(length);
      if (firstSource == null || lastSource == null) continue;
      final first = TextPoint(firstSource.node, firstSource.offset);
      final last = TextPoint(lastSource.node, lastSource.offset);
      if (doc.comparePoints(range.end, first) <= 0 ||
          doc.comparePoints(range.start, last) >= 0) {
        continue;
      }
      final start = doc.comparePoints(range.start, first) <= 0
          ? 0
          : _offsetIn(doc, map, range.start, length, isEnd: false);
      final end = doc.comparePoints(range.end, last) >= 0
          ? length
          : _offsetIn(doc, map, range.end, length, isEnd: true);
      if (end > start) placed.add(PlacedHighlight(highlight, item, start, end));
    }
  }
  return placed;
}

/// Where document point [point] falls in [item]'s paragraph: its text
/// offset, or null when the paragraph does not hold it. [isEnd] when it
/// ends a range.
int? paragraphOffsetOf(
  ContentDocument doc,
  ColumnText item,
  TextPoint point, {
  required bool isEnd,
}) {
  final box = item.paragraph.box;
  final length = box.text.length;
  if (length == 0) return null;
  final map = box.sourceMap;
  final firstSource = map.toSource(0);
  final lastSource = map.toSourceEnd(length);
  if (firstSource == null || lastSource == null) return null;
  final first = TextPoint(firstSource.node, firstSource.offset);
  final last = TextPoint(lastSource.node, lastSource.offset);
  if (doc.comparePoints(point, first) < 0 ||
      doc.comparePoints(point, last) > 0) {
    return null;
  }
  return _offsetIn(doc, map, point, length, isEnd: isEnd);
}

/// The paragraph offset of document point [point], which lies within the
/// paragraph's source; [isEnd] when it ends a range.
int _offsetIn(
  ContentDocument doc,
  TextSourceMap map,
  TextPoint point,
  int length, {
  required bool isEnd,
}) {
  final node = point.node;
  if (node >= doc.nodeCount) return length;
  final isText = doc.isText(node);
  if (isText) {
    final at = map.toParagraph(node, point.offset);
    if (at != null) return at;
  }
  // Inside (or at) what the paragraph shows as one character, such as
  // raised text: that character.
  for (
    var e = isText ? doc.parentOf(node) : node;
    e >= 0;
    e = doc.parentOf(e)
  ) {
    final at = map.toParagraph(e, 0);
    if (at != null) return isEnd && (isText || point.offset > 0) ? at + 1 : at;
  }
  final from = !isText && point.offset > 0 ? doc.subtreeEndOf(node) : node;
  return map.offsetFromNode(from) ?? length;
}
