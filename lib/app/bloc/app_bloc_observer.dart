import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:monitoring/monitoring.dart';

/// Logs bloc errors always and transitions in debug builds.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver(this._logger);

  final Logger _logger;

  @override
  void onTransition(
    Bloc<Object?, Object?> bloc,
    Transition<Object?, Object?> transition,
  ) {
    super.onTransition(bloc, transition);
    if (kDebugMode) {
      _logger.trace('${bloc.runtimeType} ← ${transition.event.runtimeType}');
    }
  }

  @override
  void onError(BlocBase<Object?> bloc, Object error, StackTrace stackTrace) {
    _logger.error(
      '${bloc.runtimeType} failed',
      error: error,
      stackTrace: stackTrace,
    );
    super.onError(bloc, error, stackTrace);
  }
}
