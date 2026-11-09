import '../document/content_document.dart';
import '../document/text_point.dart';
import '../epubcfi/cfi.dart';
import '../epubcfi/cfi_node.dart';
import '../epubcfi/cfi_resolve.dart';
import '../layout/column_layout.dart';
import '../layout/column_pages.dart';
import 'section_preparer.dart';
import 'text_anchor.dart';

/// Where things are in one laid-out section: document points, heights in
/// the column, pages and CFIs. What restoring a saved position, following
/// a link or reporting the current page needs.
///
/// CFIs are full book CFIs: the section's own ([sectionCfi]) joined with
/// the path inside its document, as foliate-js's `getCFI` writes them,
/// so positions saved by either reader open in the other.
class TextLocator {
  TextLocator(this.section, this.column, {required this.sectionCfi});

  final PreparedSection section;
  final ColumnLayout column;
  final String sectionCfi;

  ContentDocument get _doc => section.document;

  /// The first thing shown at or below [y]: the start of the first line
  /// that is whole there, or a block image; null below the content.
  TextPoint? pointAt(double y) {
    for (final item in column.items) {
      if (item.rect.bottom <= y + 0.5) continue;
      switch (item) {
        case ColumnText(:final paragraph, :final rect):
          final local = y - rect.top;
          var line = local <= 0 ? 0 : paragraph.lineAtY(local);
          if (paragraph.lineTop(line) < local - 0.5) line++;
          final map = paragraph.box.sourceMap;
          for (; line < paragraph.lines.length; line++) {
            final source = map.toSource(paragraph.lineStart(line));
            if (source != null) return TextPoint(source.node, source.offset);
          }
        case ColumnImage(:final box):
          return TextPoint(box.node, 0);
        case ColumnMarker():
          break;
      }
    }
    return null;
  }

  /// The end of the last thing shown whole above [y]: the end of the last
  /// line that ends there, or just after a block image. With [pointAt]
  /// of a page's top it is the visible range foliate-js reports.
  TextPoint? endPointAt(double y) {
    final items = column.items;
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item.rect.top >= y - 0.5) continue;
      switch (item) {
        case ColumnText(:final paragraph, :final rect):
          final local = y - rect.top;
          final lines = paragraph.lines.length;
          var line = lines - 1;
          while (line >= 0 && paragraph.lineTop(line + 1) > local + 0.5) {
            line--;
          }
          if (line < 0) continue;
          final end = line + 1 < lines
              ? paragraph.lineStart(line + 1)
              : paragraph.box.text.length;
          final source = paragraph.box.sourceMap.toSourceEnd(end);
          if (source != null) return TextPoint(source.node, source.offset);
        case ColumnImage(:final box, :final rect):
          if (rect.bottom <= y + 0.5) return TextPoint(box.node, 1);
        case ColumnMarker():
          break;
      }
    }
    return null;
  }

  /// The top of what shows document point [node] at [offset]: the line
  /// holding a text point, the first content inside or after an element.
  /// Null when the section shows nothing there (or has not laid it out
  /// yet).
  double? yOf(int node, int offset) {
    if (node < 0 || node >= _doc.nodeCount) return null;
    if (_doc.isText(node)) {
      for (final item in column.items) {
        if (item is! ColumnText) continue;
        final map = item.paragraph.box.sourceMap;
        if (map.firstNode > node || map.lastNode < node) continue;
        final at = map.toParagraph(node, offset);
        if (at != null) return _lineTopOf(item, at);
      }
      // Text inside raised text (`<sup>`) or not shown: go by its element.
      final parent = _doc.parentOf(node);
      return parent < 0 ? null : yOf(parent, 0);
    }
    for (final item in column.items) {
      switch (item) {
        case ColumnText():
          final map = item.paragraph.box.sourceMap;
          if (map.lastNode < node) continue;
          if (map.firstNode >= node) return item.rect.top;
          final at = map.offsetFromNode(node);
          if (at != null) return _lineTopOf(item, at);
        case ColumnImage(:final box, :final rect):
          if (box.node >= node) return rect.top;
        case ColumnMarker():
          break;
      }
    }
    return null;
  }

  double _lineTopOf(ColumnText item, int offset) {
    final paragraph = item.paragraph;
    return item.rect.top + paragraph.lineTop(paragraph.lineAt(offset));
  }

  /// The CFI of what is shown first at or below [y]; the section's own
  /// CFI when nothing is.
  String cfiAt(double y) {
    final point = pointAt(y);
    if (point == null) return sectionCfi;
    final inner = cfiFromPoint(_doc.cfiPointOf(point));
    return joinCfiIndirections([sectionCfi, inner.toString()]);
  }

  /// The CFI range of what is shown from [top] to [bottom], as
  /// foliate-js's `lastLocation.cfi` names a page: from the first thing
  /// shown to the end of the last; a point CFI when the range is empty.
  String rangeCfiAt(double top, double bottom) {
    final start = pointAt(top);
    final end = endPointAt(bottom);
    if (start == null || end == null || _doc.comparePoints(start, end) >= 0) {
      return cfiAt(top);
    }
    final range = cfiFromRange(_doc.cfiRangeOf(TextPointRange(start, end)));
    return joinCfiIndirections([sectionCfi, range.toInnerString()]);
  }

  /// The top of what [cfi] points to in this section; 0 for the section
  /// itself; null when its path does not resolve here.
  double? yOfCfi(String cfi) {
    final parsed = Cfi.tryParse(cfi);
    if (parsed == null) return null;
    final paths = parsed.collapse().paths;
    if (paths.length < 2) return 0;
    final CfiNodeRange range;
    try {
      range = cfiToRange(_doc, CfiLocation(paths.sublist(1)));
    } on CfiResolveException {
      return null;
    }
    final start = _doc.textPointOf(range.start);
    return yOf(start.node, start.offset);
  }

  /// The top of the element [anchor] names, or null.
  double? yOfAnchor(TextAnchor anchor) {
    final node = anchor.find(_doc);
    return node < 0 ? null : yOf(node, 0);
  }
}

/// The page of [pages] holding height [y]: the last page that starts at
/// or above it.
int pageAtY(List<ColumnPage> pages, double y) {
  if (pages.isEmpty) return 0;
  var lo = 0;
  var hi = pages.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (pages[mid].top <= y + 0.5) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}
