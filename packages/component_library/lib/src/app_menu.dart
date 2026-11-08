import 'dart:async';

import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'app_key_cap.dart';
import 'app_label_row.dart';
import 'focus_ring.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_icon_size.dart';
import 'theme/tokens/app_sizes.dart';
import 'theme/tokens/app_spacing.dart';
import 'theme/hairlines.dart';
import 'pixel_snap.dart';
import 'app_divider.dart';

/// Floating panel for context menus, autocompletion and the slash menu, in
/// the platform's menu shape: NSMenu's light plate and soft shadow, a
/// Fluent flyout, a libadwaita popover.
class AppMenuPanel extends StatelessWidget {
  const AppMenuPanel({
    required this.children,
    this.width = 300,
    this.maxHeight,
    this.footer,
    super.key,
  });

  final List<Widget> children;

  /// Stays under the items while they scroll ([AppMenuFooter]).
  final Widget? footer;

  /// A fixed width; `null` sizes the panel to its widest item (label and
  /// shortcut whole) between [AppSizes.menuMinWidth] and
  /// [AppSizes.menuMaxWidth], as native menus are.
  final double? width;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final width = this.width;
    final panel = Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        constraints: BoxConstraints(
          minWidth: width == null ? AppSizes.menuMinWidth : 0,
          maxWidth: width ?? AppSizes.menuMaxWidth,
          maxHeight: maxHeight ?? double.infinity,
        ),
        decoration: plate(context),
        clipBehavior: Clip.antiAlias,
        child: PixelSnap(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The inset is the plate's, outside the scroll: a row scrolled
              // to the edge stops short of it, as it does at rest.
              Flexible(
                child: Padding(
                  padding: EdgeInsets.all(menuPadding(context)),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ),
              ?footer,
            ],
          ),
        ),
      ),
    );
    // A few items: their intrinsic width is cheap to measure.
    return width == null ? IntrinsicWidth(child: panel) : panel;
  }

  /// The menu's plate: its fill, a hairline edge and the floating shadow.
  /// Other bars that float over content (the PDF selection bar) wear it
  /// too, so they read as menus. In light themes the fill is a shade off
  /// white, so the edge is darker than a divider and a tight shadow under
  /// it keeps the plate off a white page. The shadow follows what lies
  /// under the plate: [backdrop] when that is not the theme's own (a dark
  /// bar on a white PDF page).
  /// [radius] rounds it as other plates are (a card, a picker); a menu's
  /// by default. On macOS the edge is a window's ([AppWindowBorder.macos]).
  static ShapeDecoration plate(
    BuildContext context, {
    Brightness? backdrop,
    double? radius,
  }) {
    final dark = context.isDark;
    final darkBackdrop =
        (backdrop ?? context.theme.brightness) == Brightness.dark;
    final corner = radius ?? context.metrics.radius.menu;
    return ShapeDecoration(
      color: menuBackground(context),
      shape: context.metrics.style == AppPlatformStyle.macos
          ? AppWindowBorder.macos(radius: corner, dark: dark)
          : AppRoundedRectangleBorder(
              borderRadius: BorderRadius.circular(corner),
              insetFill: true,
              side: BorderSide(
                color: dark
                    ? context.appColors.line
                    : Colors.black.withValues(alpha: 0.18),
              ),
            ),
      shadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: darkBackdrop ? 0.4 : 0.12),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: darkBackdrop ? 0.5 : 0.24),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  /// A menu's fill: the window chrome tone on macOS (NSMenu is a shade off
  /// white), the content surface elsewhere.
  static Color menuBackground(BuildContext context) =>
      context.metrics.menuHighlightAccent
      ? context.appColors.windowChrome
      : context.colors.surface;

  /// Inset of the items from the menu's edge.
  static double menuPadding(BuildContext context) => context.metrics.menuInset;
}

/// A readout or a mode's keys floating over content on the menus' plate
/// ([AppMenuPanel.plate]): an image's zoom, a PDF mark's place among its
/// page's, the keys of a picture being resized.
class AppPlate extends StatelessWidget {
  const AppPlate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: AppMenuPanel.plate(context),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: child,
    ),
  );
}

/// Scrolls the menu row under [row] into view the shortest way once it is
/// laid out: the keys moved the cursor there. The first row of a group
/// brings its [caption] along, so a cursor back on the top row shows the
/// menu's top, not a row against its edge.
void revealMenuRow(GlobalKey row, {GlobalKey? caption}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final target = row.currentContext;
    if (target == null || !target.mounted) return;
    final top = caption?.currentContext;
    // Each policy scrolls one way only; together they move the least.
    for (final (context, policy) in [
      (target, ScrollPositionAlignmentPolicy.keepVisibleAtEnd),
      (
        top != null && top.mounted ? top : target,
        ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ),
    ]) {
      unawaited(Scrollable.ensureVisible(context, alignmentPolicy: policy));
    }
  });
}

