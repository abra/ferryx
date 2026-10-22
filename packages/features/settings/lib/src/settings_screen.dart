import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

import 'pages/about_page.dart';
import 'pages/editors_page.dart';
import 'pages/general_page.dart';
import 'pages/hotkeys_page.dart';
import 'pages/panels_page.dart';
import 'pages/tools_page.dart';
import 'pages/viewer_page.dart';

/// The pages of the settings window.
enum SettingsSection { general, panels, viewer, hotkeys, editors, tools, about }

/// The settings window: a navigation column of pages on the left, the
/// page on the right; every change is written at once.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.preferencesService,
    required this.platform,
    required this.version,
    required this.onClose,
    this.initialSection = SettingsSection.general,
    super.key,
  });

  final PreferencesService preferencesService;
  final TargetPlatform platform;
  final String version;
  final SettingsSection initialSection;
  final VoidCallback onClose;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsSection _section = widget.initialSection;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static const _groups = [
    [SettingsSection.general, SettingsSection.panels, SettingsSection.viewer],
    [SettingsSection.hotkeys],
    [SettingsSection.editors, SettingsSection.tools, SettingsSection.about],
  ];

  /// The search narrows the pages; when it leaves the open page out, the
  /// first page it keeps opens, so the hit is in view.
  void _onQuery(String query, List<SettingsSection> shown) {
    setState(() {
      _query = query;
      if (!shown.contains(_section) && shown.isNotEmpty) {
        _section = shown.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) => PreferenceBuilder<Preferences>(
    service: widget.preferencesService,
    select: (p) => p,
    builder: (context, prefs) {
      final map = ShortcutMap.forUser(
        widget.platform,
        vimMotions: prefs.vimMode,
        overrides: prefs.shortcutOverrides,
      );
      return CommandShortcuts(
        shortcuts: map.toShortcuts(
          widget.platform,
          scopes: const {CommandScope.dialogs, CommandScope.lists},
        ),
        child: CommandHandlers(
          handlers: {AppCommand.dismiss: widget.onClose},
          child: Dialog(
            clipBehavior: Clip.antiAlias,
            insetPadding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.settingsDialogWidth,
                maxHeight: AppSizes.panelDialogHeight,
              ),
              child: PixelSnap(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Navigation(
                      section: _section,
                      groups: _groups,
                      prefs: prefs,
                      query: _query,
                      controller: _search,
                      onQuery: _onQuery,
                      onSelect: (s) => setState(() => _section = s),
                    ),
                    Expanded(
                      child: _Content(
                        section: _section,
                        prefs: prefs,
                        service: widget.preferencesService,
                        platform: widget.platform,
                        shortcutMap: map,
                        version: widget.version,
                        onClose: widget.onClose,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The localized name and icon of a section.
String sectionLabel(FerryxLocalizations l10n, SettingsSection section) =>
    switch (section) {
      SettingsSection.general => l10n.settingsGeneral,
      SettingsSection.panels => l10n.settingsPanels,
      SettingsSection.viewer => l10n.settingsViewer,
      SettingsSection.hotkeys => l10n.settingsHotkeys,
      SettingsSection.editors => l10n.settingsEditors,
      SettingsSection.tools => l10n.settingsTools,
      SettingsSection.about => l10n.settingsAbout,
    };

/// The words on a page, for the search: its group titles, row labels and
/// the names of what it lists, besides the page's own name.
List<String> sectionTerms(
  FerryxLocalizations l10n,
  SettingsSection section,
  Preferences prefs,
) => switch (section) {
  SettingsSection.general => [
    l10n.themeLabel,
    l10n.themeSystem,
    l10n.themeLight,
    l10n.themeDark,
    l10n.languageLabel,
    l10n.languageSystem,
    l10n.languageEnglish,
    l10n.languageRussian,
    l10n.textSizeLabel,
    l10n.confirmationsLabel,
    l10n.confirmTrashLabel,
    l10n.confirmDeleteLabel,
    l10n.copyDefaultsLabel,
    l10n.optionPreserveAttributes,
    l10n.optionVerify,
  ],
  SettingsSection.panels => [
    l10n.panelsShowHidden,
    l10n.panelsVimMode,
    l10n.panelsVimModeHint,
    l10n.panelsParentEntry,
    l10n.panelsFoldersFirst,
    l10n.panelsExtensionlessFolders,
    l10n.panelsCollation,
    for (final c in Collation.values) l10n.collationLabel(c),
    l10n.panelsTabBarAlways,
    l10n.quickSearchTitle,
    l10n.quickSearchWhere,
    l10n.quickSearchModifier,
    l10n.quickSearchOnlyMatching,
    l10n.layoutsTitle,
    l10n.layoutsReset,
    for (final layout in prefs.layouts) layout.name,
  ],
  SettingsSection.viewer => [l10n.viewerWrapLabel, l10n.viewerFontSizeLabel],
  SettingsSection.hotkeys => [
    l10n.hotkeysReset,
    for (final scope in CommandScope.values) l10n.scopeLabel(scope),
    for (final command in AppCommand.values) l10n.commandLabel(command),
  ],
  SettingsSection.editors => [
    l10n.editorsIntro,
    l10n.editorsAdd,
    for (final editor in prefs.editors) editor.name,
  ],
  SettingsSection.tools => [
    l10n.toolsIntro,
    l10n.toolsAdd,
    for (final tool in prefs.tools) tool.title,
  ],
  SettingsSection.about => [
    l10n.appTitle,
    l10n.aboutDescription,
    l10n.aboutLicense,
  ],
};

IconData _sectionIcon(SettingsSection section) => switch (section) {
  SettingsSection.general => AppIcons.settings,
  SettingsSection.panels => AppIcons.dualPane,
  SettingsSection.viewer => AppIcons.preview,
  SettingsSection.hotkeys => AppIcons.keyboard,
  SettingsSection.editors => AppIcons.edit,
  SettingsSection.tools => AppIcons.wrench,
  SettingsSection.about => AppIcons.info,
};

/// The column of pages, filtered by the search above it: a page stays
/// while its name or a word on it matches.
class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.section,
    required this.groups,
    required this.prefs,
    required this.query,
    required this.controller,
    required this.onQuery,
    required this.onSelect,
  });

  final SettingsSection section;
  final List<List<SettingsSection>> groups;
  final Preferences prefs;
  final String query;
  final TextEditingController controller;
  final void Function(String query, List<SettingsSection> shown) onQuery;
  final ValueChanged<SettingsSection> onSelect;

  static List<SettingsSection> shownFor(
    FerryxLocalizations l10n,
    Preferences prefs,
    String query,
  ) {
    final needle = query.trim().toLowerCase();
    bool matches(String text) => text.toLowerCase().contains(needle);
    return [
      for (final s in SettingsSection.values)
        if (needle.isEmpty ||
            matches(sectionLabel(l10n, s)) ||
            sectionTerms(l10n, s, prefs).any(matches))
          s,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final metrics = context.metrics;
    final shown = shownFor(l10n, prefs, query);
    return Container(
      width: AppSizes.settingsNavWidth,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: AppBorder(right: BorderSide(color: colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              metrics.navRowMargin,
              AppSpacing.md,
              metrics.navRowMargin,
              AppSpacing.sm,
            ),
            child: AppSearchField(
              hintText: l10n.settingsSearchHint,
              controller: controller,
              onChanged: (q) => onQuery(q, shownFor(l10n, prefs, q)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              children: [
                for (var g = 0; g < groups.length; g++) ...[
                  if (g > 0 && groups[g].any(shown.contains))
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: metrics.navRowMargin,
                        vertical: AppSpacing.xs,
                      ),
                      child: const AppDivider(),
                    ),
                  for (final s in groups[g])
                    if (shown.contains(s))
                      AppNavItem(
                        key: ValueKey(s),
                        label: sectionLabel(l10n, s),
                        icon: _sectionIcon(s),
                        selected: s == section,
                        navigation: true,
                        autofocus: s == section,
                        onTap: () => onSelect(s),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The page shown, under its title and the close button.
class _Content extends StatelessWidget {
  const _Content({
    required this.section,
    required this.prefs,
    required this.service,
    required this.platform,
    required this.shortcutMap,
    required this.version,
    required this.onClose,
  });

  final SettingsSection section;
  final Preferences prefs;
  final PreferencesService service;
  final TargetPlatform platform;
  final ShortcutMap shortcutMap;
  final String version;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final metrics = context.metrics;
    final page = switch (section) {
      SettingsSection.general => GeneralPage(prefs: prefs, service: service),
      SettingsSection.panels => PanelsPage(prefs: prefs, service: service),
      SettingsSection.viewer => ViewerPage(prefs: prefs, service: service),
      SettingsSection.hotkeys => HotkeysPage(
        prefs: prefs,
        service: service,
        platform: platform,
        shortcutMap: shortcutMap,
        vim: prefs.vimMode,
      ),
      SettingsSection.editors => EditorsPage(prefs: prefs, service: service),
      SettingsSection.tools => ToolsPage(prefs: prefs, service: service),
      SettingsSection.about => AboutPage(version: version),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: metrics.topBarHeight,
          padding: EdgeInsets.only(
            left: metrics.contentMargin,
            right: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: AppBorder(bottom: BorderSide(color: colors.line)),
          ),
          child: AppTopBarRow(
            title: Text(
              sectionLabel(l10n, section),
              style: context.text.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: [
              AppIconButton(
                icon: AppIcons.close,
                tooltip: l10n.actionClose,
                shortcut: shortcutMap.labelOf(AppCommand.dismiss, platform),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        Expanded(
          child: KeyedSubtree(key: ValueKey(section), child: page),
        ),
      ],
    );
  }
}
