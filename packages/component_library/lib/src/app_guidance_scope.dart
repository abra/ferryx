import 'package:flutter/widgets.dart';

/// Localized descriptions supplied by the host, independent of app commands.
@immutable
class AppGuidanceLabels {
  const AppGuidanceLabels({
    required this.navigate,
    required this.choose,
    required this.dismiss,
    required this.clear,
    required this.nextControl,
    required this.previousControl,
    required this.toggle,
    required this.adjust,
    required this.activate,
  });

  final String navigate;
  final String choose;
  final String dismiss;
  final String clear;
  final String nextControl;
  final String previousControl;
  final String toggle;
  final String adjust;
  final String activate;
}

/// Shared guidance copy and visibility, captured with themes by popup routes.
/// It describes existing interactions; it does not install key handlers.
class AppGuidanceScope extends InheritedTheme {
  const AppGuidanceScope({
    required this.labels,
    required super.child,
    this.enabled = true,
    super.key,
  });

  final AppGuidanceLabels labels;
  final bool enabled;

  static AppGuidanceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppGuidanceScope>();

  @override
  bool updateShouldNotify(AppGuidanceScope oldWidget) =>
      enabled != oldWidget.enabled || labels != oldWidget.labels;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      AppGuidanceScope(labels: labels, enabled: enabled, child: child);
}
