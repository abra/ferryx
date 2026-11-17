import 'package:flutter/widgets.dart';
import 'package:ferryx/app/app_lifecycle.dart';
import 'package:ferryx/app/dependency_container.dart';
import 'package:ferryx/app/dependency_scope.dart';
import 'package:ferryx/app/ferryx_app.dart';
import 'package:preferences_service/preferences_service.dart';

/// Mounts dependencies and reactive scopes above the app.
class AppScopes extends StatelessWidget {
  const AppScopes({
    required this.dependencies,
    required this.lifecycle,
    super.key,
  });

  final DependenciesContainer dependencies;
  final AppLifecycle lifecycle;

  @override
  Widget build(BuildContext context) => DependenciesScope(
    dependencies: dependencies,
    child: PreferencesScope(
      service: dependencies.preferencesService,
      child: FerryxApp(lifecycle: lifecycle),
    ),
  );
}
