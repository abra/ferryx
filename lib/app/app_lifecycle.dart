import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:ferryx/app/dependency_container.dart';
import 'package:ferryx/app/window_state.dart';
import 'package:flutter/widgets.dart';
import 'package:monitoring/monitoring.dart';
import 'package:window_manager/window_manager.dart';

/// Checkpoints the current session before permitting a normal desktop exit.
class AppLifecycle extends ChangeNotifier
    with WidgetsBindingObserver, WindowListener {
  AppLifecycle(this._logger);

  final Logger _logger;
  DependenciesContainer? _dependencies;
  WindowStateSaver? _windowState;
  Future<AppExitResponse>? _exit;
  bool _closingWindow = false;
  VoidCallback? onExitSaveFailure;

  Future<void> install() async {
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  WindowStateSaver? useSession(DependenciesContainer? dependencies) {
    _windowState?.dispose();
    _dependencies = dependencies;
    return _windowState = dependencies == null
        ? null
        : WindowStateSaver(dependencies.preferencesService);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final result = await _requestExit();
    if (result == AppExitResponse.exit) await _releaseSession();
    return result;
  }

  Future<AppExitResponse> _requestExit() =>
      _exit ??= _prepareExit().then((result) {
        if (result == AppExitResponse.cancel) _exit = null;
        return result;
      });

  Future<AppExitResponse> _prepareExit() async {
    final dependencies = _dependencies;
    final windowState = _windowState;
    try {
      notifyListeners();
      await windowState?.flush();
      await dependencies?.preferencesService.flush();
    } on Object catch (error, stack) {
      _logger.warn(
        'Could not save the session',
        error: error,
        stackTrace: stack,
      );
      scheduleMicrotask(() => onExitSaveFailure?.call());
      return AppExitResponse.cancel;
    }
    return AppExitResponse.exit;
  }

  Future<void> _releaseSession() async {
    _windowState?.dispose();
    _windowState = null;
    await _dependencies?.dispose();
  }

  @override
  void onWindowClose() {
    if (_closingWindow) return;
    _closingWindow = true;
    unawaited(_closeWindow());
  }

  Future<void> _closeWindow() async {
    if (await _requestExit() == AppExitResponse.cancel) {
      _closingWindow = false;
      return;
    }
    try {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } on Object catch (error, stack) {
      _logger.warn(
        'Could not close the window',
        error: error,
        stackTrace: stack,
      );
      _exit = null;
      try {
        await windowManager.setPreventClose(true);
      } on Object catch (error, stack) {
        _logger.warn(
          'Could not restore the close handler',
          error: error,
          stackTrace: stack,
        );
      } finally {
        _closingWindow = false;
      }
      return;
    }
    await _releaseSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_releaseSession());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    _windowState?.dispose();
    super.dispose();
  }
}
