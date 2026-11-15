import 'dart:convert';
import 'dart:io';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' show FerryxBackend;
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:monitoring/monitoring.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:viewer_feature/src/text_layout.dart';
import 'package:viewer_feature/src/text_window.dart';
import 'package:viewer_feature/src/viewer_views.dart';
import 'package:viewer_feature/viewer_feature.dart';

void main() {
  final library = File(
    'rust/target/debug/${Platform.isMacOS
        ? 'libferryx_api.dylib'
        : Platform.isWindows
        ? 'ferryx_api.dll'
        : 'libferryx_api.so'}',
  );
  final skip = library.existsSync() ? null : 'run make core first';
  late FileRepository files;
  late File fixture;
  Directory? temporary;
  final en = lookupFerryxLocalizations(const Locale('en'));

  setUpAll(() async {
    if (skip != null) return;
    final backend = await FerryxBackend.initialize(
      externalLibrary: ExternalLibrary.open(library.path),
    );
    files = FileRepository(backend: backend, logger: Logger());
    final external = Platform.environment['FERRYX_LARGE_TEXT_FIXTURE'];
    if (external != null) {
      fixture = File(external);
    } else {
      temporary = await Directory.systemTemp.createTemp('ferryx-large-text-');
      fixture = File('${temporary!.path}/large.json');
      const length = 24 * 1024 * 1024;
      final bytes = Uint8List(length)..fillRange(0, length, 0x61);
      final prefix = utf8.encode('{"payload":"');
      bytes.setRange(0, prefix.length, prefix);
      bytes.setRange(length - 2, length, utf8.encode('"}'));
      await fixture.writeAsBytes(bytes);
    }
  });
  tearDownAll(() async {
    if (skip == null) await files.dispose();
    await temporary?.delete(recursive: true);
  });

  for (final wrap in [true, false]) {
    testWidgets(
      'real-core large text preview reads every part and keeps both placements responsive, wrap=$wrap',
      (tester) async {
        final preferences = await PreferencesService.create(
          storage: InMemoryPreferencesStorage(),
        );
        await preferences.update((p) => p.copyWith(viewerWrap: wrap));
        addTearDown(() async {
          final closing = preferences.dispose();
          await tester.pump();
          await closing;
        });
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final full = ValueNotifier(false);
        addTearDown(full.dispose);
        final key = GlobalKey();
        var closed = false;
        final firstFrame = Stopwatch()..start();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.of(
              AppPlatformStyle.macos,
              wrap ? Brightness.dark : Brightness.light,
            ),
            localizationsDelegates: FerryxSupportedLocales.delegates,
            supportedLocales: FerryxSupportedLocales.locales,
            home: ValueListenableBuilder<bool>(
              valueListenable: full,
              builder: (context, expanded, _) {
                final viewer = ViewerScreen(
                  key: key,
                  files: files,
                  preferences: preferences,
                  shortcutMap: ShortcutMap.defaults(TargetPlatform.macOS),
                  windowDecor: WindowDecor.none,
                  location: Location.native(fixture.absolute.path),
                  startInPreview: true,
                  fullWindow: expanded,
                  onClose: () => closed = true,
                  onToggleFullWindow: () => full.value = !full.value,
                );
                return expanded
                    ? viewer
                    : Row(
                        children: [
                          const Expanded(child: Text('Files')),
                          Expanded(child: viewer),
                        ],
                      );
              },
            ),
          ),
        );
        Future<TextView> waitForWindow(DecodedWindow? previous) async {
          for (var i = 0; i < 300; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
            final views = tester.widgetList<TextView>(find.byType(TextView));
            if (views.isNotEmpty && !identical(views.single.window, previous)) {
              await tester.pumpAndSettle();
              return views.single;
            }
          }
          throw StateError('Text window did not finish loading');
        }

        var view = await waitForWindow(null);
        firstFrame.stop();
        final size = (await tester.runAsync(fixture.length))!;
        final parts = (size / ViewerCubit.defaultWindowSize).ceil();
        for (var part = 0; part < parts; part++) {
          final lines = tester.widgetList<TextLine>(find.byType(TextLine));
          expect(lines, isNotEmpty);
          expect(lines.length, lessThan(200));
          expect(
            lines.every((line) => line.text.length <= maxTextParagraphLength),
            isTrue,
          );
          if (part + 1 < parts) {
            await tester.tap(find.text(en.viewerLoadNext));
            view = await waitForWindow(view.window);
          }
        }
        expect(find.text(en.viewerLoadNext), findsNothing);
        expect(find.text('Files'), findsOneWidget);
        full.value = true;
        await tester.pumpAndSettle();
        expect(find.text('Files'), findsNothing);
        expect(
          tester.widget<TextView>(find.byType(TextView)).window,
          same(view.window),
        );
        full.value = false;
        await tester.pumpAndSettle();
        expect(find.text('Files'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(closed, isTrue);
        expect(tester.takeException(), isNull);
        // Timing is diagnostic, not a machine-dependent pass/fail threshold.
        // Never print document contents from an external fixture.
        debugPrint(
          'Large text: $size bytes, wrap=$wrap, $parts parts, first frame ${firstFrame.elapsedMilliseconds} ms',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      skip: skip != null,
    );
  }
}
