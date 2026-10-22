import 'dart:async';

import 'package:flutter/material.dart';

import 'theme/extensions/build_context_ext.dart';

/// Tooltip with an optional shortcut label after the message, in the
/// platform's tooltip plate (the theme's `tooltipTheme`).
///
/// What the pointer shows on hover the keyboard shows on focus: when the
/// focus reaches [child] by a key (the focus ring's mode), the tooltip
/// appears after the same wait and goes when the focus leaves. A click
/// that focuses it shows nothing more than the hover would.
class AppTooltip extends StatefulWidget {
  const AppTooltip({
    required this.message,
    required this.child,
    this.shortcut,
    super.key,
  });

  final String message;
  final String? shortcut;
  final Widget child;

  /// Material's place for a tip, on the screen's pixels: a tip fades in
  /// on a layer of its own, which its hairline edge snaps within. For a
  /// [Tooltip] built directly (`positionDelegate:`).
  static TooltipPositionDelegate placeOnPixels(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return (tip) {
      final at = positionDependentBox(
        size: tip.overlaySize,
        childSize: tip.tooltipSize,
        target: tip.target,
        verticalOffset: tip.verticalOffset,
        preferBelow: tip.preferBelow,
      );
      return Offset(
        (at.dx * ratio).roundToDouble() / ratio,
        (at.dy * ratio).roundToDouble() / ratio,
      );
    };
  }

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  final _tooltip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final shortcut = widget.shortcut;
    final place = AppTooltip.placeOnPixels(context);
    final Widget tooltip;
    if (shortcut == null) {
      tooltip = Tooltip(
        key: _tooltip,
        positionDelegate: place,
        message: widget.message,
        child: widget.child,
      );
    } else {
      final textStyle = TooltipTheme.of(context).textStyle;
      final ink = textStyle?.color ?? context.colors.onSurface;
      tooltip = Tooltip(
        key: _tooltip,
        positionDelegate: place,
        richMessage: TextSpan(
          text: widget.message,
          style: textStyle,
          children: [
            const TextSpan(text: '  '),
            TextSpan(
              text: shortcut,
              style: context.metrics.typeScale.keyCap.copyWith(
                color: ink.withValues(alpha: 0.6),
                fontSize: textStyle?.fontSize,
              ),
            ),
          ],
        ),
        child: widget.child,
      );
    }
    return _FocusTooltip(tooltip: _tooltip, child: tooltip);
  }
}

/// Watches the focus inside [child] and shows [tooltip] for it.
class _FocusTooltip extends StatefulWidget {
  const _FocusTooltip({required this.tooltip, required this.child});

  final GlobalKey<TooltipState> tooltip;
  final Widget child;

  @override
  State<_FocusTooltip> createState() => _FocusTooltipState();
}

class _FocusTooltipState extends State<_FocusTooltip> {
  Timer? _wait;
  bool _shown = false;

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    _wait?.cancel();
    if (!focused) {
      if (_shown) Tooltip.dismissAllToolTips();
      _shown = false;
      return;
    }
    // Only the keyboard's focus: a click on the control already hovers it.
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return;
    }
    final wait = TooltipTheme.of(context).waitDuration ?? Duration.zero;
    _wait = Timer(wait, () {
      if (!mounted) return;
      _shown = widget.tooltip.currentState?.ensureTooltipVisible() ?? false;
    });
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: _onFocusChange,
    child: widget.child,
  );
}
