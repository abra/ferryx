import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_menu.dart';
import 'popup_focus.dart';
import 'app_transitions.dart';
import 'window_decor.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_motion.dart';
import 'theme/tokens/app_spacing.dart';

/// One line of [showAppMenu].
sealed class AppMenuEntry<T> {
  const AppMenuEntry();
}

/// A choosable item; picking it resolves the menu to [value].
final class AppMenuAction<T> extends AppMenuEntry<T> {
  const AppMenuAction({
    required this.value,
    required this.label,
    this.icon,
    this.leading,
    this.shortcut,
    this.detail,
    this.danger = false,
    this.enabled = true,
    this.checked,
    this.mixed = false,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Shown before the label in place of [icon] (a glyph, a swatch).
  final Widget? leading;

  /// The chord, shown as plain text on the right.
  final String? shortcut;

  /// Secondary text after the label (a volume's free space, a path),
  /// which yields before the label does.
  final String? detail;
  final bool danger;
  final bool enabled;

  /// A check mark before the label (an option that is on).
  final bool? checked;

  /// A dash in the check's place: on for some items, off for others.
  final bool mixed;
}

/// A hairline between groups of items.
final class AppMenuSeparator<T> extends AppMenuEntry<T> {
  const AppMenuSeparator();
}

/// A small heading above a group.
final class AppMenuSection<T> extends AppMenuEntry<T> {
  const AppMenuSection(this.label);

  final String label;
}

/// Where a menu opened from the keyboard (`AppCommand.contextMenu`) opens
/// for the row at [context]: the row's box from a little in from its
/// start, so the menu shows under the row where a right click on its label
/// would have put it, or above the row when there is no room below; never
/// over the row it is for.
Rect keyboardMenuAnchor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Rect.zero;
  final row = box.localToGlobal(Offset.zero) & box.size;
  return Rect.fromLTRB(
    math.min(row.left + AppSpacing.lg, row.right),
    row.top,
    row.right,
    row.bottom,
  );
}

/// Shows a menu of [entries] and resolves to the picked action's value, or
/// `null` when dismissed (a click outside, Esc).
///
/// Opens at [anchor]: a pointer's point (`position & Size.zero`, for a
/// right click) gets the menu at the point, flipped up or left to stay on
/// screen; a box (a button, the row the keys opened it for) gets it under
/// the box, or above it, never over it: a menu taller than the room on
/// either side scrolls. Keyboard: ↑/↓ move, Home/End jump, Enter or Space
/// picks, a letter jumps to the next item starting with it, Esc closes.
/// The pointer moves the highlight too, so mouse and keyboard share one
/// cursor, as native menus do. The menu is as wide as its widest item
/// unless [width] fixes it; [initialValue] lights an item at once.
Future<T?> showAppMenu<T>({
  required BuildContext context,
  required List<AppMenuEntry<T>> entries,
  required Rect anchor,
  double? width,
  T? initialValue,
}) => showAppPopup<T>(
  context: context,
  anchor: anchor,
  builder: (context, close) => AppMenuList<T>(
    entries: entries,
    width: width,
    initialValue: initialValue,
    onPicked: close,
    onDismissed: () => close(null),
  ),
);

/// Shows what [builder] makes in a menu's place: at [anchor] as
/// [showAppMenu] puts a menu, the focus back on the opener once it closes.
/// The content calls `close` with the result, or `null` to dismiss; a click
/// outside dismisses too. For pop-ups that are not a list of items (the
/// colour palette).
Future<T?> showAppPopup<T>({
  required BuildContext context,
  required Rect anchor,
  required Widget Function(BuildContext context, ValueChanged<T?> close)
  builder,
}) => pushReturningFocus(
  context,
  _MenuRoute<T>(
    builder: builder,
    anchor: anchor,
    duration: context.motion(AppMotion.quick),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: Navigator.of(context, rootNavigator: true).context,
    ),
  ),
);

class _MenuRoute<T> extends PopupRoute<T> {
  _MenuRoute({
    required this.builder,
    required this.anchor,
    required this.duration,
    required this.barrierLabel,
    required this.capturedThemes,
  });

