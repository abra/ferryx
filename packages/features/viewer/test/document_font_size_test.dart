import 'dart:async';
import 'dart:io';

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:viewer_feature/src/document_preview_screen.dart';
import 'package:viewer_feature/src/document_session.dart';
import 'package:viewer_feature/viewer_feature.dart';

import 'support/document_fixtures.dart';

void main() {
  testWidgets(
    'book buttons, keyboard and compact menu relayout and persist the size',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('ferryx-document-font-'),
      );
      final file = File('${directory!.path}/book.epub')
        ..writeAsBytesSync(epubFixture());
      addTearDown(() => directory.deleteSync(recursive: true));
      final source = _Source(file.path);
      final storage = InMemoryPreferencesStorage();
      final preferences = await PreferencesService.create(storage: storage);
      addTearDown(() async {
        final closed = preferences.dispose();
        // The preferences stream was created in the test's fake async zone.
        await tester.pump();
        await closed;
      });
      final l10n = lookupFerryxLocalizations(const Locale('en'));
      final shortcuts = ShortcutMap.defaults(TargetPlatform.macOS);
      final contentFocus = FocusNode(debugLabel: 'host document focus');
      addTearDown(contentFocus.dispose);
      DocumentSession? session;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          localizationsDelegates: FerryxSupportedLocales.delegates,
          supportedLocales: FerryxSupportedLocales.locales,
          home: Scaffold(
            body: CommandShortcuts(
              shortcuts: shortcuts.toShortcuts(
                TargetPlatform.macOS,
                scopes: const {CommandScope.viewer},
              ),
              child: StreamBuilder<Preferences>(
                stream: preferences.stream,
                initialData: preferences.current,
                builder: (context, snapshot) => DocumentPreviewScreen(
                  source: source,
                  generation: 0,
                  focusNode: contentFocus,
                  fontSize: snapshot.data!.documentFontSize,
                  onFontSizeChanged: (value) => unawaited(
                    preferences.update(
                      (p) => p.copyWith(documentFontSize: value),
                    ),
                  ),
                  shortcutMap: shortcuts,
                  opener: (path, format, appearance) async =>
                      session = await openDocumentSession(
                        path,
                        format,
                        appearance,
                      ),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester, () => session?.ready ?? false);
      final book = session!;
      await tester.tap(_button(l10n.documentNext));
      await _settle(tester, () => book.ready && book.index == 1);
      final controller = book.textController!;
      final initialLayout = controller.layout.generation;
      expect(controller.layout.style.fontScale, 15 / 16);

      await tester.tap(_button(l10n.documentFontIncrease));
      await _settle(tester, () => book.ready);
      expect(controller.layout.style.fontScale, 16 / 16);
      expect(controller.layout.generation, greaterThan(initialLayout));
      expect(book.index, 1, reason: 'resizing preserves the reading position');
      expect(preferences.current.documentFontSize, 16);
      expect(preferences.current.viewerFontSize, 13);
      expect(source.leases, hasLength(1), reason: 'font size does not reopen');

      await tester.tap(_button(l10n.documentFontDecrease));
      await _settle(tester, () => book.ready);
      expect(preferences.current.documentFontSize, 15);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await _settle(tester, () => book.ready);
      expect(controller.layout.style.fontScale, 16 / 16);
      expect(preferences.current.documentFontSize, 16);

      // A setting changed outside this view must update the same live book.
      unawaited(preferences.update((p) => p.copyWith(documentFontSize: 32)));
      await tester.pump();
      await _settle(tester, () => book.ready);
      expect(controller.layout.style.fontScale, 32 / 16);
      expect(
        tester
            .widget<AppIconButton>(
              _button(l10n.documentFontIncrease),
            )
            .onPressed,
        isNull,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(preferences.current.documentFontSize, 32);

      tester.view.physicalSize = const Size(440, 700);
      await tester.pump();
      await _settle(tester, () => book.ready);
      expect(_button(l10n.documentFontDecrease).hitTestable(), findsOneWidget);
      await tester.tap(_button(l10n.documentFontDecrease));
      await _settle(tester, () => book.ready);
      expect(preferences.current.documentFontSize, 31);
      expect(controller.layout.style.fontScale, 31 / 16);
      await tester.tap(_button(l10n.documentActions));
      await tester.pumpAndSettle();
      expect(find.text(l10n.documentFontSizeValue(31)), findsOneWidget);
      await tester.tap(find.text(l10n.documentFontDecrease));
      await _settle(tester, () => book.ready);
      expect(controller.layout.style.fontScale, 30 / 16);
      expect(preferences.current.documentFontSize, 30);
      expect(book.index, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await _settle(tester, () => book.ready);
      expect(preferences.current.documentFontSize, 15);
      expect(controller.layout.style.fontScale, 15 / 16);

      unawaited(preferences.update((p) => p.copyWith(documentFontSize: 10)));
      await tester.pump();
      await _settle(tester, () => book.ready);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await _settle(tester, () => book.ready);
      expect(preferences.current.documentFontSize, 9);
      expect(controller.layout.style.fontScale, 9 / 16);
      expect(
        tester
            .widget<AppIconButton>(_button(l10n.documentFontDecrease))
            .onPressed,
        isNull,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(preferences.current.documentFontSize, 9);
      final restored = await PreferencesService.create(storage: storage);
      expect(restored.current.documentFontSize, 9);
      expect(restored.current.viewerFontSize, 13);
      await restored.dispose();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester, () => source.leases.single.released);
      contentFocus.addListener(() {});
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

Finder _button(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is AppIconButton && widget.tooltip == tooltip,
);

Future<void> _settle(WidgetTester tester, bool Function() condition) async {
  // Force the callback's queued rebuild even when a previous layout is ready.
  await tester.pump();
  for (var attempt = 0; attempt < 500 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: 'document layout did not complete');
}

class _Source implements DocumentFileSource {
  _Source(this.nativePath);
  final leases = <_Lease>[];
  @override
  final String nativePath;
  @override
  String get displayName => 'book.epub';
  @override
  String get displayPath => nativePath;
  @override
  bool get isNative => true;
  @override
  PreviewFileLease preparePreview() {
    final lease = _Lease(nativePath);
    leases.add(lease);
    return lease;
  }

  @override
  Future<int> size() => throw StateError('document preview owns its input');
  @override
  Future<Uint8List> read(int offset, int length) =>
      throw StateError('document preview owns its input');
}

class _Lease implements PreviewFileLease {
  _Lease(this.file);
  final String file;
  bool released = false;
  @override
  Future<String> get path async => file;
  @override
  Future<void> close() async => released = true;
}
