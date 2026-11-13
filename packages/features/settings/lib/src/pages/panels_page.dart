import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:preferences_service/preferences_service.dart';

import '../settings_rows.dart';
import 'layout_dialog.dart';

/// What the panels show and how they sort, the quick search, the view
/// modes.
class PanelsPage extends StatelessWidget {
  const PanelsPage({required this.prefs, required this.service, super.key});

  final Preferences prefs;
  final PreferencesService service;

  Future<void> _editLayout(BuildContext context, int index) async {
    final edited = await showLayoutDialog(
      context,
      layout: prefs.layouts[index],
    );
    if (edited == null) return;
    final layouts = [...prefs.layouts];
    layouts[index] = edited;
    await service.update((p) => p.copyWith(layouts: layouts));
  }

  Future<void> _addLayout(BuildContext context) async {
    final added = await showLayoutDialog(context, layout: null);
    if (added == null) return;
    await service.update((p) => p.copyWith(layouts: [...p.layouts, added]));
  }

  Future<void> _removeLayout(int index) => service.update(
    (p) => p.copyWith(layouts: [...p.layouts]..removeAt(index)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsPage(
      children: [
        SettingsGroup(
          children: [
            ToggleRow(
              label: l10n.panelsShowHidden,
              value: prefs.showHiddenFiles,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(showHiddenFiles: v)),
            ),
            ToggleRow(
              label: l10n.panelsVimMode,
              note: l10n.panelsVimModeHint,
              value: prefs.vimMode,
              onChanged: (v) => service.update((p) => p.copyWith(vimMode: v)),
            ),
            ToggleRow(
              label: l10n.panelsParentEntry,
              value: prefs.showParentEntry,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(showParentEntry: v)),
            ),
            ToggleRow(
              label: l10n.panelsFoldersFirst,
              value: prefs.foldersFirst,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(foldersFirst: v)),
            ),
            ToggleRow(
              label: l10n.panelsExtensionlessFolders,
              value: prefs.extensionlessFolders,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(extensionlessFolders: v)),
            ),
            ChoiceRow<Collation>(
              label: l10n.panelsCollation,
              value: prefs.collation,
              items: [
                for (final c in Collation.values) (c, l10n.collationLabel(c)),
              ],
              onChanged: (c) => service.update((p) => p.copyWith(collation: c)),
            ),
            ToggleRow(
              label: l10n.panelsTabBarAlways,
              value: prefs.showTabBarAlways,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(showTabBarAlways: v)),
            ),
            ChoiceRow<PanelArrangement>(
              label: l10n.panelsArrangement,
              note: l10n.panelsArrangementHint,
              value: prefs.panelArrangement,
              items: [
                (
                  PanelArrangement.byWindowShape,
                  l10n.panelsArrangementByWindowShape,
                ),
                (PanelArrangement.sideBySide, l10n.panelsArrangementSideBySide),
                (PanelArrangement.stacked, l10n.panelsArrangementStacked),
              ],
              onChanged: (a) =>
                  service.update((p) => p.copyWith(panelArrangement: a)),
            ),
          ],
        ),
        SettingsGroup(
          title: l10n.quickSearchTitle,
          children: [
            ChoiceRow<QuickSearchWhere>(
              label: l10n.quickSearchWhere,
              value: prefs.quickSearchWhere,
              items: [
                (QuickSearchWhere.fuzzy, l10n.quickSearchFuzzy),
                (QuickSearchWhere.anywhere, l10n.quickSearchAnywhere),
                (QuickSearchWhere.beginning, l10n.quickSearchBeginning),
                (QuickSearchWhere.ending, l10n.quickSearchEnding),
                (
                  QuickSearchWhere.beginningOrEnding,
                  l10n.quickSearchBeginningOrEnding,
                ),
              ],
              onChanged: (w) =>
                  service.update((p) => p.copyWith(quickSearchWhere: w)),
            ),
            ChoiceRow<QuickSearchModifier>(
              label: l10n.quickSearchModifier,
              value: prefs.quickSearchModifier,
              items: [
                (QuickSearchModifier.none, l10n.modifierNone),
                (QuickSearchModifier.alt, l10n.modifierAlt),
                (QuickSearchModifier.controlAlt, l10n.modifierControlAlt),
                (QuickSearchModifier.shiftAlt, l10n.modifierShiftAlt),
                (QuickSearchModifier.disabled, l10n.modifierDisabled),
              ],
              onChanged: (m) =>
                  service.update((p) => p.copyWith(quickSearchModifier: m)),
            ),
            ToggleRow(
              label: l10n.quickSearchOnlyMatching,
              value: prefs.quickSearchOnlyMatching,
              onChanged: (v) =>
                  service.update((p) => p.copyWith(quickSearchOnlyMatching: v)),
            ),
          ],
        ),
        SettingsGroup(
          title: l10n.layoutsTitle,
          footer: Row(
            spacing: context.metrics.toolbarSpacing,
            children: [
              OutlinedButton.icon(
                onPressed: () => _addLayout(context),
                icon: const Icon(AppIcons.add, size: AppIconSize.sm),
                label: Text(l10n.actionAdd),
              ),
              OutlinedButton(
                onPressed: prefs.layouts == PanelLayout.defaults
                    ? null
                    : () => service.update(
                        (p) => p.copyWith(layouts: PanelLayout.defaults),
                      ),
                child: Text(l10n.layoutsReset),
              ),
            ],
          ),
          children: [
            for (var i = 0; i < prefs.layouts.length; i++)
              ListEntryRow(
                key: ValueKey('layout-$i'),
                title: '${i + 1}. ${l10n.viewModeName(prefs.layouts[i])}',
                subtitle: describeLayout(l10n, prefs.layouts[i]),
                icon: prefs.layouts[i].mode == ViewMode.thumbnails
                    ? AppIcons.layoutThumbnails
                    : prefs.layouts[i].mode == ViewMode.list
                    ? AppIcons.layoutList
                    : AppIcons.layoutBrief,
                editTooltip: l10n.hotkeysChange,
                removeTooltip: l10n.actionRemove,
                onEdit: () => _editLayout(context, i),
                onRemove: prefs.layouts.length > 1
                    ? () => _removeLayout(i)
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// `List · Name, Size, Modified` or `Brief · Three equal columns`.
String describeLayout(FerryxLocalizations l10n, PanelLayout layout) =>
    switch (layout.mode) {
      ViewMode.thumbnails => l10n.cmdThumbnailsView,
      ViewMode.list =>
        '${l10n.modeList} · ${layout.columns.map(l10n.columnLabel).join(', ')}',
      ViewMode.brief =>
        '${l10n.modeBrief} · ${switch (layout.briefColumns) {
          BriefColumns.fixed => l10n.briefColumnsFixed,
          BriefColumns.dynamic => l10n.briefColumnsDynamic,
        }}',
    };
