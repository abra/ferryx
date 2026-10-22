import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shortcuts/shortcuts.dart';

/// A panel's top bar: the path as crumbs, the sort indicator, the view
/// mode and the panel's menu. It shares the window's top row, so where the
/// app draws the title bar the bar moves the window ([decor]); the crumbs
/// and buttons keep their own clicks.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    required this.location,
    required this.sort,
    required this.layout,
    required this.active,
    required this.leftInset,
    required this.rightInset,
    required this.onOpen,
    required this.onSortMenu,
    required this.onLayoutMenu,
    required this.onPanelMenu,
    required this.shortcutMap,
    this.decor = WindowDecor.none,
    super.key,
  });

  final Location location;
  final SortOptions sort;
  final PanelLayout layout;
  final bool active;
  final double leftInset;
  final double rightInset;
  final ValueChanged<Location> onOpen;
  final void Function(Rect anchor) onSortMenu;
  final void Function(Rect anchor) onLayoutMenu;
  final void Function(Rect anchor) onPanelMenu;
  final ShortcutMap shortcutMap;
  final WindowDecor decor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final bar = Container(
      height: context.metrics.topBarHeight,
      decoration: BoxDecoration(
        color: colors.windowChrome,
        border: AppBorder(bottom: BorderSide(color: colors.line)),
      ),
      child: AppTopBarRow(
        leftInset: leftInset,
        rightInset: rightInset,
        title: Breadcrumbs(location: location, onOpen: onOpen, active: active),
        trailing: [
          _SortIndicator(sort: sort, onPressed: onSortMenu),
          _BarButton(
            icon: layout.mode == ViewMode.list
                ? AppIcons.layoutList
                : AppIcons.layoutBrief,
            tooltip: l10n.panelLayoutTooltip,
            onPressed: onLayoutMenu,
          ),
          _BarButton(
            icon: AppIcons.more,
            tooltip: l10n.panelMenuTooltip,
            onPressed: onPanelMenu,
          ),
        ],
      ),
    );
    return decor.dragArea(bar);
  }
}

/// A bar button that opens a menu by its own box.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final void Function(Rect anchor) onPressed;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => AppIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: () => onPressed(keyboardMenuAnchor(context)),
    ),
  );
}

/// The sort order as a bar button: the field's letter, as orthodox
/// managers show it (`n` by name, `S` by size the other way round), with
/// the direction's arrow beside it; the tooltip names both.
class _SortIndicator extends StatelessWidget {
  const _SortIndicator({required this.sort, required this.onPressed});

