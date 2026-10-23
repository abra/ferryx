import 'package:flutter/widgets.dart';

/// The app's own look for the chrome that shows it: a macOS alert carries
/// the app's icon above its title, as NSAlert does. Placed above the
/// navigator, so dialogs find it.
class AppIdentity extends InheritedWidget {
  const AppIdentity({required this.icon, required super.child, super.key});

  final ImageProvider icon;

  static ImageProvider? iconOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppIdentity>()?.icon;

  @override
  bool updateShouldNotify(AppIdentity oldWidget) => icon != oldWidget.icon;
}
