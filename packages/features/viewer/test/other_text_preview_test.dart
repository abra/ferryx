import 'dart:convert';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:viewer_feature/viewer_feature.dart';
import 'package:viewer_feature/src/delimited_preview.dart';
import 'package:viewer_feature/src/rich_text_preview.dart';
import 'package:viewer_feature/src/viewer_footer.dart';
import 'package:viewer_feature/src/viewer_views.dart';

class _Files extends Mock implements FileRepository {
  _Files(String text) : content = Uint8List.fromList(utf8.encode(text));
  Uint8List content;
}

class _Host {
  final full = ValueNotifier(true);
  final viewerKey = GlobalKey();
  final filesFocus = FocusNode(debugLabel: 'files');
  final viewerScope = FocusScopeNode(debugLabel: 'viewer');
  void dispose() {
    full.dispose();
    filesFocus.dispose();
    viewerScope.dispose();
  }
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

void main() {
  const file = Location.native('/tmp/test.txt');
  final en = lookupFerryxLocalizations(const Locale('en'));
  late PreferencesService preferences;
  setUpAll(() {
    registerFallbackValue(file);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(TextDocumentFormat.rtf);
  });
  setUp(
    () async => preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    ),
  );

  ViewerCubit cubit(WidgetTester tester) =>
      tester.element(find.byType(ViewerFooter)).read<ViewerCubit>();

