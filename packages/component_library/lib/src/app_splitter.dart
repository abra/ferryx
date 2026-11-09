import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart';

import 'app_key_hints.dart';
import 'app_menu.dart';
import 'hints/hint_registry.dart';
import 'theme/app_typography.dart';
import 'theme/tokens/app_motion.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_sizes.dart';
import 'theme/tokens/app_spacing.dart';
import 'pixel_snap.dart';

/// What a key asks of an [AppSplitter]; the owner decides what it means for
/// its panel (a width, a share of the panes, folding to the rail).
enum AppSplitterAction {
  /// ← and →: one small step of the edge (↑ and ↓ on an edge that moves
  /// vertically: `left` is up, toward the start).
  left,
  right,

  /// ⇧← and ⇧→ (⇧↑ and ⇧↓): one large step.
  farLeft,
  farRight,

  /// Home and End: the narrowest and the widest the panel may be.
  narrowest,
  widest,

  /// 0: the panel's default (an even split).
  reset,

  /// ⇥ and ⇧⇥: the next or the previous edge.
  next,
  previous,

  /// ↩ keeps the new width, esc goes back to the width the keys found.
  done,
  cancel,
}

/// Where the strip draws the edge's line: over the border of the panel it
/// sits in ([start], [end]), or across a border it straddles ([center],
/// between two panes, so neither loses its edge to the strip). On an edge
/// that moves vertically, start is the top.
enum AppSplitterLine { start, center, end }

/// A panel's movable edge: a thin strip the pointer drags and the keyboard
/// takes. Hovering, dragging or focusing shows [title] and [value]; focus
/// adds the keys of [hints]. Keys become [AppSplitterAction]s for [onAction].
/// An optional [onReset] adds a labelled button and a double-click action.
///
/// The strip stays out of Tab traversal (its owner gives the focus), and
/// the arrows across the edge's movement are kept so they never carry the
/// focus out of the edge by accident.
///
/// [axis] is the way the edge moves: [Axis.horizontal] between panes side
/// by side (a vertical line, ← and →), [Axis.vertical] between panes one
/// above the other (a horizontal line, ↑ and ↓, its card above it).
class AppSplitter extends StatefulWidget {
  const AppSplitter({
    required this.focusNode,
    required this.title,
    required this.value,
    required this.hints,
    required this.onAction,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.line = AppSplitterLine.end,
    this.axis = Axis.horizontal,
    this.onReset,
    this.resetLabel,
    this.resetHint,
    super.key,
  }) : assert((onReset == null) == (resetLabel == null));

  final FocusNode focusNode;

  /// What the edge sizes ("Sidebar width"); also its semantics label.
  final String title;

  /// The size now ("240 pt", "Folded").
  final String value;
  final List<AppKeyHint> hints;
  final ValueChanged<AppSplitterAction> onAction;
  final VoidCallback onDragStart;

  /// Pointer movement along [axis] since the last update, in logical
  /// pixels.
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  /// The card sits beside the line, over the panel that is not being
  /// sized: before a [AppSplitterLine.start] line, after the others.
  final AppSplitterLine line;
  final Axis axis;
  final VoidCallback? onReset;
  final String? resetLabel;
  final String? resetHint;

  @override
  State<AppSplitter> createState() => _AppSplitterState();
}

class _AppSplitterState extends State<AppSplitter> {
  final _card = OverlayPortalController();
  final _resetFocus = FocusNode(debugLabel: 'splitter reset');
  Timer? _hoverWait;
  Timer? _hideWait;
  bool _hovered = false;
  bool _hoverReady = false;
  bool _overCard = false;
  bool _dragging = false;
  Offset? _pointerPosition;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
    _resetFocus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(AppSplitter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
      _onFocusChange();
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _resetFocus.dispose();
    _hoverWait?.cancel();
    _hideWait?.cancel();
    super.dispose();
  }

  void _onFocusChange() {
    // Focus can move from the strip to its reset button in one transaction.
    scheduleMicrotask(() {
      if (!mounted) return;
      _syncCard();
      setState(() {});
    });
  }

  bool get _showCard =>
      _dragging ||
      widget.focusNode.hasFocus ||
      _resetFocus.hasFocus ||
      _hoverReady ||
      _overCard;

  void _syncCard({bool delayHide = false}) {
    _hideWait?.cancel();
    if (_showCard) {
      _card.show();
    } else if (delayHide) {
      // Leave enough time to cross the gap between the strip and its card.
      _hideWait = Timer(AppMotion.short, () {
        if (mounted && !_showCard) _card.hide();
      });
    } else {
      _card.hide();
    }
  }

