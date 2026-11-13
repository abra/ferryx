import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:find_feature/find_feature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operations_service/operations_service.dart';

class _MockFindService extends Mock implements FindService {}

/// The Spotlight option: shown where the desktop has the index, carried
/// in the request, and a search that fell back says so.
void main() {
  final en = lookupFerryxLocalizations(const Locale('en'));
  late _MockFindService service;
  late StreamController<FindUpdate> updates;

  setUpAll(() {
    registerFallbackValue(const FindRequest(root: '/'));
  });

  setUp(() {
    service = _MockFindService();
    updates = StreamController<FindUpdate>.broadcast();
    when(() => service.updates).thenAnswer((_) => updates.stream);
    when(() => service.start(any())).thenAnswer((_) async => 3);
    when(() => service.cancel(any())).thenAnswer((_) async {});
  });

  tearDown(() => updates.close());

  Future<void> open(WidgetTester tester, {required bool spotlight}) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxLocalizations.localizationsDelegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFindDialog(
                context,
                root: '/home',
                find: service,
                onView: (_) async {},
                spotlight: spotlight,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('no Spotlight, no option', (tester) async {
    await open(tester, spotlight: false);
    expect(find.text(en.findSpotlight), findsNothing);
    expect(find.text(en.findSpotlightNote), findsNothing);
  });

  testWidgets('the option goes into the request; a fallback says so', (
    tester,
  ) async {
    await open(tester, spotlight: true);
    expect(find.text(en.findSpotlightNote), findsOneWidget);
    await tester.tap(find.text(en.findSpotlight));
    await tester.pump();
    await tester.tap(find.text(en.findStart));
    await tester.pump();
    final request =
        verify(() => service.start(captureAny())).captured.single
            as FindRequest;
    expect(request.useSpotlight, isTrue);
    updates.add(
      const FindUpdate(findId: 3, done: true, spotlightFailed: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(en.findSpotlightFailed), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
