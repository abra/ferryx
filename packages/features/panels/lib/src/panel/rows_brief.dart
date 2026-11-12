import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

import 'inline_rename.dart';
import 'brief_column_offsets.dart';
import 'panel_row.dart';
import 'panel_state.dart';
import 'recent_entries.dart';
import 'rows_header.dart';
import 'rows_list.dart';

/// Brief mode: names in columns, read top to bottom and then on to the
/// next column; the cursor moves in both directions.
class RowsBrief extends StatefulWidget {
  const RowsBrief({
    required this.tab,
    required this.layout,
    required this.active,
    required this.callbacks,
    required this.onGeometry,
    required this.rename,
    required this.onSort,
    this.cursorKey,
    this.dropRow,
    super.key,
  });

  final PanelTabState tab;
  final PanelLayout layout;
  final bool active;
  final RowCallbacks callbacks;
  final ValueChanged<PanelGeometry> onGeometry;
  final RenameSpec rename;

  /// The header's tap: the sort field flips its direction.
  final ValueChanged<SortField> onSort;

  /// Goes on the cursor's cell while it is built, so the window can open
  /// a menu by it.
  final GlobalKey? cursorKey;

  /// The folder cell files hang over, lit up.
  final String? dropRow;

  /// Columns a panel shows when they are all of one width.
  static const int fixedColumns = 3;

  /// Narrowest a column sized to its names gets, at text scale 1.
  static const double minColumnWidth = 120;

  /// Columns are sized to their names up to this many rows; a longer
  /// list takes thirds of the panel.
  static const int measuredRowsAtMost = 2000;

  /// How many times names were measured, and columns built, for the
  /// tests.
  @visibleForTesting
  static int debugMeasures = 0;
  @visibleForTesting
  static int debugColumnsBuilt = 0;
  @visibleForTesting
  static int debugOffsetBuilds = 0;

  @override
  State<RowsBrief> createState() => _RowsBriefState();
}

class _RowsBriefState extends State<RowsBrief> {
  final _scroll = ScrollController();
  late final _follow = AppScrollReveal(_scroll);
  bool _jumpNextReveal = true;
  bool? _reduceMotion;
  (Size, int)? _layout;
  int _rowsPerColumn = 1;
  int _visibleColumns = RowsBrief.fixedColumns;
  List<double> _columnWidths = const [];
  BriefColumnOffsets _offsets = BriefColumnOffsets(const []);
  (int, double)? _fixedMeasure;
  List<double> _fixedWidths = const [];

  /// What the names were last measured for, and the widths they gave: a
  /// move of the cursor builds the list again, its names and room stay.
  _Measure? _measured;
  List<double> _measuredWidths = const [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = context.reduceMotion;
    if (reduced != _reduceMotion) {
      _reduceMotion = reduced;
      if (_follow.isAnimating) _follow.schedule(_reveal);
    }
  }

  /// The first column in view, for `H`, `M` and `L`.
  void _onScroll() {
    if (!_scroll.hasClients || _columnWidths.isEmpty) return;
    final column = _offsets.columnAt(_scroll.offset);
    widget.onGeometry(
      PanelGeometry(
        rowsPerPage: _rowsPerColumn * _visibleColumns,
        rowsPerColumn: _rowsPerColumn,
        firstVisibleRow: column * _rowsPerColumn,
      ),
    );
  }

  @override
  void didUpdateWidget(RowsBrief oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        widget.tab.id != oldWidget.tab.id ||
        widget.tab.location != oldWidget.tab.location;
    _jumpNextReveal |= changed;
    if (changed ||
        widget.tab.scrollRequest != oldWidget.tab.scrollRequest ||
        widget.tab.cursor != oldWidget.tab.cursor) {
      _follow.schedule(_reveal);
    }
  }

