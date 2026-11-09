import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// Pages laid out with the test font: every glyph is a box as wide as
/// the font size (12 here).
const book = BookStyle(
  fontScale: 12 / 16,
  lineHeight: 1.5,
  overrideColor: false,
  justify: false,
);
const padding = EdgeInsets.all(20);
const yellow = Color(0xD1FFE600);
const blue = Color(0xB866B2FF);

const first =
    'Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu.';
const second = 'Second paragraph with a few more words.';
final third = 'Long text to fill the column and spill onto the next page. ' * 4;
final body = '<p>$first</p><p>$second</p><p>Note<sup>12</sup> here. $third</p>';

({ContentDocument doc, ColumnLayout column, List<ColumnPage> pages}) layOut(
  String body, {
  double pageHeight = 200,
}) {
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
  final column = ColumnLayout.layout(
    buildSectionBoxes(doc, styles),
    width: 280,
    pageHeight: pageHeight,
    bookStyle: book,
    text: TextLayoutEnvironment(
      styler: InlineStyler(bookStyle: book, fonts: const BookFonts()),
      imageSize: (_) => null,
      maxImageHeight: pageHeight,
    ),
  );
  addTearDown(column.dispose);
  return (
    doc: doc,
    column: column,
    pages: paginateColumn(column, pageHeight: pageHeight),
  );
}