  final SortOptions sort;
  final void Function(Rect anchor) onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final direction = sort.descending
        ? l10n.sortDescending
        : l10n.sortAscending;
    return Builder(
      builder: (context) => AppIconButton(
        icon: AppIcons.sort,
        tooltip: l10n.panelSortSummary(
          l10n.sortFieldLabel(sort.field),
          direction,
        ),
        onPressed: () => onPressed(keyboardMenuAnchor(context)),
        glyph: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppIconSize.md,
                height: AppIconSize.md,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.controlFill,
                  borderRadius: BorderRadius.circular(
                    context.metrics.radius.chip,
                  ),
                  border: AppBorder.fromBorderSide(
                    BorderSide(color: colors.controlBorder),
                  ),
                ),
                child: Text(
                  sort.indicator,
                  style: context.mono
                      .copyWith(
                        fontSize: context.text.bodySmall?.fontSize,
                        height: 1,
                        color: context.colors.onSurface,
                      )
                      .weight(FontWeight.w600),
                ),
              ),
              Icon(
                sort.descending ? AppIcons.chevronDown : AppIcons.chevronUp,
                size: AppIconSize.xs,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The path as crumbs; a crumb opens its folder. Long paths scroll so the
/// end, the folder shown, stays in view.
class Breadcrumbs extends StatelessWidget {
  const Breadcrumbs({
    required this.location,
    required this.onOpen,
    required this.active,
    super.key,
  });

  final Location location;
  final ValueChanged<Location> onOpen;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final chain = location.ancestry;
    return ClipRect(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        physics: const ClampingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < chain.length; i++) ...[
              if (i > 0)
                Icon(
                  AppIcons.chevronRight,
                  size: AppIconSize.xs,
                  color: colors.textFaint,
                ),
              _Crumb(
                location: chain[i],
                last: i == chain.length - 1,
                active: active,
                onOpen: onOpen,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Crumb extends StatefulWidget {
  const _Crumb({
    required this.location,
    required this.last,
    required this.active,
    required this.onOpen,
  });

  final Location location;
  final bool last;
  final bool active;
  final ValueChanged<Location> onOpen;

  @override
  State<_Crumb> createState() => _CrumbState();
}

class _CrumbState extends State<_Crumb> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isArchive = widget.location.isArchiveRoot;
    final style =
        (widget.last ? context.text.titleSmall : context.text.bodyMedium)
            ?.copyWith(
              color: widget.last
                  ? (widget.active
                        ? context.colors.onSurface
                        : colors.textMuted)
                  : colors.textMuted,
            );
    final label = widget.location.name;
    return HintTarget(
      onActivate: () => widget.onOpen(widget.location),
      enabled: !widget.last,
      child: MouseRegion(
        cursor: widget.last ? MouseCursor.defer : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.last ? null : () => widget.onOpen(widget.location),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: _hovered && !widget.last ? colors.hoverFill : null,
              borderRadius: BorderRadius.circular(context.metrics.radius.chip),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isArchive) ...[
                  Icon(
                    AppIcons.fileArchive,
                    size: AppIconSize.sm,
                    color: colors.ink(1),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(label, style: style, maxLines: 1, softWrap: false),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The order of the sort, as the sort menu offers it.
enum SortDirection { ascending, descending }

/// The sort menu's entries: the fields, the direction, then the options,
/// checked as set; every item carries its chord.
List<AppMenuEntry<Object>> sortMenuEntries(
  BuildContext context,
  SortOptions sort,
  ShortcutMap map,
) {
  final l10n = context.l10n;
  final platform = Theme.of(context).platform;
  String? chord(AppCommand command) => map.labelOf(command, platform);
  return [
    AppMenuSection(l10n.sortMenuTitle),
    for (final (field, command) in [
      (SortField.name, AppCommand.sortByName),
      (SortField.extension, AppCommand.sortByExtension),
      (SortField.size, AppCommand.sortBySize),
      (SortField.modified, AppCommand.sortByModified),
      (SortField.created, AppCommand.sortByCreated),
      (SortField.added, AppCommand.sortByAdded),
      (SortField.accessed, AppCommand.sortByAccessed),
    ])
      AppMenuAction<Object>(
        value: field,
        label: l10n.sortFieldLabel(field),
        shortcut: chord(command),
        checked: sort.field == field,
      ),
    const AppMenuSeparator(),
    AppMenuAction<Object>(
      value: SortDirection.ascending,
      label: l10n.sortAscending,
      checked: !sort.descending,
    ),
    AppMenuAction<Object>(
      value: SortDirection.descending,
      label: l10n.sortDescending,
      shortcut: chord(AppCommand.vimSortReverse),
      checked: sort.descending,
    ),
    const AppMenuSeparator(),
    AppMenuAction<Object>(
      value: AppCommand.toggleFoldersFirst,
      label: l10n.cmdToggleFoldersFirst,
      shortcut: chord(AppCommand.toggleFoldersFirst),
      checked: sort.foldersFirst,
    ),
    AppMenuAction<Object>(
      value: AppCommand.toggleExtensionlessFolders,
      label: l10n.cmdToggleExtensionlessFolders,
      shortcut: chord(AppCommand.toggleExtensionlessFolders),
      checked: sort.extensionlessFolders,
    ),
    const AppMenuSeparator(),
    for (final (collation, command) in [
      (Collation.natural, AppCommand.collationNatural),
      (Collation.caseInsensitive, AppCommand.collationCaseInsensitive),
      (Collation.caseSensitive, AppCommand.collationCaseSensitive),
    ])
      AppMenuAction<Object>(
        value: command,
        label: l10n.collationLabel(collation),
        shortcut: chord(command),
        checked: sort.collation == collation,
      ),
  ];
}
