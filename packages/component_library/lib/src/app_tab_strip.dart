import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_context_menu.dart';
import 'app_focus_area.dart';
import 'app_icon_button.dart';
import 'app_icons.dart';
import 'app_tooltip.dart';
import 'focus_ring.dart';
import 'hints/hint_registry.dart';
import 'theme/app_platform_style.dart';
import 'theme/app_typography.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_icon_size.dart';
import 'theme/tokens/app_motion.dart';
import 'theme/tokens/app_sizes.dart';
import 'theme/tokens/app_spacing.dart';
import 'theme/hairlines.dart';
import 'app_divider.dart';

/// One tab of an [AppTabStrip].
@immutable
class AppTab {
  const AppTab({
    required this.id,
    required this.label,
    required this.icon,
    this.tooltip,
    this.pinned = false,
  });

  /// Stable across reorders: the tab keeps its state and its focus.
  final Object id;
  final String label;
  final IconData icon;

  /// What the tab says on hover and focus; the label when `null`. The
  /// whole path of a folder tab, so two "src" tabs tell apart.
  final String? tooltip;

  /// Kept at the start, without a close button.
  final bool pinned;
}

/// A row of tabs, the platform's way: Finder's window tabs on macOS 15
/// (equal segments filling the bar, lines between them, the active one
/// open to the bar above, the close button at the start on hover), rounded
/// tabs on the bar on macOS 26, Explorer's on Windows (the active tab joins
/// the page, the close button at the end), libadwaita's on GNOME (rounded
/// tabs, titles centred).
///
/// Tabs share the width between [minTabWidth] and [maxTabWidth], scaled
/// with the text; more than fit scroll sideways, the active one always in
/// view, and a ⌄ button lists them all. Each tab is focusable as a row of a
/// list: ←/→ (Home, End) move between them, Enter or Space selects one;
/// [wrapTab] adds the keys of the caller (a menu key, a close chord). A
/// click selects without taking the focus from the page; ⌘J labels every
/// tab, ⇧ with the label gives it the focus instead. A drag reorders.
class AppTabStrip extends StatefulWidget {
  const AppTabStrip({
    required this.tabs,
    required this.active,
    required this.onSelect,
    required this.onClose,
    required this.onReorder,
    required this.onMenu,
    required this.onNewTab,
    required this.closeTooltip,
    required this.newTabTooltip,
    required this.listTooltip,
    this.newTabShortcut,
    this.wrapTab,
    this.onLeave,
    super.key,
  });

  /// A pinned tab is as wide as its name, up to this (scaled with the
  /// text).
  static const double maxPinnedWidth = 150;

  final List<AppTab> tabs;
  final int active;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;

  /// [from] is to go to [to], both indices of [tabs] as they are.
  final void Function(int from, int to) onReorder;

  /// The tab's menu at [anchor]: a right click's point, or the tab.
  final void Function(int index, Rect anchor) onMenu;
  final VoidCallback onNewTab;
  final String closeTooltip;
  final String newTabTooltip;
  final String? newTabShortcut;
  final String listTooltip;

  /// Wraps each tab (its keys, its menu's handler), given its index.
  final Widget Function(int index, Widget tab)? wrapTab;

  /// Esc on a focused tab: the focus goes back to the page.
  final VoidCallback? onLeave;

  /// The strip's height at the text size in [context]: the platform's tab
  /// height and a margin, growing with the label's line.
  static double heightOf(BuildContext context) {
    final spec = _specOf(context);
    return _tabHeight(context) + spec.top + spec.bottom;
  }

  /// Whether the strip draws the edge under the bar above it, the active
  /// tab open to that bar in its colour (macOS 15's window tabs): the bar
  /// above then draws no bottom edge of its own.
  static bool joinsBarAbove(BuildContext context) => _specOf(context).flat;

  static double _tabHeight(BuildContext context) {
    final spec = _specOf(context);
    final line =
        MediaQuery.textScalerOf(context).scale(spec.font.fontSize!) *
        spec.font.height!;
    return math.max(spec.height, line + 2 * AppSpacing.xs);
  }

