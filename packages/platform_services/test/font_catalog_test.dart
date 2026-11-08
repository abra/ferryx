import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ferryx/test-font-catalog');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final (name, create) in <(String, PlatformServices Function())>[
    ('macOS', () => ChannelPlatformServices(channel: channel)),
    ('desktop', () => DesktopPlatformServices(channel: channel)),
  ]) {
    group('$name font catalog', () {
      late PlatformServices services;
      late Object? response;
      late List<MethodCall> calls;

      setUp(() {
        response = <String>[];
        calls = [];
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'keyboard.latin') return true;
          calls.add(call);
          final value = response;
          if (value is Exception) throw value;
          return value;
        });
        services = create();
      });

      tearDown(() async {
        await services.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      });

      test(
        'reads on demand, removes blanks and duplicates, and sorts families',
        () async {
          response = [
            'Zed Mono',
            ' Menlo ',
            '',
            'Cascadia Mono',
            'Menlo',
            '  ',
          ];
          expect(calls, isEmpty);
          final families = await services.monospaceFontFamilies();
          expect(families, ['Cascadia Mono', 'Menlo', 'Zed Mono']);
          expect(calls.single.method, 'fonts.monospaceFamilies');
          expect(calls.single.arguments, isNull);
          expect(() => families.add('Other'), throwsUnsupportedError);

          response = ['New Mono'];
          expect(await services.monospaceFontFamilies(), ['New Mono']);
          expect(calls, hasLength(2));
        },
      );

      test('reports a native failure to the settings screen', () async {
        response = PlatformException(code: 'font_catalog_unavailable');
        await expectLater(
          services.monospaceFontFamilies(),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'font_catalog_unavailable',
            ),
          ),
        );
      });

      test('reports a runner without the font method', () async {
        response = MissingPluginException();
        await expectLater(
          services.monospaceFontFamilies(),
          throwsA(isA<MissingPluginException>()),
        );
      });

      test(
        'does not silently turn a null native result into an empty catalog',
        () async {
          response = null;
          await expectLater(
            services.monospaceFontFamilies(),
            throwsA(isA<PlatformException>()),
          );
        },
      );
    });
  }
}