  void _hover(bool hovered) {
    _hoverWait?.cancel();
    setState(() {
      _hovered = hovered;
      _hoverReady = false;
    });
    if (hovered) {
      _hoverWait = Timer(
        TooltipTheme.of(context).waitDuration ?? AppMotion.medium,
        () {
          if (!mounted || !_hovered) return;
          setState(() => _hoverReady = true);
          _syncCard();
        },
      );
    } else {
      _syncCard(delayHide: true);
    }
  }

  static const _repeatable = {
    AppSplitterAction.left,
    AppSplitterAction.right,
    AppSplitterAction.farLeft,
    AppSplitterAction.farRight,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab && widget.onReset != null && !shift) {
      _resetFocus.requestFocus();
      return KeyEventResult.handled;
    }
    final vertical = widget.axis == Axis.vertical;
    final back = vertical
        ? LogicalKeyboardKey.arrowUp
        : LogicalKeyboardKey.arrowLeft;
    final forth = vertical
        ? LogicalKeyboardKey.arrowDown
        : LogicalKeyboardKey.arrowRight;
    final across = vertical
        ? [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight]
        : [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown];
    final action = switch (key) {
      _ when key == back =>
        shift ? AppSplitterAction.farLeft : AppSplitterAction.left,
      _ when key == forth =>
        shift ? AppSplitterAction.farRight : AppSplitterAction.right,
      LogicalKeyboardKey.home => AppSplitterAction.narrowest,
      LogicalKeyboardKey.end => AppSplitterAction.widest,
      LogicalKeyboardKey.digit0 ||
      LogicalKeyboardKey.numpad0 => AppSplitterAction.reset,
      LogicalKeyboardKey.tab =>
        shift ? AppSplitterAction.previous : AppSplitterAction.next,
      LogicalKeyboardKey.enter ||
      LogicalKeyboardKey.numpadEnter => AppSplitterAction.done,
      LogicalKeyboardKey.escape => AppSplitterAction.cancel,
      _ => null,
    };
    if (action == null) {
      // The arrows across would move the focus out of the edge; nothing
      // else is ours.
      return across.contains(key)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent && !_repeatable.contains(action)) {
      return KeyEventResult.handled;
    }
    widget.onAction(action);
    return KeyEventResult.handled;
  }

  void _endDrag() {
    if (!_dragging || !mounted) return;
    setState(() => _dragging = false);
    _syncCard(delayHide: true);
    widget.onDragEnd();
  }

  KeyEventResult _onCardKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onAction(AppSplitterAction.done);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        HardwareKeyboard.instance.isShiftPressed) {
      widget.focusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    final lit = _dragging || focused || _hovered;
    final start = widget.line == AppSplitterLine.start;
    final vertical = widget.axis == Axis.vertical;
    void dragStart(Offset position) {
      setState(() {
        _dragging = true;
        _pointerPosition = position;
      });
      _syncCard();
      widget.onDragStart();
    }

    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _card,
      overlayChildBuilder: (context, info) {
        final pointer = _pointerPosition;
        final anchor = focused || pointer == null
            ? Offset.zero & info.childSize
            : vertical
            ? Rect.fromLTWH(pointer.dx, 0, 0, info.childSize.height)
            : Rect.fromLTWH(0, pointer.dy, info.childSize.width, 0);
        return CustomSingleChildLayout(
          delegate: _SplitterCardPosition(
            anchor: MatrixUtils.transformRect(
              info.childPaintTransform,
              anchor,
            ),
            axis: widget.axis,
            before: start,
            ratio: MediaQuery.devicePixelRatioOf(context),
          ),
          child: MouseRegion(
            onEnter: (_) {
              _overCard = true;
              _syncCard();
            },
            onExit: (_) {
              _overCard = false;
              _syncCard(delayHide: true);
            },
            child: IgnorePointer(
              ignoring: _dragging,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onCardKey,
                child: PixelSnap(
                  child: _SplitterCard(
                    title: widget.title,
                    value: widget.value,
                    hints: focused ? widget.hints : const [],
                    resetLabel: _dragging ? null : widget.resetLabel,
                    resetHint: _dragging ? null : widget.resetHint,
                    onReset: widget.onReset,
                    resetFocus: _resetFocus,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: Semantics(
        label: widget.title,
        value: widget.value,
        hint: widget.resetHint,
        focusable: true,
        focused: focused,
        child: HintTarget(
          onActivate: widget.focusNode.requestFocus,
          child: Focus(
            focusNode: widget.focusNode,
            onKeyEvent: _onKey,
            child: MouseRegion(
              cursor: vertical
                  ? SystemMouseCursors.resizeUpDown
                  : SystemMouseCursors.resizeLeftRight,
              onEnter: (event) {
                _pointerPosition = event.localPosition;
                _hover(true);
              },
              onHover: (event) {
                if (!_hoverReady) _pointerPosition = event.localPosition;
              },
              onExit: (_) => _hover(false),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: widget.onReset,
                // Include the first delta when a panel tap also competes.
                dragStartBehavior: DragStartBehavior.down,
                onHorizontalDragStart: vertical
                    ? null
                    : (details) => dragStart(details.localPosition),
                onHorizontalDragUpdate: vertical
                    ? null
                    : (details) {
                        _pointerPosition = details.localPosition;
                        widget.onDragUpdate(details.delta.dx);
                      },
                onHorizontalDragEnd: vertical ? null : (_) => _endDrag(),
                onHorizontalDragCancel: vertical ? null : _endDrag,
                onVerticalDragStart: vertical
                    ? (details) => dragStart(details.localPosition)
                    : null,
                onVerticalDragUpdate: vertical
                    ? (details) {
                        _pointerPosition = details.localPosition;
                        widget.onDragUpdate(details.delta.dy);
                      }
                    : null,
                onVerticalDragEnd: vertical ? (_) => _endDrag() : null,
                onVerticalDragCancel: vertical ? _endDrag : null,
                child: SizedBox(
                  width: vertical ? null : AppSizes.resizeHandleWidth,
                  height: vertical ? AppSizes.resizeHandleWidth : null,
                  child: Align(
                    alignment: switch ((widget.line, vertical)) {
                      (AppSplitterLine.start, false) => Alignment.centerLeft,
                      (AppSplitterLine.end, false) => Alignment.centerRight,
                      (AppSplitterLine.start, true) => Alignment.topCenter,
                      (AppSplitterLine.end, true) => Alignment.bottomCenter,
                      (AppSplitterLine.center, _) => Alignment.center,
                    },
                    child: AnimatedOpacity(
                      duration: context.motion(AppMotion.quick),
                      opacity: lit ? 1 : 0,
                      child: Container(
                        width: vertical ? null : 2,
                        height: vertical ? 2 : null,
                        color: context.colors.primary,
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

/// The card beside a focused edge: what it sizes, the size, the keys.
class _SplitterCard extends StatelessWidget {
  const _SplitterCard({
    required this.title,
    required this.value,
    required this.hints,
    required this.resetFocus,
    this.resetLabel,
    this.resetHint,
    this.onReset,
  });

  final String title;
  final String value;
  final List<AppKeyHint> hints;
  final FocusNode resetFocus;
  final String? resetLabel;
  final String? resetHint;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: AppSizes.splitterBadgeWidth),
    child: Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        decoration: AppMenuPanel.plate(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: context.text.bodySmall?.weight(FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                style: context.text.titleSmall
                    ?.weight(FontWeight.w600)
                    .copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              if (hints.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                AppKeyHints(hints),
              ],
              if (resetHint case final hint?) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(hint, style: context.text.bodySmall),
              ],
              if (resetLabel case final label?) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton(
                    focusNode: resetFocus,
                    onPressed: onReset,
                    child: Text(label),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Place the card beside the edge, flipping and clamping within the overlay.
class _SplitterCardPosition extends SingleChildLayoutDelegate {
  const _SplitterCardPosition({
    required this.anchor,
    required this.axis,
    required this.before,
    required this.ratio,
  });
  final Rect anchor;
  final Axis axis;
  final bool before;
  final double ratio;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(
          AppSizes.splitterBadgeWidth,
          math.max(0, constraints.maxWidth - AppSpacing.md * 2),
        ),
        maxHeight: math.max(0, constraints.maxHeight - AppSpacing.md * 2),
      );
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const gap = AppSpacing.md;
    double clamp(double value, double extent, double child) =>
        value.clamp(gap, math.max(gap, extent - child - gap)).toDouble();
    final double x;
    final double y;
    if (axis == Axis.vertical) {
      x = clamp(
        anchor.center.dx - childSize.width / 2,
        size.width,
        childSize.width,
      );
      final above = anchor.top - childSize.height - gap;
      y = clamp(
        above >= gap ? above : anchor.bottom + gap,
        size.height,
        childSize.height,
      );
    } else {
      final left = anchor.left - childSize.width - gap;
      final right = anchor.right + gap;
      final onLeft = before
          ? left >= gap
          : right + childSize.width + gap > size.width && left >= gap;
      x = clamp(onLeft ? left : right, size.width, childSize.width);
      y = clamp(
        anchor.center.dy - childSize.height / 2,
        size.height,
        childSize.height,
      );
    }
    return Offset((x * ratio).round() / ratio, (y * ratio).round() / ratio);
  }

  @override
  bool shouldRelayout(_SplitterCardPosition old) =>
      old.anchor != anchor ||
      old.axis != axis ||
      old.before != before ||
      old.ratio != ratio;
}
