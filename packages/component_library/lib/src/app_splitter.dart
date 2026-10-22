import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_key_hints.dart';
import 'app_menu.dart';
import 'hints/hint_registry.dart';
import 'theme/app_typography.dart';
import 'theme/app_platform_style.dart';
import 'theme/tokens/app_motion.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_sizes.dart';
import 'theme/tokens/app_spacing.dart';

/// What a key asks of an [AppSplitter]; the owner decides what it means for
/// its panel (a width, a share of the panes, folding to the rail).
enum AppSplitterAction {
  /// ← and →: one small step of the edge.
  left,
  right,

  /// ⇧← and ⇧→: one large step.
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
/// between two panes, so neither loses its edge to the strip).
enum AppSplitterLine { start, center, end }

/// A panel's movable edge: a thin strip the pointer drags and the keyboard
/// takes. Focused (by a chord or its ⌘J label) it lights its line and shows
/// a card beside it with [title], [value] and the keys of [hints]; every
/// key becomes an [AppSplitterAction] for [onAction].
///
/// The strip stays out of Tab traversal (its owner gives the focus), and ↑
/// and ↓ are kept so they never carry the focus out of the edge by
/// accident.
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
    super.key,
  });

  final FocusNode focusNode;

  /// What the edge sizes ("Sidebar width"); also its semantics label.
  final String title;

  /// The size now ("240 pt", "Folded").
  final String value;
  final List<AppKeyHint> hints;
  final ValueChanged<AppSplitterAction> onAction;
  final VoidCallback onDragStart;

  /// Horizontal pointer movement since the last update, in logical pixels.
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  /// The card sits beside the line, over the panel that is not being
  /// sized: before a [AppSplitterLine.start] line, after the others.
  final AppSplitterLine line;

  @override
  State<AppSplitter> createState() => _AppSplitterState();
}

class _AppSplitterState extends State<AppSplitter> {
  final _link = LayerLink();
  final _card = OverlayPortalController();
  bool _hovered = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(AppSplitter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      _card.show();
    } else {
      _card.hide();
    }
    setState(() {});
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
    final action = switch (key) {
      LogicalKeyboardKey.arrowLeft =>
        shift ? AppSplitterAction.farLeft : AppSplitterAction.left,
      LogicalKeyboardKey.arrowRight =>
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
      // ↑/↓ would move the focus out of the edge; nothing else is ours.
      return key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown
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
    if (mounted) setState(() => _dragging = false);
    widget.onDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    final lit =
        _dragging ||
        focused ||
        (_hovered && context.metrics.style != AppPlatformStyle.macos);
    final start = widget.line == AppSplitterLine.start;
    return OverlayPortal(
      controller: _card,
      overlayChildBuilder: (context) => Align(
        alignment: AlignmentDirectional.topStart,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: start ? Alignment.centerLeft : Alignment.centerRight,
          followerAnchor: start ? Alignment.centerRight : Alignment.centerLeft,
          offset: Offset(start ? -AppSpacing.md : AppSpacing.md, 0),
          child: _SplitterCard(
            title: widget.title,
            value: widget.value,
            hints: widget.hints,
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: Semantics(
          label: widget.title,
          value: widget.value,
          focusable: true,
          focused: focused,
          child: HintTarget(
            onActivate: widget.focusNode.requestFocus,
            child: Focus(
              focusNode: widget.focusNode,
              onKeyEvent: _onKey,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) {
                    setState(() => _dragging = true);
                    widget.onDragStart();
                  },
                  onHorizontalDragUpdate: (details) =>
                      widget.onDragUpdate(details.delta.dx),
                  onHorizontalDragEnd: (_) => _endDrag(),
                  onHorizontalDragCancel: _endDrag,
                  child: SizedBox(
                    width: AppSizes.resizeHandleWidth,
                    child: Align(
                      alignment: switch (widget.line) {
                        AppSplitterLine.start => Alignment.centerLeft,
                        AppSplitterLine.center => Alignment.center,
                        AppSplitterLine.end => Alignment.centerRight,
                      },
                      child: AnimatedOpacity(
                        duration: context.motion(AppMotion.quick),
                        opacity: lit ? 1 : 0,
                        child: Container(
                          width: 2,
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
  });

  final String title;
  final String value;
  final List<AppKeyHint> hints;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: context.text.bodySmall?.weight(FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  value,
                  style: context.text.titleSmall
                      ?.weight(FontWeight.w600)
                      .copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AppKeyHints(hints),
          ],
        ),
      ),
    ),
  );
}
