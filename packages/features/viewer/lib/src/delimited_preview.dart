import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import 'text_preview_data.dart';
import 'viewer_views.dart';

/// Rows stay lazy; horizontal scrolling keeps the same column widths. All
/// source rows remain data, with generated column labels and one-based indices.
class DelimitedPreview extends StatefulWidget {
  const DelimitedPreview({
    required this.data,
    required this.fontSize,
    super.key,
  });
  final TablePreviewData data;
  final double fontSize;
  @override
  State<DelimitedPreview> createState() => _DelimitedPreviewState();
}

class _DelimitedPreviewState extends State<DelimitedPreview> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.rows.isEmpty) {
      return AppEmptyState(
        title: context.l10n.viewerEmptyFile,
        icon: AppIcons.file,
      );
    }
    final style = context.mono.copyWith(fontSize: widget.fontSize);
    final characterWidth = charWidthOf(context, style);
    final height =
        (MediaQuery.textScalerOf(context)
                    .scale(widget.fontSize * style.height!) +
                AppSpacing.md)
            .clamp(context.metrics.controlHeight, double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Text(
            context.l10n.textPreviewTableSize(
              widget.data.rows.length,
              widget.data.columns,
            ),
            style: context.text.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final widths = List<double>.generate(widget.data.columns, (
                column,
              ) {
                var length = 8;
                for (final row in widget.data.rows.take(100)) {
                  if (column < row.length && row[column].length > length) {
                    length = row[column].length;
                  }
                }
                return (length.clamp(8, 40) * characterWidth +
                        2 * AppSpacing.md)
                    .clamp(
                      AppSizes.previewTableMinColumnWidth,
                      AppSizes.previewTableMaxColumnWidth,
                    );
              });
              final indexWidth =
                  (widget.data.rows.length.toString().length * characterWidth +
                          AppSpacing.lg)
                      .clamp(AppSizes.previewTableIndexWidth, double.infinity);
              final width = widths
                  .fold(indexWidth, (sum, w) => sum + w)
                  .clamp(constraints.maxWidth, double.infinity);
              return SelectionArea(
                child: ViewerScrollFrame(
                  vertical: _vertical,
                  horizontal: _horizontal,
                  contentWidth: width,
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: Column(
                      children: [
                        _TableRow(
                          values: [
                            for (var i = 0; i < widths.length; i++)
                              _columnLabel(i),
                          ],
                          widths: widths,
                          index: '',
                          indexWidth: indexWidth,
                          height: height,
                          style: style,
                          header: true,
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: _vertical,
                            itemExtent: height,
                            itemCount: widget.data.rows.length,
                            itemBuilder: (context, index) => _TableRow(
                              values: widget.data.rows[index],
                              widths: widths,
                              index: '${index + 1}',
                              indexWidth: indexWidth,
                              height: height,
                              style: style,
                            ),
                          ),
                        ),
                      ],
                    ),
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

String _columnLabel(int index) {
  var value = index + 1;
  var label = '';
  while (value > 0) {
    value--;
    label = String.fromCharCode(65 + value % 26) + label;
    value ~/= 26;
  }
  return label;
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.values,
    required this.widths,
    required this.index,
    required this.indexWidth,
    required this.height,
    required this.style,
    this.header = false,
  });
  final List<String> values;
  final List<double> widths;
  final String index;
  final double indexWidth;
  final double height;
  final TextStyle style;
  final bool header;
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: header ? context.appColors.surfaceSunken : null,
      border: AppBorder(bottom: BorderSide(color: context.appColors.line)),
    ),
    child: Row(
      children: [
        SelectionContainer.disabled(
          child: SizedBox(
            width: indexWidth,
            child: Text(
              index,
              textAlign: TextAlign.center,
              style: style.copyWith(color: context.appColors.textMuted),
            ),
          ),
        ),
        for (var i = 0; i < widths.length; i++)
          SizedBox(
            width: widths[i],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                border: AppBorder(
                  left: BorderSide(color: context.appColors.line),
                ),
              ),
              alignment: AlignmentDirectional.centerStart,
              child: AppTooltip(
                message: i < values.length ? values[i] : '',
                child: Focus(
                  canRequestFocus:
                      !header && i < values.length && values[i].isNotEmpty,
                  child: Builder(
                    builder: (context) => FocusRing(
                      radius: context.metrics.radius.tableRow,
                      child: Text(
                        i < values.length ? values[i] : '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: header ? style.weight(FontWeight.w600) : style,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
