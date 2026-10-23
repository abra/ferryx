import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../panel/file_icon.dart';
import '../path_text.dart';
import 'shelf.dart';

/// The shelf above the key hints: its name and count, the items in a row
/// (each with its icon, name and folder, a button to take it off), Clear,
/// and Copy Here / Move Here into the active panel's folder.
///
/// The row is one place for the keys ([focusNode], an [AppFocusArea]):
/// ← → Home End move between the items, Return shows the item in the
/// active panel, Delete or Backspace takes it off, Esc goes back to the
/// panel ([onLeave]); Tab reaches the buttons. Items gone from the disk are
/// faint and say so. The row builds the items in view only.
class ShelfStrip extends StatefulWidget {
  const ShelfStrip({
    required this.shelf,
    required this.focusNode,
    required this.destination,
    required this.home,
    required this.addKey,
    required this.onReveal,
    required this.onRemove,
    required this.onClear,
    required this.onCopyHere,
    required this.onMoveHere,
    required this.onLeave,
    super.key,
  });

  final Shelf shelf;
  final FocusNode focusNode;

  /// The active panel's folder as shown (`~/docs`), or `null` where
  /// nothing can be put (inside an archive).
  final String? destination;

  /// The home folder, written `~` in the items' folders.
  final String home;

  /// The key of Add to Shelf, for the empty shelf's hint.
  final String? addKey;
  final ValueChanged<ShelfItem> onReveal;
  final ValueChanged<ShelfItem> onRemove;
  final VoidCallback onClear;
  final VoidCallback onCopyHere;
  final VoidCallback onMoveHere;
  final VoidCallback onLeave;

  /// The strip's height at the text size in [context]: a chip, a margin
  /// above and below.
  static double heightOf(BuildContext context) =>
      _chipHeight(context) + 2 * AppSpacing.xs;

  static double _chipHeight(BuildContext context) {
    final line = context.text.bodySmall!;
    final text = MediaQuery.textScalerOf(
      context,
    ).scale(line.fontSize! * (line.height ?? 1.2));
    return math.max(context.metrics.controlHeightSmall, text + AppSpacing.xs);
  }

  /// An item's width: room for a name and its folder, wider with the text.
  static double chipWidthOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(_chipWidth).roundToDouble();

  static const double _chipWidth = 232;

  @override
  State<ShelfStrip> createState() => _ShelfStripState();
}

class _ShelfStripState extends State<ShelfStrip> {
  final _scroll = ScrollController();
  int _cursor = 0;

  List<ShelfItem> get _items => widget.shelf.items;

  @override
  void initState() {
    super.initState();
    widget.focusNode
      ..onKeyEvent = _onKey
      ..addListener(_onFocus);
  }