  final Widget Function(BuildContext context, ValueChanged<T?> close) builder;
  final Rect anchor;
  final Duration duration;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => capturedThemes.wrap(
    CustomSingleChildLayout(
      // The window's buttons stay over every route: a menu keeps the top
      // row they sit in clear, as a native one keeps to the screen.
      delegate: _MenuLayout(
        anchor,
        top: WindowDecor.of(context).integrated
            ? math.max(context.metrics.topBarHeight, _MenuLayout._margin)
            : _MenuLayout._margin,
      ),
      child: builder(context, (value) => Navigator.of(context).pop(value)),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => AppSurfaceTransition(animation: animation, slide: false, child: child);
}

/// Puts the menu at the anchor's bottom-left: under a box with a small
/// gap, at a point exactly. It ends at the anchor's right when it would
/// leave the window on the right, and above the anchor when there is no
/// room below; a box is never covered (the menu gets the larger side's
/// height and scrolls), a point may be when neither side has the room.
class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout(this.anchor, {required this.top});

  final Rect anchor;

  /// The highest the menu may reach: the margin, or below the window's
  /// top row when the content draws it.
  final double top;
  static const _margin = AppSpacing.sm;
  static const _gap = AppSpacing.xs;

  bool get _box => anchor.height > 0;
  double get _gapToAnchor => _box ? _gap : 0;

  double _roomBelow(Size window) =>
      window.height - _margin - (anchor.bottom + _gapToAnchor);
  double _roomAbove() => anchor.top - _gapToAnchor - top;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final window = constraints.biggest;
    final loose = BoxConstraints.loose(window).deflate(
      EdgeInsets.fromLTRB(_margin, top, _margin, _margin),
    );
    if (!_box) return loose;
    final room = math.max(_roomBelow(window), _roomAbove());
    return loose.copyWith(
      maxHeight: room.clamp(0, loose.maxHeight).toDouble(),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.left;
    if (x + childSize.width + _margin > size.width) {
      x = anchor.right - childSize.width;
    }
    final below = anchor.bottom + _gapToAnchor;
    final fitsBelow = childSize.height <= _roomBelow(size);
    final y = fitsBelow || (_box && _roomBelow(size) >= _roomAbove())
        ? below
        : anchor.top - _gapToAnchor - childSize.height;
    return Offset(
      x.clamp(_margin, size.width - childSize.width - _margin).toDouble(),
      y
          .clamp(top, math.max(top, size.height - childSize.height - _margin))
          .toDouble(),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout old) =>
      old.anchor != anchor || old.top != top;
}

/// The items of a menu with its keyboard cursor: what [showAppMenu] shows,
/// for a menu that sits in a dialog of its own. ↑/↓ move, Home/End jump,
/// Enter or Space picks, a letter jumps to the next item starting with it,
/// Esc dismisses; the lit item is kept in view when the menu scrolls.
class AppMenuList<T> extends StatefulWidget {
  const AppMenuList({
    required this.entries,
    required this.onPicked,
    required this.onDismissed,
    this.width,
    this.initialValue,
    super.key,
  });

  final List<AppMenuEntry<T>> entries;
  final ValueChanged<T> onPicked;
  final VoidCallback onDismissed;

  /// The action lit when the menu opens (a pop-up button's current choice),
  /// as native pop-ups open; otherwise nothing is lit until a key or the
  /// pointer moves.
  final T? initialValue;

  /// See [AppMenuPanel.width].
  final double? width;

  @override
  State<AppMenuList<T>> createState() => _AppMenuListState<T>();
}

class _AppMenuListState<T> extends State<AppMenuList<T>> {
  /// Index into the entries of the highlighted action, or -1.
  int _highlight = -1;

  /// Keys of the rows the keyboard has lit, to scroll them into view.
  final _rowKeys = <int, GlobalKey>{};

  bool _choosable(int index) {
    final entry = widget.entries[index];
    return entry is AppMenuAction<T> && entry.enabled;
  }

  /// Every item keeps room for a check mark while one can show: on macOS
  /// while an item is checked (NSMenu since macOS 14), elsewhere while one
  /// is an option at all, so the labels stay in line.
  bool _checks(BuildContext context) => widget.entries.any(
    (e) =>
        e is AppMenuAction<T> &&
        (e.mixed ||
            (context.metrics.style == AppPlatformStyle.macos
                ? e.checked ?? false
                : e.checked != null)),
  );

  /// A menu with an icon anywhere keeps one column for it, so the labels
  /// line up; symbols count only where the platform's menus show them.
  bool _icons(BuildContext context) => widget.entries.any(
    (e) =>
        e is AppMenuAction<T> &&
        (e.leading != null || (e.icon != null && context.metrics.menuIcons)),
  );

  /// The highlight the keys set stays while the pointer leaves the menu;
  /// one the pointer set goes with it, as a native menu's does.
  bool _litByKeys = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.entries.indexWhere(
      (entry) =>
          entry is AppMenuAction<T> &&
          entry.enabled &&
          entry.value == widget.initialValue,
    );
    if (widget.initialValue != null && initial >= 0) {
      _highlight = initial;
      _reveal(initial);
    }
  }

  void _light(int index) {
    _litByKeys = true;
    setState(() => _highlight = index);
    _reveal(index);
  }

  /// Keys of the sections' captions, by index.
  final _sectionKeys = <int, GlobalKey>{};

  /// Scrolls row [index] into view; the first row of a section brings its
  /// caption along.
  void _reveal(int index) {
    final row = _rowKeys[index];
    if (row == null) return;
    final before = index - 1;
    revealMenuRow(
      row,
      caption: before >= 0 && widget.entries[before] is AppMenuSection<T>
          ? _sectionKeys[before]
          : null,
    );
  }

  void _move(int delta) {
    final count = widget.entries.length;
    // Nothing lit yet: ↓ starts at the top, ↑ at the bottom.
    var index = _highlight < 0 && delta < 0 ? count : _highlight;
    for (var step = 0; step < count; step++) {
      index = (index + delta) % count;
      if (index < 0) index += count;
      if (_choosable(index)) {
        _light(index);
        return;
      }
    }
  }

  void _jumpTo(int index, int delta) {
    _highlight = index - delta;
    _move(delta);
  }

  void _pick(int index) {
    final entry = widget.entries[index];
    if (entry is AppMenuAction<T> && entry.enabled) {
      widget.onPicked(entry.value);
    }
  }

  /// Type-select: the next item whose label starts with [char].
  void _typeSelect(String char) {
    final needle = char.toLowerCase();
    final count = widget.entries.length;
    for (var step = 1; step <= count; step++) {
      final index = (_highlight + step) % count;
      final entry = widget.entries[index];
      if (entry is AppMenuAction<T> &&
          entry.enabled &&
          entry.label.toLowerCase().startsWith(needle)) {
        _light(index);
        return;
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.home) {
      _jumpTo(0, 1);
    } else if (key == LogicalKeyboardKey.end) {
      _jumpTo(widget.entries.length - 1, -1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (_highlight >= 0) _pick(_highlight);
    } else if (key == LogicalKeyboardKey.escape) {
      widget.onDismissed();
    } else {
      final char = event.character;
      if (char == null || char.trim().isEmpty) return KeyEventResult.ignored;
      _typeSelect(char);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final checks = _checks(context);
    final icons = _icons(context);
    final metrics = context.metrics;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: AppMenuPanel(
          width: widget.width,
          children: [
            for (var i = 0; i < widget.entries.length; i++)
              switch (widget.entries[i]) {
                final AppMenuAction<T> action => MouseRegion(
                  key: _rowKeys.putIfAbsent(i, GlobalKey.new),
                  onEnter: (_) {
                    if (action.enabled) {
                      _litByKeys = false;
                      setState(() => _highlight = i);
                    }
                  },
                  onExit: (_) {
                    if (_highlight == i && !_litByKeys) {
                      setState(() => _highlight = -1);
                    }
                  },
                  child: AppMenuItem(
                    label: action.label,
                    leading:
                        action.leading ??
                        (action.icon != null && metrics.menuIcons
                            ? Icon(action.icon)
                            : icons
                            ? const SizedBox.shrink()
                            : null),
                    shortcut: action.shortcut,
                    trailing: action.detail == null
                        ? null
                        : Text(action.detail!),
                    danger: action.danger,
                    enabled: action.enabled,
                    checked: checks ? (action.checked ?? false) : null,
                    mixed: action.mixed,
                    selected: i == _highlight,
                    onTap: () => _pick(i),
                  ),
                ),
                AppMenuSeparator<T>() => const AppMenuDivider(),
                final AppMenuSection<T> section => AppMenuHeader(
                  section.label,
                  leadingInset: checks
                      ? metrics.menuCheckWidth - metrics.menuCheckPull
                      : 0,
                  key: _sectionKeys.putIfAbsent(i, GlobalKey.new),
                ),
              },
          ],
        ),
      ),
    );
  }
}
