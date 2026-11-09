import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

import 'corpus_book.dart';
import 'corpus_report.dart';

/// pagecraft on a whole folder of real books: every EPUB, FB2 and MOBI in
/// `PAGECRAFT_CORPUS` opens (or is refused with a [PagecraftException]), its
/// cover reads, its contents point into the book, every section's styles
/// resolve without losing a character, and every section lays out into
/// pages. It also times every open, section load, style pass and layout
/// and records the process memory growth; `PAGECRAFT_CORPUS_REPORT=<file>`
/// writes the table as Markdown.
///
///     PAGECRAFT_CORPUS=~/Books fvm flutter test test/corpus/corpus_test.dart
///
/// Skipped when `PAGECRAFT_CORPUS` is not set: the corpus is not in the repo.
void main() {
  final corpus = Platform.environment['PAGECRAFT_CORPUS'];
  if (corpus == null || corpus.isEmpty) {
    test(
      'corpus',
      () {},
      skip: 'set PAGECRAFT_CORPUS to run on real books',
    );
    return;
  }
  final files =
      Directory(corpus)
          .listSync(followLinks: true)
          .whereType<File>()
          .where((f) => isCorpusBook(f.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final report = CorpusReport();

  tearDownAll(() {
    final markdown = report.toMarkdown();
    // ignore: avoid_print
    print(markdown);
    final out = Platform.environment['PAGECRAFT_CORPUS_REPORT'];
    if (out != null && out.isNotEmpty) File(out).writeAsStringSync(markdown);
  });

  for (final file in files) {
    final path = file.path;
    final name = path.substring(path.lastIndexOf('/') + 1);

    group(name, () {
      CorpusBook? book;
      Object? refusal;
      late CorpusRow row;

      setUpAll(() async {
        final bytes = file.lengthSync();
        final rssBefore = ProcessInfo.currentRss;
        final watch = Stopwatch()..start();
        try {
          book = await CorpusBook.open(path);
        } on Object catch (error) {
          refusal = error;
          report.add(
            row = CorpusRow(
              name: name,
              kind: 'refused',
              bytes: bytes,
              note: '$error',
            ),
          );
          return;
        }
        final openMs = watch.elapsedMilliseconds;
        watch.reset();
        final loaded = await book!.loadAllSections();
        report.add(
          row = CorpusRow(
            name: name,
            kind: book!.kind,
            bytes: bytes,
            openMs: openMs,
            sectionsMs: watch.elapsedMilliseconds,
            sectionCount: loaded.length,
            textBytes: loaded.fold<int>(0, (sum, s) => sum + s.bytes),
            rssGrowthBytes: ProcessInfo.currentRss - rssBefore,
          ),
        );
      });

      tearDownAll(() => book?.close());

      /// The opened book, or a skip when it was refused.
      CorpusBook? opened() {
        if (book == null) markTestSkipped('refused: $refusal');
        return book;
      }

      test('opens, or is refused with a PagecraftException', () {
        if (refusal != null) expect(refusal, isA<PagecraftException>());
      });

      test('its cover reads', () async {
        await opened()?.readCover();
      });

      test('its contents point into the book', () async {
        final book = opened();
        if (book == null) return;
        var unresolved = 0;
        for (final href in book.navHrefs()) {
          final index = await book.resolveHrefIndex(href);
          if (index == null || index < 0) {
            // A publisher's entry for a file the book lacks.
            unresolved++;
            continue;
          }
          expect(index, lessThan(book.sectionCount), reason: href);
        }
        if (unresolved > 0) {
          row.notes.add('$unresolved nav entries open nothing');
        }
      });

      test('styles resolve and boxes keep every character', () async {
        final book = opened();
        if (book == null) return;
        // The CSS engine must take every real stylesheet and document
        // without failing, in reasonable time, with few distinct styles.
        final ua = CssSheetSource(
          CssStyleSheet.parse(cssUserAgentStyleSheet),
          CssOrigin.userAgent,
        );
        var sheets = 0;
        var rules = 0;
        var distinct = 0;
        var elements = 0;
        // Sections sharing a sheet set share a resolver, as a reader would.
        final resolvers = <String, StyleResolver>{};
        final lost = <String>[];
        final treeWatch = Stopwatch();
        final boxWatch = Stopwatch();
        final styleWatch = Stopwatch();
        for (var i = 0; i < book.sectionCount; i++) {
          treeWatch.start();
          final doc = await book.contentDocument(i);
          treeWatch.stop();
          if (doc == null) continue;
          styleWatch.start();
          final loaded = await book.styleSheets(i, doc);
          sheets += loaded.length;
          rules += loaded.fold<int>(0, (n, s) => n + s.rules.length);
          final key = loaded.map((s) => identityHashCode(s)).join(',');
          final resolver = resolvers.putIfAbsent(
            key,
            () => StyleResolver([
              ua,
              for (final sheet in loaded)
                CssSheetSource(sheet, CssOrigin.author),
            ]),
          );
          final styles = resolver.resolve(doc);
          styleWatch.stop();
          distinct += styles.distinctStyleCount;
          elements += doc.nodeCount;
          boxWatch.start();
          final boxes = buildSectionBoxes(doc, styles);
          boxWatch.stop();
          lost.addAll(
            lostCharacters(doc, styles, boxes).map((l) => 'section $i: $l'),
          );
        }
        row
          ..treeMs = treeWatch.elapsedMilliseconds
          ..styleMs = styleWatch.elapsedMilliseconds
          ..boxMs = boxWatch.elapsedMilliseconds
          ..sheets = sheets
          ..rules = rules
          ..distinctStyles = distinct
          ..styledNodes = elements;
        expect(
          lost,
          isEmpty,
          reason:
              'every rendered character must reach a paragraph:\n'
              '${lost.take(10).join('\n')}',
        );
      });

      // A book of hundreds of chapters takes longer than a test's default
      // 30 seconds; per-section times go to the report.
      test(
        'lays every section out into pages',
        timeout: const Timeout(Duration(minutes: 5)),
        () async {
          if (opened() == null) return;
          // The whole text pipeline on a real book at a phone's page size:
          // sections prepared in an isolate, laid out, paginated. The host
          // draws with the test font, so times are for comparison between
          // runs, not for the device budget.
          final source = textBookSourceOf(await openBook(path));
          final images = BookImageCache(read: source.readImage);
          const style = BookStyle();
          final preparer = SectionPreparer(source);
          final prepareWatch = Stopwatch();
          final layoutWatch = Stopwatch();
          var pages = 0;
          var worstLayout = 0;
          try {
            for (var i = 0; i < source.sectionCount; i++) {
              prepareWatch.start();
              final section = await preparer.prepare(i, style);
              prepareWatch.stop();
              final started = layoutWatch.elapsedMilliseconds;
              layoutWatch.start();
              final column = await layoutSection(
                section,
                width: 340,
                pageHeight: 600,
                style: style,
                fonts: const BookFonts(),
                images: images,
              );
              final sectionPages = paginateColumn(column, pageHeight: 600);
              layoutWatch.stop();
              final spent = layoutWatch.elapsedMilliseconds - started;
              if (spent > worstLayout) worstLayout = spent;
              expect(sectionPages.first.top, 0);
              // The margins after the last content take no page.
              expect(sectionPages.last.bottom, column.contentHeight);
              for (final page in sectionPages) {
                expect(page.height, lessThanOrEqualTo(600.5));
              }
              pages += sectionPages.length;
              column.dispose();
            }
          } finally {
            images.dispose();
            await source.close();
          }
          row
            ..prepareMs = prepareWatch.elapsedMilliseconds
            ..layoutMs = layoutWatch.elapsedMilliseconds
            ..worstLayoutMs = worstLayout
            ..pages = pages;
        },
      );
    });
  }
}
