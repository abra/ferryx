import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_context_menu.dart';
import 'app_divider.dart';
import 'app_focus_area.dart';
import 'focus_ring.dart';
import 'hints/hint_registry.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/hairlines.dart';
import 'theme/tokens/app_spacing.dart';

/// Where the keys and the pointer are in an [AppRowList]: the lead row
/// (the arrows move from it), the selected rows, and the anchor a ⇧-run
/// grows from. Rows are indexes into the list as shown; when the rows
/// change, [reset] starts over.
class AppRowListController extends ChangeNotifier {
  AppRowListController([this._count = 0]);

  int _count;
  int _lead = -1;
  int _anchor = -1;
  final Set<int> _selected = {};

  int get count => _count;
  int get lead => _lead;

  /// The selected rows, unordered.
  Set<int> get selected => Set.unmodifiable(_selected);

  bool isSelected(int index) => _selected.contains(index);

  /// The rows a command works on: the selection in row order, else the
  /// lead row; none in an empty list.
  List<int> get targets {
    if (_selected.isNotEmpty) return _selected.toList()..sort();
    return _lead >= 0 && _lead < _count ? [_lead] : const [];
  }

  /// [count] rows now; the lead and the selection stay where they still
  /// fit (rows added at the end keep them all).
  set count(int value) {
    if (value == _count) return;
    _count = value;
    _selected.removeWhere((i) => i >= value);
    if (_lead >= value) _lead = value - 1;
    if (_anchor >= value) _anchor = _lead;
    notifyListeners();
  }

  /// Other rows: nothing selected and no lead; the first key or click
  /// picks a row.
  void reset(int count) {
    _count = count;
    _selected.clear();
    _lead = -1;
    _anchor = -1;
    notifyListeners();
  }

  /// The lead to [index]: alone selected, or with [extend] the rows from
  /// the anchor to it (as ⇧ with the arrows or a click does).
  void moveTo(int index, {bool extend = false}) {
    if (_count == 0) return;
    final target = index.clamp(0, _count - 1);
    if (extend && _anchor >= 0) {
      _selected
        ..clear()
        ..addAll(_range(_anchor, target));
    } else {
      _selected
        ..clear()
        ..add(target);
      _anchor = target;
    }
    _lead = target;
    notifyListeners();
  }

  /// The lead [delta] rows on; from no lead, the first row.
  void moveBy(int delta, {bool extend = false}) =>
      moveTo(_lead < 0 ? 0 : _lead + delta, extend: extend);

  /// A click with the primary modifier: [index] in or out of the
  /// selection, the lead on it.
  void toggle(int index) {
    if (index < 0 || index >= _count) return;
    if (!_selected.remove(index)) _selected.add(index);
    _lead = index;
    _anchor = index;
    notifyListeners();
  }

  void selectAll() {
    if (_count == 0) return;
    _selected
      ..clear()
      ..addAll(Iterable<int>.generate(_count));
    notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  static Iterable<int> _range(int a, int b) sync* {
    final low = math.min(a, b);
    final high = math.max(a, b);
    for (var i = low; i <= high; i++) {
      yield i;
    }
  }
}

/// How a row of an [AppRowList] is drawn.
@immutable
class AppRowState {
  const AppRowState({
    required this.selected,
    required this.lead,
    required this.emphasized,
  });

  final bool selected;

  /// The row the keys move from.
  final bool lead;

  /// Selected in the list the keys are in, in the active window: its text
  /// goes on the accent ([ink], [muted]).
  final bool emphasized;

  /// The colour of the row's text.
  Color ink(BuildContext context) =>
      emphasized ? context.appColors.onAccent : context.colors.onSurface;

