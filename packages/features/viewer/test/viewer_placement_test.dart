import 'dart:convert';
import 'dart:io';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pagecraft/all_formats.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:viewer_feature/src/document_preview_screen.dart';
import 'package:viewer_feature/src/markdown_preview.dart';
import 'package:viewer_feature/viewer_feature.dart';

import 'support/document_fixtures.dart';

class _Files extends Mock implements FileRepository {}

class _Lease implements PreviewFileLease {
  _Lease(this.file);
  final String file;
  int closes = 0;
  @override
  Future<String> get path async => file;
  @override
  Future<void> close() async => closes++;
}

void main() {
  late Directory directory;
  late PreferencesService preferences;
  late InMemoryPreferencesStorage storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ferryx-placement-');
    storage = InMemoryPreferencesStorage();
    preferences = await PreferencesService.create(storage: storage);
  });
  tearDown(() => directory.delete(recursive: true));

  testWidgets(
    'Markdown keeps its read, scroll and focus when changing placement',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        final closed = preferences.dispose();
        await tester.pump();
        await closed;
      });
      const location = Location.native('/tmp/README.md');
      final bytes = Uint8List.fromList(
        utf8.encode(List.generate(100, (i) => 'Paragraph $i.').join('\n\n')),
      );
      final files = _Files();
      when(() => files.fileSize(location))
          .thenAnswer((_) async => bytes.length);
      when(() => files.readRange(location, 0, bytes.length))
          .thenAnswer((_) async => bytes);
      final fileFocus = FocusNode(debugLabel: 'files');
      final viewerScope = FocusScopeNode(debugLabel: 'preview');
      final fullWindow = ValueNotifier(false);
      addTearDown(fileFocus.dispose);
      addTearDown(viewerScope.dispose);
      addTearDown(fullWindow.dispose);
      final viewerKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          localizationsDelegates: FerryxSupportedLocales.delegates,
          supportedLocales: FerryxSupportedLocales.locales,
          home: ValueListenableBuilder<bool>(
            valueListenable: fullWindow,
            builder: (context, full, _) {
              final viewer = ViewerScreen(
                key: viewerKey,
                files: files,
                preferences: preferences,
                shortcutMap: ShortcutMap.defaults(TargetPlatform.macOS),
                windowDecor: WindowDecor.none,
                location: location,
                autofocus: false,
                focusScope: viewerScope,
                fullWindow: full,
                onToggleFullWindow: () => fullWindow.value = !full,
                onFocusFiles: fileFocus.requestFocus,
                onClose: fileFocus.requestFocus,
              );
              return full
                  ? viewer
                  : Row(
                      children: [
                        Expanded(
                          child: Focus(
                            focusNode: fileFocus,
                            autofocus: true,
                            child: const Text('Files'),
                          ),
                        ),
                        Expanded(child: viewer),
                      ],
                    );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fileFocus.hasPrimaryFocus, isTrue);
      viewerScope.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      final reader = tester.state(find.byType(MarkdownPreview));
      final scroll = tester.widget<Markdown>(find.byType(Markdown)).controller!;
      final position = scroll.offset;
      expect(position, greaterThan(0));
      for (final full in [true, false]) {
        expect(
          invokeCommand(
            FocusManager.instance.primaryFocus!.context!,
            AppCommand.viewerToggleFullWindow,
          ),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(fullWindow.value, full);
        expect(tester.state(find.byType(MarkdownPreview)), same(reader));
        expect(
          tester.widget<Markdown>(find.byType(Markdown)).controller,
          same(scroll),
        );
        expect(scroll.offset, position);
        viewerScope.requestFocus();
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(fileFocus.hasPrimaryFocus, isTrue);
      verify(() => files.readRange(location, 0, bytes.length)).called(1);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'pane and full window share reader resources, position, size and focus',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        final closed = preferences.dispose();
        await tester.pump();
        await closed;
      });
      final file = File('${directory.path}/book.epub')
        ..writeAsBytesSync(epubFixture());
      final location = Location.native(file.path);
      final lease = _Lease(file.path);
      final files = _Files();
      when(() => files.preparePreview(location)).thenReturn(lease);
      final fileFocus = FocusNode(debugLabel: 'file list');
      final viewerScope = FocusScopeNode(debugLabel: 'preview scope');
      final fullWindow = ValueNotifier(false);
      addTearDown(fileFocus.dispose);
      addTearDown(viewerScope.dispose);
      addTearDown(fullWindow.dispose);
      final viewerKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          localizationsDelegates: FerryxSupportedLocales.delegates,
          supportedLocales: FerryxSupportedLocales.locales,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: fullWindow,
              builder: (context, full, child) {
                final viewer = ViewerScreen(
                  key: viewerKey,
                  files: files,
                  preferences: preferences,
                  shortcutMap: ShortcutMap.defaults(TargetPlatform.macOS),
                  windowDecor: WindowDecor.none,
                  location: location,
                  autofocus: false,
                  focusScope: viewerScope,
                  fullWindow: full,
                  onToggleFullWindow: () => fullWindow.value = !full,
                  onFocusFiles: fileFocus.requestFocus,
                  onClose: fileFocus.requestFocus,
                );
                return full
                    ? viewer
                    : Row(
                        children: [
                          Expanded(
                            child: Focus(
                              focusNode: fileFocus,
                              autofocus: true,
                              child: const Center(child: Text('Files')),
                            ),
                          ),
                          Expanded(child: viewer),
                        ],
                      );
              },
            ),
          ),
        ),
      );
      TextPagesController? controller() => tester
          .widgetList<TextPagesView>(find.byType(TextPagesView))
          .firstOrNull
          ?.controller;
      await _settle(tester, () => controller()?.isReady ?? false);
      expect(
        fileFocus.hasPrimaryFocus,
        isTrue,
        reason: 'opening a neighboring preview does not steal file focus',
      );
      final engine = controller()!;
      final documentState = tester.state(find.byType(DocumentPreviewScreen));
      final sessionKey = tester
          .widget<TextPagesView>(
            find.byType(TextPagesView),
          )
          .key;
      final viewerState = viewerKey.currentState;

      viewerScope.requestFocus();
      await tester.pump();
      await tester.pump();
      final documentFocus = tester
          .widget<DocumentPreviewScreen>(
            find.byType(DocumentPreviewScreen),
          )
          .focusNode!;
      expect(documentFocus.hasPrimaryFocus, isTrue);
      fileFocus.requestFocus();
      await tester.pump();
      await tester.tap(find.byType(TextPagesView));
      await tester.pump();
      expect(
        documentFocus.hasPrimaryFocus,
        isTrue,
        reason: 'clicking the document body takes focus from the file list',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await _settle(tester, () => engine.position?.section == 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await _settle(tester, () => engine.isReady);
      expect(engine.layout.style.fontScale, 16 / 16);
      expect(preferences.current.documentFontSize, 16);
      final anchor = engine.position!.cfi;

      for (final full in [true, false]) {
        expect(
          invokeCommand(
            documentFocus.context!,
            AppCommand.viewerToggleFullWindow,
          ),
          isTrue,
        );
        await _settle(tester, () => engine.isReady);
        expect(fullWindow.value, full);
        expect(viewerKey.currentState, same(viewerState));
        expect(
          tester.state(find.byType(DocumentPreviewScreen)),
          same(documentState),
        );
        expect(controller(), same(engine));
        expect(
          tester.widget<TextPagesView>(find.byType(TextPagesView)).key,
          sessionKey,
        );
        expect(engine.position!.section, 1);
        expect(engine.position!.cfi, anchor);
        expect(engine.layout.style.fontScale, 16 / 16);
        expect(lease.closes, 0);
        viewerScope.requestFocus();
        await tester.pump();
        await tester.pump();
      }

      expect(documentFocus.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(fileFocus.hasPrimaryFocus, isTrue);
      verify(() => files.preparePreview(location)).called(1);
      verifyNever(() => files.fileSize(location));
      expect(preferences.current.viewerFontSize, 13);
      expect((await storage.load())!.documentFontSize, 16);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester, () => lease.closes == 1);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

Future<void> _settle(WidgetTester tester, bool Function() condition) async {
  await tester.pump();
  for (var attempt = 0; attempt < 500 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: 'document work did not complete');
}
