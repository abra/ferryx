import 'package:flutter/material.dart';

import 'theme/tokens/app_spacing.dart';

/// The platform's tooltip plate over the point [at] of [child], while
/// [visible]: what a keyboard cursor in a chart shows for the lit value,
/// the same words a hover tooltip shows. One plate for the whole chart, so
/// a year of cells costs one overlay, not one each.
///
/// [at] is relative to [child]'s size (as an [Alignment]), so the chart
/// needs no layout callback to place it: charts sit in intrinsic layouts.
class AppValueTip extends StatefulWidget {
  const AppValueTip({
    required this.message,
    required this.visible,
    required this.child,
    this.at = Alignment.topCenter,
    super.key,
  });

  final String message;

  /// Where the plate points: the top centre of the lit part.
  final Alignment at;
  final bool visible;
  final Widget child;

  @override
  State<AppValueTip> createState() => _AppValueTipState();
}

class _AppValueTipState extends State<AppValueTip> {
  final _link = LayerLink();
  final _plate = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    // Shown for good, and empty while not [AppValueTip.visible]: a chart
    // rebuilds as its cursor moves, mostly inside a layout pass, where the
    // portal may not be toggled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _plate.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = TooltipTheme.of(context);
    return OverlayPortal(
      controller: _plate,
      overlayChildBuilder: (context) => !widget.visible
          ? const SizedBox.shrink()
          : Align(
              alignment: AlignmentDirectional.topStart,
              child: CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: widget.at,
                followerAnchor: Alignment.bottomCenter,
                offset: const Offset(0, -AppSpacing.xs),
                child: IgnorePointer(
                  child: Container(
                    padding:
                        theme.padding ??
                        const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                    decoration: theme.decoration,
                    child: Text(
                      widget.message,
                      style: theme.textStyle,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
            ),
      child: CompositedTransformTarget(link: _link, child: widget.child),
    );
  }
}