  /// The colour of the row's secondary text.
  Color muted(BuildContext context) => emphasized
      ? context.appColors.onAccentMuted
      : context.appColors.textMuted;
}

typedef AppRowBuilder = Widget Function(
  BuildContext context,
  int index,
  AppRowState state,
);

/// A long list of rows the keys walk, in a sunken frame under an optional
/// [header]: ↑ ↓ Home End PageUp PageDown move the lead row and select
/// it, with ⇧ they select the run from the anchor; a click selects a row,
/// with the primary modifier it flips one, with ⇧ it extends the run; a
/// double click activates; a right click opens [onMenu]. Built lazily at
/// one [itemExtent], so a hundred thousand rows cost what the visible
/// ones do. [onKey] sees each key first (a feature's Space or arrows).
///
/// The list takes the focus as one control (a ring around its frame in
/// keyboard mode); its selection takes the accent while it has the focus
/// and greys elsewhere, as a macOS table's does.
class AppRowList extends StatefulWidget {
  const AppRowList({
    required this.controller,
    required this.itemExtent,
    required this.itemBuilder,
    this.header,
    this.empty,
    this.focusNode,
    this.autofocus = false,
    this.onActivate,
    this.onMenu,
    this.onKey,
    this.semanticLabel,
    super.key,
  });

  final AppRowListController controller;
  final double itemExtent;
  final AppRowBuilder itemBuilder;

  /// Column titles above the rows, outside the scrolling.
  final Widget? header;

  /// Shown in place of the rows when there are none.
  final Widget? empty;
  final FocusNode? focusNode;
  final bool autofocus;

  /// A double click on a row.
  final ValueChanged<int>? onActivate;

  /// A right click (at its point) or the keys (by the lead row) ask for
  /// the menu of a row.
  final void Function(int index, Rect anchor)? onMenu;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final String? semanticLabel;

  /// A row's extent for text of [style]: the platform's list row, taller
  /// when the text is scaled up.
  static double extentOf(BuildContext context, {TextStyle? style}) {
    final text = style ?? context.text.bodyMedium!;
    final line =
        MediaQuery.textScalerOf(context).scale(text.fontSize!) *
        (text.height ?? 1.3);
    return math.max(context.metrics.listRowHeight, line + 2 * AppSpacing.xs);
  }

