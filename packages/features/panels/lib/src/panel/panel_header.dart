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
    required this.onCommandPalette,
    required this.shortcutMap,
    this.decor = WindowDecor.none,
    this.edge = true,
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
  final VoidCallback onCommandPalette;
  final ShortcutMap shortcutMap;
  final WindowDecor decor;

  /// The line under the bar; none over a tab strip that draws its own and
  /// opens its active tab into the bar ([AppTabStrip.joinsBarAbove]).
  final bool edge;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final bar = Container(
      height: context.metrics.topBarHeight,
      decoration: BoxDecoration(
        color: colors.windowChrome,
        // The height stays: the bar's last row is its own colour then.
        border: AppBorder(
          bottom: BorderSide(
            color: edge ? colors.line : colors.windowChrome,
          ),
        ),
      ),
      child: AppTopBarRow(
        leftInset: leftInset,
        rightInset: rightInset,
        title: Breadcrumbs(location: location, onOpen: onOpen, active: active),
        measureKey: sort.field,
        forms: [
          [
            _SortIndicator(sort: sort, onPressed: onSortMenu),
            _PaletteButton(
              shortcutMap: shortcutMap,
              onPressed: onCommandPalette,
            ),
          ],
          [
            _SortIndicator(sort: sort, onPressed: onSortMenu),
            _PaletteButton(
              shortcutMap: shortcutMap,
              onPressed: onCommandPalette,
              compact: true,
            ),
          ],
          [
            _SortIndicator(sort: sort, onPressed: onSortMenu, compact: true),
            _PaletteButton(
              shortcutMap: shortcutMap,
              onPressed: onCommandPalette,
              compact: true,
            ),
          ],
        ],
        trailing: [
          _BarButton(
            icon: layout.mode == ViewMode.thumbnails
                ? AppIcons.layoutThumbnails
                : layout.mode == ViewMode.list
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

/// The field and direction, with an icon fallback when the path needs room.
class _SortIndicator extends StatelessWidget {
  const _SortIndicator({
    required this.sort,
    required this.onPressed,
    this.compact = false,
  });

  final SortOptions sort;
  final void Function(Rect anchor) onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final direction = sort.descending
        ? l10n.sortDescending
        : l10n.sortAscending;
    final label = l10n.sortFieldLabel(sort.field);
    final tooltip = l10n.panelSortSummary(label, direction);
    if (compact) {
      return _BarButton(
        icon: AppIcons.sort,
        tooltip: tooltip,
        onPressed: onPressed,
      );
    }
    return AppTooltip(
      message: tooltip,
      child: TextButton(
        onPressed: () => onPressed(keyboardMenuAnchor(context)),
        style: AppButtonStyles.bar(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.xs,
          children: [
            Text(label),
            Icon(
              sort.descending ? AppIcons.keyDown : AppIcons.keyUp,
              size: AppIconSize.sm,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaletteButton extends StatelessWidget {
  const _PaletteButton({
    required this.shortcutMap,
    required this.onPressed,
    this.compact = false,
  });

  final ShortcutMap shortcutMap;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shortcut = shortcutMap.labelOf(
      AppCommand.commandPalette,
      context.platform,
    );
    if (compact) {
      return AppIconButton(
        icon: AppIcons.search,
        tooltip: l10n.cmdCommandPalette,
        shortcut: shortcut,
        onPressed: onPressed,
      );
    }
    return AppTooltip(
      message: l10n.cmdCommandPalette,
      shortcut: shortcut,
      child: TextButton.icon(
        onPressed: onPressed,
        style: AppButtonStyles.bar(context),
        icon: const Icon(AppIcons.search, size: AppIconSize.sm),
        label: Text(l10n.commandsButton),
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
    final isServer = widget.location.isRemoteRoot;
    final style =
        (widget.last ? context.text.titleSmall : context.text.bodyMedium)
            ?.copyWith(
              color: widget.last
                  ? (widget.active
                        ? context.colors.onSurface
                        : colors.textMuted)
                  : colors.textMuted,
            );
    final label = isServer
        ? _serverLabel(widget.location)
        : widget.location.name;
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
                if (isArchive || isServer) ...[
                  Icon(
                    isServer ? AppIcons.server : AppIcons.fileArchive,
                    size: AppIconSize.sm,
                    color: isServer ? colors.ink(4) : colors.ink(1),
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

/// A server's root crumb: who on which host (`me@host`), the scheme left
/// to the icon and the footer.
String _serverLabel(Location location) {
  final key = ServerKey.parse(location.server ?? '');
  if (key == null) return location.name;
  final root = key.displayRoot;
  final scheme = root.indexOf('://');
  return scheme < 0 ? root : root.substring(scheme + 3);
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
