import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import 'panel_row.dart';
import 'rows_list.dart';

/// The column headers over the rows, a push target each: the sorted one
/// in a heavier weight with its arrow. Brief mode shows the one header of
/// the sorted field, so both views stand the same height and their rows
/// line up across the panels.
class RowsHeader extends StatelessWidget {
  const RowsHeader({
    this.nameField = SortField.name,
    this.nameLabel,
    required this.columns,
    required this.widths,
    required this.sort,
    required this.onSort,
    required this.height,
    super.key,
  });

  final List<ListColumn> columns;
  final List<double> widths;
  final SortOptions sort;
  final ValueChanged<SortField> onSort;
  final double height;

  /// What the first header sorts by and says: the name, or in brief mode
  /// the field the rows are sorted by.
  final SortField nameField;
  final String? nameLabel;

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
        horizontal: context.metrics.tableRowInset + AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _HeaderCell(
              label: nameLabel ?? context.l10n.columnName,
              field: nameField,
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
