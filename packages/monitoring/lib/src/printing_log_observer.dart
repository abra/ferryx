import 'package:flutter/foundation.dart';

import 'logger.dart';

/// Prints messages at or above [logLevel] with [debugPrint].
///
/// Attach in debug and profile builds only; release builds keep the logger
/// silent so no user data reaches the console.
class PrintingLogObserver with LogObserver {
  const PrintingLogObserver({required this.logLevel});

  final LogLevel logLevel;

  @override
  void onLog(LogMessage logMessage) {
    if (logMessage.level.index < logLevel.index) return;

    final dt = logMessage.timestamp;
    final stamp =
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}.'
        '${dt.millisecond.toString().padLeft(3, '0')}';
    final buffer = StringBuffer()
      ..write(stamp)
      ..write(' [${logMessage.level.toShortName()}] ')
      ..write(logMessage.message);
    if (logMessage.error case final error?) buffer.write('\n$error');
    if (logMessage.stackTrace case final stack?) buffer.write('\n$stack');
    debugPrint(buffer.toString());
  }

  String _pad(int value) => value.toString().padLeft(2, '0');
}