/// One row of a menu. [selected] is the keyboard cursor; [shortcut] shows
/// the chord on the right as plain text, as native menus do.
///
/// The highlighted row (pointer or keyboard) takes the accent with light
/// text on macOS and a subtle fill elsewhere.
class AppMenuItem extends StatefulWidget {
  const AppMenuItem({
    required this.label,
    this.onTap,
    this.leading,
    this.trailing,
    this.shortcut,
    this.selected = false,
    this.danger = false,
    this.enabled = true,
    this.checked,
    this.mixed = false,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;
  final String? shortcut;
  final bool selected;
  final bool danger;
  final bool enabled;

  /// A check mark before the label when `true`; room for one when `false`.
  final bool? checked;

  /// With [checked] `false`: a dash in the check's place, for an option
  /// that is on for some of the items and off for others (NSMenu's mixed
  /// state).
  final bool mixed;

  @override
  State<AppMenuItem> createState() => _AppMenuItemState();
}

class _AppMenuItemState extends State<AppMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.metrics;
    final lit = widget.enabled && (widget.selected || _hovered);
    final accentLit = lit && metrics.menuHighlightAccent;
    final foreground = !widget.enabled
        ? colors.textFaint
        : accentLit
        ? colors.onSelection
        : widget.danger
        ? colors.danger
        : context.colors.onSurface;
    final secondary = accentLit ? colors.onSelectionMuted : colors.textMuted;
    final label = Text(
      widget.label,
      style: context.text.bodyMedium?.copyWith(color: foreground),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final fill = !lit
        ? null
        : accentLit
        ? colors.selectionAccent
        : colors.hoverFill;
    final radius = BorderRadius.circular(metrics.radius.menuItem);
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: Container(
            constraints: BoxConstraints(minHeight: metrics.menuItemHeight),
            margin: metrics.menuItemMargin,
            // The check mark's column starts a little before an unchecked
            // label would (NSMenu: the mark 6 in, the labels 20).
            padding: EdgeInsetsDirectional.only(
              start:
                  metrics.menuItemPadding -
                  (widget.checked != null ? metrics.menuCheckPull : 0),
              end: metrics.menuItemPadding,
              top: AppSpacing.xxs,
              bottom: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(color: fill, borderRadius: radius),
            child: Row(
              children: [
                if (widget.checked != null)
                  SizedBox(
                    width: metrics.menuCheckWidth,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: widget.checked!
                          ? Icon(
                              AppIcons.check,
                              size: AppIconSize.sm,
                              color: foreground,
                            )
                          : widget.mixed
                          ? Icon(
                              AppIcons.minus,
                              size: AppIconSize.sm,
                              color: foreground,
                            )
                          : null,
                    ),
                  ),
                if (widget.leading != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(
                      size: AppIconSize.md,
                      color: foreground,
                    ),
                    child: SizedBox(
                      width: 20,
                      // On the accent a coloured glyph (a card separator)
                      // turns to the label's colour, as a template image
                      // does in a native menu, so it stays readable.
                      child: accentLit
                          ? ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                foreground,
                                BlendMode.srcIn,
                              ),
                              child: widget.leading,
                            )
                          : widget.leading,
                    ),
                  ),
                  SizedBox(width: metrics.menuIconGap),
                ],
                Expanded(
                  child: switch (widget.trailing) {
                    null => label,
                    // The label keeps its width; a long path after it
                    // yields, not the label.
                    final trailing => AppLabelRow(
                      label: label,
                      trailing: DefaultTextStyle.merge(
                        style: context.text.bodySmall?.copyWith(
                          color: secondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: trailing,
                      ),
                    ),
                  },
                ),
                if (widget.shortcut?.isNotEmpty ?? false) ...[
                  SizedBox(width: metrics.menuShortcutGap),
                  AppShortcutLabel(widget.shortcut!, color: secondary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A section label inside a menu, in the platform's small bold heading.
class AppMenuHeader extends StatelessWidget {
  const AppMenuHeader(this.text, {this.leadingInset = 0, super.key});

  final String text;

  /// Room before the text, so it lines up with the items' labels past
  /// their check column.
  final double leadingInset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      context.metrics.menuItemMargin.left +
          context.metrics.menuItemPadding +
          leadingInset,
      AppSpacing.sm,
      AppSpacing.sm,
      AppSpacing.xxs,
    ),
    child: Text(
      text,
      style: context.text.labelSmall?.copyWith(
        color: context.appColors.textMuted,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

class AppMenuDivider extends StatelessWidget {
  const AppMenuDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: context.metrics.menuSeparatorSpace,
    ),
    child: AppDivider(height: 1, color: context.appColors.line),
  );
}

/// Footer line with key hints: `↑↓ select · ↩ open · Esc close`.
class AppMenuFooter extends StatelessWidget {
  const AppMenuFooter({required this.hints, super.key});

  /// Pairs of key label and description.
  final List<(String, String)> hints;

  @override
  Widget build(BuildContext context) {
    final faint = context.text.bodySmall?.copyWith(
      color: context.appColors.textFaint,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: AppBorder(top: BorderSide(color: context.appColors.line)),
      ),
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.xs,
        children: [
          for (final (keyLabel, text) in hints)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppKeyCap(keyLabel),
                const SizedBox(width: AppSpacing.xs),
                Text(text, style: faint),
              ],
            ),
        ],
      ),
    );
  }
}

/// A keyboard-focusable wrapper used by menus that manage their own cursor.
class AppMenuFocusScope extends StatelessWidget {
  const AppMenuFocusScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FocusRing(decorate: false, child: child);
}
