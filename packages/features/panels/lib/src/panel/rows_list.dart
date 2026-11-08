import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

import '../native/panel_drag_hooks.dart';
import 'inline_rename.dart';
import 'panel_row.dart';
import 'panel_state.dart';
import 'rows_header.dart';

/// What the rows need from their panel: which row is where, and what a
/// click or a key does.
class RowCallbacks {
  const RowCallbacks({
    required this.onTapDown,
    required this.onDoubleTap,
    required this.onSecondaryTapDown,
    required this.onRenameCommit,
    required this.onRenameCancel,
    this.drag,
  });

  final void Function(int index, {bool toggle, bool range}) onTapDown;
  final void Function(int index) onDoubleTap;
  final void Function(int index, Offset globalPosition) onSecondaryTapDown;
  final void Function(String name) onRenameCommit;
  final VoidCallback onRenameCancel;

  /// Rows dragged out, files dropped on folder rows; none without it.
  final PanelDragHooks? drag;
}

/// How a row's rename field is built: the caret's place and the keys it
/// keeps from the panel.
class RenameSpec {
  const RenameSpec({required this.caret, required this.shortcutMap});

  final RenameCaret caret;
  final ShortcutMap shortcutMap;
}

/// The look of row [index] of [tab] in a panel that is [active] (its
/// flag and the focus area's together); [dropRow] names the folder row
/// files hang over.
RowLook rowLookOf(
  PanelTabState tab,
  int index, {
  required bool active,
  String? dropRow,
}) {
  final entry = tab.rows[index];
  return RowLook(
    cursor: index == tab.cursor,
    active: active,
    selected: tab.selected.contains(entry.key),
    match: tab.matches[entry.key],
    dimmed:
        tab.quickSearch.isNotEmpty &&
        !entry.isParent &&
        !tab.matches.containsKey(entry.key),
    dropTarget: dropRow != null && entry.key == dropRow,
  );
}

/// A row's gestures with what dragging adds: the row as a drag source
/// (past the desktop's threshold, never while it is renamed) and, for a
/// folder, as a drop target.
class RowDragArea extends StatelessWidget {
  const RowDragArea({
    required this.index,
    required this.entry,
    required this.location,
    required this.renaming,
    required this.drag,
    required this.child,
    super.key,
  });

  final int index;
  final FileEntry entry;

  /// The folder the row is in.
  final Location location;
  final bool renaming;
  final PanelDragHooks? drag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final drag = this.drag;
    return RowDropTarget(
      spot: drag == null ? null : rowDropSpot(location, entry),
      hooks: drag,
      child: FileDragSource(
        enabled: drag != null && !renaming && !entry.isParent,
        onDragStart: (global) => drag?.onDragStart(index, global),
        child: child,
      ),
    );
  }
}

/// The room a row keeps at its end for the selection's check mark, so
/// a selected row's columns stay where the others' are.
const double checkSlotWidth = AppIconSize.xs;

/// List mode: one row per item, the layout's columns, a header that sorts.
class RowsList extends StatefulWidget {
  const RowsList({
    required this.tab,
    required this.layout,
    required this.active,
    required this.callbacks,
    required this.onSort,
    required this.onGeometry,
    required this.rename,
    this.cursorKey,
    this.dropRow,
    super.key,
  });

  final PanelTabState tab;
  final PanelLayout layout;
  final bool active;
  final RowCallbacks callbacks;
  final ValueChanged<SortField> onSort;
  final ValueChanged<PanelGeometry> onGeometry;
  final RenameSpec rename;

  /// Goes on the cursor's row while it is built, so the window can open a
  /// menu by it.
  final GlobalKey? cursorKey;

  /// The folder row files hang over, lit up.
  final String? dropRow;

  @override
  State<RowsList> createState() => _RowsListState();
}

