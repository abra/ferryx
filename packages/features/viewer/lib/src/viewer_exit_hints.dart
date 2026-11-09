import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shortcuts/shortcuts.dart';

/// Exit instructions remain visible even when the workspace hints are hidden.
class ViewerExitHints extends StatelessWidget {
  const ViewerExitHints({
    required this.shortcutMap,
    required this.showFiles,
    super.key,
  });

  final ShortcutMap shortcutMap;
  final bool showFiles;

  @override
  Widget build(BuildContext context) {
    final close = shortcutMap.labelOf(AppCommand.dismiss, context.platform);
    final files = shortcutMap.labelOf(AppCommand.switchPanel, context.platform);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: DefaultTextStyle(
        style: context.text.bodySmall!.copyWith(
          color: context.appColors.textMuted,
        ),
        child: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            if (close != null) Text(context.l10n.viewerCloseHint(close)),
            if (showFiles && files != null)
              Text(context.l10n.viewerFilesHint(files)),
          ],
        ),
      ),
    );
  }
}
