/// One piece of text belongs to at most one highlight: saving a selection
/// absorbs every saved highlight it shares text with, as the WebView
/// reader's `planHighlightMerge` (`readflex_range.js`) plans it.
library;

import '../document/content_document.dart';
import '../document/text_point.dart';

/// A saved highlight of the section: its id and where it is.
typedef HighlightRangeEntry = ({String id, TextPointRange range});

/// What saving a selection replaces: the [range] covering it and every
/// highlight it touches, those highlights ([absorbed], in document
/// order), and [sameAs], the absorbed highlight whose range is the whole
/// union, if any: saving onto it keeps its identity (a recolour).
class HighlightMergePlan {
  const HighlightMergePlan({
    required this.range,
    required this.absorbed,
    required this.sameAs,
  });

  final TextPointRange range;
  final List<HighlightRangeEntry> absorbed;
  final HighlightRangeEntry? sameAs;
}

/// Plans saving [selection] as a highlight over [saved]. The union grows
/// until no remaining entry shares a character with it: an absorbed
/// highlight that reaches further pulls in one it overlapped. Null when
/// the selection shares no character with any. O(absorbed × saved)
/// comparisons, once per settled selection.
HighlightMergePlan? planHighlightMerge(
  ContentDocument doc,
  TextPointRange selection,
  List<HighlightRangeEntry> saved,
) {
  if (doc.isCollapsedRange(selection) || saved.isEmpty) return null;
  final pending = [
    for (final entry in saved)
      if (entry.id.isNotEmpty && !doc.isCollapsedRange(entry.range)) entry,
  ];
  final absorbed = <HighlightRangeEntry>[];
  var start = selection.start;
  var end = selection.end;
  var grew = true;
  while (grew && pending.isNotEmpty) {
    grew = false;
    for (var i = pending.length - 1; i >= 0; i--) {
      final entry = pending[i];
      if (!doc.rangesIntersect(TextPointRange(start, end), entry.range)) {
        continue;
      }
      pending.removeAt(i);
      absorbed.add(entry);
      if (doc.comparePoints(start, entry.range.start) > 0) {
        start = entry.range.start;
      }
      if (doc.comparePoints(end, entry.range.end) < 0) end = entry.range.end;
      grew = true;
    }
  }
  if (absorbed.isEmpty) return null;
  absorbed.sort((a, b) {
    final byStart = doc.comparePoints(a.range.start, b.range.start);
    return byStart != 0 ? byStart : doc.comparePoints(a.range.end, b.range.end);
  });
  final union = TextPointRange(start, end);
  HighlightRangeEntry? sameAs;
  for (final entry in absorbed) {
    if (doc.comparePoints(entry.range.start, start) == 0 &&
        doc.comparePoints(entry.range.end, end) == 0) {
      sameAs = entry;
      break;
    }
  }
  return HighlightMergePlan(range: union, absorbed: absorbed, sameAs: sameAs);
}
