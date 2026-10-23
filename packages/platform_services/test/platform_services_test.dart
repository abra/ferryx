import 'package:component_library/component_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';
import 'package:platform_services/src/system_file_drags.dart';
import 'package:platform_services/testing.dart';
import 'package:super_native_extensions/raw_drag_drop.dart' as raw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformServices.forPlatform', () {
    test('macOS has Quick Look, the share picker and file drags', () async {
      final services = PlatformServices.forPlatform(TargetPlatform.macOS);
      expect(services, isA<ChannelPlatformServices>());
      expect(
        services.capabilities,
        const PlatformCapabilities(
          quickLook: true,
          share: true,
          fileDrags: true,
        ),
      );
      await services.dispose();
    });

    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      test(
        '$platform has file drags alone, and the rest does nothing',
        () async {
          final services = PlatformServices.forPlatform(platform);
          expect(services, isA<DesktopPlatformServices>());
          expect(
            services.capabilities,
            const PlatformCapabilities(fileDrags: true),
          );
          await services.showQuickLook(QuickLookItems(const ['/a']));
          expect(services.quickLookOpen.value, isFalse);
          await services.share(const ['/a'], anchor: Rect.zero);
          await services.dispose();
        },
      );
    }
  });

  group('ChannelPlatformServices', () {
    const channel = MethodChannel(ChannelPlatformServices.channelName);
    late List<MethodCall> calls;
    late ChannelPlatformServices services;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // The layout the runner reports when asked; its read is no request.
    var latin = true;

    setUp(() {
      calls = [];
      latin = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'keyboard.latin') return latin;
        calls.add(call);
        return null;
      });
      services = ChannelPlatformServices();
    });

    tearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await services.dispose();
    });

    /// The runner calling Dart.
    Future<void> fromRunner(String method, [Object? arguments]) =>
        messenger.handlePlatformMessage(
          ChannelPlatformServices.channelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );

    test('opens, turns and closes Quick Look', () async {
      await services.showQuickLook(
        QuickLookItems(const ['/a', '/b'], index: 1),
      );
      expect(services.quickLookOpen.value, isTrue);
      await services.selectQuickLookItem(0);
      await services.closeQuickLook();
      expect(services.quickLookOpen.value, isFalse);
      // Closed: nothing more is sent.
      await services.selectQuickLookItem(1);
      await services.closeQuickLook();
      expect(
        [for (final c in calls) c.method],
        [
          'quickLook.show',
          'quickLook.select',
          'quickLook.close',
        ],
      );
      expect(calls.first.arguments, {
        'paths': ['/a', '/b'],
        'index': 1,
      });
      expect(calls[1].arguments, {'index': 0});
    });

    test('an empty list closes the panel rather than opening it', () async {
      await services.showQuickLook(QuickLookItems(const ['/a']));
      await services.showQuickLook(QuickLookItems(const []));
      expect(services.quickLookOpen.value, isFalse);
      expect(calls.last.method, 'quickLook.close');
    });

    test("tells the panel's close and its ↑ ↓ to the window", () async {
      final events = <QuickLookEvent>[];
      final subscription = services.quickLookEvents.listen(events.add);
      await services.showQuickLook(QuickLookItems(const ['/a', '/b']));
      await fromRunner('quickLook.step', {'delta': 1});
      await fromRunner('quickLook.step', {'delta': -1});
      await fromRunner('quickLook.step', {'delta': 'nonsense'});
      await fromRunner('quickLook.closed');
      expect(services.quickLookOpen.value, isFalse);
      // A close the window asked for itself is not news.
      await services.showQuickLook(QuickLookItems(const ['/a']));
      await services.closeQuickLook();
      await fromRunner('quickLook.closed');
      // Steps of a closed panel are stale.
      await fromRunner('quickLook.step', {'delta': 1});
      await pumpEventQueue();
      expect(events, const [
        QuickLookStep(1),
        QuickLookStep(-1),
        QuickLookClosed(),
      ]);
      await subscription.cancel();
    });

    test('follows the keyboard layout: asked at the start, then as the '
        'runner reports it', () async {
      await services.dispose();
      latin = false;
      services = ChannelPlatformServices();
      await pumpEventQueue();
      expect(services.latinKeyboard.value, isFalse);
      await fromRunner('keyboard.changed', {'latin': true});
      expect(services.latinKeyboard.value, isTrue);
      await fromRunner('keyboard.changed', {'latin': false});
      expect(services.latinKeyboard.value, isFalse);
    });

    test('shares the paths with the anchor in logical coordinates', () async {
      await services.share(
        const ['/a', '/b'],
        anchor: const Rect.fromLTWH(10, 20, 300, 22),
      );
      await services.share(const [], anchor: Rect.zero);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'share');
      expect(calls.single.arguments, {
        'paths': ['/a', '/b'],
        'rect': [10.0, 20.0, 300.0, 22.0],
      });
    });

    test("the runner's failure reaches the caller", () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'no');
      });
      await expectLater(
        services.share(const ['/a'], anchor: Rect.zero),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  test('QuickLookItems keeps its index inside the list', () {
    expect(QuickLookItems(const ['/a', '/b'], index: 5).index, 1);
    expect(QuickLookItems(const ['/a'], index: -2).index, 0);
    expect(QuickLookItems(const []).index, 0);
    expect(QuickLookItems(const ['/a']), QuickLookItems(const ['/a']));
    expect(
      QuickLookItems(const ['/a']),
      isNot(QuickLookItems(const ['/b'])),
    );
  });

  test('the drop operations as the desktop names them', () {
    expect(toRawOperation(FileDropOperation.copy), raw.DropOperation.copy);
    expect(toRawOperation(FileDropOperation.move), raw.DropOperation.move);
    expect(toRawOperation(FileDropOperation.link), raw.DropOperation.link);
    expect(toRawOperation(FileDropOperation.none), isNull);
    expect(toRawOperation(FileDropOperation.forbidden), isNull);
  });

  group('PlatformDropArea', () {
    testWidgets('without file drags it is its child alone', (tester) async {
      const child = SizedBox(key: ValueKey('app'));
      await tester.pumpWidget(
        const PlatformDropArea(enabled: false, child: child),
      );
      expect(find.byKey(const ValueKey('app')), findsOneWidget);
      expect(
        tester.widget(find.byType(PlatformDropArea)),
        isA<PlatformDropArea>(),
      );
      expect(
        find.descendant(
          of: find.byType(PlatformDropArea),
          matching: find.byType(MetaData),
        ),
        findsNothing,
      );
    });

    testWidgets('with them, the window takes drags around its content', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(),
          child: PlatformDropArea(
            enabled: true,
            child: SizedBox(key: ValueKey('app')),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('app')), findsOneWidget);
    });
  });

  group('FakePlatformServices', () {
    test('records what was asked and plays the desktop', () async {
      final fake = FakePlatformServices();
      final events = <QuickLookEvent>[];
      final subscription = fake.quickLookEvents.listen(events.add);
      await fake.showQuickLook(QuickLookItems(const ['/a', '/b']));
      await fake.selectQuickLookItem(1);
      expect(fake.shown, QuickLookItems(const ['/a', '/b'], index: 1));
      fake.userStepsQuickLook(-1);
      fake.userClosesQuickLook();
      fake.userClosesQuickLook();
      await pumpEventQueue();
      expect(events, const [QuickLookStep(-1), QuickLookClosed()]);
      expect(fake.closes, 0, reason: 'the user closed it');
      await fake.share(const ['/a'], anchor: Rect.zero);
      expect(fake.shares.single.paths, ['/a']);
      await subscription.cancel();
      await fake.dispose();
    });
  });
}
