import 'dart:async';
import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
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
    this.serverState,
    this.onReconnect,
    super.key,
  });

  final PanelTabState tab;
  final bool active;
  final VimLine? vim;

  /// `3 on the shelf`, `2 cut`.
  final String? shelfNote;

  /// The flat view's capsule was clicked: back to the folder.
  final VoidCallback? onLeaveFlat;

  /// The state of the server the tab is on; `null` elsewhere.
  final ServerState? serverState;

  /// The server's capsule was clicked while it is out of reach.
  final VoidCallback? onReconnect;

  /// The footer's height at the text size in [context]: the hint line's
  /// under it, a bar button's and a margin (as Finder's path and status
  /// bars, 27 and a line on macOS 15, match), taller as the text grows.
  static double heightOf(BuildContext context) {
    final line = context.text.bodySmall!;
    final text = MediaQuery.textScalerOf(
      context,
    ).scale(line.fontSize! * line.height!);
    return math.max(
          context.metrics.iconButtonSize.height,
          text + AppSpacing.sm,
        ) +
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
            // Cut too when the footer is narrow (a server's capsule, Vim's).
            Flexible(child: _Line(details, strong)),
          ],
        ],
      );
    } else {
      left = const SizedBox.shrink();
    }
    // `..` leads the rows when it is there.
    final rows = tab.rows;
    final count =
        rows.length - (rows.isNotEmpty && rows.first.isParent ? 1 : 0);
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
        horizontal: context.metrics.tableRowInset + AppSpacing.sm,
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
          if (_server case final server?) ...[
            _ServerCap(
              server: server,
              state: serverState ?? ServerState.closed,
              busy: tab.loading,
              active: active,
              onReconnect: onReconnect,
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          // The count and the free space keep to the end, up to half the
          // line; the focused item's name gives way first.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Expanded(child: left),
                  const SizedBox(width: AppSpacing.md),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth / 2,
                    ),
                    child: _Line(right, muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  ServerKey? get _server {
    final key = tab.location.server;
    return key == null ? null : ServerKey.parse(key);
  }
}

/// A server's capsule: its protocol, with a lock when the connection is
/// encrypted and an open one when it is not, and its state when it is not
/// simply open; the platform's spinner while a folder is read. Out of
/// reach, a click (or its ⌘J hint) connects again.
class _ServerCap extends StatelessWidget {
  const _ServerCap({
    required this.server,
    required this.state,
    required this.busy,
    required this.active,
    required this.onReconnect,
  });

  final ServerKey server;
  final ServerState state;
  final bool busy;
  final bool active;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final secure = server.protocol.secure;
    final open = state == ServerState.connected;
    final (fill, ink) = !active
        ? (colors.selectionMuted, colors.textMuted)
        : !open
        ? (colors.wash(0), colors.ink(0))
        : secure
        ? (colors.wash(3), colors.ink(3))
        : (colors.wash(1), colors.ink(1));
    final style = context.text.labelSmall!
        .copyWith(color: ink)
        .weight(FontWeight.w700);
    // The glyphs grow with the text beside them.
    final size = MediaQuery.textScalerOf(
      context,
    ).scale(style.fontSize ?? AppIconSize.xs);
    final said = l10n.serverStateLabel(
      state,
      server.displayRoot,
      secure: secure,
    );
    final capsule = Semantics(
      label: said,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(context.metrics.radius.chip),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                _Later(
                  placeholder: _LockGlyph(secure: secure, size: size, ink: ink),
                  child: AppSpinner(size: size),
                )
              else
                _LockGlyph(secure: secure, size: size, ink: ink),
              const SizedBox(width: AppSpacing.xs),
              Text(l10n.protocolShortName(server.protocol), style: style),
              if (!open) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  state == ServerState.lost
                      ? l10n.networkCapsuleLost
                      : l10n.networkCapsuleClosed,
                  style: style.weight(FontWeight.w500),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final reconnect = onReconnect;
    if (open || reconnect == null) {
      return AppTooltip(message: said, child: capsule);
    }
    return AppTooltip(
      message: l10n.networkReconnect,
      child: HintTarget(
        onActivate: reconnect,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(onTap: reconnect, child: capsule),
        ),
      ),
    );
  }
}

/// A closed lock for an encrypted connection, an open one otherwise.
class _LockGlyph extends StatelessWidget {
  const _LockGlyph({
    required this.secure,
    required this.size,
    required this.ink,
  });

  final bool secure;
  final double size;
  final Color ink;

  @override
  Widget build(BuildContext context) =>
      Icon(secure ? AppIcons.lock : AppIcons.unlocked, size: size, color: ink);
}

/// [child] once a moment has passed, [placeholder] until then: a quick
/// read never flashes its spinner.
class _Later extends StatefulWidget {
  const _Later({required this.placeholder, required this.child});

  static const delay = Duration(milliseconds: 300);

  final Widget placeholder;
  final Widget child;

  @override
  State<_Later> createState() => _LaterState();
}

class _LaterState extends State<_Later> {
  Timer? _wait;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _wait = Timer(_Later.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _shown ? widget.child : widget.placeholder;
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