  Future<(_Files, _Host)> open(
    WidgetTester tester,
    String name,
    String source, {
    String converted = '<h1>Formatted heading</h1><p><strong>Bold</strong> and <em>italic</em>.</p>',
    Brightness brightness = Brightness.light,
    double width = 900,
    double scale = 1,
    bool fullWindow = true,
  }) async {
    final host = _Host();
    host.full.value = fullWindow;
    addTearDown(host.dispose);
    addTearDown(() async {
      final closed = preferences.dispose();
      await tester.pump();
      await closed;
    });
    final files = _Files(source);
    when(() => files.fileSize(any()))
        .thenAnswer((_) async => files.content.length);
    when(() => files.readRange(any(), any(), any())).thenAnswer((call) async {
      final offset = call.positionalArguments[1] as int;
      final length = call.positionalArguments[2] as int;
      return Uint8List.sublistView(
        files.content,
        offset,
        (offset + length).clamp(0, files.content.length),
      );
    });
    when(() => files.renderTextDocument(any(), any()))
        .thenAnswer((_) async => converted);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(AppPlatformStyle.macos, brightness),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ValueListenableBuilder<bool>(
          valueListenable: host.full,
          builder: (context, full, _) {
            final viewer = ViewerScreen(
              key: host.viewerKey,
              files: files,
              preferences: preferences,
              shortcutMap: ShortcutMap.defaults(TargetPlatform.macOS),
              windowDecor: WindowDecor.none,
              location: Location.native('/tmp/$name'),
              startInPreview: true,
              autofocus: full,
              focusScope: host.viewerScope,
              fullWindow: full,
              onClose: host.filesFocus.requestFocus,
              onToggleFullWindow: () => host.full.value = !full,
              onFocusFiles: host.filesFocus.requestFocus,
            );
            return full
                ? viewer
                : Row(
                    children: [
                      Expanded(
                        child: Focus(
                          focusNode: host.filesFocus,
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
    await _waitFor(tester, () => !cubit(tester).state.loading);
    await tester.pumpAndSettle();
    return (files, host);
  }

  for (final brightness in Brightness.values) {
    for (final (name, format) in [
      ('doc.rtf', TextDocumentFormat.rtf),
      ('doc.adoc', TextDocumentFormat.asciiDoc),
      ('doc.rst', TextDocumentFormat.reStructuredText),
      ('doc.docx', TextDocumentFormat.docx),
      ('doc.xlsx', TextDocumentFormat.xlsx),
      ('doc.pptx', TextDocumentFormat.pptx),
      ('doc.doc', TextDocumentFormat.doc),
      ('doc.xls', TextDocumentFormat.xls),
      ('doc.ppt', TextDocumentFormat.ppt),
    ]) {
      testWidgets(
        '${brightness.name}: $name uses its native converter and renders formatted text',
        (tester) async {
          final (files, _) = await open(
            tester,
            name,
            'source bytes',
            brightness: brightness,
          );
          expect(find.byType(RichTextPreview), findsOneWidget);
          expect(
            find.text('Formatted heading', findRichText: true),
            findsWidgets,
          );
          expect(cubit(tester).state.mode, ViewerMode.preview);
          verify(() => files.renderTextDocument(any(), format)).called(1);
          verify(() => files.readRange(any(), 0, files.content.length))
              .called(1);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '${brightness.name}: narrow HTML retains document content and keyboard links',
      (tester) async {
        final (files, _) = await open(
          tester,
          'guide.html',
          '<h1>Heading</h1><p><b>Bold</b> <a href="https://example.com">Reference</a></p><script>do_not_run()</script>',
          width: 340,
          scale: 1.75,
          brightness: brightness,
        );
        expect(find.text('Heading', findRichText: true), findsWidgets);
        final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
        expect(html.html, isNot(contains('<script')));
        final focus = Focus.of(tester.element(find.text('Reference')));
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(find.text(en.viewerLinkTitle), findsOneWidget);
        await tester.tap(find.text(en.actionDone));
        await tester.pumpAndSettle();
        verifyNever(() => files.renderTextDocument(any(), any()));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${brightness.name}: CSV table preserves source rows and strings at large text scale',
      (tester) async {
        await open(
          tester,
          'table.csv',
          'id,note,value\n001,"comma, inside",002\n003,last,004',
          width: 340,
          scale: 1.75,
          brightness: brightness,
        );
        final table = tester.widget<DelimitedPreview>(
          find.byType(DelimitedPreview),
        );
        expect(table.data.rows.length, 3);
        expect(table.data.rows[1], ['001', 'comma, inside', '002']);
        expect(find.text('A'), findsOneWidget);
        expect(find.text('001'), findsOneWidget);
        expect(find.text(en.textPreviewTableSize(3, 3)), findsOneWidget);
        final highlight = FocusManager.instance.highlightStrategy;
        addTearDown(() => FocusManager.instance.highlightStrategy = highlight);
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        final cell = find.text('comma, inside');
        final focus = Focus.of(tester.element(cell));
        focus.requestFocus();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(focus.hasPrimaryFocus, isTrue);
        expect(find.text('comma, inside'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'HTML fragment links navigate to an offscreen heading',
    (tester) async {
      await open(
        tester,
        'guide.html',
        '<p><a href="#last">Jump to end</a></p>'
            '${List.generate(100, (i) => '<p>Paragraph $i.</p>').join()}'
            '<h2 id="last">Last section</h2>',
      );
      final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
      final scroll = (html.renderMode as ListViewMode).controller!;
      final focus = Focus.of(tester.element(find.text('Jump to end')));
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(find.text('Last section', findRichText: true), findsWidgets);
      expect(find.text(en.viewerLinkTitle), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'code highlighting retains Find and does not reparse or reread on a query change',
    (tester) async {
      final (files, _) = await open(
        tester,
        'source.rs',
        'fn main() { let message = "Привет"; }',
      );
      await _waitFor(tester, () => cubit(tester).state.syntaxRevision > 0);
      final before = cubit(tester).state;
      final text = tester.widget<TextView>(find.byType(TextView));
      expect(
        text.syntax.expand((line) => line).any((t) => t.scope.isNotEmpty),
        isTrue,
      );
      expect(
        invokeCommand(
          tester.element(find.byType(TextView)),
          AppCommand.viewerFind,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(AppSearchField), 'message');
      await tester.pumpAndSettle();
      expect(find.text(en.viewerMatches(1, 1)), findsOneWidget);
      expect(cubit(tester).state.syntaxRevision, before.syntaxRevision);
      expect(cubit(tester).state.syntax, same(before.syntax));
      verify(() => files.readRange(any(), 0, files.content.length)).called(1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid and oversized table previews expose a working Open Text button',
    (tester) async {
      final (files, _) = await open(tester, 'table.csv', '"unclosed');
      expect(find.text(en.textPreviewFailed), findsOneWidget);
      await tester.tap(find.text(en.textPreviewSource));
      await tester.pumpAndSettle();
      expect(find.byType(TextView), findsOneWidget);
      expect(cubit(tester).state.window.lines, ['"unclosed']);
      verify(() => files.readRange(any(), 0, files.content.length)).called(2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final table in [false, true]) {
    testWidgets(
      '${table ? 'table' : 'HTML'} keeps scroll, state and file focus across placements',
      (tester) async {
        final source = table
            ? List.generate(200, (i) => '$i,value $i').join('\n')
            : List.generate(100, (i) => '<p>Paragraph $i.</p>').join();
        final (files, host) = await open(
          tester,
          table ? 'data.tsv' : 'doc.html',
          table ? source.replaceAll(',', '\t') : source,
          width: 1400,
          fullWindow: false,
        );
        expect(host.filesFocus.hasPrimaryFocus, isTrue);
        host.viewerScope.requestFocus();
        await tester.pumpAndSettle();
        final preview = table
            ? find.byType(DelimitedPreview)
            : find.byType(RichTextPreview);
        final state = tester.state(preview);
        final scroll = table
            ? tester
                  .widget<ViewerScrollFrame>(find.byType(ViewerScrollFrame))
                  .vertical
            : (tester.widget<HtmlWidget>(find.byType(HtmlWidget)).renderMode
                      as ListViewMode)
                  .controller!;
        await _waitFor(tester, () => scroll.hasClients);
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
        final offset = scroll.offset;
        expect(offset, greaterThan(0));
        for (final full in [true, false]) {
          expect(
            invokeCommand(
              tester.element(preview),
              AppCommand.viewerToggleFullWindow,
            ),
            isTrue,
          );
          await tester.pumpAndSettle();
          expect(host.full.value, full);
          expect(tester.state(preview), same(state));
          expect(scroll.offset, offset);
        }
        verify(() => files.readRange(any(), 0, files.content.length)).called(1);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
