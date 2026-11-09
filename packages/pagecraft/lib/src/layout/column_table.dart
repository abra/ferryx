part of 'column_layout.dart';

/// A cell's place in its table's grid (HTML's table model): its first
/// row and column and how many of each it spans.
class _GridCell {
  const _GridCell(
    this.cell,
    this.rowIndex,
    this.column, {
    required this.rowSpan,
    required this.columnSpan,
  });

  final TableCellBox cell;
  final int rowIndex;
  final int column;
  final int rowSpan;
  final int columnSpan;

  int get lastRow => rowIndex + rowSpan - 1;
  int get lastColumn => column + columnSpan - 1;
}

/// The grid of a [TableBox]: each cell in the first free slot of its row,
/// slots below a cell that spans rows taken, as browsers place them.
class _TableGrid {
  _TableGrid._(this.rows, this.columns, this.cells, this._slots);

  factory _TableGrid.of(TableBox box) {
    final rows = box.rows.length;
    final slots = [for (var r = 0; r < rows; r++) <int, _GridCell>{}];
    final cells = <_GridCell>[];
    var columns = 0;
    for (var r = 0; r < rows; r++) {
      var column = 0;
      for (final cell in box.rows[r].cells) {
        while (slots[r].containsKey(column)) {
          column++;
        }
        if (column >= _maxColumns) break;
        final rowSpan = cell.rowSpan.clamp(1, rows - r);
        final columnSpan = cell.columnSpan.clamp(1, _maxColumns - column);
        final placed = _GridCell(
          cell,
          r,
          column,
          rowSpan: rowSpan,
          columnSpan: columnSpan,
        );
        cells.add(placed);
        for (var rr = r; rr < r + rowSpan; rr++) {
          for (var c = column; c < column + columnSpan; c++) {
            slots[rr][c] = placed;
          }
        }
        column += columnSpan;
        if (column > columns) columns = column;
      }
    }
    return _TableGrid._(rows, columns, cells, slots);
  }

  /// Columns past this many are dropped: a stray `colspan="1000"`.
  static const _maxColumns = 200;

  final int rows;
  final int columns;

  /// In document order, which is grid order: by row, then column.
  final List<_GridCell> cells;
  final List<Map<int, _GridCell>> _slots;

  /// The cell covering slot ([row], [column]), or null.
  _GridCell? at(int row, int column) =>
      row < 0 || row >= rows ? null : _slots[row][column];
}

/// One edge of a collapsed border: the winner of the borders that meet
/// there.
class _Edge {
  const _Edge(this.width, this.style, this.color);

  static const none = _Edge(0, CssBorderStyle.none, 0);

  final double width;
  final CssBorderStyle style;
  final int color;

  bool get isHidden => style == CssBorderStyle.hidden;

  /// CSS 2.1 §17.6.2.1: `hidden` wins, then the wider border, then the
  /// style in this order; ties go to the earlier candidate (the cell
  /// before the row before the table).
  static _Edge resolve(Iterable<_Edge> candidates) {
    var best = none;
    for (final edge in candidates) {
      if (edge.isHidden) return const _Edge(0, CssBorderStyle.hidden, 0);
      if (edge.style == CssBorderStyle.none || edge.width <= 0) continue;
      if (best.style == CssBorderStyle.none ||
          edge.width > best.width ||
          (edge.width == best.width && _rank(edge.style) > _rank(best.style))) {
        best = edge;
      }
    }
    return best;
  }

  static int _rank(CssBorderStyle style) => switch (style) {
    CssBorderStyle.double => 8,
    CssBorderStyle.solid => 7,
    CssBorderStyle.dashed => 6,
    CssBorderStyle.dotted => 5,
    CssBorderStyle.ridge => 4,
    CssBorderStyle.outset => 3,
    CssBorderStyle.groove => 2,
    CssBorderStyle.inset => 1,
    CssBorderStyle.none || CssBorderStyle.hidden => 0,
  };
}