class _RowsListState extends State<RowsList> {
  final _scroll = ScrollController();
  int _lastScrollRequest = -1;
  int _rowsPerPage = 20;
  int _firstVisible = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  /// The first row in view, for `H`, `M` and `L`.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final first = ((_scroll.offset - rowsInset) / panelRowHeight(context))
        .floor()
        .clamp(0, 1 << 20);
    if (first != _firstVisible) {
      _firstVisible = first;
      widget.onGeometry(
        PanelGeometry(
          rowsPerPage: _rowsPerPage,
          rowsPerColumn: 1,
          firstVisibleRow: first,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(RowsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab.scrollRequest != _lastScrollRequest ||
        widget.tab.cursor != oldWidget.tab.cursor) {
      _lastScrollRequest = widget.tab.scrollRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The data columns as they fit beside the name: all of them at their
  /// wanted widths while the name keeps [ColumnWidths.nameMin]; else the
  /// last columns go, one by one, before any is squeezed (a date cut
  /// short says nothing; a column that is not there is just not there).
  (List<ListColumn>, List<double>) _fitColumns(
    BuildContext context,
    List<ListColumn> columns,
    List<double> wanted,
    double width,
  ) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    double chrome(int count) =>
        2 * (context.metrics.tableRowInset + AppSpacing.sm) +
        count * AppSpacing.sm +
        AppSpacing.xs +
        checkSlotWidth;
    // A flat view's name column holds the folder too: the data columns
    // give way to it sooner.
    final nameMin =
        (widget.tab.isFlat ? ColumnWidths.flatNameMin : ColumnWidths.nameMin) *
        scale;
    var count = columns.length;
    while (count > 0) {
      final fixed = wanted.take(count).fold(0.0, (sum, w) => sum + w);
      if (fixed <= width - chrome(count) - nameMin) break;
      count--;
    }
    return (columns.take(count).toList(), wanted.take(count).toList());
  }

  /// Scrolls as little as it takes to show the cursor's row, or puts the
  /// row at the top, the middle or the bottom when asked (`zt zz zb`).
  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final cursor = widget.tab.cursor;
    if (cursor < 0) return;
    final height = panelRowHeight(context);
    final top = rowsInset + cursor * height;
    final bottom = top + height;
    final viewport = _scroll.position.viewportDimension;
    final offset = _scroll.offset;
    final max = _scroll.position.maxScrollExtent;
    switch (widget.tab.scrollAlign) {
      case ScrollAlign.top:
        _scroll.jumpTo(top.clamp(0, max));
        return;
      case ScrollAlign.center:
        _scroll.jumpTo((top - (viewport - height) / 2).clamp(0, max));
        return;
      case ScrollAlign.bottom:
        _scroll.jumpTo((bottom - viewport).clamp(0, max));
        return;
      case ScrollAlign.reveal:
        break;
    }
    if (top < offset) {
      _scroll.jumpTo(top);
    } else if (bottom > offset + viewport) {
      _scroll.jumpTo(
        (bottom - viewport).clamp(0, _scroll.position.maxScrollExtent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = panelRowHeight(context);
    final active = widget.active && AppFocusArea.activeOf(context);
    final wantedColumns = widget.layout.columns
        .where((c) => c != ListColumn.name)
        .toList();
    final wanted = [for (final c in wantedColumns) columnWidth(context, c)];
    return LayoutBuilder(
      builder: (context, constraints) {
        final (columns, widths) = _fitColumns(
          context,
          wantedColumns,
          wanted,
          constraints.maxWidth,
        );
        final rowsPerPage =
            ((constraints.maxHeight - height - 2 * rowsInset) / height)
                .floor()
                .clamp(1, 1 << 20);
        _rowsPerPage = rowsPerPage;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onGeometry(
            PanelGeometry(
              rowsPerPage: rowsPerPage,
              rowsPerColumn: 1,
              firstVisibleRow: _firstVisible,
            ),
          );
        });
        return Column(
          children: [
            RowsHeader(
              columns: columns,
              widths: widths,
              sort: widget.tab.sort,
              onSort: widget.onSort,
              height: height,
            ),
            Expanded(
              child: widget.tab.rows.isEmpty
                  ? EmptyRows(read: widget.tab.listing != null)
                  : Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                          vertical: rowsInset,
                        ),
                        itemExtent: height,
                        itemCount: widget.tab.rows.length,
                        addRepaintBoundaries: false,
                        itemBuilder: (context, index) => _ListRow(
                          key: ValueKey(widget.tab.rows[index].key),
                          index: index,
                          entry: widget.tab.rows[index],
                          columns: columns,
                          widths: widths,
                          look: rowLookOf(
                            widget.tab,
                            index,
                            active: active,
                            dropRow: widget.dropRow,
                          ),
                          location: widget.tab.location,
                          renaming: widget.tab.renaming == index,
                          rename: widget.rename,
                          callbacks: widget.callbacks,
                          height: height,
                          cursorKey: index == widget.tab.cursor
                              ? widget.cursorKey
                              : null,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// The column headers, each a button that sorts by its column; the
/// cells sit over the rows' cells, inset as the rows are.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.index,
    required this.entry,
    required this.columns,
    required this.widths,
    required this.look,
    required this.renaming,
    required this.rename,
    required this.callbacks,
    required this.height,
    required this.cursorKey,
    required this.location,
    super.key,
  });

  final int index;
  final FileEntry entry;
  final Location location;
  final List<ListColumn> columns;
  final List<double> widths;
  final RowLook look;
  final bool renaming;
  final RenameSpec rename;
  final RowCallbacks callbacks;
  final double height;
  final GlobalKey? cursorKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final secondary = look.secondary(colors);
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
            onTapDown: (details) => callbacks.onTapDown(
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
                  // The field is opaque on its own; no fill under it.
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
                    for (var i = 0; i < columns.length; i++) ...[
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: widths[i],
                        child: Text(
                          columnText(context, entry, columns[i]),
                          style: columnStyle(
                            context,
                            column: columns[i],
                          ).copyWith(color: secondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          textAlign: columnRightAligned(columns[i])
                              ? TextAlign.end
                              : TextAlign.start,
                        ),
                      ),
                    ],
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
