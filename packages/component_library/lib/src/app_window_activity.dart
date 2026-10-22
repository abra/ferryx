import 'package:flutter/widgets.dart';

/// Whether the app's window is the active one, the one the keys go to.
/// macOS greys the emphasized selection and the focus bar of a window
/// that is not key; Flutter reports the app inactive once its window
/// resigns that. One at the app's root; read through [of].
class AppWindowActivity extends StatefulWidget {
  const AppWindowActivity({required this.child, super.key});

  final Widget child;

  /// True outside any [AppWindowActivity] (tests, a bare widget).
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WindowActive>()?.active ??
      true;

  @override
  State<AppWindowActivity> createState() => _AppWindowActivityState();
}

class _AppWindowActivityState extends State<AppWindowActivity>
    with WidgetsBindingObserver {
  late bool _active = _isActive(WidgetsBinding.instance.lifecycleState);

  /// Before the first frame the state is unknown or detached: the window
  /// about to show counts as active.
  static bool _isActive(AppLifecycleState? state) => switch (state) {
    null || AppLifecycleState.resumed || AppLifecycleState.detached => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = _isActive(state);
    if (active != _active) setState(() => _active = active);
  }

  @override
  Widget build(BuildContext context) =>
      _WindowActive(active: _active, child: widget.child);
}

class _WindowActive extends InheritedWidget {
  const _WindowActive({required this.active, required super.child});

  final bool active;

  @override
  bool updateShouldNotify(_WindowActive oldWidget) =>
      active != oldWidget.active;
}