_Edge _edgeOf(ComputedStyle style, String side) => switch (side) {
  'top' => _Edge(
    style.borderWidth.top,
    style.borderStyle.top,
    style.borderColor.top,
  ),
  'right' => _Edge(
    style.borderWidth.right,
    style.borderStyle.right,
    style.borderColor.right,
  ),
  'bottom' => _Edge(
    style.borderWidth.bottom,
    style.borderStyle.bottom,
    style.borderColor.bottom,
  ),
  _ => _Edge(
    style.borderWidth.left,
    style.borderStyle.left,
    style.borderColor.left,
  ),
};

/// A collapsed table cell's borders: what it shares with its neighbours,
/// its row and the table, resolved per edge. Its geometry takes [half]
/// of each; its decoration draws the [width] centred on the grid line.
class _CellBorders {
  _CellBorders(this.top, this.right, this.bottom, this.left)
    : width = CssEdges(top.width, right.width, bottom.width, left.width),
      half = CssEdges(
        top.width / 2,
        right.width / 2,
        bottom.width / 2,
        left.width / 2,
      ),
      style = CssEdges(top.style, right.style, bottom.style, left.style),
      color = CssEdges(top.color, right.color, bottom.color, left.color);

  final _Edge top;
  final _Edge right;
  final _Edge bottom;
  final _Edge left;
  final CssEdges<double> width;
  final CssEdges<double> half;
  final CssEdges<CssBorderStyle> style;
  final CssEdges<int> color;

  bool get hasBorder =>
      width.top > 0 || width.right > 0 || width.bottom > 0 || width.left > 0;

  /// The borders of [cell] in [grid] of [table]: each edge against the
  /// neighbouring cell's opposite edge, the rows' and the table's at
  /// the outside. A cell spanning several neighbours is judged against
  /// the first.
  factory _CellBorders.of(_GridCell cell, _TableGrid grid, TableBox table) {
    final rows = table.rows;
    final cellStyle = cell.cell.style;
    final firstRow = rows[cell.rowIndex].style;
    final lastRow = rows[cell.lastRow].style;
    final above = grid.at(cell.rowIndex - 1, cell.column);
    final below = grid.at(cell.lastRow + 1, cell.column);
    final before = cell.column == 0
        ? null
        : grid.at(cell.rowIndex, cell.column - 1);
    final after = grid.at(cell.rowIndex, cell.lastColumn + 1);
    final atStart = cell.column == 0;
    final atEnd = cell.lastColumn == grid.columns - 1;
    return _CellBorders(
      _Edge.resolve([
        _edgeOf(cellStyle, 'top'),
        if (above != null) _edgeOf(above.cell.style, 'bottom'),
        _edgeOf(firstRow, 'top'),
        if (cell.rowIndex > 0) _edgeOf(rows[cell.rowIndex - 1].style, 'bottom'),
        if (cell.rowIndex == 0) _edgeOf(table.style, 'top'),
      ]),
      _Edge.resolve([
        _edgeOf(cellStyle, 'right'),
        if (after != null) _edgeOf(after.cell.style, 'left'),
        if (atEnd) _edgeOf(firstRow, 'right'),
        if (atEnd) _edgeOf(table.style, 'right'),
      ]),
      _Edge.resolve([
        _edgeOf(cellStyle, 'bottom'),
        if (below != null) _edgeOf(below.cell.style, 'top'),
        _edgeOf(lastRow, 'bottom'),
        if (cell.lastRow + 1 < rows.length)
          _edgeOf(rows[cell.lastRow + 1].style, 'top'),
        if (cell.lastRow == rows.length - 1) _edgeOf(table.style, 'bottom'),
      ]),
      _Edge.resolve([
        _edgeOf(cellStyle, 'left'),
        if (before != null) _edgeOf(before.cell.style, 'right'),
        if (atStart) _edgeOf(firstRow, 'left'),
        if (atStart) _edgeOf(table.style, 'left'),
      ]),
    );
  }
}

