import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

/// {@template logger}
/// Application logger. Dispatches every [LogMessage] to its observers; by
/// itself it writes nowhere. Attach a [PrintingLogObserver] in debug builds.
///
/// [destroy] stops dispatch and drops observers; their own resources stay with
/// whoever created them.
/// {@endtemplate}
base class Logger {
  /// {@macro logger}
  Logger({List<LogObserver>? observers}) {
    _observers.addAll(observers ?? const []);
  }

  final _observers = <LogObserver>{};
  var _destroyed = false;

  /// Dispatches [logMessage] to every observer.
  @mustCallSuper
  void log(LogMessage logMessage) {
    if (_destroyed) return;
    for (final observer in _observers) {
      observer.onLog(logMessage);
    }
  }

  void trace(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(message, LogLevel.trace, error, stackTrace);

  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(message, LogLevel.debug, error, stackTrace);

  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(message, LogLevel.info, error, stackTrace);

  void warn(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(message, LogLevel.warn, error, stackTrace);

  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(message, LogLevel.error, error, stackTrace);

  void fatal(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(message, LogLevel.fatal, error, stackTrace);

  void _log(String message, LogLevel level, Object? error, StackTrace? stack) {
    log(
      LogMessage(
        message: message,
        level: level,
        timestamp: clock.now(),
        error: error,
        stackTrace: stack,
      ),
    );
  }

  /// Handler for `runZonedGuarded`.
  void logZoneError(Object error, StackTrace stackTrace) =>
      this.error('Zone error', error: error, stackTrace: stackTrace);

  /// Handler for `FlutterError.onError`.
  void logFlutterError(FlutterErrorDetails details) => error(
    'Flutter error',
    error: details.exception,
    stackTrace: details.stack,
  );

  /// Handler for `PlatformDispatcher.onError`; returns `true` as "handled".
  bool logPlatformDispatcherError(Object error, StackTrace stackTrace) {
    this.error('Platform error', error: error, stackTrace: stackTrace);
    return true;
  }

  void addObserver(LogObserver observer) => _observers.add(observer);

  void removeObserver(LogObserver observer) => _observers.remove(observer);

  bool get destroyed => _destroyed;

  /// Stops logging and removes observers. The logger must not be used after.
  @mustCallSuper
  Future<void> destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    _observers.clear();
  }
}

/// Severity of a [LogMessage]; ordered from least to most severe.
enum LogLevel implements Comparable<LogLevel> {
  trace,
  debug,
  info,
  warn,
  error,
  fatal;

  @override
  int compareTo(LogLevel other) => index - other.index;

  String toShortName() => switch (this) {
    LogLevel.trace => 'TRC',
    LogLevel.debug => 'DBG',
    LogLevel.info => 'INF',
    LogLevel.warn => 'WRN',
    LogLevel.error => 'ERR',
    LogLevel.fatal => 'FTL',
  };
}

/// Receives every message a [Logger] dispatches.
mixin LogObserver {
  void onLog(LogMessage logMessage);
}

/// One log record.
class LogMessage {
  const LogMessage({
    required this.message,
    required this.level,
    required this.timestamp,
    this.error,
    this.stackTrace,
  });

  final String message;
  final LogLevel level;
  final DateTime timestamp;
  final Object? error;
  final StackTrace? stackTrace;
}
