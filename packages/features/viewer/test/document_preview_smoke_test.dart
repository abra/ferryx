import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pagecraft/testing.dart';
import 'package:viewer_feature/src/document_preview_screen.dart';
import 'package:viewer_feature/src/document_session.dart';
import 'package:viewer_feature/viewer_feature.dart';

import 'support/document_fixtures.dart';

class _Lease implements PreviewFileLease {
  _Lease(this.file);
  final String file;
  final released = Completer<void>();
  @override
  Future<String> get path async => file;
  @override
  Future<void> close() async {
    if (!released.isCompleted) released.complete();
  }
}

class _Source implements DocumentFileSource {
  _Source(this.nativePath, this.displayName);
  final leases = <_Lease>[];
  @override
  final String displayName;
  @override
  String get displayPath => '/smoke';
  @override
  bool get isNative => true;
  @override
  final String nativePath;
  @override
  PreviewFileLease preparePreview() {
    final lease = _Lease(nativePath);
    leases.add(lease);
    return lease;
  }

  @override
  Future<int> size() => throw StateError('document preview must own its I/O');
  @override
  Future<Uint8List> read(int offset, int length) =>
      throw StateError('document preview must not read a text window');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await preparePdfEngineForTests();
    for (final (family, asset) in [
      ('Inter', 'Inter-Variable.ttf'),
      ('Geist Mono', 'GeistMono-Variable.ttf'),
      ('.AppleSystemUIFont', 'Inter-Variable.ttf'),
      ('.AppleSystemUIFontMonospaced', 'GeistMono-Variable.ttf'),
    ]) {
      await (FontLoader(family)..addFont(
            rootBundle.load('packages/component_library/fonts/$asset'),
          ))
          .load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  for (final (name, fileName, bytes, size, dark, language, scale) in [
    (
      'epub',
      'book.epub',
      epubFixture(),
      const Size(900, 600),
      false,
      'en',
      1.0,
    ),
    ('pdf', 'book.pdf', pdfFixture(), const Size(900, 600), false, 'en', 1.0),
    (
      'ru-narrow',
      'book.pdf',
      pdfFixture(),
      const Size(480, 700),
      true,
      'ru',
      2.0,
    ),
  ]) {
    testWidgets(
      'real $name preview renders, navigates and releases its lease',
      (tester) async {
        final directory = await tester.runAsync(
          () => Directory.systemTemp.createTemp('ferryx-document-widget-'),
        );
        final file = File('${directory!.path}/$fileName');
        file.writeAsBytesSync(bytes);
        addTearDown(() => directory.deleteSync(recursive: true));
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final source = _Source(file.path, fileName);
        final generation = ValueNotifier(0);
        addTearDown(generation.dispose);
        final opened = Completer<DocumentSession>();
        final sessions = <DocumentSession>[];
        final shot = GlobalKey();
        final l10n = lookupFerryxLocalizations(Locale(language));

        await tester.pumpWidget(
          MaterialApp(
            theme: dark
                ? AppTheme.dark(AppPlatformStyle.macos)
                : AppTheme.light(AppPlatformStyle.macos),
            locale: Locale(language),
            localizationsDelegates: FerryxSupportedLocales.delegates,
            supportedLocales: FerryxSupportedLocales.locales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: shot,
              child: Scaffold(
                body: ValueListenableBuilder<int>(
                  valueListenable: generation,
                  builder: (context, value, child) => DocumentPreviewScreen(
                    source: source,
                    generation: value,
                    opener: (path, format, appearance) async {
                      try {
                        final session = await openDocumentSession(
                          path,
                          format,
                          appearance,
                        );
                        sessions.add(session);
                        if (!opened.isCompleted) opened.complete(session);
                        return session;
                      } catch (error, stack) {
                        if (!opened.isCompleted) {
                          opened.completeError(error, stack);
                        }
                        rethrow;
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await _settle(tester, () => opened.isCompleted);
        final session = await opened.future;
        final lease = source.leases.single;
        await _settle(tester, () => session.ready || session.error != null);
        if (session.fixedPages != null) {
          await _settle(
            tester,
            () => tester
                .widgetList<RawImage>(
                  find.byType(RawImage),
                )
                .any((image) => image.image != null),
          );
        }
        await tester.pump();
        expect(session.ready, isTrue);
        expect(session.error, isNull);
        expect(tester.takeException(), isNull);
        if (session.fixedPages != null) {
          final position = tester.renderObject<RenderParagraph>(
            find.text(l10n.documentPage(1, session.count)),
          );
          expect(
            position.didExceedMaxLines,
            isFalse,
            reason: 'the page position must remain readable in a narrow bar',
          );
        }

        final shots = Platform.environment['FERRYX_DOCUMENT_SHOTS'];
        if (shots != null) {
          await tester.runAsync(
            () => _capture(shot, '$shots/ferryx-document-$name.png'),
          );
        }

        final next = find.byWidgetPredicate(
          (widget) =>
              widget is AppIconButton && widget.tooltip == l10n.documentNext,
        );
        await tester.tap(next);
        await _settle(tester, () => session.index == 1);
        await tester.pump();
        expect(session.index, 1);
        expect(lease.released.isCompleted, isFalse);

        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await _settle(tester, () => session.index == 0);
        await tester.pump();
        expect(session.index, 0);
        expect(tester.takeException(), isNull);

        if (language == 'ru') {
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is AppIconButton &&
                  widget.tooltip == l10n.documentActions,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.documentGoToPage));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(EditableText), '2');
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, l10n.actionGo));
          await _settle(
            tester,
            () =>
                session.index == 1 &&
                find.byType(EditableText).evaluate().isEmpty,
          );
          expect(
            session.index,
            1,
            reason: 'compact menu still exposes page jumps',
          );
          expect(tester.takeException(), isNull);
        }

        generation.value++;
        await tester.pump();
        await _settle(
          tester,
          () => sessions.length == 2 && lease.released.isCompleted,
        );
        final refreshed = sessions.last;
        await _settle(tester, () => refreshed.ready || refreshed.error != null);
        expect(refreshed.error, isNull);
        expect(source.leases, hasLength(2));
        expect(source.leases.last.released.isCompleted, isFalse);

        // Detach while the next page's layout or native render can be pending.
        await tester.tap(next);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await _settle(
          tester,
          () => source.leases.every((lease) => lease.released.isCompleted),
        );
        expect(
          file.existsSync(),
          isTrue,
          reason: 'a native original is borrowed',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

// Native I/O completes on real time; callbacks and widget layout need pumps.
Future<void> _settle(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 500 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: 'native document work did not complete');
}

Future<void> _capture(GlobalKey key, String path) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(png!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
