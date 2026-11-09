import 'column_layout.dart';

/// One page: the slice `[top, bottom)` of a column.
class ColumnPage {
  const ColumnPage(this.top, this.bottom);

  final double top;
  final double bottom;

  double get height => bottom - top;

  bool contains(double y) => y >= top && y < bottom;

  @override
  bool operator ==(Object other) =>
      other is ColumnPage && other.top == top && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(top, bottom);

  @override
  String toString() => 'ColumnPage($top, $bottom)';
}

/// Cuts [column] into pages [pageHeight] tall at its break
/// opportunities: a page ends at a forced break if one comes first,
/// otherwise at the lowest allowed break that fits, at an avoided one
/// if no allowed break does, and through the content only when nothing
/// fits (an unbreakable box taller than a page). A page that would hold
/// less than [minFill] of a page because of an `allowed` break prefers
/// a later `avoid` one, so headings rarely end a page with little
/// above them. At a break the margins between the blocks are truncated,
/// as CSS fragments them: the page ends with the content above
/// ([ColumnBreak.fit]), the next starts at the block below, and the
/// margins after the last content take no page of their own.
///
/// While [column] is still being laid out, only the pages its laid-out
/// part decides are returned: a page whose bottom could still move (its
/// page height reaches past the laid-out height) is left for later, so
/// the pages returned never change.
List<ColumnPage> paginateColumn(
  ColumnLayout column, {
  required double pageHeight,
  double minFill = 0.5,
}) {
  final total = column.height;
  final content = column.isComplete ? column.contentHeight : total;
  final breaks = column.breaks;
  if (total <= 0 || pageHeight <= 0) {
    return column.isComplete ? const [ColumnPage(0, 0)] : const [];
  }
  final pages = <ColumnPage>[];
  var top = 0.0;
  var i = 0;
  while (top < content - 0.5) {
    final limit = top + pageHeight;
    if (!column.isComplete && limit + 0.5 > total) break;
    while (i < breaks.length && breaks[i].y <= top + 0.5) {
      i++;
    }
    ColumnBreak? forced;
    ColumnBreak? allowed;
    ColumnBreak? avoid;
    var j = i;
    while (j < breaks.length && breaks[j].fit <= limit + 0.5) {
      final b = breaks[j];
      switch (b.kind) {
        case ColumnBreakKind.forced:
          forced ??= b;
        case ColumnBreakKind.allowed:
          if (forced == null) allowed = b;
        case ColumnBreakKind.avoid:
          if (forced == null) avoid = b;
      }
      if (forced != null) break;
      j++;
    }
    final ColumnBreak? end;
    if (forced != null) {
      end = forced;
    } else if (content <= limit + 0.5) {
      end = ColumnBreak(total, ColumnBreakKind.forced, fit: content);
    } else if (allowed != null &&
        (avoid == null ||
            allowed.fit - top >= minFill * pageHeight ||
            avoid.y < allowed.y)) {
      end = allowed;
    } else {
      end = avoid ?? allowed;
    }
    var bottom = end?.fit ?? limit;
    var next = end?.y ?? limit;
    if (next <= top) bottom = next = limit;
    pages.add(ColumnPage(top, bottom > total ? total : bottom));
    top = next;
  }
  if (pages.isEmpty && !column.isComplete) return const [];
  return pages.isEmpty ? const [ColumnPage(0, 0)] : pages;
}
