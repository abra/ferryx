import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pagecraft/all_formats.dart';
import 'package:pagecraft/testing.dart';

/// A section laid out with the test font, whose glyphs are boxes: the
/// goldens show where text, borders, markers and images go, not glyphs.
const book = BookStyle(
  fontScale: 12 / 16,
  lineHeight: 1.5,
  textIndent: 1.5,
  overrideColor: false,
);

final body =
    '''
<h1>Chapter</h1>
<p>The first paragraph has enough words to wrap over several lines of the page.</p>
<p>A second one, with <b>bold</b> and <i>italic</i> words and <a href="#n">a link</a>.</p>
<ul><li>One item</li><li>Another item</li></ul>
<blockquote style="border-left: 3px solid #888; padding-left: 8px; background-color: #eeeeee">A quoted line.</blockquote>
<p style="text-align: center"><img src="pic.png"/></p>
<p>${'Long text to fill the rest of the column and spill onto the next page. ' * 6}</p>
''';

void main() {
  final images = <String, Uint8List>{
    'pic.png': encodeSolidPng(120, 60, rgba: 0x3366AAFF),
  };

  Future<(ColumnLayout, List<ColumnPage>, BookImageCache)> laidOut(
    WidgetTester tester, {
    double width = 280,
  }) async {
    final doc = ContentDocument.parseXml(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body>$body</body></html>',
    );
    final styles =
        StyleResolver([
          CssSheetSource(
            CssStyleSheet.parse(cssUserAgentStyleSheet),
            CssOrigin.userAgent,
          ),
          ...readerSheetSources(book),
        ]).resolve(
          doc,
          options: StyleResolverOptions(rootFontSize: book.rootFontSize),
        );
    final cache = BookImageCache(read: (key) async => images[key]);
    await tester.runAsync(() => cache.probe(images.keys));
    final column = ColumnLayout.layout(
      buildSectionBoxes(doc, styles),
      width: width,
      pageHeight: 360,
      bookStyle: book,
      text: TextLayoutEnvironment(
        styler: InlineStyler(bookStyle: book, fonts: const BookFonts()),
        imageSize: cache.sizeOf,
        maxImageHeight: 360,
      ),
    );
    addTearDown(column.dispose);
    addTearDown(cache.dispose);
    return (column, paginateColumn(column, pageHeight: 360), cache);
  }

  Future<void> show(
    WidgetTester tester,
    ColumnLayout column,
    ColumnPage page,
    BookImageCache cache,
  ) async {
    tester.view.physicalSize = const Size(320, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ColoredBox(
        color: Colors.white,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: const ValueKey('page'),
            child: TextColumnPage(
              column: column,
              page: page,
              images: cache,
              imageKey: (src) => src,
              padding: const EdgeInsets.all(20),
            ),
          ),
        ),
      ),
    );
    // Let the image decode, then repaint.
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && cache.image('pic.png', 120) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
  }

  testWidgets('the page is the column width plus padding, sized by the page', (
    tester,
  ) async {
    final (column, pages, cache) = await laidOut(tester);
    expect(pages.length, greaterThan(1));
    await show(tester, column, pages.first, cache);
    final page = tester.renderObject<RenderBox>(find.byType(TextColumnPage));
    expect(page.size, Size(320, pages.first.height + 40));
    expect((page as RenderTextColumnPage).isRepaintBoundary, isTrue);
  });

  testWidgets('a new page, column or padding resizes the page', (
    tester,
  ) async {
    // The page view reuses a page's render object for the next page.
    final (column, pages, cache) = await laidOut(tester);
    final short = pages.last;
    final tall = pages.first;
    expect(short.height, lessThan(tall.height));
    RenderBox page() =>
        tester.renderObject<RenderBox>(find.byType(TextColumnPage));
    await show(tester, column, short, cache);
    expect(page().size, Size(320, short.height + 40));
    await show(tester, column, tall, cache);
    expect(page().size, Size(320, tall.height + 40));

    await tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: const ValueKey('page'),
          child: TextColumnPage(
            column: column,
            page: tall,
            images: cache,
            imageKey: (src) => src,
            padding: const EdgeInsets.all(10),
          ),
        ),
      ),
    );
    expect(page().size, Size(300, tall.height + 20));

    final (narrow, narrowPages, narrowCache) = await laidOut(
      tester,
      width: 200,
    );
    await tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: const ValueKey('page'),
          child: TextColumnPage(
            column: narrow,
            page: narrowPages.first,
            images: narrowCache,
            imageKey: (src) => src,
            padding: const EdgeInsets.all(10),
          ),
        ),
      ),
    );
    expect(page().size, Size(220, narrowPages.first.height + 20));
  });

  testWidgets('first page', (tester) async {
    final (column, pages, cache) = await laidOut(tester);
    await show(tester, column, pages.first, cache);
    await expectLater(
      find.byKey(const ValueKey('page')),
      matchesGoldenFile('goldens/text_page_first.png'),
    );
  });

  testWidgets('second page starts on a whole line', (tester) async {
    final (column, pages, cache) = await laidOut(tester);
    await show(tester, column, pages[1], cache);
    await expectLater(
      find.byKey(const ValueKey('page')),
      matchesGoldenFile('goldens/text_page_second.png'),
    );
  });
}