  @override
  State<AppRowList> createState() => AppRowListState();
}

class AppRowListState extends State<AppRowList> {
  final _scroll = ScrollController();
  late FocusNode _focus = widget.focusNode ?? FocusNode(debugLabel: 'rows');
  final _leadKey = GlobalKey(debugLabel: 'lead row');
  int _lastLead = -1;
  DateTime? _lastTap;
  int? _lastTapIndex;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(AppRowList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      if (oldWidget.focusNode == null) _focus.dispose();
      _focus = widget.focusNode ?? FocusNode(debugLabel: 'rows');
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    if (widget.focusNode == null) _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final lead = widget.controller.lead;
    if (lead != _lastLead) {
      _lastLead = lead;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  /// Scrolls just enough to show the lead row.
  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final lead = widget.controller.lead;
    if (lead < 0) return;
    final top = lead * widget.itemExtent;
    final bottom = top + widget.itemExtent;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top.clamp(0, position.maxScrollExtent));
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (bottom - position.viewportDimension).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  /// Rows a page moves by: what fits, less one.
  int get _page {
    if (!_scroll.hasClients) return 10;
    return math.max(
      1,
      (_scroll.position.viewportDimension / widget.itemExtent).floor() - 1,
    );
  }

  /// Where a menu for the lead row opens from the keys: by the row when it
  /// is built, else by the list's top.
  Rect leadAnchor() {
    final row = _leadKey.currentContext;
    if (row != null) return keyboardMenuAnchor(row);
    return keyboardMenuAnchor(context);
  }

  /// Opens the lead row's menu, as the menu key does.
  void openMenu() {
    final lead = widget.controller.lead;
    if (lead >= 0) widget.onMenu?.call(lead, leadAnchor());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final custom = widget.onKey?.call(event);
    if (custom != null && custom != KeyEventResult.ignored) return custom;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final extend = keyboard.isShiftPressed;
    final controller = widget.controller;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        controller.moveBy(1, extend: extend);
      case LogicalKeyboardKey.arrowUp:
        controller.moveBy(-1, extend: extend);
      case LogicalKeyboardKey.pageDown:
        controller.moveBy(_page, extend: extend);
      case LogicalKeyboardKey.pageUp:
        controller.moveBy(-_page, extend: extend);
      case LogicalKeyboardKey.home:
        controller.moveTo(0, extend: extend);
      case LogicalKeyboardKey.end:
        controller.moveTo(controller.count - 1, extend: extend);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  bool get _primaryHeld {
    final keyboard = HardwareKeyboard.instance;
    return context.metrics.style == AppPlatformStyle.macos
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
  }

  void _tap(int index) {
    _focus.requestFocus();
    final now = DateTime.now();
    final last = _lastTap;
    final controller = widget.controller;
    if (_lastTapIndex == index &&
        last != null &&
        now.difference(last) <= kDoubleTapTimeout) {
      _lastTap = null;
      widget.onActivate?.call(index);
      return;
    }
    _lastTap = now;
    _lastTapIndex = index;
    if (_primaryHeld) {
      controller.toggle(index);
    } else {
      controller.moveTo(
        index,
        extend: HardwareKeyboard.instance.isShiftPressed,
      );
    }
  }

  void _secondaryTap(int index, Offset position) {
    _focus.requestFocus();
    if (!widget.controller.isSelected(index)) {
      widget.controller.moveTo(index);
    }
    widget.onMenu?.call(index, position & Size.zero);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = context.metrics.radius.card;
    final controller = widget.controller;
    // The focus inside the area, so the area is the active one while the
    // list has the keys and the selection takes the accent.
    return Semantics(
      label: widget.semanticLabel,
      container: true,
      child: FocusRing(
        focused: _focus.hasFocus,
        radius: radius,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BorderRadius.circular(radius),
            border: AppBorder.all(color: colors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: AppFocusArea(
            child: Focus(
              focusNode: _focus,
              autofocus: widget.autofocus,
              onKeyEvent: _onKey,
              onFocusChange: (_) => setState(() {}),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.header != null) ...[
                    widget.header!,
                    AppRule(color: colors.line),
                  ],
                  Expanded(
                    child: controller.count == 0
                        ? (widget.empty ?? const SizedBox.shrink())
                        : ListView.builder(
                            controller: _scroll,
                            itemExtent: widget.itemExtent,
                            itemCount: controller.count,
                            itemBuilder: (context, index) => _Row(
                              key: index == controller.lead ? _leadKey : null,
                              index: index,
                              selected: controller.isSelected(index),
                              lead: index == controller.lead,
                              focused: _focus.hasFocus,
                              builder: widget.itemBuilder,
                              onTap: _tap,
                              onSecondaryTap: _secondaryTap,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row: the selection's plate, the hover, the hint target, and what
/// the feature draws in it.
class _Row extends StatefulWidget {
  const _Row({
    required this.index,
    required this.selected,
    required this.lead,
    required this.focused,
    required this.builder,
    required this.onTap,
    required this.onSecondaryTap,
    super.key,
  });

  final int index;
  final bool selected;
  final bool lead;
  final bool focused;
  final AppRowBuilder builder;
  final ValueChanged<int> onTap;
  final void Function(int index, Offset position) onSecondaryTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.metrics;
    final emphasized =
        widget.selected && widget.focused && AppFocusArea.activeOf(context);
    final fill = widget.selected
        ? (emphasized ? colors.selectionAccent : colors.selectionMuted)
        : _hovered && metrics.navHover
        ? colors.hoverFill
        : null;
    final state = AppRowState(
      selected: widget.selected,
      lead: widget.lead,
      emphasized: emphasized,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(widget.index),
        onSecondaryTapUp: (details) =>
            widget.onSecondaryTap(widget.index, details.globalPosition),
        child: HintTarget(
          onActivate: () => widget.onTap(widget.index),
          child: Semantics(
            selected: widget.selected,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.rowInset),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(metrics.radius.row),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: widget.builder(context, widget.index, state),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
