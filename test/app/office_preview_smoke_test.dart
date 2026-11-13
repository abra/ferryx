import 'dart:io';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' show FerryxBackend;
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoring/monitoring.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';
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
  setUpAll(() async {
    if (skip != null) return;
    final backend = await FerryxBackend.initialize(
      externalLibrary: ExternalLibrary.open(library.path),
    );
    files = FileRepository(backend: backend, logger: Logger());
  });
  tearDownAll(() async {
    if (skip == null) await files.dispose();
  });
  for (final (name, heading, dark) in [
    ('fixture.docx', 'Ferryx office preview', false),
    ('fixture.xlsx', 'Summary', true),
    ('fixture.pptx', 'Ferryx presentation', false),
    ('image.docx', 'Ferryx office preview', true),
  ]) {
    testWidgets(
      '$name renders through the real Rust converter in a neighboring pane',
      (tester) async {
        final preferences = await PreferencesService.create(
          storage: InMemoryPreferencesStorage(),
        );
        addTearDown(() async {
          final closing = preferences.dispose();
          await tester.pump();
          await closing;
        });
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final full = ValueNotifier(false);
        final key = GlobalKey();
        addTearDown(full.dispose);
        final archive = File(
          'rust/crates/ferryx_core/tests/fixtures/office.zip',
        ).absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.of(
              AppPlatformStyle.macos,
              dark ? Brightness.dark : Brightness.light,
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
                  location: Location.inArchive(archive: archive, path: name),
                  startInPreview: true,
                  fullWindow: expanded,
                  onClose: () {},
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
        final content = find.text(heading, findRichText: true);
        for (var i = 0; i < 500 && content.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        if (name == 'image.docx') {
          final image = find.byType(Image);
          for (var i = 0; i < 500 && image.evaluate().isEmpty; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(image, findsWidgets);
          // Image codecs finish on real async tasks, outside the fake clock
          // advanced by pumpAndSettle. Wait for decoding before settling UI.
          await tester.runAsync(
            () => precacheImage(
              tester.widget<Image>(image.first).image,
              tester.element(image.first),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(content, findsWidgets);
        expect(find.text('Files'), findsOneWidget);
        if (name == 'image.docx') {
          expect(find.byType(Image), findsWidgets);
          expect(
            find.textContaining('HIDDEN_PREVIEW_TEXT', findRichText: true),
            findsNothing,
          );
        }
        full.value = true;
        await tester.pumpAndSettle();
        expect(content, findsWidgets);
        expect(find.text('Files'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      skip: skip != null,
    );
  }
}
