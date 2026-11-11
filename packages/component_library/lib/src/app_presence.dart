import 'package:flutter/widgets.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_motion.dart';

/// Fades an optional surface in and out, optionally revealing its extent.
/// Closing content stops accepting input immediately and is removed after
/// the exit. A reversal continues from the current position.
///
/// Use [maintainState] for live views that must survive hiding. For a view
/// moved between hosts with a GlobalKey, set [retainOnExit] to false: the old
/// host must release it as soon as its [child] becomes null.
class AppPresence extends StatefulWidget {
  const AppPresence({
    required this.child,
    this.visible = true,
    this.resize = false,
    this.axis = Axis.vertical,
    this.alignment = Alignment.topLeft,
    this.maintainState = false,
    this.retainOnExit = true,
    this.animateInitially = false,
    super.key,
  });

  final Widget? child;
  final bool visible;
  final bool resize;
  final Axis axis;
  final AlignmentGeometry alignment;
  final bool maintainState;
  final bool retainOnExit;
  final bool animateInitially;

  @override
  State<AppPresence> createState() => _AppPresenceState();
}

class _AppPresenceState extends State<AppPresence>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: _visible && !widget.animateInitially ? 1 : 0,
  )..addStatusListener(_onStatus);
  late final _progress = _controller.drive(CurveTween(curve: AppMotion.curve));
  Widget? _content;
  bool _hasShown = false;

  bool get _visible => widget.visible && widget.child != null;

  @override
  void initState() {
    super.initState();
    _content = widget.child;
    _hasShown = _visible;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller
      ..duration = context.motion(AppMotion.short)
      ..reverseDuration = context.motion(AppMotion.quick);
    _animate();
  }

  @override
  void didUpdateWidget(AppPresence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child != null || !widget.retainOnExit) _content = widget.child;
    _hasShown |= _visible;
    _animate();
  }

  void _animate() {
    if (context.reduceMotion) {
      _controller.value = _visible ? 1 : 0;
    } else if (_visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() {
        if (widget.child == null) _content = null;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final present =
        _visible ||
        !_controller.isDismissed ||
        (widget.maintainState && _hasShown && widget.child != null);
    final body = Offstage(
      offstage: !_visible && _controller.isDismissed,
      child: TickerMode(
        enabled: _visible,
        child: IgnorePointer(
          ignoring: !_visible,
          child: ExcludeFocus(
            excluding: !_visible,
            child: ExcludeSemantics(
              excluding: !_visible,
              child: FadeTransition(
                opacity: _progress,
                child: present ? _content : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    return widget.resize
        ? SizeTransition(
            sizeFactor: _progress,
            axis: widget.axis,
            alignment: widget.alignment,
            child: body,
          )
        : body;
  }
}
