import 'dart:async';
import 'dart:ui';

import 'package:ferryx/app/app_lifecycle.dart';
import 'package:ferryx/app/dependency_container.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';
import 'package:preferences_service/preferences_service.dart';

class _Dependencies extends Mock implements DependenciesContainer {}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  late bool preventClose;
  late bool failNativeClose;
  late Completer<void> windowClosed;
  late Completer<void> closeRearmed;
  late AppLifecycle lifecycle;
  late _Dependencies dependencies;
  late _ControlledStorage storage;
  late PreferencesService preferences;

  Future<void> windowClose() =>
      binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onEvent', {'eventName': 'close'}),
        ),
        null,
      );

  setUp(() async {
    preventClose = false;
    failNativeClose = false;
    windowClosed = Completer<void>();
    closeRearmed = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'setPreventClose':
          preventClose = call.arguments['isPreventClose'] as bool;
          if (preventClose && failNativeClose) closeRearmed.complete();
          return null;
        case 'close':
          if (failNativeClose) throw PlatformException(code: 'close failed');
          windowClosed.complete();
          return null;
        case 'isMaximized':
        case 'isMinimized':
        case 'isFullScreen':
          return false;
        case 'getBounds':
          return {'x': 13.0, 'y': 27.0, 'width': 1020.0, 'height': 760.0};
      }
      fail('Unexpected window method ${call.method}');
    });
    storage = _ControlledStorage();
    preferences = await PreferencesService.create(storage: storage);
    dependencies = _Dependencies();
    when(() => dependencies.preferencesService).thenReturn(preferences);
    when(dependencies.dispose).thenAnswer((_) => preferences.dispose());
    lifecycle = AppLifecycle(Logger());
    await lifecycle.install();
    lifecycle.useSession(dependencies);
    addTearDown(() async {
      lifecycle.dispose();
      await preferences.dispose();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });
  });

  test(
    'window and application close wait for one final disk snapshot',
    () async {
      var snapshots = 0;
      lifecycle.addListener(() {
        snapshots++;
        unawaited(preferences.update((p) => p.copyWith(splitFraction: 0.73)));
      });

      final storageReady = Completer<void>();
      storage.gate = storageReady.future;
      await windowClose();
      await windowClose();
      final response = binding.handleRequestAppExit();
      await storage.started.future;
      expect(preventClose, isTrue);
      expect(windowClosed.isCompleted, isFalse);
      expect(await storage.load(), isNull);

      storageReady.complete();
      expect(await response, AppExitResponse.exit);
      await windowClosed.future;
      expect(preventClose, isFalse);
      expect(snapshots, 1);
      final saved = await storage.load();
      expect(saved?.splitFraction, 0.73);
      expect(
        saved?.windowBounds,
        const WindowBounds(x: 13, y: 27, width: 1020, height: 760),
      );
    },
  );

  test(
    'failed persistence keeps the session alive for the next exit request',
    () async {
      final failed = Completer<void>();
      lifecycle.onExitSaveFailure = failed.complete;
      storage.fails = true;
      expect(await binding.handleRequestAppExit(), AppExitResponse.cancel);
      verifyNever(dependencies.dispose);
      await failed.future;

      storage.fails = false;
      expect(await binding.handleRequestAppExit(), AppExitResponse.exit);
      expect((await storage.load())?.windowBounds?.x, 13);
    },
  );

  test('a native close failure keeps the session usable until retry', () async {
    failNativeClose = true;
    await windowClose();
    await closeRearmed.future;
    expect(preventClose, isTrue);
    verifyNever(dependencies.dispose);

    failNativeClose = false;
    await preferences.update((p) => p.copyWith(splitFraction: 0.61));
    await windowClose();
    await windowClosed.future;
    expect((await storage.load())?.splitFraction, 0.61);
  });
}

class _ControlledStorage extends InMemoryPreferencesStorage {
  final started = Completer<void>();
  Future<void>? gate;
  bool fails = false;

  @override
  Future<void> save(Preferences preferences) async {
    if (!started.isCompleted) started.complete();
    await gate;
    if (fails) throw StateError('Storage unavailable');
    await super.save(preferences);
  }
}
