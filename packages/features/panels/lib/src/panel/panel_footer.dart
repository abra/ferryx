import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import 'panel_state.dart';

/// What Vim mode shows in the footer: the mode's name, the keys that
/// wait, or the command line in place of the rest.
class VimLine {
  const VimLine({required this.mode, this.pending = '', this.commandLine});

  final VimMode mode;

  /// Keys typed and waiting: a count, a prefix (`g`, `d`), `f`.
  final String pending;

  /// The `:` line while it is open.
  final Widget? commandLine;
}

enum VimMode { normal, visual, search, command }

/// Under the rows: the focused item with its size and date, or the
/// selection's count and size; what the shelf holds, the number of items
/// and the free space. With Vim keys on, the mode leads the line.
class PanelFooter extends StatelessWidget {
  const PanelFooter({
    required this.tab,
    required this.active,
    this.vim,
    this.shelfNote,
    this.onLeaveFlat,
    super.key,
  });

  final PanelTabState tab;
  final bool active;
  final VimLine? vim;

  /// `3 on the shelf`, `2 cut`.
  final String? shelfNote;

  /// The flat view's capsule was clicked: back to the folder.
  final VoidCallback? onLeaveFlat;

  /// The footer's height at the text size in [context]: a control's
  /// height and a margin, taller as the text grows.
  static double heightOf(BuildContext context) {
    final line = context.text.bodySmall!;
    final text = MediaQuery.textScalerOf(
      context,
    ).scale(line.fontSize! * line.height!);
    return math.max(context.metrics.controlHeight, text + AppSpacing.sm) +
        AppSpacing.xs;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final muted = context.text.bodySmall!.copyWith(
      color: colors.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final strong = context.text.bodySmall!.copyWith(
      color: active ? context.colors.onSurface : colors.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final mono = context.mono.copyWith(fontSize: strong.fontSize);
    final focused = tab.focused;
    final vim = this.vim;
    final Widget left;
    if (vim?.commandLine != null) {
      left = vim!.commandLine!;
    } else if (tab.searching || (vim != null && tab.quickSearch.isNotEmpty)) {
      left = _Line('/${tab.quickSearch}${tab.searching ? '▏' : ''}', mono);
    } else if (tab.quickSearch.isNotEmpty) {
      left = _Line(l10n.panelQuickSearch(tab.quickSearch), strong);
    } else if (tab.selected.isNotEmpty) {
      left = _Line(
        l10n.panelSelectedSummary(
          tab.selected.length,
          l10n.fileSize(tab.selectedBytes),
        ),
        strong,
      );
    } else if (focused != null && !focused.isParent) {
      final size = focused.size;
      final modified = focused.modified;
      final details = size != null && modified != null
          ? l10n.joinedDetails(l10n.fileSize(size), l10n.dateTime(modified))
          : size != null
          ? l10n.fileSize(size)
          : modified != null
          ? l10n.dateTime(modified)
          : null;
      left = Row(
        children: [
          // A flat view's row says its folder too.
          Flexible(child: AppMiddleEllipsis(focused.key, style: strong)),
          if (details != null) ...[
            const SizedBox(width: AppSpacing.md),
            _Line(details, strong),
          ],
        ],
      );
    } else {
      left = const SizedBox.shrink();
    }
    final count = tab.rows.where((r) => !r.isParent).length;
    final free = tab.listing?.freeBytes;
    final flat = tab.flat;
    final right = [
      ?shelfNote,
      if (flat == null)
        l10n.panelItemsCount(count)
      else if (flat.capped)
        l10n.flatCappedCount(count)
      else
        l10n.flatFileCount(count),
      if (free != null) l10n.panelFreeSpace(l10n.fileSize(free)),
    ].reduce(l10n.joinedDetails);
    return Container(
      height: heightOf(context),
      padding: EdgeInsets.symmetric(
        horizontal: context.metrics.rowInset + AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.windowChrome,
        border: AppBorder(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          if (vim != null) ...[
            _ModeCap(mode: vim.mode, active: active),
            if (vim.pending.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                vim.pending,
                style: mono.copyWith(color: colors.textMuted),
              ),
            ],
            const SizedBox(width: AppSpacing.md),
          ],
          if (flat != null) ...[
            _FlatCap(busy: flat.busy, active: active, onLeave: onLeaveFlat),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(child: left),
          const SizedBox(width: AppSpacing.md),
          Flexible(child: _Line(right, muted)),
        ],
      ),
    );
  }
}

/// One line of the footer, cut with an ellipsis.
class _Line extends StatelessWidget {
  const _Line(this.text, this.style);

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: style,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    softWrap: false,
  );
}

/// The flat view's capsule: its name, with the platform's spinner while
/// the tree is walked; a click (or its ⌘J hint) goes back to the folder,
/// as the command and Esc do.
class _FlatCap extends StatelessWidget {
  const _FlatCap({
    required this.busy,
    required this.active,
    required this.onLeave,
  });

  final bool busy;
  final bool active;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final (fill, ink) = active
        ? (colors.wash(4), colors.ink(4))
        : (colors.selectionMuted, colors.textMuted);
    final style = context.text.labelSmall!
        .copyWith(color: ink)
        .weight(FontWeight.w700);
    final capsule = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(context.metrics.radius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            Semantics(
              label: l10n.flatWalking,
              child: AppSpinner(size: style.fontSize ?? AppIconSize.xs),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(l10n.flatCapsule, style: style),
        ],
      ),
    );
    final leave = onLeave;
    if (leave == null) return capsule;
    return AppTooltip(
      message: l10n.flatLeave,
      child: HintTarget(
        onActivate: leave,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(onTap: leave, child: capsule),
        ),
      ),
    );
  }
}

/// The mode's name in a small capsule: the accent while the panel has the
/// keys, a tag colour for the other modes, grey elsewhere, as Vim's
/// status line colours its mode.
class _ModeCap extends StatelessWidget {
  const _ModeCap({required this.mode, required this.active});

  final VimMode mode;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final label = switch (mode) {
      VimMode.normal => l10n.vimModeNormal,
      VimMode.visual => l10n.vimModeVisual,
      VimMode.search => l10n.vimModeSearch,
      VimMode.command => l10n.vimModeCommand,
    };
    final (fill, ink) = !active
        ? (colors.selectionMuted, colors.textMuted)
        : switch (mode) {
            VimMode.normal => (colors.accent, colors.onAccent),
            VimMode.visual => (colors.wash(5), colors.ink(5)),
            VimMode.search => (colors.wash(3), colors.ink(3)),
            VimMode.command => (colors.wash(1), colors.ink(1)),
          };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(context.metrics.radius.chip),
      ),
      child: Text(
        label,
        style: context.text.labelSmall!
            .copyWith(color: ink)
            .weight(FontWeight.w700),
      ),
    );
  }
}
