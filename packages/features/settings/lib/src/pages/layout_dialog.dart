import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import '../settings_rows.dart';

/// Edits a view mode, or makes a new one when [layout] is null; answers
/// the layout saved.
Future<PanelLayout?> showLayoutDialog(
  BuildContext context, {
  required PanelLayout? layout,
}) => showAppDialog<PanelLayout>(
  context,
  (context) => _LayoutDialog(layout: layout),
);

class _LayoutDialog extends StatefulWidget {
  const _LayoutDialog({required this.layout});

  final PanelLayout? layout;

  @override
  State<_LayoutDialog> createState() => _LayoutDialogState();
}

class _LayoutDialogState extends State<_LayoutDialog> {
  /// The name as shown: a default mode's in this language.
  late final String _shownName = switch (widget.layout) {
    final layout? => context.l10n.viewModeName(layout),
    null => '',
  };
  late final TextEditingController _name = TextEditingController(
    text: _shownName,
  );
  late ViewMode _mode = widget.layout?.mode ?? ViewMode.list;
  late BriefColumns _briefColumns =
      widget.layout?.briefColumns ?? BriefColumns.fixed;
  late List<ListColumn> _columns = [
    ...widget.layout?.columns ?? const [ListColumn.name, ListColumn.size],
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _complete => _name.text.trim().isNotEmpty;

  void _toggleColumn(ListColumn column, bool on) {
    setState(() {
      if (on) {
        // Columns keep the order of the enum.
        _columns = [
          for (final c in ListColumn.values)
            if (c == column || _columns.contains(c)) c,
        ];
      } else {
        _columns = [..._columns]..remove(column);
      }
    });
  }

  void _save() {
    if (!_complete) return;
    Navigator.of(context).pop(
      PanelLayout(
        // A default mode left as named keeps its name, which every
        // language shows in its own words.
        name: switch (widget.layout) {
          final layout? when _name.text.trim() == _shownName => layout.name,
          _ => _name.text.trim(),
        },
        mode: _mode,
        briefColumns: _briefColumns,
        columns: _columns.isEmpty ? const [ListColumn.name] : _columns,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _name,
      builder: (context, _) => AppDialog(
        title: l10n.layoutsTitle,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(
              label: l10n.layoutName,
              controller: _name,
              autofocus: true,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.md),
            LabeledControl(
              label: l10n.layoutMode,
              child: AppSegmentedControl<ViewMode>(
                options: [
                  (ViewMode.brief, l10n.modeBrief),
                  (ViewMode.list, l10n.modeList),
                  (ViewMode.thumbnails, l10n.cmdThumbnailsView),
                ],
                value: _mode,
                onChanged: (m) => setState(() => _mode = m),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_mode == ViewMode.brief)
              LabeledControl(
                label: l10n.briefColumnsLabel,
                child: AppSegmentedControl<BriefColumns>(
                  options: [
                    (BriefColumns.fixed, l10n.briefColumnsFixed),
                    (BriefColumns.dynamic, l10n.briefColumnsDynamic),
                  ],
                  value: _briefColumns,
                  onChanged: (b) => setState(() => _briefColumns = b),
                ),
              )
            else
              LabeledControl(
                label: l10n.columnsLabel,
                child: Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final column in ListColumn.values)
                      if (column != ListColumn.name)
                        AppCheckbox(
                          key: ValueKey(column),
                          label: l10n.columnLabel(column),
                          value: _columns.contains(column),
                          onChanged: (on) => _toggleColumn(column, on),
                        ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: _complete ? _save : null,
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
  }
}
