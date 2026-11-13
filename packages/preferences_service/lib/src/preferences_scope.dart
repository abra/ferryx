import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'preferences.dart';
import 'preferences_service.dart';

/// Rebuilds dependents whenever the [PreferencesService] snapshot changes.
///
/// Read with [PreferencesScope.of] (rebuilds on any change) or the typed
/// helpers such as [themeModeOf] when only one aspect matters.
class PreferencesScope extends StatefulWidget {
  const PreferencesScope({
    required this.service,
    required this.child,
    super.key,
  });

  final PreferencesService service;
  final Widget child;

  static Preferences of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_PreferencesInherited>()!
      .preferences;

  static PreferencesService serviceOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_PreferencesInherited>()!.service;

  static ThemeMode themeModeOf(BuildContext context) =>
      switch (of(context).themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  static Locale? localeOf(BuildContext context) {
    final code = of(context).localeCode;
    return code == null ? null : Locale(code);
  }

  @override
  State<PreferencesScope> createState() => _PreferencesScopeState();
}

class _PreferencesScopeState extends State<PreferencesScope> {
  late Preferences _preferences = widget.service.current;
  StreamSubscription<Preferences>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(PreferencesScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      _preferences = widget.service.current;
      _listen();
    }
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = widget.service.stream.listen((next) {
      if (mounted) setState(() => _preferences = next);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PreferencesInherited(
    preferences: _preferences,
    service: widget.service,
    child: widget.child,
  );
}

class _PreferencesInherited extends InheritedWidget {
  const _PreferencesInherited({
    required this.preferences,
    required this.service,
    required super.child,
  });

  final Preferences preferences;
  final PreferencesService service;

  @override
  bool updateShouldNotify(_PreferencesInherited oldWidget) =>
      preferences != oldWidget.preferences;
}