/// A table cell laid out in its row: the ranges of [ColumnLayout.items]
/// and decorations it added, and where its content ends.
class _PlacedCell {
  const _PlacedCell(
    this.grid, {
    required this.items,
    required this.decorations,
    required this.bottom,
    required this.decorated,
  });

  final _GridCell grid;
  final (int, int) items;
  final (int, int) decorations;
  final double bottom;

  /// Whether the cell's own background and borders come first in
  /// [decorations].
  final bool decorated;
}

/// How a table's grid sits in its border box: the space around the
/// columns and between them, in px.
class _TableFrame {
  const _TableFrame({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.spacingX,
    required this.spacingY,
  });

  /// From the border box's edge to the first column's (or row's) edge:
  /// border, padding and spacing when separated, half the outer
  /// collapsed border when collapsed.
  final double left;
  final double right;
  final double top;
  final double bottom;

  /// Between columns and rows; zero when collapsed.
  final double spacingX;
  final double spacingY;

  /// What the frame adds to [columns] columns' widths.
  double extraWidth(int columns) =>
      left + right + spacingX * (columns > 1 ? columns - 1 : 0);
}

/// CSS tables (CSS 2.1 §17): the grid, column widths by the automatic
/// table layout, separated borders with `border-spacing` or collapsed
/// ones, rows that span, captions above or below.
extension _TableLayout on _ColumnBuilder {
  /// Lays [box] out: each column between its widest word and its content
  /// on one line, the table as wide as its columns ask or its set width,
  /// within the column. Rows never split, nor do rows tied together by a
  /// cell spanning them; a row is as tall as its tallest cell, every
  /// cell's background and borders reach the row's bottom and its
  /// content sits by `vertical-align` (middle unless the book says
  /// otherwise).
  ///
  /// A table that scrolls (`overflow-x: auto` or `scroll`, not inside
  /// another table) is never narrower than its words and may be wider
  /// than the column, up to its `max-width`: then it starts at its
  /// containing block's start edge and scrolls sideways in it, with a
  /// [ColumnScroller] over its items and decorations; its caption stays
  /// put, as wide as the column.
  void _table(TableBox box, double left, double width) {
    final s = box.style;
    _clear(s.clear);
    _clearBeside(left, width);
    final margins = _margins(box, width);
    _pending = _pending.add(margins.top);
    final available = width - (margins.left ?? 0) - (margins.right ?? 0);
    final viewLeft = left + (margins.left ?? 0);
    final scrolls = s.overflowX.scrolls && _tables == 0;
    final grid = _TableGrid.of(box);
    final collapsed = s.borderCollapse;
    final cellBorders = collapsed
        ? {
            for (final cell in grid.cells)
              cell: _CellBorders.of(cell, grid, box),
          }
        : const <_GridCell, _CellBorders>{};
    final frame = _frameOf(box, grid, available, cellBorders);
    final columns = grid.columns;
    final widths = columns == 0
        ? const <double>[]
        : _columnWidths(
            box,
            grid,
            available,
            frame,
            cellBorders,
            scrolls: scrolls,
          );
    final tableWidth = columns == 0
        ? available
        : widths.fold(0.0, (a, b) => a + b) + frame.extraWidth(columns);
    final wide = scrolls && tableWidth > available + 0.5;
    final tableLeft = wide
        ? (s.direction == CssDirection.rtl
              ? viewLeft + available - tableWidth
              : viewLeft)
        : switch ((margins.left, margins.right)) {
            (null, null) => left + (width - tableWidth) / 2,
            (null, final right?) => left + width - right - tableWidth,
            (final left0?, _) => left + left0,
          };
    final caption = box.caption;
    if (caption != null && s.captionSide == CssCaptionSide.top) {
      _placeNow(
        caption,
        wide ? viewLeft : tableLeft,
        wide ? available : tableWidth,
      );
    }
    final firstItem = items.length;
    final firstDecoration = decorations.length;
    // Collapsed, the table's borders are drawn by its cells.
    final decorated = collapsed
        ? (s.backgroundColor >> 24) != 0
        : _isDecorated(s);
    final decorationIndex = decorated ? decorations.length : -1;
    if (decorated) decorations.add(null);

    // Each column's left edge.
    final columnLeft = <double>[];
    var x = tableLeft + frame.left;
    for (var c = 0; c < columns; c++) {
      columnLeft.add(x);
      x += widths[c] + frame.spacingX;
    }
    double spanWidth(_GridCell cell) {
      var w = frame.spacingX * (cell.columnSpan - 1);
      for (var c = cell.column; c <= cell.lastColumn; c++) {
        w += widths[c];
      }
      return w;
    }

    _tables++;
    double? top;
    final rowTops = <double>[];
    final rowBottoms = <double>[];
    final placed = <_PlacedCell>[];
    var nextCell = 0;
    // The last row a cell spanning rows reaches: no page breaks before it.
    var tiedUntil = -1;
    for (var r = 0; r < grid.rows; r++) {
      final row = box.rows[r];
      if (r > tiedUntil) {
        _placeEdge();
      } else {
        y += _pending.value;
        _pending = _Margin.zero;
      }
      if (top == null) {
        top = y;
        y += frame.top;
      } else {
        y += frame.spacingY;
      }
      final rowTop = y;
      rowTops.add(rowTop);
      final rowDecoration = (row.style.backgroundColor >> 24) != 0
          ? decorations.length
          : -1;
      if (rowDecoration >= 0) decorations.add(null);
      var rowBottom = rowTop + _rowMinHeight(row);
      _noBreaks++;
      while (nextCell < grid.cells.length &&
          grid.cells[nextCell].rowIndex == r) {
        final cell = grid.cells[nextCell++];
        if (cell.lastRow > tiedUntil) tiedUntil = cell.lastRow;
        y = rowTop;
        _pending = _Margin.zero;
        final firstItem = items.length;
        final firstDecoration = decorations.length;
        // A cell's floats are its own (a block formatting context).
        final floats = _withOwnFloats(
          () => _placeNow(
            cell.cell,
            columnLeft[cell.column],
            spanWidth(cell),
            collapsed: cellBorders[cell],
          ),
        );
        var cellBottom = y + (_pending.value > 0 ? _pending.value : 0);
        if (floats > cellBottom) cellBottom = floats;
        placed.add(
          _PlacedCell(
            cell,
            items: (firstItem, items.length),
            decorations: (firstDecoration, decorations.length),
            bottom: cellBottom,
            decorated: _isCellDecorated(cell.cell.style, cellBorders[cell]),
          ),
        );
        if (cell.rowSpan == 1 && cellBottom > rowBottom) rowBottom = cellBottom;
      }
      // A cell spanning rows that end here is as tall as they are,
      // and makes the last of them taller if its content asks for it.
      for (final cell in placed) {
        if (cell.grid.lastRow == r && cell.grid.rowSpan > 1) {
          if (cell.bottom > rowBottom) rowBottom = cell.bottom;
        }
      }
      rowBottoms.add(rowBottom);
      for (final cell in placed) {
        if (cell.grid.lastRow == r) _fitCellToRow(cell, rowBottom);
      }
      if (rowDecoration >= 0 && columns > 0) {
        decorations[rowDecoration] = ColumnDecoration(
          rect: Rect.fromLTRB(
            columnLeft.first,
            rowTop,
            columnLeft.last + widths.last,
            rowBottom,
          ),
          background: row.style.backgroundColor,
          borderWidth: const CssEdges.all(0),
          borderStyle: const CssEdges.all(CssBorderStyle.none),
          borderColor: const CssEdges.all(0),
        );
      }
      _noBreaks--;
      _pending = _Margin.zero;
      y = rowBottom;
      _nextBreak = null;
    }
    _tables--;
    if (top != null) y += frame.bottom;
    if (decorated) {
      final tableTop = top ?? y;
      decorations[decorationIndex] = ColumnDecoration(
        rect: Rect.fromLTRB(tableLeft, tableTop, tableLeft + tableWidth, y),
        background: s.backgroundColor,
        borderWidth: collapsed ? const CssEdges.all(0) : s.borderWidth,
        borderStyle: s.borderStyle,
        borderColor: s.borderColor,
        radius: collapsed
            ? const CssCorners.all(CssRadius.zero)
            : s.borderRadius,
        backgroundImage: s.backgroundImage,
      );
    }
    if (wide) {
      final scroller = ColumnScroller(
        viewport: Rect.fromLTRB(viewLeft, top ?? y, viewLeft + available, y),
        contentLeft: tableLeft,
        contentWidth: tableWidth,
      );
      scrollers.add(scroller);
      for (var i = firstItem; i < items.length; i++) {
        items[i] = items[i].inScroller(scroller);
      }
      for (var i = firstDecoration; i < decorations.length; i++) {
        decorations[i] = decorations[i]?.inScroller(scroller);
      }
    }
    if (caption != null && s.captionSide == CssCaptionSide.bottom) {
      _placeNow(
        caption,
        wide ? viewLeft : tableLeft,
        wide ? available : tableWidth,
      );
    }
    _pending = _pending.add(margins.bottom);
  }

