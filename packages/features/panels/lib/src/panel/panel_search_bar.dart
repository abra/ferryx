import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shortcuts/shortcuts.dart';

import 'panel_search_state.dart';

class PanelSearchBar extends StatelessWidget {
  const PanelSearchBar({
    required this.search,
    required this.onStop,
    required this.onRefresh,
    required this.onOpenRoot,
    super.key,
  });
  final PanelSearchState search;
  final VoidCallback onStop, onRefresh, onOpenRoot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title =
        search.label ??
        (search.request.name.isEmpty
            ? l10n.searchResultsTitle
            : search.request.name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.appColors.windowChrome,
        border: AppBorder(bottom: BorderSide(color: context.appColors.line)),
      ),
      child: AppTopBarRow(
        title: AppTooltip(
          message: search.capped
              ? l10n.searchLimit
              : l10n.joinedDetails(title, search.request.root),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall,
          ),
        ),
        leading: [
          if (search.running)
            const AppSpinner(size: AppIconSize.xs)
          else
            Icon(
              search.capped ? AppIcons.warning : AppIcons.search,
              size: AppIconSize.sm,
              color: context.appColors.textMuted,
            ),
        ],
        trailing: [
          if (search.running)
            AppIconButton(
              icon: AppIcons.cancel,
              tooltip: l10n.searchStop,
              onPressed: onStop,
            )
          else
            AppIconButton(
              icon: AppIcons.refresh,
              tooltip: l10n.cmdRefresh,
              onPressed: onRefresh,
            ),
          AppIconButton(
            icon: AppIcons.search,
            tooltip: l10n.searchEdit,
            onPressed: () => Actions.invoke(
              context,
              const CommandIntent(AppCommand.findFiles),
            ),
          ),
          AppIconButton(
            icon: AppIcons.bookmark,
            tooltip: l10n.savedSearchesTitle,
            onPressed: () => Actions.invoke(
              context,
              const CommandIntent(AppCommand.manageSavedSearches),
            ),
          ),
          AppIconButton(
            icon: AppIcons.folderOpen,
            tooltip: l10n.searchOpenRoot,
            onPressed: onOpenRoot,
          ),
        ],
      ),
    );
  }
}
