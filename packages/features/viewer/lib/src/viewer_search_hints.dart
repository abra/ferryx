import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortcuts/shortcuts.dart';

/// Search input consumes Escape to clear first; match navigation is only
/// useful once there are results. Content focus does not submit the field.
class ViewerSearchHints extends StatelessWidget {
  const ViewerSearchHints({
    required this.chord,
    required this.focusNode,
    required this.hasQuery,
    required this.hasMatches,
    super.key,
  });

  final String? Function(AppCommand command) chord;
  final FocusNode focusNode;
  final bool hasQuery;
  final bool hasMatches;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: focusNode,
    builder: (context, _) {
      final l10n = context.l10n;
      final clear = focusNode.hasFocus && hasQuery;
      final dismiss = clear
          ? Chord.keyLabel(LogicalKeyboardKey.escape, context.platform)
          : chord(AppCommand.dismiss);
      final submit = chord(AppCommand.confirm);
      return AppKeyHints([
        if (dismiss != null)
          AppKeyHint([dismiss], clear ? l10n.actionClear : l10n.actionClose),
        if (hasMatches) ...[
          if (focusNode.hasFocus && submit != null)
            AppKeyHint([submit], l10n.cmdViewerFindNext),
          if (chord(AppCommand.viewerFindNext) case final next?)
            AppKeyHint([next], l10n.cmdViewerFindNext),
          if (chord(AppCommand.viewerFindPrevious) case final previous?)
            AppKeyHint([previous], l10n.cmdViewerFindPrevious),
        ],
      ], singleLine: true);
    },
  );
}
