import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;

import 'app_icons.dart';
import 'app_key_cap.dart';
import 'app_label_row.dart';
import 'app_tooltip.dart';
import 'focus_ring.dart';
import 'hints/hint_registry.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/app_metrics.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_icon_size.dart';
import 'theme/tokens/app_motion.dart';
import 'theme/tokens/app_radius.dart';
import 'theme/tokens/app_spacing.dart';

/// A button at the end of a sidebar row (a folder's +), shown while the
/// row is hovered, open or holds the keyboard focus. It takes no focus of
/// its own: ⌘J labels it, and the row's menu offers the same.
@immutable
class AppNavAction {
  const AppNavAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;

  /// [anchor] is the button's frame, for a menu under it.
  final void Function(Rect anchor) onPressed;
}

/// A sidebar row: icon or chevron, label, optional badge, key cap,
/// [value] or [action]. A label cut with an ellipsis shows whole in a
/// tooltip while the pointer rests on the row or the keyboard reaches it,
/// as the expansion tooltips of the platforms' lists do.
///
/// Marks the selection the platform's way (`AppMetrics.navSelection`): a
/// macOS source list greys the selected row and turns it to the accent
/// while the list holds the keyboard focus; Fluent adds an accent pill at
/// the left; libadwaita fills the row with the text colour. Fully
/// keyboard-operable: focusable, activates on Enter/Space, and shows a
/// focus ring. [depth] indents nested documents.
class AppNavItem extends StatefulWidget {
  const AppNavItem({
    required this.label,
    this.onTap,
    this.onAltTap,
    this.onSecondaryTap,
    this.onMiddleTap,
    this.icon,
    this.expanded,
    this.onToggle,
    this.selected = false,
    this.depth = 0,
    this.badge,
    this.shortcut,
    this.trailing,
    this.value,
    this.action,
    this.focusNode,
    this.autofocus = false,
    this.compact = false,
    this.accent = false,
    this.navigation = false,
    this.focusOnTap = true,
    this.tooltip,
    super.key,
  });

  final String label;

  /// Shown on hover and keyboard focus whether or not the label is cut (a
  /// bookmark's path); the full label otherwise, only when it is cut.
  final String? tooltip;
  final VoidCallback? onTap;

  /// Shift+hint in hint mode (⌘J): open in the right pane.
  final VoidCallback? onAltTap;
  final VoidCallback? onSecondaryTap;

  /// The middle button: open in a new tab, as a link does in a browser.
  final VoidCallback? onMiddleTap;
  final IconData? icon;

  /// `null` = no chevron; `true`/`false` = expanded/collapsed chevron. With
  /// an [icon] as well (a folder), the icon shows and the chevron takes its
  /// place while hovered.
  final bool? expanded;
  final VoidCallback? onToggle;
  final bool selected;
  final int depth;
  final String? badge;
  final String? shortcut;

  /// Secondary text after the label that yields to it: shortened, then
  /// hidden when the row is narrow (a format's file types).
  final Widget? trailing;

  /// A short value at the row's end that always shows, the label ending in
  /// an ellipsis first (a page number in a table of contents); faint, in
  /// figures of one width so a column of them lines up.
  final String? value;
  final AppNavAction? action;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Icon only, for the collapsed rail.
  final bool compact;

  /// Drawn in the accent colour: a call to action such as Create.
  final bool accent;

  /// A place in the app (Search, Today, Flashcards) rather than a document:
  /// macOS tints such icons with the accent, as Finder and Mail do.
  final bool navigation;

  /// A click takes the keyboard focus, as a list row does on every desktop,
  /// so the arrows go on from the row picked. A row that opens a window or a
  /// menu (Search, Create, Settings) passes `false`: like a button it leaves
  /// the focus where it was, and closing the window returns there.
  final bool focusOnTap;

  @override
  State<AppNavItem> createState() => _AppNavItemState();

