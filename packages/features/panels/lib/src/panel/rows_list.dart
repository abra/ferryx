import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

import 'inline_rename.dart';
import 'panel_row.dart';
import 'panel_state.dart';

/// What the rows need from their panel: which row is where, and what a
/// click or a key does.
class RowCallbacks {
  const RowCallbacks({
    required this.onTapDown,
    required this.onDoubleTap,
    required this.onSecondaryTapDown,
    required this.onRenameCommit,
    required this.onRenameCancel,
  });

  final void Function(int index, {bool toggle, bool range}) onTapDown;
  final void Function(int index) onDoubleTap;
  final void Function(int index, Offset globalPosition) onSecondaryTapDown;
  final void Function(String name) onRenameCommit;
  final VoidCallback onRenameCancel;
}

/// How a row's rename field is built: the caret's place and the keys it
/// keeps from the panel.
class RenameSpec {
  const RenameSpec({required this.caret, required this.shortcutMap});

  final RenameCaret caret;
  final ShortcutMap shortcutMap;
}

/// The look of row [index] of [tab] in a panel that is [active] (its
/// flag and the focus area's together).
RowLook rowLookOf(PanelTabState tab, int index, {required bool active}) {
  final entry = tab.rows[index];
  return RowLook(
    cursor: index == tab.cursor,
    active: active,
    selected: tab.selected.contains(entry.name),
    match: tab.matches[entry.name],
    dimmed:
        tab.quickSearch.isNotEmpty &&
        !entry.isParent &&
        !tab.matches.containsKey(entry.name),
  );
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
    final first = (_scroll.offset / panelRowHeight(context)).floor();
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

  /// The data columns as they fit beside the name: their wanted widths
  /// while the name keeps [ColumnWidths.nameMin], else scaled down
  /// together, never below half.
  List<double> _fitColumns(
    BuildContext context,
    List<double> wanted,
    double width,
  ) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final chrome =
        2 * (context.metrics.rowInset + AppSpacing.sm) +
        wanted.length * AppSpacing.sm +
        AppSpacing.xs +
        checkSlotWidth;
    final fixed = wanted.fold(0.0, (sum, w) => sum + w);
    final room = width - chrome - ColumnWidths.nameMin * scale;
    if (fixed <= room) return wanted;
    final factor = (room / fixed).clamp(0.5, 1.0);
    return [for (final w in wanted) (w * factor).roundToDouble()];
  }

  /// Scrolls as little as it takes to show the cursor's row, or puts the
  /// row at the top, the middle or the bottom when asked (`zt zz zb`).
  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final cursor = widget.tab.cursor;
    if (cursor < 0) return;
    final height = panelRowHeight(context);
    final top = cursor * height;
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
    final columns = widget.layout.columns
        .where((c) => c != ListColumn.name)
        .toList();
    final wanted = [for (final c in columns) columnWidth(context, c)];
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _fitColumns(context, wanted, constraints.maxWidth);
        final rowsPerPage = ((constraints.maxHeight - height) / height)
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
            _Header(
              columns: columns,
              widths: widths,
              sort: widget.tab.sort,
              onSort: widget.onSort,
              height: height,
            ),
            Expanded(
              child: widget.tab.rows.isEmpty
                  ? const EmptyRows()
                  : Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        itemExtent: height,
                        itemCount: widget.tab.rows.length,
                        addRepaintBoundaries: false,
                        itemBuilder: (context, index) => _ListRow(
                          key: ValueKey(widget.tab.rows[index].name),
                          index: index,
                          entry: widget.tab.rows[index],
                          columns: columns,
                          widths: widths,
                          look: rowLookOf(widget.tab, index, active: active),
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
class _Header extends StatelessWidget {
  const _Header({
    required this.columns,
    required this.widths,
    required this.sort,
    required this.onSort,
    required this.height,
  });

  final List<ListColumn> columns;
  final List<double> widths;
  final SortOptions sort;
  final ValueChanged<SortField> onSort;
  final double height;

  SortField? _fieldOf(ListColumn column) => switch (column) {
    ListColumn.name => SortField.name,
    ListColumn.extension => SortField.extension,
    ListColumn.size => SortField.size,
    ListColumn.modified => SortField.modified,
    ListColumn.created => SortField.created,
    ListColumn.added => SortField.added,
    ListColumn.accessed => SortField.accessed,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: AppBorder(bottom: BorderSide(color: colors.line)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: context.metrics.rowInset + AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _HeaderCell(
              label: context.l10n.columnName,
              field: SortField.name,
              sort: sort,
              onSort: onSort,
              alignEnd: false,
            ),
          ),
          for (var i = 0; i < columns.length; i++) ...[
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: widths[i],
              child: _HeaderCell(
                label: context.l10n.columnLabel(columns[i]),
                field: _fieldOf(columns[i]),
                sort: sort,
                onSort: onSort,
                alignEnd: columnRightAligned(columns[i]),
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.xs + checkSlotWidth),
        ],
      ),
    );
  }
}

/// A column's header: a push target with the platform's hover and pressed
/// fills, the sorted column in a heavier weight with its arrow.
class _HeaderCell extends StatefulWidget {
  const _HeaderCell({
    required this.label,
    required this.field,
    required this.sort,
    required this.onSort,
    required this.alignEnd,
  });

  final String label;
  final SortField? field;
  final SortOptions sort;
  final ValueChanged<SortField> onSort;
  final bool alignEnd;

  @override
  State<_HeaderCell> createState() => _HeaderCellState();
}

class _HeaderCellState extends State<_HeaderCell> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final field = widget.field;
    final sorted = field != null && widget.sort.field == field;
    final base = context.text.labelMedium!.copyWith(
      color: sorted ? context.colors.onSurface : colors.textMuted,
    );
    final style = sorted ? base.weight(FontWeight.w600) : base;
    final text = Text(
      widget.label,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final alignEnd = widget.alignEnd;
    final child = Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        if (alignEnd && sorted) _SortArrow(descending: widget.sort.descending),
        Flexible(child: text),
        if (!alignEnd && sorted) _SortArrow(descending: widget.sort.descending),
      ],
    );
    if (field == null) return child;
    void sort() => widget.onSort(field);
    final fill = _pressed
        ? colors.pressedFill
        : _hovered
        ? colors.hoverFill
        : null;
    return HintTarget(
      onActivate: sort,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: sort,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(context.metrics.radius.row),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SortArrow extends StatelessWidget {
  const _SortArrow({required this.descending});

  final bool descending;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
    child: Icon(
      descending ? AppIcons.chevronDown : AppIcons.chevronUp,
      size: AppIconSize.xs,
      color: context.appColors.textMuted,
    ),
  );
}

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
    super.key,
  });

  final int index;
  final FileEntry entry;
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
      label: entry.isParent ? context.l10n.panelParentFolder : entry.name,
      child: HintTarget(
        onActivate: () => callbacks.onDoubleTap(index),
        onActivateAlt: () =>
            callbacks.onTapDown(index, toggle: true, range: false),
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
              margin: EdgeInsets.symmetric(
                horizontal: context.metrics.rowInset,
              ),
              decoration: BoxDecoration(
                // The field is opaque on its own; no fill under it.
                color: renaming ? null : look.background(colors),
                borderRadius: BorderRadius.circular(
                  context.metrics.radius.row,
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
    );
  }
}
