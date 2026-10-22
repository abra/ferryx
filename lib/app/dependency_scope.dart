import 'package:flutter/widgets.dart';
import 'package:ferryx/app/dependency_container.dart';

/// Exposes [DependenciesContainer] to the app shell and routing only; feature
/// Views consume their Bloc/Cubit and callbacks, never this scope.
class DependenciesScope extends InheritedWidget {
  const DependenciesScope({
    required this.dependencies,
    required super.child,
    super.key,
  });

  final DependenciesContainer dependencies;

  static DependenciesContainer of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<DependenciesScope>();
    assert(scope != null, 'DependenciesScope is missing above this context');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(DependenciesScope oldWidget) =>
      !identical(dependencies, oldWidget.dependencies);
}