  /// The strip's geometry on each desktop. macOS 15: NSWindow's tab bar
  /// as Finder has it, measured beside AppKit: tabs 28 high filling the
  /// bar edge to edge, a line under them, 1 pt lines between them, titles
  /// centred. macOS 26: rounded tabs a regular control high, room around
  /// for the 3 pt focus ring. Windows: TabView's tabs 32 high on an 8 px
  /// top margin, standing on the page, 100–240 wide. GNOME: AdwTabBar's
  /// 34-high tabs in a 47 bar, 5 apart, at least 126 wide, titles centred
  /// in the body face.
  static _Spec _specOf(BuildContext context) {
    final metrics = context.metrics;
    final text = context.text;
    return switch (metrics.style) {
      AppPlatformStyle.macos when metrics.generation == MacGeneration.sequoia =>
        (
          height: 28.0,
          top: 0.0,
          // The line under the tabs.
          bottom: 1.0,
          side: 0.0,
          gap: 0.0,
          minWidth: 120.0,
          maxWidth: double.infinity,
          separatorInset: 0.0,
          centred: true,
          flat: true,
          font: text.labelMedium!,
        ),
      AppPlatformStyle.macos => (
        height: metrics.controlHeight,
        top: 3.5,
        bottom: 3.5,
        side: 3.5,
        gap: 0.0,
        minWidth: 120.0,
        maxWidth: double.infinity,
        separatorInset: 4.0,
        centred: true,
        flat: false,
        font: text.labelMedium!,
      ),
      AppPlatformStyle.windows => (
        height: 32.0,
        top: 8.0,
        bottom: 0.0,
        side: 4.0,
        gap: 0.0,
        minWidth: 100.0,
        maxWidth: 240.0,
        separatorInset: 8.0,
        centred: false,
        flat: false,
        font: text.labelMedium!,
      ),
      AppPlatformStyle.gnome => (
        height: 34.0,
        top: 6.0,
        bottom: 6.0,
        side: 6.0,
        gap: 5.0,
        minWidth: 126.0,
        maxWidth: double.infinity,
        separatorInset: null,
        centred: true,
        flat: false,
        font: text.bodyMedium!,
      ),
    };
  }

  @override
  State<AppTabStrip> createState() => _AppTabStripState();
}

class _AppTabStripState extends State<AppTabStrip> {
  final _scroll = ScrollController();
  final _keys = <Object, GlobalKey>{};

  /// Each tab's focus node, kept by its id so a moved tab keeps its focus.
  final _nodes = <Object, FocusNode>{};
  bool _overflows = false;

  GlobalKey _keyOf(Object id) => _keys.putIfAbsent(id, GlobalKey.new);

