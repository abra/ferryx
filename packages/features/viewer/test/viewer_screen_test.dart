import 'dart:convert';
import 'dart:typed_data';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:viewer_feature/viewer_feature.dart';

class _Files extends Mock implements FileRepository {}

void main() {
  const file = Location.native('/tmp/notes.txt');
  final bytes = Uint8List.fromList(utf8.encode('quarterly numbers\n'));

  late PreferencesService preferences;

  setUpAll(() => registerFallbackValue(file));

  // Outside the test's fake time: the service writes as it starts.
  setUp(() async {
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
  });

  tearDown(() => preferences.dispose());

  testWidgets('the viewer is a page of its own: shown as the app routes to '
      'it, with nothing above it, its bar draws', (tester) async {
    final files = _Files();
    when(() => files.fileSize(any())).thenAnswer((_) async => bytes.length);
    when(() => files.readRange(any(), any(), any())).thenAnswer((call) async {
      final offset = call.positionalArguments[1] as int;
      final length = call.positionalArguments[2] as int;
      return Uint8List.sublistView(
        bytes,
        offset,
        (offset + length).clamp(0, bytes.length),
      );
    });
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        // No Scaffold or Material around it, as a route page has none.
        home: ViewerScreen(
          files: files,
          preferences: preferences,
          shortcutMap: ShortcutMap.defaults(TargetPlatform.macOS),
          windowDecor: WindowDecor.none,
          location: file,
          onClose: () {},
        ),
      ),
    );
    // The file read, the lines laid out (a spinner may still turn).
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(AppIconButton), findsWidgets);
    expect(find.textContaining('quarterly numbers'), findsOneWidget);
  });
}