  /// A row's extent at the text size in [context]: the platform's row
  /// height, until the label's line would leave less than [AppSpacing.xs]
  /// above and below it, then that line and room; and the platform's gap
  /// to the next row (`AppMetrics.navItemGap`). Lists of rows lay out at
  /// this one extent.
  static double extentOf(BuildContext context) =>
      _heightOf(context) + context.metrics.navItemGap;

  /// The row's fill: its extent less the gap.
  static double _heightOf(BuildContext context) {
    final style = context.text.bodyMedium!;
    final line =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    return math.max(
      context.metrics.navItemHeight,
      line + 2 * AppSpacing.xs,
    );
  }
}

class _AppNavItemState extends State<AppNavItem> {
  bool _hovered = false;

  /// The label's paragraph, asked whether it is cut when the pointer or
  /// the keyboard arrives: a list's rows pay nothing at layout.
  final _label = GlobalKey();
  final _tip = GlobalKey<TooltipState>();

  /// The full label's tooltip is in the tree: only while it shows, so a
  /// list's rows hold no tooltip (each listens to every pointer event).
  bool _tipping = false;
  Timer? _tipWait;

  /// The row's focus node when the caller gives none, so a click can take
  /// the focus.
  FocusNode? _ownFocus;
  FocusNode get _focus =>
      widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'AppNavItem'));

  @override
  void dispose() {
    _tipWait?.cancel();
    _ownFocus?.dispose();
    super.dispose();
  }

  bool get _labelCut {
    final paragraph = _label.currentContext?.findRenderObject();
    return paragraph is RenderParagraph && paragraph.didExceedMaxLines;
  }

  /// After the platform's tooltip wait, the full label when it is cut
  /// then: a row the keys reach as it is built has no layout yet.
  void _showFullLabel() {
    _tipWait?.cancel();
    if (widget.compact) return;
    final wait = TooltipTheme.of(context).waitDuration ?? Duration.zero;
    _tipWait = Timer(wait, () {
      if (!mounted || (widget.tooltip == null && !_labelCut)) return;
      setState(() => _tipping = true);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _tip.currentState?.ensureTooltipVisible(),
      );
    });
  }

  /// The full label's tooltip under the label, its text where the label's
  /// starts, as the expansion tooltips of lists sit; kept in the window.
  TooltipPositionDelegate _underLabel(BuildContext context) {
    final theme = TooltipTheme.of(context);
    final direction = Directionality.of(context);
    final inset =
        (theme.margin?.resolve(direction).left ?? 0) +
        (theme.padding?.resolve(direction).left ?? 0);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    // On the screen's pixels, as AppTooltip.placeOnPixels puts a tip.
    double onPixel(double v) => (v * ratio).roundToDouble() / ratio;
    return (place) {
      final below = positionDependentBox(
        size: place.overlaySize,
        childSize: place.tooltipSize,
        target: place.target,
        verticalOffset: place.verticalOffset,
        preferBelow: place.preferBelow,
      );
      final start = place.target.dx - place.targetSize.width / 2 - inset;
      final room = place.overlaySize.width - place.tooltipSize.width;
      return Offset(
        onPixel(start.clamp(0, math.max(0, room)).toDouble()),
        onPixel(below.dy),
      );
    };
  }

  void _hideFullLabel() {
    _tipWait?.cancel();
    if (_tipping) setState(() => _tipping = false);
  }

  void _onFocusChange(bool focused) {
    // A row given the focus by a click on its visible part, or by code,
    // comes wholly into view, as a list scrolls to its selected row.
    if (focused) {
      context.findRenderObject()?.showOnScreen(
        duration: context.motion(AppMotion.short),
        curve: Curves.easeOutCubic,
      );
    }
    // The action button shows while the row holds the focus.
    if (widget.action != null) setState(() {});
    // The keyboard's focus only: a click already hovers the row.
    if (focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      _showFullLabel();
    } else if (!_hovered) {
      _hideFullLabel();
    }
  }

  /// A click or a ⌘J hint: the row takes the focus first (see
  /// [AppNavItem.focusOnTap]), then acts, so a window it opens returns the
  /// focus to the right place.
  void _activate() {
    if (widget.focusOnTap) _focus.requestFocus();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.metrics;
    final selection = metrics.navSelection;
    // The list's own focus scope: true while any row of it has the focus.
    final listFocused = Focus.maybeOf(context)?.hasFocus ?? false;
    final emphasized =
        widget.selected && selection == AppNavSelection.tint && listFocused;
    final background = widget.selected
        ? (emphasized ? colors.selectionAccent : colors.selectionMuted)
        : _hovered && metrics.navHover
        ? colors.hoverFill
        : null;
    final ink = emphasized
        ? colors.onSelection
        : widget.accent
        ? colors.accent
        : context.colors.onSurface;
    final label = Text(
      widget.label,
      key: _label,
      style: context.text.bodyMedium?.copyWith(color: ink),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final iconColor = emphasized
        ? colors.onSelection
        : widget.accent
        ? colors.accent
        : widget.navigation && metrics.style == AppPlatformStyle.macos
        ? colors.accent
        : metrics.style == AppPlatformStyle.macos
        ? colors.textMuted
        : context.colors.onSurface;
    final chevron = widget.expanded == null
        ? null
        : Icon(
            widget.expanded! ? AppIcons.chevronDown : AppIcons.chevronRight,
            size: AppIconSize.sm,
            color: emphasized ? colors.onSelection : colors.textFaint,
          );

    // The same row folded or not: the icon keeps its place on the
    // sidebar's icon axis, so nothing shifts when the rail opens or closes.
    final Widget row = Row(
      children: [
        if (!widget.compact) SizedBox(width: widget.depth * metrics.navIndent),
        if (chevron != null && (widget.icon == null || _hovered))
          GestureDetector(
            onTap: widget.onToggle,
            behavior: HitTestBehavior.opaque,
            // Same box as a leading icon, so labels of items with and
            // without a chevron start at the same x.
            child: SizedBox(
              width: AppIconSize.md,
              child: Center(child: chevron),
            ),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: AppIconSize.md, color: iconColor),
        if (!widget.compact) ...[
          if (chevron != null || widget.icon != null)
            SizedBox(width: metrics.navLabelGap),
          Expanded(
            child: Stack(
              children: [
                switch (widget.trailing) {
                  null => label,
                  // The label keeps its width; the trailing text yields.
                  final trailing => AppLabelRow(
                    label: label,
                    trailing: trailing,
                  ),
                },
                // Last, so its coming and going moves no other child; the
                // label it covers takes the pointer.
                if (_tipping)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Tooltip(
                        key: _tip,
                        message: widget.tooltip ?? widget.label,
                        excludeFromSemantics: true,
                        positionDelegate: _underLabel(context),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.value case final value?) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              value,
              style: context.text.labelSmall?.copyWith(
                color: emphasized ? colors.onSelection : colors.textFaint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              maxLines: 1,
            ),
          ],
          if (widget.badge != null) ...[
            const SizedBox(width: AppSpacing.sm),
            _Badge(widget.badge!, emphasized: emphasized),
          ],
          if (widget.shortcut != null) ...[
            const SizedBox(width: AppSpacing.sm),
            AppKeyCap(widget.shortcut!),
          ],
          if (widget.action case final action?)
            // Always in the tree, shown or not, so a hover never remounts
            // the row's subtree.
            Visibility(
              visible: _hovered || widget.selected || _focus.hasFocus,
              maintainState: true,
              maintainAnimation: true,
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: _ActionButton(action, emphasized: emphasized),
              ),
            ),
        ],
      ],
    );

    final gap = metrics.navItemGap / 2;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: gap),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        child: MouseRegion(
          onEnter: (_) {
            setState(() => _hovered = true);
            _showFullLabel();
          },
          onExit: (_) {
            setState(() => _hovered = false);
            if (!_focus.hasFocus) _hideFullLabel();
          },
          child: GestureDetector(
            onSecondaryTap: widget.onSecondaryTap,
            onTertiaryTapUp: widget.onMiddleTap == null
                ? null
                : (_) => widget.onMiddleTap!(),
            child: HintTarget(
              onActivate: widget.onTap == null ? null : _activate,
              onActivateAlt: widget.onAltTap,
              child: InkWell(
                focusNode: _focus,
                autofocus: widget.autofocus,
                onFocusChange: _onFocusChange,
                onTap: widget.onTap == null ? null : _activate,
                borderRadius: BorderRadius.circular(metrics.radius.row),
                mouseCursor: SystemMouseCursors.basic,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: _RowFace(
                  selected: widget.selected,
                  emphasized: emphasized,
                  background: background,
                  compactLabel: widget.compact ? widget.label : null,
                  child: row,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a row shows under the pointer's and the keys' handling: its fill,
/// the focus ring, Fluent's selection pill, and in the collapsed rail the
/// label as a tooltip ([compactLabel]).
class _RowFace extends StatelessWidget {
  const _RowFace({
    required this.selected,
    required this.emphasized,
    required this.background,
    required this.compactLabel,
    required this.child,
  });

  final bool selected;

  /// On the accent: the row is its own focus mark.
  final bool emphasized;
  final Color? background;
  final String? compactLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.metrics;
    final radius = BorderRadius.circular(metrics.radius.row);
    return FocusRing(
      radius: metrics.radius.row,
      // A source list's accent row is its focus mark; a ring around it
      // would say the same thing twice.
      decorate: !emphasized,
      child: Container(
        height: AppNavItem._heightOf(context),
        padding: EdgeInsets.symmetric(horizontal: metrics.navRowPadding),
        decoration: BoxDecoration(color: background, borderRadius: radius),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: [
            if (selected && metrics.navSelection == AppNavSelection.indicator)
              Positioned(
                left: -metrics.navRowPadding,
                child: Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
            switch (compactLabel) {
              final label? => Tooltip(
                positionDelegate: AppTooltip.placeOnPixels(context),
                message: label,
                child: child,
              ),
              null => child,
            },
          ],
        ),
      ),
    );
  }
}

/// [AppNavAction]'s button: a square a little lower than the row, filled
/// on hover as toolbar buttons are.
class _ActionButton extends StatefulWidget {
  const _ActionButton(this.action, {required this.emphasized});

  final AppNavAction action;

  /// On the accent row: light ink and fills.
  final bool emphasized;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _press() {
    final box = context.findRenderObject()! as RenderBox;
    widget.action.onPressed(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final side = AppNavItem._heightOf(context) - 2 * AppSpacing.xs;
    final fill = !_hovered && !_pressed
        ? null
        : widget.emphasized
        ? colors.onSelection.withValues(alpha: _pressed ? 0.3 : 0.2)
        : _pressed
        ? colors.pressedFill
        : colors.hoverFill;
    return AppTooltip(
      message: widget.action.tooltip,
      child: Semantics(
        button: true,
        label: widget.action.tooltip,
        child: HintTarget(
          onActivate: _press,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() {
              _hovered = false;
              _pressed = false;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: () {
                setState(() => _pressed = false);
                _press();
              },
              child: Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(
                    context.metrics.radius.control,
                  ),
                ),
                child: Icon(
                  widget.action.icon,
                  size: AppIconSize.sm,
                  color: widget.emphasized
                      ? colors.onSelection
                      : colors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A count after the label: a quiet capsule on macOS and GNOME, Fluent's
/// accent InfoBadge on Windows.
class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.emphasized});

  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final windows = context.metrics.style == AppPlatformStyle.windows;
    final fill = windows
        ? colors.accent
        : emphasized
        ? colors.onSelection.withValues(alpha: 0.25)
        : colors.selectionFill;
    final ink = windows
        ? colors.onAccent
        : emphasized
        ? colors.onSelection
        : colors.textMuted;
    // No alignment on the box: it would stretch the capsule to the row's
    // height. A short count centres in the minimum width instead.
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        text,
        style: context.text.labelMedium?.copyWith(color: ink),
        textAlign: TextAlign.center,
        maxLines: 1,
      ),
    );
  }
}
