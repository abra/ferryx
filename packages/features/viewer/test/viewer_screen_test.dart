import 'dart:async';
import 'dart:convert';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:mocktail/mocktail.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:viewer_feature/viewer_feature.dart';
import 'package:viewer_feature/src/markdown_format.dart';

class _Files extends Mock implements FileRepository {}

class _PendingPreview implements PreviewFileLease {
  final prepared = Completer<String>();
  int closes = 0;

  @override
  Future<String> get path => prepared.future;

  @override
  Future<void> close() async {
    closes++;
    if (!prepared.isCompleted) {
      prepared.completeError(
        const FerryxException(FerryxErrorKind.cancelled, 'preview closed'),
      );
    }
  }
}

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

  Future<_Files> open(
    WidgetTester tester, {
    double width = 900,
    Brightness brightness = Brightness.light,
    double textScale = 1,
    bool startInPreview = false,
    Location location = file,
    Map<Location, Uint8List> images = const {},
    Map<Location, int> imageSizes = const {},
    PreviewFileLease Function()? preparePreview,
  }) async {
    addTearDown(() async {
      // Finish the stream's close in the widget test's clock.
      final disposed = preferences.dispose();
      await tester.pump();
      await disposed;
    });
    final files = _Files();
    if (preparePreview != null) {
      when(() => files.preparePreview(any()))
          .thenAnswer((_) => preparePreview());
    }
    when(() => files.fileSize(any())).thenAnswer((call) async {
      final at = call.positionalArguments.first as Location;
      return at == location
          ? bytes.length
          : imageSizes[at] ?? images[at]!.length;
    });
    when(() => files.readRange(any(), any(), any())).thenAnswer((call) async {
      final at = call.positionalArguments[0] as Location;
      final content = at == location ? bytes : images[at]!;
      final offset = call.positionalArguments[1] as int;
      final length = call.positionalArguments[2] as int;
      return Uint8List.sublistView(
        content,
        offset,
        (offset + length).clamp(0, content.length),
      );
    });
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(AppPlatformStyle.macos, brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        // No Scaffold or Material around it, as a route page has none.
        home: ViewerScreen(
          files: files,
          preferences: preferences,
          shortcutMap: ShortcutMap.defaults(TargetPlatform.macOS),
          windowDecor: WindowDecor.none,
          location: location,
          startInPreview: startInPreview,
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

  for (final name in ['notes.txt', 'settings.json', 'LICENSE']) {
    testWidgets('neighboring preview opens $name as searchable text', (
      tester,
    ) async {
      final files = await open(
        tester,
        location: Location.native('/tmp/$name'),
        startInPreview: true,
      );
      expect(find.textContaining('quarterly numbers'), findsOneWidget);
      expect(find.text(en.viewerNoPreview), findsNothing);
      final modes = tester.widget<AppSegmentedControl<ViewerMode>>(
        find.byType(AppSegmentedControl<ViewerMode>),
      );
      expect(modes.value, ViewerMode.text);
      await menu(tester);
      expect(item(tester, en.cmdViewerFind).enabled, isTrue);
      expect(item(tester, en.cmdViewerGoTo).enabled, isTrue);
      expect(item(tester, en.cmdViewerToggleWrap).enabled, isTrue);
      await pick(tester, en.cmdViewerFind);
      await tester.enterText(find.byType(AppSearchField), 'numbers');
      await tester.pumpAndSettle();
      expect(find.text(en.viewerMatches(1, 1)), findsOneWidget);
      verify(() => files.readRange(any(), 0, bytes.length)).called(1);
      expect(tester.takeException(), isNull);
    });
  }

  Future<void> settleImage(WidgetTester tester) async {
    // Engine codecs run outside the widget test's fake clock.
    for (
      var i = 0;
      i < 100 &&
          !tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((image) => image.image != null);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    for (final location in [
      const Location.native('/tmp/README.MD'),
      const Location.inArchive(archive: '/tmp/docs.zip', path: 'README.md'),
      const Location.remote(
        server: 'sftp://user@example.com:22',
        path: '/README.md',
      ),
    ]) {
      testWidgets(
        '${brightness.name}: ${location.kind.name} Markdown opens rendered once',
        (tester) async {
          bytes = Uint8List.fromList(
            utf8.encode(
              '# Heading\n\nText with **bold** and `code`.\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n- [x] Done\n- [ ] Todo\n\n```dart\nfinal answer = 42;\n```',
            ),
          );
          final files = await open(
            tester,
            location: location,
            brightness: brightness,
          );
          final markdown = tester.widget<Markdown>(find.byType(Markdown));
          expect(markdown.selectable, isTrue);
          expect(
            markdown.styleSheet!.h1!.fontSize,
            greaterThan(markdown.styleSheet!.p!.fontSize!),
          );
          expect(find.byType(Table), findsOneWidget);
          expect(
            tester
                .widgetList<AppCheckbox>(find.byType(AppCheckbox))
                .map((c) => c.value),
            [true, false],
          );
          verify(() => files.readRange(location, 0, bytes.length)).called(1);
          verifyNever(() => files.preparePreview(any()));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Markdown refresh and source/hex switching use current file contents',
    (tester) async {
      const location = Location.native('/tmp/readme.md');
      bytes = Uint8List.fromList(utf8.encode('# Original'));
      final files = await open(tester, location: location);
      bytes = Uint8List.fromList(utf8.encode('# Revised'));
      await tester.tap(button(en.cmdRefresh));
      await tester.pumpAndSettle();
      expect(tester.widget<Markdown>(find.byType(Markdown)).data, '# Revised');
      await menu(tester);
      await pick(tester, en.cmdViewerText);
      expect(find.textContaining('# Revised'), findsOneWidget);
      await menu(tester);
      await pick(tester, en.cmdViewerHex);
      expect(find.byType(Markdown), findsNothing);
      await menu(tester);
      await pick(tester, en.cmdViewerPreview);
      expect(tester.widget<Markdown>(find.byType(Markdown)).data, '# Revised');
      verify(() => files.readRange(location, 0, any())).called(4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Markdown scrolls with keys and changes type size without rereading',
    (tester) async {
      bytes = Uint8List.fromList(
        utf8.encode(
          List.generate(100, (i) => 'Paragraph $i with text.').join('\n\n'),
        ),
      );
      final files = await open(
        tester,
        location: const Location.native('/tmp/notes.md'),
        width: 480,
      );
      final initial = tester.widget<Markdown>(find.byType(Markdown));
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(initial.controller!.offset, greaterThan(0));
      unawaited(preferences.update((p) => p.copyWith(viewerFontSize: 20)));
      await tester.pumpAndSettle();
      final resized = tester.widget<Markdown>(find.byType(Markdown));
      expect(resized.controller, same(initial.controller));
      expect(resized.styleSheet!.p!.fontSize, 20);
      verify(() => files.readRange(any(), 0, any())).called(1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow Markdown at large text scale keeps links keyboard accessible',
    (tester) async {
      bytes = Uint8List.fromList(
        utf8.encode(
          '# Guide\n\nA [reference](https://example.com/docs).\n\n> Quote\n\n```\nlong_code_line_that_scrolls_horizontally_without_overflow\n```',
        ),
      );
      await open(
        tester,
        location: const Location.native('/tmp/guide.md'),
        width: 340,
        textScale: 2,
      );
      final focus = Focus.of(tester.element(find.text('reference')));
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text(en.viewerLinkTitle), findsOneWidget);
      expect(find.text('https://example.com/docs'), findsWidgets);
      await tester.tap(find.text(en.actionDone));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('oversized Markdown shows the limit without reading the body', (
    tester,
  ) async {
    bytes = Uint8List(maxMarkdownPreviewBytes + 1);
    final files = await open(
      tester,
      location: const Location.native('/tmp/large.md'),
    );
    expect(
      find.text(en.markdownTooLarge(en.fileSize(maxMarkdownPreviewBytes))),
      findsOneWidget,
    );
    expect(find.byType(Markdown), findsNothing);
    verifyNever(() => files.readRange(any(), any(), any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'relative Markdown images read through the repository, external ones retain alt text',
    (tester) async {
      const location = Location.inArchive(
        archive: '/tmp/docs.zip',
        path: 'guide/README.md',
      );
      const image = Location.inArchive(
        archive: '/tmp/docs.zip',
        path: 'images/pixel.png',
      );
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
      );
      bytes = Uint8List.fromList(
        utf8.encode(
          '[![Pixel](../images/pixel.png)](../images/pixel.png)\n\n![Remote image](https://example.com/image.png)',
        ),
      );
      final files = await open(
        tester,
        location: location,
        images: {image: png},
      );
      await settleImage(tester);
      expect(find.text('Remote image'), findsOneWidget);
      verify(() => files.fileSize(image)).called(1);
      verify(() => files.readRange(image, 0, png.length)).called(1);
      final widget = tester.widget<Image>(find.byType(Image));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(widget.image, isA<ResizeImage>());
      expect((widget.image as ResizeImage).policy, ResizeImagePolicy.fit);
      await tester.tap(button(en.cmdRefresh));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settleImage(tester);
      verify(() => files.readRange(image, 0, png.length)).called(1);
      verifyNever(() => files.preparePreview(any()));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'oversized Markdown images retain alt text without reading their body',
    (tester) async {
      const image = Location.native('/tmp/large.png');
      bytes = Uint8List.fromList(utf8.encode('![Large image](large.png)'));
      final files = await open(
        tester,
        location: const Location.native('/tmp/README.md'),
        imageSizes: {image: 8 * 1024 * 1024 + 1},
      );
      await tester.pumpAndSettle();
      expect(find.text('Large image'), findsOneWidget);
      verify(() => files.fileSize(image)).called(1);
      verifyNever(() => files.readRange(image, any(), any()));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the viewer is a page of its own: shown as the app routes to '
      'it, with nothing above it, its bar draws', (tester) async {
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(AppIconButton), findsWidgets);
    expect(find.textContaining('quarterly numbers'), findsOneWidget);
  });

  testWidgets('scroll keys reach the text viewport from the viewer focus', (
    tester,
  ) async {
    bytes = Uint8List.fromList(
      utf8.encode(List.generate(200, (i) => 'Line $i').join('\n')),
    );
    await open(tester);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).last);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
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

  testWidgets('books start in Preview without reading a binary text window; '
      'switching to Hex cancels preparation', (tester) async {
    final lease = _PendingPreview();
    const book = Location.native('/tmp/book.epub');
    final files = await open(
      tester,
      location: book,
      preparePreview: () => lease,
    );
    verify(() => files.preparePreview(book)).called(1);
    verifyNever(() => files.fileSize(any()));
    verifyNever(() => files.readRange(any(), any(), any()));
    await tester.tap(button(en.viewerActions));
    await tester.pump(const Duration(milliseconds: 300));
    expect(item(tester, en.cmdViewerPreview).checked, isTrue);
    await pick(tester, en.cmdViewerHex);
    expect(lease.closes, 1);
    verify(() => files.readRange(book, 0, bytes.length)).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh replaces a pending document lease and route disposal '
      'cancels the replacement', (tester) async {
    final leases = <_PendingPreview>[];
    await open(
      tester,
      location: const Location.inArchive(
        archive: '/tmp/library.zip',
        path: 'book.epub',
      ),
      preparePreview: () {
        final lease = _PendingPreview();
        leases.add(lease);
        return lease;
      },
    );
    expect(leases, hasLength(1));
    // A pending document intentionally animates its spinner.
    await tester.tap(button(en.cmdRefresh));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(leases, hasLength(2));
    expect(leases.first.closes, 1);
    expect(leases.last.closes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(leases.last.closes, 1);
    expect(tester.takeException(), isNull);
  });
}
