import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import 'dialog_support.dart';

/// "New Tag…": a name and a colour (Finder's, or none).
Future<FileTag?> showNewTagDialog(BuildContext context) =>
    showWorkspaceDialog<FileTag>(context, (context) => const NewTagDialog());

class NewTagDialog extends StatefulWidget {
  const NewTagDialog({super.key});

  @override
  State<NewTagDialog> createState() => _NewTagDialogState();
}

class _NewTagDialogState extends State<NewTagDialog> {
  final _name = TextEditingController();
  int _color = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(FileTag(name, color: _color));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDialog(
      title: l10n.tagsNewTitle,
      width: AppSizes.compactDialogWidth,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogField(
            label: l10n.tagsNameLabel,
            controller: _name,
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          dialogRowGap,
          DialogChoice<int>(
            label: l10n.tagsColorLabel,
            value: _color,
            items: [
              (0, l10n.tagsColorNone),
              for (final color in AppTagColors.menuOrder)
                (color, l10n.tagColorName(color)),
            ],
            onChanged: (v) => setState(() => _color = v),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        DialogSubmitButton(
          label: l10n.tagsAdd,
          controllers: [_name],
          onPressed: _submit,
        ),
      ],
    );
  }
}
