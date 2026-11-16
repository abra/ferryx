import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortcuts/shortcuts.dart';

/// Status and exit instructions share one row with the file panel's footer.
/// In a narrow pane the exit instructions take priority over metadata.
class ViewerFooter extends StatelessWidget {
  const ViewerFooter({
    required this.status,
    required this.shortcutMap,
    required this.showFiles,
    this.hints = const [],
    this.searchShown = false,
    this.clearSearch = false,
    super.key,
  });

  final String status;
  final ShortcutMap shortcutMap;
  final bool showFiles;
  final List<AppKeyHint> hints;
  final bool searchShown;
  final bool clearSearch;

  @override
  Widget build(BuildContext context) => AppStatusBar(
    child: Visibility(
      visible: ModalRoute.of(context)?.isCurrent != false,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: AppFitOrElse(
        fallback: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _ExitHints(
            shortcutMap: shortcutMap,
            showFiles: showFiles,
            searchShown: searchShown,
            clearSearch: clearSearch,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: AppFitOrElse(
                fallback: Text(status),
                child: Row(
                  children: [
                    Flexible(child: Text(status)),
                    if (hints.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: AppKeyHints(hints, singleLine: true)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _ExitHints(
                  shortcutMap: shortcutMap,
                  showFiles: showFiles,
                  searchShown: searchShown,
                  clearSearch: clearSearch,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Kept on one line even with large text; full labels remain in tooltips
/// and semantics, and each key retains its own share of the available room.
class _ExitHints extends StatelessWidget {
  const _ExitHints({
    required this.shortcutMap,
    required this.showFiles,
    required this.searchShown,
    required this.clearSearch,
  });

  final ShortcutMap shortcutMap;
  final bool showFiles;
  final bool searchShown;
  final bool clearSearch;

  @override
  Widget build(BuildContext context) {
    final close = clearSearch
        ? Chord.keyLabel(LogicalKeyboardKey.escape, context.platform)
        : shortcutMap.labelOf(AppCommand.dismiss, context.platform);
    final files = shortcutMap.labelOf(AppCommand.switchPanel, context.platform);
    final hints = [
      if (close != null)
        clearSearch
            ? context.l10n.viewerFindClearHint(close)
            : searchShown
            ? context.l10n.viewerFindCloseHint(close)
            : context.l10n.viewerCloseHint(close),
      if (showFiles && files != null) context.l10n.viewerFilesHint(files),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.md,
      children: [
        for (final hint in hints)
          Flexible(
            child: AppTooltip(message: hint, child: Text(hint)),
          ),
      ],
    );
  }
}