  @override
  void didUpdateWidget(ShelfStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode
        ..onKeyEvent = null
        ..removeListener(_onFocus);
      widget.focusNode
        ..onKeyEvent = _onKey
        ..addListener(_onFocus);
    }
    if (_cursor >= _items.length) _cursor = math.max(0, _items.length - 1);
  }

  @override
  void dispose() {
    widget.focusNode
      ..onKeyEvent = null
      ..removeListener(_onFocus);
    _scroll.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  void _moveTo(int index) {
    if (_items.isEmpty) return;
    setState(() => _cursor = index.clamp(0, _items.length - 1));
    _reveal();
  }

  /// Scrolls the cursor's item into view the shortest way.
  void _reveal() {
    if (!_scroll.hasClients) return;
    final extent = ShelfStrip.chipWidthOf(context) + AppSpacing.xs;
    final position = _scroll.position;
    final start = _cursor * extent;
    final end = start + extent;
    if (start < position.pixels) {
      position.jumpTo(start);
    } else if (end > position.pixels + position.viewportDimension) {
      position.jumpTo(
        (end - position.viewportDimension).clamp(0, position.maxScrollExtent),
      );
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final item = _items.elementAtOrNull(_cursor);
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveTo(_cursor - 1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _moveTo(_cursor + 1);
    } else if (key == LogicalKeyboardKey.home) {
      _moveTo(0);
    } else if (key == LogicalKeyboardKey.end) {
      _moveTo(_items.length - 1);
    } else if (key == LogicalKeyboardKey.escape) {
      widget.onLeave();
    } else if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        item != null) {
      if (event is KeyDownEvent) widget.onReveal(item);
    } else if ((key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace) &&
        item != null) {
      widget.onRemove(item);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final metrics = context.metrics;
    final shelf = widget.shelf;
    final destination = widget.destination;
    final canPut = destination != null && !shelf.isEmpty;
    final tip = destination == null ? null : l10n.shelfInto(destination);
    final chipWidth = ShelfStrip.chipWidthOf(context);
    final focused = widget.focusNode.hasFocus;
    return Container(
      height: ShelfStrip.heightOf(context),
      padding: EdgeInsets.only(
        left: metrics.tableRowInset + AppSpacing.sm,
        right: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.windowChrome,
        border: AppBorder(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.paste, size: AppIconSize.sm, color: colors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Text(
            l10n.shelfTitle,
            style: context.text.labelMedium!.weight(FontWeight.w600),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${shelf.length}',
            style: context.text.labelMedium!.copyWith(
              color: colors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Focus(
              focusNode: widget.focusNode,
              child: Semantics(
                label: l10n.shelfTitle,
                child: shelf.isEmpty
                    ? _EmptyShelf(addKey: widget.addKey)
                    : ListView.builder(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        itemExtent: chipWidth + AppSpacing.xs,
                        itemCount: shelf.length,
                        itemBuilder: (context, index) => Padding(
                          key: ValueKey(shelf.items[index].path),
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: Center(
                            child: _ShelfChip(
                              item: shelf.items[index],
                              home: widget.home,
                              cursor: focused && index == _cursor,
                              onReveal: () =>
                                  widget.onReveal(shelf.items[index]),
                              onRemove: () =>
                                  widget.onRemove(shelf.items[index]),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _StripButton(
            label: l10n.shelfClear,
            onPressed: shelf.isEmpty ? null : widget.onClear,
          ),
          SizedBox(width: metrics.toolbarSpacing),
          _StripButton(
            label: l10n.shelfCopyHere,
            tooltip: tip,
            onPressed: canPut ? widget.onCopyHere : null,
          ),
          SizedBox(width: metrics.toolbarSpacing),
          _StripButton(
            label: l10n.shelfMoveHere,
            tooltip: tip,
            onPressed: canPut ? widget.onMoveHere : null,
          ),
        ],
      ),
    );
  }
}

/// A push button of the strip, the platform's small size, ⌘J labels it.
class _StripButton extends StatelessWidget {
  const _StripButton({required this.label, this.tooltip, this.onPressed});

  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final button = HintTarget(
      onActivate: onPressed,
      enabled: onPressed != null,
      child: OutlinedButton(
        style: AppButtonStyles.small(context),
        onPressed: onPressed,
        child: Text(label, maxLines: 1, softWrap: false),
      ),
    );
    final tooltip = this.tooltip;
    return tooltip == null || onPressed == null
        ? button
        : AppTooltip(message: tooltip, child: button);
  }
}

/// The shelf with nothing on it: how to put things there.
class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.addKey});

  final String? addKey;

  @override
  Widget build(BuildContext context) {
    final key = addKey;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        key == null ? '' : context.l10n.shelfEmpty(key),
        style: context.text.bodySmall!.copyWith(
          color: context.appColors.textMuted,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// One item: its icon, its name and folder, a button to take it off. A
/// click shows it in the active panel. The keys' item takes the selection
/// colour; one gone from the disk is faint and says so.
class _ShelfChip extends StatelessWidget {
  const _ShelfChip({
    required this.item,
    required this.home,
    required this.cursor,
    required this.onReveal,
    required this.onRemove,
  });

  final ShelfItem item;
  final String home;
  final bool cursor;
  final VoidCallback onReveal;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final metrics = context.metrics;
    final lit = cursor && AppFocusArea.activeOf(context);
    final ink = lit
        ? colors.onAccent
        : item.missing
        ? colors.textFaint
        : context.colors.onSurface;
    final secondary = lit
        ? colors.onAccentMuted
        : item.missing
        ? colors.textFaint
        : colors.textMuted;
    final style = context.text.bodySmall!.copyWith(color: ink);
    final detailStyle = style.copyWith(color: secondary);
    final folder = PathText.tilde(item.folder, home: home);
    final chip = Container(
      height: ShelfStrip._chipHeight(context),
      padding: const EdgeInsets.only(left: AppSpacing.sm, right: AppSpacing.xs),
      decoration: BoxDecoration(
        color: lit
            ? colors.selectionAccent
            : cursor
            ? colors.selectionMuted
            : colors.surfaceSunken,
        borderRadius: BorderRadius.circular(metrics.radius.chip),
      ),
      child: Row(
        children: [
          if (item.missing)
            Icon(AppIcons.file, size: AppIconSize.sm, color: ink)
          else if (lit)
            Icon(
              FileIcon.describe(item.entry, colors).$1,
              size: AppIconSize.sm,
              color: ink,
            )
          else
            FileIcon(item.entry, size: AppIconSize.sm),
          if (item.cut) ...[
            const SizedBox(width: AppSpacing.xxs),
            AppTooltip(
              message: l10n.shelfCutTooltip,
              child: Icon(
                AppIcons.scissors,
                size: AppIconSize.xs,
                color: secondary,
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AppLabelAndDetail(
              label: item.name,
              labelStyle: style,
              labelHighlights: const [],
              labelMatched: style,
              detail: item.missing ? l10n.shelfMissing : folder,
              detailStyle: detailStyle,
              detailHighlights: const [],
              detailMatched: detailStyle,
            ),
          ),
          HintTarget(
            onActivate: onRemove,
            child: AppTooltip(
              message: l10n.shelfRemove,
              child: ExcludeFocus(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    child: Icon(
                      AppIcons.close,
                      size: AppIconSize.xs,
                      color: secondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: cursor,
      label: item.missing
          ? l10n.shelfMissingTooltip(item.path)
          : l10n.joinedDetails(item.name, folder),
      child: HintTarget(
        onActivate: onReveal,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onReveal,
          child: item.missing
              ? AppTooltip(
                  message: l10n.shelfMissingTooltip(item.path),
                  child: chip,
                )
              : chip,
        ),
      ),
    );
  }
}