  FocusNode _nodeOf(Object id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'tab $id'));

  /// Each tab's width and the room before the first, as last laid out:
  /// every tab has a width of its own, so where one sits is arithmetic,
  /// built or not (a list builds only what is near its view).
  List<double> _widths = const [];
  double _margin = 0;

  /// Scrolls the least that brings tab [index] wholly into view.
  void _reveal(int index, {required bool animate}) {
    if (!_scroll.hasClients || index < 0 || index >= _widths.length) return;
    final position = _scroll.position;
    var start = _margin;
    for (var i = 0; i < index; i++) {
      start += _widths[i];
    }
    final end = start + _widths[index];
    final double target;
    if (start - _margin < position.pixels) {
      target = start - _margin;
    } else if (end + _margin > position.pixels + position.viewportDimension) {
      target = end + _margin - position.viewportDimension;
    } else {
      return;
    }
    final to = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (animate) {
      unawaited(
        position.animateTo(
          to,
          duration: context.motion(AppMotion.short),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      position.jumpTo(to);
    }
  }

  /// The keys along the strip: [to] a tab, by its index, stopping at the
  /// ends. It comes into view at once and takes the focus, the frame after
  /// when it was not built yet.
  void _focusTab(int to) {
    if (to < 0 || to >= widget.tabs.length) return;
    _reveal(to, animate: false);
    final node = _nodeOf(widget.tabs[to].id);
    if (node.context != null) {
      node.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  @override
  void didUpdateWidget(AppTabStrip old) {
    super.didUpdateWidget(old);
    final ids = {for (final tab in widget.tabs) tab.id};
    _keys.removeWhere((id, _) => !ids.contains(id));
    // A closed tab's node goes once its widget has.
    final gone = [
      for (final MapEntry(:key, :value) in _nodes.entries)
        if (!ids.contains(key)) value,
    ];
    _nodes.removeWhere((id, _) => !ids.contains(id));
    if (gone.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in gone) {
          node.dispose();
        }
      });
    }
    if (old.active != widget.active || old.tabs.length != widget.tabs.length) {
      _revealActive();
    }
  }

  @override
  void initState() {
    super.initState();
    _revealActive();
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// The strip's width at its last layout: a narrower strip (a split, a
  /// resized window) keeps its scroll, which may leave the active tab past
  /// its end, so it comes back into view, without an animation, as nothing
  /// else of a resize moves smoothly.
  double? _width;

  void _onWidth(double width) {
    final was = _width;
    _width = width;
    if (was == null || was == width) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(widget.active, animate: false);
    });
  }

  /// The active tab comes into view after this frame's layout.
  void _revealActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(widget.active, animate: true);
    });
  }

  /// The ⌄ button comes or goes after this frame; the strip it narrows
  /// brings the active tab into view again.
  void _setOverflow(bool overflows) {
    if (overflows == _overflows) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _overflows = overflows);
      _revealActive();
    });
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final colors = context.appColors;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final spec = AppTabStrip._specOf(context);
    // Up to a whole pixel, as the tabs' widths are below.
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final margin = (spec.side * ratio).ceilToDouble() / ratio;
    final tabHeight = AppTabStrip._tabHeight(context);
    final flat = spec.flat ? _FlatColors.of(context) : null;
    // Sunken, so the active tab (the page's colour) stands out of it as
    // Safari's, Explorer's and libadwaita's do.
    final background = flat?.bar ?? colors.surfaceSunken;
    return Container(
      height: AppTabStrip.heightOf(context),
      padding: flat != null
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: background,
        border: AppBorder(
          bottom: BorderSide(color: flat?.bottom ?? colors.line),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The edge under the bar above, under the tabs: the active tab
          // covers it and opens into that bar.
          if (flat != null) _FlatEdge(colors: flat),
          Row(
            spacing: flat != null ? 0 : metrics.toolbarSpacing,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _onWidth(constraints.maxWidth);
                    // A pinned tab is as wide as its name, the others share
                    // what is left; each in whole pixels, so the tabs (each on
                    // a layer of the list's own) and their lines land on them.
                    final pinned = [
                      for (final tab in widget.tabs)
                        if (tab.pinned)
                          (_pinnedWidth(context, tab, scale) * ratio)
                                  .ceilToDouble() /
                              ratio,
                    ];
                    final rest = widget.tabs.length - pinned.length;
                    final gaps = spec.gap * (widget.tabs.length - 1);
                    final room =
                        constraints.maxWidth -
                        2 * margin -
                        gaps -
                        pinned.fold(0.0, (sum, w) => sum + w);
                    final width = rest == 0
                        ? 0.0
                        : ((room / rest).clamp(
                                        spec.minWidth * scale,
                                        spec.maxWidth * scale,
                                      ) *
                                      ratio)
                                  .floorToDouble() /
                              ratio;
                    var nextPinned = 0;
                    // Each tab's extent along the strip: its width and the gap
                    // after it.
                    _widths = [
                      for (final (i, tab) in widget.tabs.indexed)
                        (tab.pinned ? pinned[nextPinned++] : width) +
                            (i < widget.tabs.length - 1 ? spec.gap : 0),
                    ];
                    _margin = margin;
                    final total = _widths.fold(2 * margin, (sum, w) => sum + w);
                    _setOverflow(total > constraints.maxWidth + 0.5);
                    return ReorderableListView.builder(
                      scrollController: _scroll,
                      scrollDirection: Axis.horizontal,
                      // The room the focus ring of an end tab needs.
                      padding: EdgeInsets.symmetric(horizontal: margin),
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, _, _) => Material(
                        type: MaterialType.transparency,
                        child: child,
                      ),
                      itemCount: widget.tabs.length,
                      // The index it lands at, the moved tab taken out first.
                      onReorderItem: (from, to) {
                        if (to != from) widget.onReorder(from, to);
                      },
                      itemBuilder: (context, index) {
                        final tab = widget.tabs[index];
                        Widget item = _Tab(
                          key: _keyOf(tab.id),
                          focusNode: _nodeOf(tab.id),
                          onStep: (by) => _focusTab(switch (by) {
                            _toStart => 0,
                            _toEnd => widget.tabs.length - 1,
                            _ => index + by,
                          }),
                          tab: tab,
                          active: index == widget.active,
                          height: tabHeight,
                          width:
                              _widths[index] -
                              (index < widget.tabs.length - 1 ? spec.gap : 0),
                          spec: spec,
                          // No line before the first; beside the active one
                          // only between flat tabs.
                          separator:
                              index > 0 &&
                              (flat != null ||
                                  index != widget.active &&
                                      index - 1 != widget.active),
                          onSelect: () => widget.onSelect(index),
                          onClose: () => widget.onClose(index),
                          onMenu: (anchor) => widget.onMenu(index, anchor),
                          onLeave: widget.onLeave,
                          closeTooltip: widget.closeTooltip,
                        );
                        item = widget.wrapTab?.call(index, item) ?? item;
                        return ReorderableDragStartListener(
                          key: ValueKey(tab.id),
                          index: index,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: flat != null ? 0 : spec.top,
                              bottom: flat != null ? 0 : spec.bottom,
                              right: index < widget.tabs.length - 1
                                  ? spec.gap
                                  : 0,
                            ),
                            child: item,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (_overflows)
                _ButtonCell(
                  flat: flat,
                  child: AppIconButton(
                    icon: AppIcons.chevronDown,
                    tooltip: widget.listTooltip,
                    onPressed: _showList,
                  ),
                ),
              _ButtonCell(
                flat: flat,
                child: AppIconButton(
                  icon: AppIcons.add,
                  tooltip: widget.newTabTooltip,
                  shortcut: widget.newTabShortcut,
                  onPressed: widget.onNewTab,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A pinned tab's width: its icon, name and pin, up to
  /// [AppTabStrip.maxPinnedWidth].
  double _pinnedWidth(BuildContext context, AppTab tab, double scale) {
    final painter = TextPainter(
      text: TextSpan(
        text: tab.label,
        style: AppTabStrip._specOf(context).font,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    const chrome =
        2 * AppSpacing.sm + 2 * AppIconSize.sm + 2 * _tabGap + 2 * 1 + 1;
    return (chrome + width).clamp(
      AppTabStrip._specOf(context).minWidth * scale * 0.4,
      AppTabStrip.maxPinnedWidth * scale,
    );
  }

  /// Every tab, the active one checked, under the ⌄ button.
  Future<void> _showList() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset(box.size.width, box.size.height));
    final choice = await showAppMenu<int>(
      context: context,
      anchor: anchor & Size.zero,
      entries: [
        for (final (index, tab) in widget.tabs.indexed)
          AppMenuAction(
            value: index,
            label: tab.label,
            icon: tab.icon,
            checked: index == widget.active,
          ),
      ],
    );
    if (choice != null && mounted) widget.onSelect(choice);
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.tab,
    required this.active,
    required this.height,
    required this.width,
    required this.separator,
    required this.spec,
    required this.onSelect,
    required this.onClose,
    required this.onMenu,
    required this.closeTooltip,
    required this.focusNode,
    required this.onStep,
    this.onLeave,
    super.key,
  });

  final AppTab tab;
  final FocusNode focusNode;

  /// ← →: one place either way (−1, 1); Home and End: [_toStart], [_toEnd].
  final ValueChanged<int> onStep;
  final bool active;
  final double height;

  /// Its share of the strip, or a pinned tab's own.
  final double width;

  /// A line at its start, between two tabs that are not active (macOS).
  final bool separator;
  final _Spec spec;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(Rect anchor) onMenu;
  final VoidCallback? onLeave;
  final String closeTooltip;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  FocusNode get _focus => widget.focusNode;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final colors = context.appColors;
    final style = metrics.style;
    final tab = widget.tab;
    final active = widget.active;
    final ink = active ? context.colors.onSurface : colors.textMuted;
    final text = widget.spec.font.copyWith(color: ink);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // A narrow tab gives its close button's room to its name: only the
    // active one keeps it there, as browsers do.
    final roomy = widget.width >= _roomyWidth * scale;
    // Fluent shows every tab's close button; libadwaita the active one's
    // and the hovered one's; Safari and Finder only the hovered tab's.
    final showClose =
        !tab.pinned &&
        switch (style) {
          AppPlatformStyle.windows => true,
          AppPlatformStyle.gnome => active || (roomy && _hovered),
          AppPlatformStyle.macos => _hovered && (active || roomy),
        };
    final closeButton = AppTooltip(
      message: widget.closeTooltip,
      child: _CloseButton(onTap: widget.onClose, ink: ink),
    );
    final label = Text(
      tab.label,
      style: style == AppPlatformStyle.gnome && active
          ? text.weight(FontWeight.w600)
          : text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final pin = tab.pinned
        ? Icon(AppIcons.pin, size: AppIconSize.sm, color: colors.textFaint)
        : null;
    final icon = Icon(tab.icon, size: AppIconSize.sm, color: ink);
    final flat = widget.spec.flat ? _FlatColors.of(context) : null;
    final fill = active
        ? switch (style) {
            // A window tab is the bar above's own colour.
            AppPlatformStyle.macos when flat != null => colors.windowChrome,
            AppPlatformStyle.macos ||
            AppPlatformStyle.windows => context.colors.surface,
            AppPlatformStyle.gnome => colors.selectionFill,
          }
        : _hovered
        ? colors.hoverFill
        : null;
    final radius = metrics.radius.control;
    // TabView's selected tab: top corners of an overlay's radius.
    final shape = flat != null
        ? BorderRadius.zero
        : style == AppPlatformStyle.windows
        ? BorderRadius.vertical(top: Radius.circular(metrics.radius.popover))
        : BorderRadius.circular(radius);
    // A centred name takes its icon along, as Safari's and AdwTabBar's do.
    final centred = widget.spec.centred;
    final name = Expanded(
      child: centred
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: _tabGap,
              children: [
                icon,
                Flexible(child: label),
              ],
            )
          : label,
    );
    // The close button's room is held while it may show, so a hover never
    // moves the name: at the start on macOS, as Safari has it, at the end
    // elsewhere.
    final close = !tab.pinned && (active || roomy)
        ? Visibility(
            visible: showClose,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: closeButton,
          )
        : null;
    final children = style == AppPlatformStyle.macos
        ? <Widget>[?close, if (!centred) icon, name, ?pin]
        : <Widget>[if (!centred) icon, name, ?pin, ?close];
    Widget body = Container(
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      foregroundDecoration: active
          ? BoxDecoration(
              border: AppBorder(
                bottom: BorderSide(
                  color: AppFocusArea.activeOf(context)
                      ? colors.accent
                      : colors.controlBorder,
                  width: AppSizes.focusBarHeight,
                ),
              ),
            )
          : null,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: shape,
        boxShadow: active && style == AppPlatformStyle.macos && flat == null
            ? [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: context.isDark ? 0.5 : 0.12,
                  ),
                  blurRadius: 1.5,
                ),
              ]
            : null,
      ),
      child: Row(spacing: _tabGap, children: children),
    );
    // Flat tabs touch: the ring goes inside.
    body = flat != null
        ? Stack(
            children: [
              body,
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(metrics.focusRingWidth + 1),
                  child: FocusRing(radius: radius, child: const SizedBox()),
                ),
              ),
            ],
          )
        : FocusRing(radius: radius, child: body);
    final separatorInset = widget.spec.separatorInset;
    final separator = separatorInset != null && widget.separator;
    return Semantics(
      button: true,
      selected: active,
      label: tab.label,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(1),
          SingleActivator(LogicalKeyboardKey.home): _StepIntent(_toStart),
          SingleActivator(LogicalKeyboardKey.end): _StepIntent(_toEnd),
          SingleActivator(LogicalKeyboardKey.escape): _LeaveIntent(),
        },
        child: Actions(
          actions: {
            _StepIntent: CallbackAction<_StepIntent>(
              onInvoke: (intent) => widget.onStep(intent.by),
            ),
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => widget.onSelect(),
            ),
            _LeaveIntent: CallbackAction<_LeaveIntent>(
              onInvoke: (_) => widget.onLeave?.call(),
            ),
          },
          // The tooltip outside the tab's focus, so the tab's focus shows it
          // and the ring below reads the tab's.
          child: AppTooltip(
            message: tab.tooltip ?? tab.label,
            child: Focus(
              focusNode: _focus,
              child: HintTarget(
                onActivate: widget.onSelect,
                onActivateAlt: _focus.requestFocus,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hovered = true),
                  onExit: (_) => setState(() => _hovered = false),
                  child: Listener(
                    onPointerDown: (event) {
                      if (event.buttons == kMiddleMouseButton && !tab.pinned) {
                        widget.onClose();
                      }
                    },
                    child: GestureDetector(
                      onTap: widget.onSelect,
                      onSecondaryTapUp: (details) =>
                          widget.onMenu(details.globalPosition & Size.zero),
                      child: Container(
                        width: widget.width,
                        padding: EdgeInsets.symmetric(
                          horizontal: flat != null ? 0 : 1,
                        ),
                        // A line at the start: the bar's height between
                        // flat tabs, short elsewhere, as TabView's stand
                        // off the bar's edges.
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            body,
                            if (separator)
                              Positioned(
                                left: flat != null ? 0 : -1,
                                top: separatorInset,
                                bottom: separatorInset,
                                child: SizedBox(
                                  width: 1,
                                  child: AppRule(
                                    axis: Axis.vertical,
                                    color: flat?.line ?? colors.line,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Between a tab's icon, name and pin.
const _tabGap = AppSpacing.xs + 2;

/// Below this share of the strip (scaled with the text) only the active
/// tab shows its close button.
const _roomyWidth = 130.0;

/// [_StepIntent]'s steps to the first and the last tab.
const _toStart = -1 << 20;
const _toEnd = 1 << 20;

class _StepIntent extends Intent {
  const _StepIntent(this.by);

  final int by;
}

class _LeaveIntent extends Intent {
  const _LeaveIntent();
}

/// See [AppTabStrip._specOf].
typedef _Spec = ({
  double height,
  double top,
  double bottom,
  double side,
  double gap,
  double minWidth,
  double maxWidth,
  double? separatorInset,
  bool centred,

  /// macOS 15's window tabs: edge to edge, the active one open to the bar
  /// above ([_FlatColors]).
  bool flat,
  TextStyle font,
});

/// Flat window tabs keep their native geometry and use the same blue-gray
/// surface roles as the panel toolbar. The shallow edge separates inactive
/// tabs without introducing an unrelated gray palette.
@immutable
class _FlatColors {
  const _FlatColors({
    required this.bar,
    required this.edge,
    required this.shade,
    required this.line,
    required this.cellLine,
    required this.bottom,
  });

  factory _FlatColors.of(BuildContext context) {
    final colors = context.appColors;
    final bar = context.isDark ? context.colors.surface : colors.surfaceSunken;
    return _FlatColors(
      bar: bar,
      edge: colors.controlBorder,
      shade: context.isDark
          ? const []
          : [
              Color.alphaBlend(
                colors.controlBorder.withValues(alpha: 0.3),
                bar,
              ),
            ],
      line: colors.line,
      cellLine: colors.controlBorder,
      bottom: colors.line,
    );
  }

  /// Under the inactive tabs and the buttons.
  final Color bar;

  /// The bar's top edge, and the rows of shade under it.
  final Color edge;
  final List<Color> shade;

  /// Between two tabs.
  final Color line;

  /// Before the ⌄ and + cells.
  final Color cellLine;

  /// Under the bar.
  final Color bottom;
}

/// A flat strip's top edge with its shade, along the whole bar.
class _FlatEdge extends StatelessWidget {
  const _FlatEdge({required this.colors});

  final _FlatColors colors;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppRule(color: colors.edge),
        for (final shade in colors.shade)
          SizedBox(height: 1, child: ColoredBox(color: shade)),
      ],
    ),
  );
}

/// The ⌄ or + button: on a flat strip in a cell of its own after a line,
/// as Finder's +; as it is on the others.
class _ButtonCell extends StatelessWidget {
  const _ButtonCell({required this.flat, required this.child});

  final _FlatColors? flat;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final flat = this.flat;
    if (flat == null) return child;
    return Container(
      width: context.metrics.iconButtonSize.width,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: AppBorder(left: BorderSide(color: flat.cellLine)),
      ),
      child: child,
    );
  }
}

/// A tab's close button: a small square that fills under the pointer and
/// while pressed, as Safari's does, so the glyph is not the whole target.
class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onTap, required this.ink});

  final VoidCallback onTap;
  final Color ink;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: AppIconSize.lg,
            height: AppIconSize.lg,
            decoration: BoxDecoration(
              color: _pressed
                  ? colors.pressedFill
                  : _hovered
                  ? colors.hoverFill
                  : null,
              borderRadius: BorderRadius.circular(
                context.metrics.radius.chip,
              ),
            ),
            child: Icon(
              AppIcons.close,
              size: AppIconSize.sm,
              color: widget.ink,
            ),
          ),
        ),
      ),
    );
  }
}