  @override
  void dispose() {
    _follow.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _reveal() {
    if (!mounted || !_scroll.hasClients || _columnWidths.isEmpty) return;
    final cursor = widget.tab.cursor;
    if (cursor < 0) return;
    final column = (cursor ~/ _rowsPerColumn).clamp(0, _offsets.length - 1);
    _follow.reveal(
      start: _offsets.startOf(column),
      end: _offsets.endOf(column),
      alignment: widget.tab.scrollAlign.alignment,
      reduceMotion: context.reduceMotion,
      immediate: _jumpNextReveal,
    );
    _jumpNextReveal = false;
  }

  /// What a cell holds besides its name: the row's inset and padding, the
  /// icon and its gap, the check mark's slot.
  double _chrome(BuildContext context) =>
      2 * context.metrics.tableRowInset +
      2 * AppSpacing.sm +
      AppIconSize.md +
      AppSpacing.sm +
      AppSpacing.xs +
      checkSlotWidth;

  /// The width of each column: a third of the panel, or as wide as its
  /// longest name.
  List<double> _widths(
    BuildContext context,
    double available,
    int rowsPerColumn,
  ) {
    final rows = widget.tab.rows;
    final columns = rows.isEmpty ? 1 : (rows.length / rowsPerColumn).ceil();
    // A flat view's rows carry their folders, and measuring every name of
    // a long list on each build would cost more than it shows: thirds.
    if (widget.layout.briefColumns == BriefColumns.fixed ||
        widget.tab.isFlat ||
        rows.length > RowsBrief.measuredRowsAtMost) {
      final width = (available / RowsBrief.fixedColumns).floorToDouble();
      final measure = (columns, width);
      if (_fixedMeasure != measure) {
        _fixedMeasure = measure;
        _fixedWidths = List.filled(columns, width);
      }
      return _fixedWidths;
    }
    final style = context.text.bodyMedium!;
    final scaler = MediaQuery.textScalerOf(context);
    final measure = (
      rows: rows,
      rowsPerColumn: rowsPerColumn,
      available: available,
      style: style,
      scaler: scaler,
      chrome: _chrome(context),
    );
    if (measure == _measured) return _measuredWidths;
    assert(() {
      RowsBrief.debugMeasures++;
      return true;
    }());
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    );
    try {
      final chrome = measure.chrome;
      final max = (available / 2).floorToDouble();
      final min = math.min(
        available,
        RowsBrief.minColumnWidth * scaler.scale(1),
      );
      _measured = measure;
      return _measuredWidths = [
        for (var c = 0; c < columns; c++)
          () {
            var widest = 0.0;
            final end = math.min(rows.length, (c + 1) * rowsPerColumn);
            for (var i = c * rowsPerColumn; i < end; i++) {
              painter.text = TextSpan(
                text: rows[i].isParent ? '..' : rows[i].name,
                style: style,
              );
              painter.layout();
              widest = math.max(widest, painter.width);
            }
            return (widest + chrome).clamp(min, max).ceilToDouble();
          }(),
      ];
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = panelRowHeight(context);
    final active = widget.active && AppFocusArea.activeOf(context);
    final sort = widget.tab.sort;
    return Column(
      children: [
        RowsHeader(
          columns: const [],
          widths: const [],
          sort: sort,
          onSort: widget.onSort,
          height: height,
          nameField: sort.field,
          nameLabel: context.l10n.columnLabel(
            ListColumn.values.byName(sort.field.name),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rowsPerColumn =
                  ((constraints.maxHeight - 2 * rowsInset) / height)
                      .floor()
                      .clamp(
                        1,
                        1 << 20,
                      );
              final widths = _widths(
                context,
                constraints.maxWidth,
                rowsPerColumn,
              );
              _rowsPerColumn = rowsPerColumn;
              final layout = (constraints.biggest, rowsPerColumn);
              if (!identical(_columnWidths, widths) || _layout != layout) {
                _layout = layout;
                if (!identical(_columnWidths, widths)) {
                  _columnWidths = widths;
                  _offsets = BriefColumnOffsets(widths);
                  assert(() {
                    RowsBrief.debugOffsetBuilds++;
                    return true;
                  }());
                }
                _jumpNextReveal = true;
                _follow.schedule(_reveal);
              }
              final visibleColumns = widths.isEmpty
                  ? RowsBrief.fixedColumns
                  : math.max(1, (constraints.maxWidth / widths.first).floor());
              _visibleColumns = visibleColumns;
              WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
              if (widget.tab.rows.isEmpty) {
                return EmptyRows(read: widget.tab.listing != null);
              }
              final uniform = identical(widths, _fixedWidths);
              return NotificationListener<UserScrollNotification>(
                onNotification: _follow.onUserScroll,
                child: Scrollbar(
                  controller: _scroll,
                  child: ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    itemCount: widths.length,
                    // The widths are known: a jump to the end lays out only
                    // the columns it lands on, and the extent is exact.
                    itemExtent: uniform ? widths.first : null,
                    itemExtentBuilder: uniform
                        ? null
                        : (column, _) => widths[column],
                    addRepaintBoundaries: false,
                    itemBuilder: (context, column) {
                      assert(() {
                        RowsBrief.debugColumnsBuilt++;
                        return true;
                      }());
                      return SizedBox(
                        width: widths[column],
                        child: _BriefColumn(
                          tab: widget.tab,
                          active: active,
                          start: column * rowsPerColumn,
                          count: math.min(
                            rowsPerColumn,
                            widget.tab.rows.length - column * rowsPerColumn,
                          ),
                          height: height,
                          callbacks: widget.callbacks,
                          rename: widget.rename,
                          cursorKey: widget.cursorKey,
                          dropRow: widget.dropRow,
                          last: column == widths.length - 1,
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BriefColumn extends StatelessWidget {
  const _BriefColumn({
    required this.tab,
    required this.active,
    required this.start,
    required this.count,
    required this.height,
    required this.callbacks,
    required this.rename,
    required this.cursorKey,
    required this.dropRow,
    required this.last,
  });

  final PanelTabState tab;
  final bool active;
  final int start;
  final int count;
  final double height;
  final RowCallbacks callbacks;
  final RenameSpec rename;
  final GlobalKey? cursorKey;
  final String? dropRow;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: last
          ? null
          : BoxDecoration(
              border: AppBorder(right: BorderSide(color: colors.line)),
            ),
      padding: const EdgeInsets.symmetric(vertical: rowsInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = start; i < start + count; i++)
            _BriefCell(
              key: ValueKey(tab.rows[i].key),
              index: i,
              entry: tab.rows[i],
              look: rowLookOf(
                tab,
                i,
                active: active,
                dropRow: dropRow,
                now: RecentEntriesClock.nowOf(context),
              ),
              location: tab.location,
              renaming: tab.renaming == i,
              rename: rename,
              height: height,
              callbacks: callbacks,
              cursorKey: i == tab.cursor ? cursorKey : null,
            ),
        ],
      ),
    );
  }
}

class _BriefCell extends StatelessWidget {
  const _BriefCell({
    required this.index,
    required this.entry,
    required this.look,
    required this.renaming,
    required this.rename,
    required this.height,
    required this.callbacks,
    required this.cursorKey,
    required this.location,
    super.key,
  });

  final int index;
  final FileEntry entry;
  final Location location;
  final RowLook look;
  final bool renaming;
  final RenameSpec rename;
  final double height;
  final RowCallbacks callbacks;
  final GlobalKey? cursorKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      button: true,
      selected: look.selected || look.cursor,
      label: rowSemanticsLabel(context, entry),
      child: HintTarget(
        onActivate: () => callbacks.onDoubleTap(index),
        onActivateAlt: () =>
            callbacks.onTapDown(index, toggle: true, range: false),
        child: RowDragArea(
          index: index,
          entry: entry,
          location: location,
          renaming: renaming,
          drag: callbacks.drag,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => callbacks.onTapDown(
              index,
              toggle: Chord.primaryHeld(Theme.of(context).platform),
              range: HardwareKeyboard.instance.isShiftPressed,
            ),
            onDoubleTap: () => callbacks.onDoubleTap(index),
            onSecondaryTapDown: (details) =>
                callbacks.onSecondaryTapDown(index, details.globalPosition),
            child: KeyedSubtree(
              key: cursorKey,
              child: Container(
                height: height,
                foregroundDecoration: renaming
                    ? null
                    : look.cursorDecoration(colors),
                margin: EdgeInsets.symmetric(
                  horizontal: context.metrics.tableRowInset,
                ),
                decoration: BoxDecoration(
                  color: renaming ? null : look.background(colors),
                  borderRadius: BorderRadius.circular(
                    context.metrics.radius.tableRow,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: RowName(
                        entry: entry,
                        look: look,
                        field: renaming
                            ? InlineRename(
                                name: entry.name,
                                caret: rename.caret,
                                shortcutMap: rename.shortcutMap,
                                onCommit: callbacks.onRenameCommit,
                                onCancel: callbacks.onRenameCancel,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    SizedBox(
                      width: checkSlotWidth,
                      child: look.selected && !renaming
                          ? Icon(
                              AppIcons.check,
                              size: AppIconSize.xs,
                              color: look.checkMark(colors),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What brief mode measured its names for ([_RowsBriefState._measured]):
/// the rows by identity, the room and the face.
typedef _Measure = ({
  List<FileEntry> rows,
  int rowsPerColumn,
  double available,
  TextStyle style,
  TextScaler scaler,
  double chrome,
});
