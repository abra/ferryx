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
  final en = lookupFerryxLocalizations(const Locale('en'));

  late PreferencesService preferences;
  late Uint8List bytes;

  setUpAll(() => registerFallbackValue(file));

  // Outside the test's fake time: the service writes as it starts.
  setUp(() async {
    bytes = Uint8List.fromList(utf8.encode('quarterly numbers\n'));
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
  });

  Future<_Files> open(WidgetTester tester, {double width = 900}) async {
    addTearDown(() async {
      // Finish the stream's close in the widget test's clock.
      final disposed = preferences.dispose();
      await tester.pump();
      await disposed;
    });
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
    tester.view.physicalSize = Size(width, 600);
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
    return files;
  }

  Finder button(String tooltip) => find.byWidgetPredicate(
    (w) => w is AppIconButton && w.tooltip == tooltip,
  );

  Future<void> menu(WidgetTester tester) async {
    await tester.tap(button(en.viewerActions));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(AppMenuItem, label));
    await tester.pumpAndSettle();
  }

  AppMenuItem item(WidgetTester tester, String label) =>
      tester.widget<AppMenuItem>(find.widgetWithText(AppMenuItem, label));

  testWidgets('the viewer is a page of its own: shown as the app routes to '
      'it, with nothing above it, its bar draws', (tester) async {
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(AppIconButton), findsWidgets);
    expect(find.textContaining('quarterly numbers'), findsOneWidget);
  });

  testWidgets('a narrow viewer keeps wrap and find usable through its menu', (
    tester,
  ) async {
    await open(tester, width: 480);
    expect(button(en.cmdViewerFind), findsNothing);
    expect(button(en.viewerWrap), findsNothing);
    await menu(tester);
    expect(item(tester, en.cmdViewerToggleWrap).checked, isTrue);
    await pick(tester, en.cmdViewerToggleWrap);
    expect(preferences.current.viewerWrap, isFalse);

    await menu(tester);
    expect(item(tester, en.cmdViewerToggleWrap).checked, isFalse);
    expect(
      item(tester, en.cmdViewerFind).shortcut,
      ShortcutMap.defaults(
        TargetPlatform.macOS,
      ).labelOf(AppCommand.viewerFind, TargetPlatform.macOS),
    );
    await pick(tester, en.cmdViewerFind);
    await tester.enterText(find.byType(AppSearchField), 'numbers');
    await tester.pumpAndSettle();
    expect(find.text(en.viewerMatches(1, 1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow viewer menu goes to an offset and refreshes that '
      'part of the file', (tester) async {
    final files = await open(tester, width: 480);
    expect(button(en.cmdViewerGoTo), findsNothing);
    expect(button(en.cmdRefresh), findsNothing);
    await menu(tester);
    await pick(tester, en.cmdViewerGoTo);
    await tester.enterText(find.byType(TextField), '10');
    await tester.tap(find.text(en.actionGo));
    await tester.pumpAndSettle();
    verify(() => files.readRange(file, 10, bytes.length - 10)).called(1);
    expect(find.text('numbers'), findsOneWidget);

    bytes = Uint8List.fromList(utf8.encode('quarterly revised\n'));
    await menu(tester);
    await pick(tester, en.cmdRefresh);
    expect(find.text('revised'), findsOneWidget);
    expect(find.text('numbers'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the menu switches modes when even the mode control does not '
      'fit and disables tools unavailable in preview', (tester) async {
    await open(tester, width: 280);
    expect(find.byType(AppSegmentedControl<ViewerMode>), findsNothing);
    await menu(tester);
    await pick(tester, en.cmdViewerPreview);
    await menu(tester);
    expect(item(tester, en.cmdViewerPreview).checked, isTrue);
    for (final label in [
      en.cmdViewerToggleWrap,
      en.cmdViewerFind,
      en.cmdViewerGoTo,
    ]) {
      expect(item(tester, label).enabled, isFalse);
    }
    expect(item(tester, en.cmdRefresh).enabled, isTrue);
    await pick(tester, en.cmdViewerText);
    expect(find.textContaining('quarterly numbers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
