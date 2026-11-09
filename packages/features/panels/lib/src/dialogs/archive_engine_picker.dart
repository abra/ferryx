import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import 'dialog_support.dart';

/// The same engine selector in compression and extraction dialogs.
class ArchiveEnginePicker extends StatelessWidget {
  const ArchiveEnginePicker({
    required this.tools,
    required this.value,
    required this.onChanged,
    this.onManage,
    this.includeBuiltin = true,
    this.automaticName,
    super.key,
  });
  final List<ArchiveTool> tools;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onManage;
  final bool includeBuiltin;
  final String? automaticName;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      DialogChoice<String>(
        label: context.l10n.archiveEngineLabel,
        value: value,
        items: [
          (
            '',
            automaticName == null
                ? context.l10n.archiversAutomatic
                : context.l10n.joinedDetails(
                    context.l10n.archiversAutomatic,
                    automaticName!,
                  ),
          ),
          if (includeBuiltin)
            (builtInArchiverId, context.l10n.archiversBuiltin),
          for (final tool in tools) (tool.id, tool.name),
        ],
        onChanged: onChanged,
      ),
      if (onManage != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onManage,
            icon: const Icon(AppIcons.settings, size: AppIconSize.sm),
            label: Text(context.l10n.archiversManage),
          ),
        ),
    ],
  );
}

ArchiveTool? toolById(List<ArchiveTool> tools, String id) {
  for (final tool in tools) {
    if (tool.id == id) return tool;
  }
  return null;
}
