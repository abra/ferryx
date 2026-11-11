import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'app_divider.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_motion.dart';
import 'theme/tokens/app_sizes.dart';

enum AppSplitPane { first, second }

/// Two persistent panes. Expanding one animates the boundary; dragging the
/// fraction and resizing the window stay immediate. A closing pane is clipped
/// at its previous readable extent rather than laid out at a near-zero width.
class AppSplitView extends StatefulWidget {
  const AppSplitView({
    required this.first,
    required this.second,
    required this.axis,
    required this.fraction,
    required this.handle,
    this.expandedPane,
    super.key,
  });

  final Widget first;
  final Widget second;
  final Axis axis;
  final double fraction;
  final Widget handle;
  final AppSplitPane? expandedPane;

  @override
  State<AppSplitView> createState() => _AppSplitViewState();
}

class _AppSplitViewState extends State<AppSplitView>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, value: 1);
  late final _progress = _controller.drive(CurveTween(curve: AppMotion.curve));
  late double _fromFraction = _targetFraction;
  late double _fromLine = _targetLine;

  double get _targetFraction => switch (widget.expandedPane) {
    AppSplitPane.first => 1,
    AppSplitPane.second => 0,
    null => widget.fraction.clamp(0, 1),
  };
  double get _targetLine => widget.expandedPane == null ? 1 : 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = context.motion(AppMotion.short);
    if (context.reduceMotion) _controller.value = 1;
  }

  @override
  void didUpdateWidget(AppSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expandedPane != widget.expandedPane) {
      final oldFraction = switch (oldWidget.expandedPane) {
        AppSplitPane.first => 1.0,
        AppSplitPane.second => 0.0,
        null => oldWidget.fraction.clamp(0.0, 1.0),
      };
      final oldLine = oldWidget.expandedPane == null ? 1.0 : 0.0;
      _fromFraction += (oldFraction - _fromFraction) * _progress.value;
      _fromLine += (oldLine - _fromLine) * _progress.value;
      _controller.forward(from: 0);
    } else if (oldWidget.fraction != widget.fraction) {
      _fromFraction = _targetFraction;
      _fromLine = _targetLine;
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final horizontal = widget.axis == Axis.horizontal;
        final extent = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final line = _fromLine + (_targetLine - _fromLine) * _progress.value;
        final fraction =
            _fromFraction + (_targetFraction - _fromFraction) * _progress.value;
        final first = ((extent - line) * fraction).roundToDouble();
        final second = math.max(0.0, extent - first - line);
        final normalFirst = ((extent - 1) * widget.fraction).roundToDouble();
        final children = [widget.first, widget.second];
        final sizes = [first, second];
        final normalSizes = [
          normalFirst,
          math.max(0.0, extent - 1 - normalFirst),
        ];
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < 2; i++)
              Positioned(
                left: horizontal ? (i == 0 ? 0 : first + line) : 0,
                top: horizontal ? 0 : (i == 0 ? 0 : first + line),
                width: horizontal ? sizes[i] : null,
                height: horizontal ? null : sizes[i],
                right: horizontal ? null : 0,
                bottom: horizontal ? 0 : null,
                child: _SplitPane(
                  axis: widget.axis,
                  extent: sizes[i],
                  layoutExtent: math.max(sizes[i], normalSizes[i]),
                  enabled:
                      widget.expandedPane == null ||
                      widget.expandedPane!.index == i,
                  child: children[i],
                ),
              ),
            if (line > 0)
              Positioned(
                left: horizontal ? first : 0,
                top: horizontal ? 0 : first,
                width: horizontal ? line : null,
                height: horizontal ? null : line,
                right: horizontal ? null : 0,
                bottom: horizontal ? 0 : null,
                child: AppRule(
                  axis: horizontal ? Axis.vertical : Axis.horizontal,
                ),
              ),
            if (widget.expandedPane == null)
              Positioned(
                left: horizontal ? first - AppSizes.resizeHandleWidth / 2 : 0,
                top: horizontal ? 0 : first - AppSizes.resizeHandleWidth / 2,
                right: horizontal ? null : 0,
                bottom: horizontal ? 0 : null,
                width: horizontal ? AppSizes.resizeHandleWidth + line : null,
                height: horizontal ? null : AppSizes.resizeHandleWidth + line,
                child: widget.handle,
              ),
          ],
        );
      },
    ),
  );
}

class _SplitPane extends StatelessWidget {
  const _SplitPane({
    required this.axis,
    required this.extent,
    required this.layoutExtent,
    required this.enabled,
    required this.child,
  });

  final Axis axis;
  final double extent;
  final double layoutExtent;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: !enabled,
    child: ExcludeSemantics(
      excluding: !enabled,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Offstage(
          offstage: extent <= 0,
          child: TickerMode(
            enabled: extent > 0,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: axis == Axis.horizontal ? layoutExtent : null,
                maxWidth: axis == Axis.horizontal ? layoutExtent : null,
                minHeight: axis == Axis.vertical ? layoutExtent : null,
                maxHeight: axis == Axis.vertical ? layoutExtent : null,
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