void main() {
  /// Text node [n] (0-based) of the document.
  int textNode(ContentDocument doc, int n) {
    var seen = 0;
    for (var i = 0; i < doc.nodeCount; i++) {
      if (doc.isText(i) && seen++ == n) return i;
    }
    throw StateError('$n');
  }

  int element(ContentDocument doc, String name) {
    for (var i = 0; i < doc.nodeCount; i++) {
      if (doc.isElement(i) && doc.localNameOf(i) == name) return i;
    }
    throw StateError(name);
  }

  TextHighlight highlight(
    String id,
    TextPoint start,
    TextPoint end, [
    Color color = yellow,
  ]) => TextHighlight(
    id: id,
    range: TextPointRange(start, end),
    color: color,
  );

  test('a highlight inside a paragraph covers its words', () {
    final (:doc, :column, :pages) = layOut(body);
    final t = textNode(doc, 0);
    final placed = placeHighlights(doc, column, pages.first, [
      highlight('beta', TextPoint(t, 6), TextPoint(t, 10)),
    ]);
    expect(placed, hasLength(1));
    expect((placed.single.start, placed.single.end), (6, 10));
    expect(placed.single.rects.single.width, 4 * 12);
    final item = placed.single.item;
    expect(placed.single.rects.single.top, greaterThanOrEqualTo(item.rect.top));
  });

  test('a highlight across paragraphs has a part in each', () {
    final (:doc, :column, :pages) = layOut(body);
    final one = textNode(doc, 0);
    final two = textNode(doc, 1);
    final placed = placeHighlights(doc, column, pages.first, [
      highlight('span', TextPoint(one, first.length - 3), TextPoint(two, 6)),
    ]);
    expect(
      [for (final p in placed) (p.start, p.end)],
      [
        (first.length - 3, first.length),
        (0, 6),
      ],
    );
  });

  test('raised text and element boundaries map to their placeholder', () {
    final (:doc, :column, :pages) = layOut(body);
    final sup = element(doc, 'sup');
    final placed = placeHighlights(doc, column, pages.first, [
      highlight('ref', TextPoint(sup, 0), TextPoint(sup, 1)),
      highlight('word', TextPoint(sup - 1, 0), TextPoint(sup, 1)),
      highlight('number', TextPoint(sup + 1, 0), TextPoint(sup + 1, 1)),
    ]);
    expect(
      [for (final p in placed) (p.start, p.end)],
      [
        (4, 5),
        (0, 5),
        (4, 5),
      ],
      reason: 'part of the number is the whole placeholder',
    );
    expect(placed.first.item.paragraph.box.plainText(0, 5), 'Note12');
  });

  test('pages place only what they show, a split paragraph on both', () {
    final (:doc, :column, :pages) = layOut(body);
    expect(pages.length, greaterThan(1));
    final long = textNode(doc, 4);
    final whole = highlight(
      'long',
      TextPoint(long, 0),
      TextPoint(long, doc.textOf(long).length),
    );
    final onFirst = placeHighlights(doc, column, pages.first, [whole]);
    final onSecond = placeHighlights(doc, column, pages[1], [whole]);
    expect(onFirst, hasLength(1));
    expect(onSecond, hasLength(1));
    expect(onSecond.single.item, same(onFirst.single.item));
    final t = textNode(doc, 0);
    expect(
      placeHighlights(doc, column, pages[1], [
        highlight('beta', TextPoint(t, 6), TextPoint(t, 10)),
      ]),
      isEmpty,
      reason: 'not on this page',
    );
    expect(
      placeHighlights(doc, column, pages.first, [
        highlight('empty', TextPoint(t, 6), TextPoint(t, 6)),
      ]),
      isEmpty,
    );
  });

  group('on a page', () {
    late BookImageCache images;
    setUp(() => images = BookImageCache(read: (_) async => null));
    tearDown(() => images.dispose());

    Future<RenderTextColumnPage> show(
      WidgetTester tester,
      ContentDocument doc,
      ColumnLayout column,
      ColumnPage page,
      List<TextHighlight> highlights,
    ) async {
      tester.view.physicalSize = const Size(320, 260);
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
                images: images,
                imageKey: (src) => src,
                padding: padding,
                document: doc,
                highlights: highlights,
              ),
            ),
          ),
        ),
      );
      return tester.renderObject<RenderTextColumnPage>(
        find.byType(TextColumnPage),
      );
    }

    testWidgets('taps find the topmost highlight, menus its boxes', (
      tester,
    ) async {
      final (:doc, :column, :pages) = layOut(body);
      final t = textNode(doc, 0);
      final page = await show(tester, doc, column, pages.first, [
        highlight('older', TextPoint(t, 0), TextPoint(t, 10)),
        highlight('newer', TextPoint(t, 6), TextPoint(t, 16), blue),
      ]);
      final item = column.items.whereType<ColumnText>().first;
      Offset atChar(int offset) =>
          padding.topLeft +
          item.rect.topLeft +
          item.paragraph.boxesFor(offset, offset + 1).first.toRect().center;
      expect(page.highlightAt(atChar(1))?.id, 'older');
      expect(page.highlightAt(atChar(7))?.id, 'newer', reason: 'on top');
      expect(page.highlightAt(atChar(12))?.id, 'newer');
      expect(page.highlightAt(atChar(20)), isNull);
      expect(page.highlightAt(const Offset(5, 5)), isNull, reason: 'margin');
      final rects = page.highlightRects('newer');
      expect(rects, hasLength(1));
      expect(rects.single.contains(atChar(12)), isTrue);
      expect(page.highlightRects('missing'), isEmpty);
    });

    testWidgets('a highlight split by the page answers only where shown', (
      tester,
    ) async {
      final (:doc, :column, :pages) = layOut(body);
      final long = textNode(doc, 4);
      final whole = highlight(
        'long',
        TextPoint(long, 0),
        TextPoint(long, doc.textOf(long).length),
      );
      final page = await show(tester, doc, column, pages[1], [whole]);
      final rects = page.highlightRects('long');
      expect(rects, isNotEmpty);
      for (final rect in rects) {
        expect(rect.top, greaterThanOrEqualTo(padding.top - 0.5));
        expect(rect.bottom, lessThanOrEqualTo(padding.top + pages[1].height));
      }
      expect(page.highlightAt(rects.first.center)?.id, 'long');
    });

    testWidgets('highlights are tinted under the text', (tester) async {
      final (:doc, :column, :pages) = layOut(body);
      final one = textNode(doc, 0);
      final two = textNode(doc, 1);
      final sup = element(doc, 'sup');
      await show(tester, doc, column, pages.first, [
        highlight('a', TextPoint(one, 6), TextPoint(one, 30)),
        highlight('b', TextPoint(one, 23), TextPoint(two, 6), blue),
        highlight('c', TextPoint(sup, 0), TextPoint(sup, 1)),
      ]);
      await expectLater(
        find.byKey(const ValueKey('page')),
        matchesGoldenFile('goldens/text_page_highlights.png'),
      );
    });

    testWidgets('new highlights repaint the page', (tester) async {
      final (:doc, :column, :pages) = layOut(body);
      final t = textNode(doc, 0);
      final item = column.items.whereType<ColumnText>().first;
      final at =
          padding.topLeft +
          item.rect.topLeft +
          item.paragraph.boxesFor(1, 2).first.toRect().center;
      var page = await show(tester, doc, column, pages.first, const []);
      expect(page.highlightAt(at), isNull);
      page = await show(tester, doc, column, pages.first, [
        highlight('new', TextPoint(t, 0), TextPoint(t, 5)),
      ]);
      expect(page.highlightAt(at)?.id, 'new');
      expect(page.debugNeedsPaint, isFalse);
    });
  });
}