  /// A row's set height, the least it is.
  double _rowMinHeight(TableRowBox row) {
    final height = row.style.height;
    return height == null || height.hasPercent ? 0 : InlineStyler.px(height, 0);
  }

  /// The space around and between [box]'s columns, [available] wide:
  /// separated, the table's border and padding and its spacing; collapsed,
  /// half of the widest outer cell border on each side.
  _TableFrame _frameOf(
    TableBox box,
    _TableGrid grid,
    double available,
    Map<_GridCell, _CellBorders> collapsed,
  ) {
    final s = box.style;
    if (collapsed.isNotEmpty) {
      var left = 0.0;
      var right = 0.0;
      var top = 0.0;
      var bottom = 0.0;
      for (final MapEntry(key: cell, value: borders) in collapsed.entries) {
        if (cell.column == 0 && borders.half.left > left) {
          left = borders.half.left;
        }
        if (cell.lastColumn == grid.columns - 1 && borders.half.right > right) {
          right = borders.half.right;
        }
        if (cell.rowIndex == 0 && borders.half.top > top) {
          top = borders.half.top;
        }
        if (cell.lastRow == grid.rows - 1 && borders.half.bottom > bottom) {
          bottom = borders.half.bottom;
        }
      }
      return _TableFrame(
        left: left,
        right: right,
        top: top,
        bottom: bottom,
        spacingX: 0,
        spacingY: 0,
      );
    }
    double px(CssLength length) => InlineStyler.px(length, available);
    return _TableFrame(
      left: s.borderWidth.left + px(s.padding.left) + s.borderSpacingX,
      right: s.borderWidth.right + px(s.padding.right) + s.borderSpacingX,
      top: s.borderWidth.top + px(s.padding.top) + s.borderSpacingY,
      bottom: s.borderWidth.bottom + px(s.padding.bottom) + s.borderSpacingY,
      spacingX: s.borderSpacingX,
      spacingY: s.borderSpacingY,
    );
  }

