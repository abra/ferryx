import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoring/monitoring.dart';

class _RecordingObserver with LogObserver {
  final messages = <LogMessage>[];

  @override
  void onLog(LogMessage logMessage) => messages.add(logMessage);
}

void main() {
  test('dispatches messages with level and timestamp to observers', () {
    final observer = _RecordingObserver();
    final logger = Logger(observers: [observer]);
    final fixed = DateTime(2026, 10, 9, 12);

    withClock(Clock.fixed(fixed), () {
      logger.info('hello');
      logger.error('boom', error: StateError('x'));
    });

    expect(observer.messages, hasLength(2));
    expect(observer.messages.first.level, LogLevel.info);
    expect(observer.messages.first.timestamp, fixed);
    expect(observer.messages.last.error, isA<StateError>());
  });

  test('destroy stops dispatch and clears observers', () async {
    final observer = _RecordingObserver();
    final logger = Logger()..addObserver(observer);
    await logger.destroy();
    logger.warn('late');
    expect(observer.messages, isEmpty);
    expect(logger.destroyed, isTrue);
  });

  test('levels are ordered by severity', () {
    expect(LogLevel.trace.compareTo(LogLevel.fatal), isNegative);
    expect(LogLevel.error.toShortName(), 'ERR');
  });
}