  /// Stretches [placed]'s own decoration to [rowBottom] and moves its
  /// content down by its `vertical-align`.
  void _fitCellToRow(_PlacedCell placed, double rowBottom) {
    final (firstDecoration, endDecoration) = placed.decorations;
    final style = placed.grid.cell.style;
    final own = placed.decorated ? firstDecoration : -1;
    if (own >= 0) {
      final decoration = decorations[own]!;
      final rect = decoration.rect;
      // A collapsed cell's decoration reaches half its bottom border
      // past the row.
      final overhang = rect.bottom - placed.bottom;
      decorations[own] = decoration.at(
        Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.right,
          rowBottom + (overhang > 0 ? overhang : 0),
        ),
      );
    }
    final slack = rowBottom - placed.bottom;
    final shift = switch (style.verticalAlign) {
      CssVerticalAlign.middle => slack / 2,
      CssVerticalAlign.bottom => slack,
      _ => 0.0,
    };
    if (shift <= 0) return;
    final offset = Offset(0, shift);
    final (firstItem, endItem) = placed.items;
    for (var i = firstItem; i < endItem; i++) {
      items[i] = items[i].shift(offset);
    }
    for (var i = own >= 0 ? own + 1 : firstDecoration; i < endDecoration; i++) {
      final decoration = decorations[i];
      if (decoration != null) {
        decorations[i] = decoration.at(decoration.rect.shift(offset));
      }
    }
  }

  /// Whether a cell draws a background or borders: its own when the
  /// table separates them, the resolved ones when it collapses them.
  bool _isCellDecorated(ComputedStyle style, _CellBorders? collapsed) =>
      collapsed == null
      ? _isDecorated(style)
      : collapsed.hasBorder ||
            (style.backgroundColor >> 24) != 0 ||
            style.backgroundImage != null;

  /// The widths of [box]'s columns, its [frame] taken out of [available]:
  /// each column's narrowest and widest content (a spanning cell's shared
  /// out evenly over its columns), then CSS 2.1's distribution: every
  /// column at its widest when that fits (wider in proportion for a set
  /// table width), else from its narrowest towards its widest in
  /// proportion to the difference, else narrower than its words in
  /// proportion.
  ///
  /// The table is as wide as its `width` (a length or an intrinsic
  /// size) within its `min-width` and `max-width`, or its widest content
  /// up to [available]; never wider than [available] unless it [scrolls],
  /// and then never narrower than its words.
  List<double> _columnWidths(
    TableBox box,
    _TableGrid grid,
    double available,
    _TableFrame frame,
    Map<_GridCell, _CellBorders> collapsed, {
    bool scrolls = false,
  }) {
    final n = grid.columns;
    final extra = frame.extraWidth(n);
    final room = available - extra < 1 ? 1.0 : available - extra;
    final mins = List.filled(n, 0.0);
    final maxes = List.filled(n, 0.0);
    final spanning = <(int, int, ({double min, double max}))>[];
    for (final cell in grid.cells) {
      var widths = _intrinsic(cell.cell, room);
      final borders = collapsed[cell];
      if (borders != null) {
        // A collapsed cell's box holds half of its shared borders, not
        // its own.
        final own = cell.cell.style.borderWidth;
        final change =
            borders.half.left + borders.half.right - own.left - own.right;
        widths = (min: widths.min + change, max: widths.max + change);
      }
      if (cell.columnSpan == 1) {
        if (widths.min > mins[cell.column]) mins[cell.column] = widths.min;
        if (widths.max > maxes[cell.column]) maxes[cell.column] = widths.max;
      } else {
        // A spanning cell's own spacing is spacing, not content.
        final inner = frame.spacingX * (cell.columnSpan - 1);
        spanning.add((
          cell.column,
          cell.columnSpan,
          (
            min: widths.min > inner ? widths.min - inner : 0.0,
            max: widths.max > inner ? widths.max - inner : 0.0,
          ),
        ));
      }
    }
    for (final (start, span, widths) in spanning) {
      for (final (values, wanted) in [
        (mins, widths.min),
        (maxes, widths.max),
      ]) {
        var have = 0.0;
        for (var c = start; c < start + span; c++) {
          have += values[c];
        }
        if (wanted <= have) continue;
        for (var c = start; c < start + span; c++) {
          values[c] += (wanted - have) / span;
        }
      }
    }
    var sumMin = 0.0;
    var sumMax = 0.0;
    for (var c = 0; c < n; c++) {
      if (maxes[c] < mins[c]) maxes[c] = mins[c];
      sumMin += mins[c];
      sumMax += maxes[c];
    }
    final s = box.style;
    // Tables size their border box (the HTML default): widths here are
    // the columns' alone.
    double? columnsOf(CssLength? length) => length == null
        ? null
        : InlineStyler.px(length, available) -
              (s.boxSizing == CssBoxSizing.borderBox ? extra : 0);
    final fit = sumMax < room ? sumMax : room;
    var target =
        switch (s.widthKeyword) {
          CssSizeKeyword.maxContent => sumMax,
          CssSizeKeyword.minContent => sumMin,
          CssSizeKeyword.fitContent => fit > sumMin ? fit : sumMin,
          null => columnsOf(s.width),
        } ??
        fit;
    final maxWidth = columnsOf(s.maxWidth);
    if (maxWidth != null && target > maxWidth) target = maxWidth;
    final minWidth = columnsOf(s.minWidth);
    if (minWidth != null && target < minWidth) target = minWidth;
    if (scrolls) {
      if (target < sumMin) target = sumMin;
    } else {
      target = target.clamp(sumMin < room ? sumMin : room, room);
    }
    if (target >= sumMax) {
      return [
        for (var c = 0; c < n; c++)
          sumMax > 0 ? maxes[c] * target / sumMax : target / n,
      ];
    }
    if (target >= sumMin && sumMax > sumMin) {
      final spare = target - sumMin;
      return [
        for (var c = 0; c < n; c++)
          mins[c] + spare * (maxes[c] - mins[c]) / (sumMax - sumMin),
      ];
    }
    return [
      for (var c = 0; c < n; c++)
        sumMin > 0 ? mins[c] * target / sumMin : target / n,
    ];
  }

  /// [box]'s narrowest and widest content, its border box included:
  /// CSS's min-content and max-content widths, measured [available] wide.
  ({double min, double max}) _intrinsic(LayoutBox box, double available) {
    switch (box) {
      case FloatBox(:final content):
        return _intrinsic(content, available);
      case ParagraphBox():
        final paragraph = ParagraphLayout.layout(
          box,
          width: available,
          environment: text,
        );
        final widths = (
          min: paragraph.minIntrinsicWidth,
          max: paragraph.maxIntrinsicWidth,
        );
        paragraph.dispose();
        return widths;
      case ImageBox():
        final size = ParagraphLayout.imageSize(
          box.style,
          text.imageSize(box.src),
          maxWidth: available,
          maxHeight: pageHeight,
        );
        return (min: size.width, max: size.width);
      case TableBox():
        final grid = _TableGrid.of(box);
        if (grid.columns == 0) return (min: 0, max: 0);
        final collapsed = box.style.borderCollapse
            ? {
                for (final cell in grid.cells)
                  cell: _CellBorders.of(cell, grid, box),
              }
            : const <_GridCell, _CellBorders>{};
        final frame = _frameOf(box, grid, available, collapsed);
        final widths = _columnWidths(box, grid, available, frame, collapsed);
        final total =
            widths.fold(0.0, (a, b) => a + b) + frame.extraWidth(grid.columns);
        return (min: total, max: total);
      case BlockBox():
        var min = 0.0;
        var max = 0.0;
        for (final child in box.children) {
          final widths = _intrinsic(child, available);
          if (widths.min > min) min = widths.min;
          if (widths.max > max) max = widths.max;
        }
        final s = box.style;
        final padding =
            InlineStyler.px(s.padding.left, available) +
            InlineStyler.px(s.padding.right, available);
        final borders = s.borderWidth.left + s.borderWidth.right;
        final specified = s.width == null
            ? null
            : InlineStyler.px(s.width!, available) -
                  (s.boxSizing == CssBoxSizing.borderBox
                      ? padding + borders
                      : 0);
        if (specified != null) {
          // A set width is what the box asks for, if its words fit.
          if (specified > min) min = specified;
          max = min;
        }
        final margins = _margins(box, available);
        final edges =
            borders + padding + (margins.left ?? 0) + (margins.right ?? 0);
        return (min: min + edges, max: max + edges);
    }
  }
}
