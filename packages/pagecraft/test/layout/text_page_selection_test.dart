import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// Pages laid out with the test font: every glyph is a box as wide as
/// the font size (12 here), so offsets map to known places.
const book = BookStyle(
  fontScale: 12 / 16,
  lineHeight: 1.5,
  overrideColor: false,
);
const padding = EdgeInsets.all(20);

const first =
    'Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu.';
const second = 'Second paragraph with a few more words.';
final third = 'Long text to fill the column and spill onto the next page. ' * 3;
final body = '<p>$first</p><p>$second</p><p>$third</p>';

({ContentDocument doc, ColumnLayout column, List<ColumnPage> pages}) layOut(
  String body, {
  double width = 280,
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
    width: width,
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

List<ColumnText> textsOf(ColumnLayout column) =>
    column.items.whereType<ColumnText>().toList();

void main() {
  late BookImageCache images;
  setUp(() => images = BookImageCache(read: (_) async => null));
  tearDown(() => images.dispose());

  Future<void> show(
    WidgetTester tester,
    ColumnLayout column,
    List<ColumnPage> pages, {
    ValueChanged<SelectedContent?>? onSelectionChanged,
    bool selectable = true,
    ContentDocument? document,
    List<TextHighlight> highlights = const [],
  }) async {
    tester.view.physicalSize = const Size(700, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final row = Align(
      alignment: Alignment.topLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, page) in pages.indexed)
            RepaintBoundary(
              key: ValueKey('page$i'),
              child: TextColumnPage(
                column: column,
                page: page,
                images: images,
                imageKey: (src) => src,
                padding: padding,
                document: document,
                highlights: highlights,
              ),
            ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          textSelectionTheme: const TextSelectionThemeData(
            selectionColor: Color(0x663D7BFF),
          ),
        ),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: selectable
              ? SelectionArea(
                  onSelectionChanged: onSelectionChanged,
                  child: row,
                )
              : row,
        ),
      ),
    );
  }

  RenderTextColumnPage renderPage(WidgetTester tester, [int index = 0]) =>
      tester
          .renderObjectList<RenderTextColumnPage>(find.byType(TextColumnPage))
          .elementAt(index);

  /// The screen position of the character at [offset] of [item].
  Offset at(
    WidgetTester tester,
    ColumnPage page,
    ColumnText item,
    int offset, {
    int pageIndex = 0,
  }) {
    final box = item.paragraph.boxesFor(offset, offset + 1).first.toRect();
    return renderPage(tester, pageIndex).localToGlobal(
      padding.topLeft +
          Offset(item.rect.left, item.rect.top - page.top) +
          box.center,
    );
  }

  int textNodeOf(ColumnText item) => item.paragraph.box.sourceMap.firstNode;

  test("each paragraph's lines are tiled by the pages, no gap, no overlap", () {
    final long = List.generate(
      20,
      (i) =>
          '<p>Paragraph $i ${'with a good few words in it ' * (i % 5 + 1)}</p>',
    ).join();
    final (:doc, :column, :pages) = layOut(long, pageHeight: 150);
    expect(pages.length, greaterThan(5));
    final owner = RenderConstrainedBox(
      additionalConstraints: const BoxConstraints(),
    );
    final covered = <ColumnText, List<(int, int)>>{};
    var split = 0;
    for (final page in pages) {
      final fragments = PageParagraphSelectable.forPage(
        owner,
        column,
        page,
        Offset.zero,
      );
      for (final fragment in fragments) {
        covered.putIfAbsent(fragment.item, () => []).add((
          fragment.start,
          fragment.end,
        ));
        fragment.dispose();
      }
    }
    for (final item in textsOf(column)) {
      final ranges = covered[item]!;
      if (ranges.length > 1) split++;
      expect(ranges.first.$1, 0);
      expect(ranges.last.$2, item.paragraph.box.text.length);
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].$1, ranges[i - 1].$2, reason: 'contiguous');
      }
    }
    expect(split, greaterThan(0), reason: 'some paragraphs cross a page');
    owner.dispose();
  });

  testWidgets('without a selection region nothing registers', (tester) async {
    final (:doc, :column, :pages) = layOut(body);
    await show(tester, column, [pages.first], selectable: false);
    expect(renderPage(tester).debugSelectables, isEmpty);
    expect(renderPage(tester).selection, isNull);
    expect(
      find.descendant(
        of: find.byType(TextColumnPage),
        matching: find.byType(SelectionContainer),
      ),
      findsNothing,
    );
  });

  testWidgets('a long press selects the word under the finger', (
    tester,
  ) async {
    final (:doc, :column, :pages) = layOut(body);
    SelectedContent? content;
    await show(
      tester,
      column,
      [pages.first],
      onSelectionChanged: (value) => content = value,
    );
    final page = renderPage(tester);
    expect(page.debugSelectables, hasLength(3));
    final item = textsOf(column).first;
    await tester.longPressAt(at(tester, pages.first, item, 7));
    await tester.pumpAndSettle();
    expect(content?.plainText, 'beta');
    final node = textNodeOf(item);
    expect(
      page.selection,
      PageTextSelection(
        start: TextPoint(node, 6),
        end: TextPoint(node, 10),
        text: 'beta',
      ),
    );
    expect(doc.textOf(node), first);
    // The platform's handles and toolbar follow the selection.
    final selectable = page.debugSelectables.first;
    final geometry = selectable.value;
    expect(geometry.status, SelectionStatus.uncollapsed);
    expect(
      geometry.startSelectionPoint!.localPosition,
      selectable.origin + item.paragraph.caretBottom(6),
    );
    expect(
      geometry.endSelectionPoint!.localPosition,
      selectable.origin + item.paragraph.caretBottom(10),
    );
    expect(geometry.selectionRects, hasLength(1));
    expect(geometry.selectionRects.single.width, 4 * 12);
    expect(page.selectionBounds, geometry.selectionRects.single);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('a long-press drag selects by words across paragraphs', (
    tester,
  ) async {
    final (:doc, :column, :pages) = layOut(body);
    SelectedContent? content;
    await show(
      tester,
      column,
      [pages.first],
      onSelectionChanged: (value) => content = value,
    );
    final [one, two, ...] = textsOf(column);
    final gesture = await tester.startGesture(at(tester, pages.first, one, 7));
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveTo(at(tester, pages.first, two, 9));
    await tester.pump();
    expect(content?.plainText, '${first.substring(6)}\nSecond paragraph');
    // Backwards past the pressed word: it stays selected.
    await gesture.moveTo(at(tester, pages.first, one, 1));
    await tester.pump();
    expect(content?.plainText, 'Alpha beta');
    await gesture.up();
    await tester.pumpAndSettle();
    final selection = renderPage(tester).selection!;
    final rects = renderPage(
      tester,
    ).debugSelectables.first.value.selectionRects;
    expect(renderPage(tester).selectionBounds, rects.single);
    expect(selection.start, TextPoint(textNodeOf(one), 0));
    expect(selection.end, TextPoint(textNodeOf(one), 10));
  });

  testWidgets('select all takes this page, in reading order across pages', (
    tester,
  ) async {
    final (:doc, :column, :pages) = layOut(body);
    expect(pages, hasLength(2));
    SelectedContent? content;
    await show(
      tester,
      column,
      pages,
      onSelectionChanged: (value) => content = value,
    );
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    expect(content?.plainText, '$first\n$second\n${third.trim()}');
    final texts = textsOf(column);
    final split = texts.last;
    final one = renderPage(tester).selection!;
    final two = renderPage(tester, 1).selection!;
    expect(one.start, TextPoint(textNodeOf(texts.first), 0));
    expect(one.text, startsWith('$first\n$second\n'));
    expect(
      one.text.length + two.text.length,
      '$first\n$second\n${third.trim()}'.length,
      reason: 'the split paragraph is in both, once',
    );
    expect(one.end, two.start, reason: 'page two goes on where one ends');
    expect(two.end, TextPoint(textNodeOf(split), third.trimRight().length));
  });

  testWidgets(
    'keys extend the selection by characters, words and lines',
    (tester) async {
      final (:doc, :column, :pages) = layOut(body);
      SelectedContent? content;
      await show(
        tester,
        column,
        [pages.first],
        onSelectionChanged: (value) => content = value,
      );
      final item = textsOf(column).first;
      final beta = at(tester, pages.first, item, 7);
      await tester.tapAt(beta);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(beta);
      await tester.pumpAndSettle();
      expect(content?.plainText, 'beta');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(content?.plainText, 'beta ');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
      await tester.pump();
      expect(content?.plainText, 'beta gamma');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      final range = renderPage(tester).debugSelectables.first.selection!;
      expect(range.start, 6);
      expect(
        item.paragraph.lineAt(range.end),
        1,
        reason: 'the end went down a line',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('the selection is tinted over its lines', (tester) async {
    final (:doc, :column, :pages) = layOut(body);
    await show(tester, column, [pages.first]);
    final [one, two, ...] = textsOf(column);
    final gesture = await tester.startGesture(at(tester, pages.first, one, 7));
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveTo(at(tester, pages.first, two, 9));
    await gesture.up();
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('page0')),
      matchesGoldenFile('goldens/text_page_selection.png'),
    );
  });

  testWidgets('a new page or column drops the old selectables', (
    tester,
  ) async {
    final (:doc, :column, :pages) = layOut(body);
    await show(tester, column, [pages.first]);
    final before = renderPage(tester).debugSelectables;
    await show(tester, column, [pages.last]);
    final after = renderPage(tester).debugSelectables;
    expect(after, isNot(same(before)));
    expect(after.first.start, greaterThan(0), reason: 'mid-paragraph');
  });

  testWidgets('a page reused for a taller one selects all over it', (
    tester,
  ) async {
    // The page view keeps a page's render object for the next page.
    final (:doc, :column, :pages) = layOut(body);
    final short = pages.last;
    final tall = pages.first;
    await show(tester, column, [short]);
    await show(tester, column, [tall]);
    final item = textsOf(column).lastWhere(
      (t) => t.rect.top >= tall.top + short.height && tall.contains(t.rect.top),
    );
    SelectedContent? content;
    await show(
      tester,
      column,
      [tall],
      onSelectionChanged: (value) => content = value,
    );
    await tester.longPressAt(at(tester, tall, item, 1));
    await tester.pumpAndSettle();
    expect(content?.plainText, isNotEmpty);
    expect(renderPage(tester).selection?.start.node, textNodeOf(item));
  });

  testWidgets('a screen reader reads the text on the page', (tester) async {
    final semantics = tester.ensureSemantics();
    final (:doc, :column, :pages) = layOut(body);
    await show(tester, column, pages, selectable: false);
    final one = tester.getSemantics(find.byType(TextColumnPage).first);
    expect(one.label, startsWith('$first\n$second\n'));
    final two = tester.getSemantics(find.byType(TextColumnPage).last);
    expect(
      '${one.label}${two.label}',
      '$first\n$second\n${third.trim()}',
      reason: 'the split paragraph read once, across both',
    );
    semantics.dispose();
  });

  group('edge points put a selection edge', () {
    /// Moves the selection's edges to [start] and [end], points on page 0,
    /// as dragged handles would.
    void selectBetween(WidgetTester tester, Offset start, Offset end) {
      final page = renderPage(tester);
      final region =
          SelectionContainer.maybeOf(
                tester.element(find.byType(TextColumnPage)),
              )!
              as SelectionHandler;
      region
        ..dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forStart(
            globalPosition: page.localToGlobal(start),
          ),
        )
        ..dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forEnd(
            globalPosition: page.localToGlobal(end),
          ),
        );
    }

    testWidgets('on a document point', (tester) async {
      final (:doc, :column, :pages) = layOut(body);
      await show(tester, column, [pages.first], document: doc);
      final page = renderPage(tester);
      final item = textsOf(column).first;
      final node = textNodeOf(item);
      final start = page.selectionEdgeAt(TextPoint(node, 6), isEnd: false)!;
      final end = page.selectionEdgeAt(TextPoint(node, 10), isEnd: true)!;
      // Inside the character on the edge's side: 'b' of "beta" near its
      // left, 'a' near its right.
      final origin = padding.topLeft + item.rect.topLeft;
      final b = item.paragraph.boxesFor(6, 7).single.toRect().shift(origin);
      final a = item.paragraph.boxesFor(9, 10).single.toRect().shift(origin);
      expect(b.contains(start), isTrue);
      expect(start.dx, lessThan(b.center.dx));
      expect(a.contains(end), isTrue);
      expect(end.dx, greaterThan(a.center.dx));
      selectBetween(tester, start, end);
      await tester.pump();
      expect(page.selection?.text, 'beta');
      expect(page.selection?.start, TextPoint(node, 6));
      expect(page.selection?.end, TextPoint(node, 10));
      // Text on the next page is not here.
      final last = textsOf(column).last;
      expect(
        page.selectionEdgeAt(
          TextPoint(textNodeOf(last), last.paragraph.box.text.length),
          isEnd: true,
        ),
        isNull,
      );
    });

    testWidgets('at the end of the first line and the start of the last', (
      tester,
    ) async {
      final (:doc, :column, :pages) = layOut(body);
      await show(tester, column, [pages.first], document: doc);
      final page = renderPage(tester);
      final fragments = page.debugSelectables;
      final head = fragments.first;
      final tail = fragments.last;
      final headNode = textNodeOf(head.item);
      final tailNode = textNodeOf(tail.item);

      // From the page's start to its first line's end.
      selectBetween(
        tester,
        page.selectionEdgeAt(TextPoint(headNode, 0), isEnd: false)!,
        page.lineEdge(isEnd: true)!,
      );
      await tester.pump();
      final lineEnd = head.item.paragraph.lineStart(1);
      expect(head.item.paragraph.box.text[lineEnd - 1], ' ');
      expect(
        page.selection!.end,
        TextPoint(headNode, lineEnd - 1),
        reason: 'before the space the line ends with',
      );

      // From the last line's start to the page's end.
      final pageEnd = tail.item.paragraph.box.sourceMap.toSourceEnd(tail.end)!;
      selectBetween(
        tester,
        page.lineEdge(isEnd: false)!,
        page.selectionEdgeAt(
          TextPoint(pageEnd.node, pageEnd.offset),
          isEnd: true,
        )!,
      );
      await tester.pump();
      final paragraph = tail.item.paragraph;
      final lastLine = paragraph.lineStart(paragraph.lineAt(tail.end - 1));
      expect(page.selection!.start, TextPoint(tailNode, lastLine));
      expect(page.selection!.end, TextPoint(pageEnd.node, pageEnd.offset));
    });

    testWidgets('on a page that starts inside a paragraph', (tester) async {
      final (:doc, :column, :pages) = layOut(body);
      final page = pages.firstWhere(
        (p) =>
            PageParagraphSelectable.forPage(
              RenderConstrainedBox(
                additionalConstraints: const BoxConstraints(),
              ),
              column,
              p,
              Offset.zero,
            ).first.start >
            0,
      );
      await show(tester, column, [page], document: doc);
      final render = renderPage(tester);
      final head = render.debugSelectables.first;
      expect(head.start, greaterThan(0), reason: 'a paragraph continued');
      final paragraph = head.item.paragraph;
      final firstLine = paragraph.box
          .plainText(
            head.start,
            paragraph.lineStart(
              List.generate(
                paragraph.lines.length,
                (l) => l,
              ).firstWhere((l) => paragraph.lineStart(l) > head.start),
            ),
          )
          .trim();
      final headStart = paragraph.box.sourceMap.toSource(head.start)!;
      selectBetween(
        tester,
        render.selectionEdgeAt(
          TextPoint(headStart.node, headStart.offset),
          isEnd: false,
        )!,
        render.lineEdge(isEnd: true)!,
      );
      await tester.pump();
      expect(render.selection?.text, firstLine);
    });

    testWidgets('in right-to-left text', (tester) async {
      const hebrew = 'אבג דהו זחט';
      final (:doc, :column, :pages) = layOut(
        '<p dir="rtl">$hebrew $hebrew</p>',
      );
      await show(tester, column, [pages.first], document: doc);
      final page = renderPage(tester);
      final item = textsOf(column).first;
      final node = textNodeOf(item);
      final start = page.selectionEdgeAt(TextPoint(node, 4), isEnd: false)!;
      final end = page.selectionEdgeAt(TextPoint(node, 7), isEnd: true)!;
      final origin = padding.topLeft + item.rect.topLeft;
      final first = item.paragraph.boxesFor(4, 5).single;
      expect(first.direction, TextDirection.rtl);
      // A character's start is on its right.
      expect(start.dx, greaterThan(first.toRect().shift(origin).center.dx));
      selectBetween(tester, start, end);
      await tester.pump();
      expect(page.selection?.text, 'דהו');
    });
  });

  group('a table that scrolls sideways', () {
    // Cells 158, 146 and 146 wide with the test font: 450 in a 280 column.
    const table =
        '<p>Before.</p><table style="margin: 0; border-spacing: 0; '
        'overflow-x: auto"><tr><td>Configuration</td><td>Coordination</td>'
        '<td><a href="#x">Distribution</a></td></tr></table><p>After.</p>';

    ColumnText cell(ColumnLayout column, String text) => textsOf(
      column,
    ).firstWhere((t) => t.paragraph.box.text == text);

    /// Where character [offset] of [item] is shown on screen.
    Offset shownAt(WidgetTester tester, ColumnText item, int offset) {
      final box = item.paragraph.boxesFor(offset, offset + 1).first.toRect();
      final scroll = item.scroller?.offset.value ?? 0;
      return renderPage(tester).localToGlobal(
        padding.topLeft + item.rect.topLeft + box.center - Offset(scroll, 0),
      );
    }

    testWidgets('its scroll moves what is hit and clips what is drawn', (
      tester,
    ) async {
      final (:doc, :column, :pages) = layOut(table);
      await show(tester, column, [pages.first], document: doc);
      final page = renderPage(tester);
      final scroller = column.scrollers.single;
      expect(scroller.maxOffset, 450 - 280);
      final link = cell(column, 'Distribution');
      final before = cell(column, 'Before.');
      Offset local(Offset global) => page.globalToLocal(global);

      expect(
        page.scrollerAt(local(shownAt(tester, link, 0))),
        isNull,
        reason: 'past the column, not shown',
      );
      expect(page.scrollerAt(local(shownAt(tester, before, 0))), isNull);
      final first = cell(column, 'Configuration');
      expect(page.scrollerAt(local(shownAt(tester, first, 0))), scroller);

      scroller.scrollTo(scroller.maxOffset);
      await tester.pump();
      final at = local(shownAt(tester, link, 2));
      expect(at.dx, lessThan(padding.left + 280));
      expect(page.scrollerAt(at), scroller);
      expect(page.linkAt(at), isNotNull);
      // The first cell went left, out of the column: nothing to hit, and
      // nothing drawn in the page's margin.
      final gone = local(shownAt(tester, first, 0));
      expect(gone.dx, lessThan(padding.left));
      expect(page.scrollerAt(gone), isNull);
      final image = await tester.runAsync(() async {
        final boundary =
            tester.renderObject(find.byKey(const ValueKey('page0')))
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData();
        final width = image.width;
        image.dispose();
        return (bytes!, width);
      });
      final (bytes, width) = image!;
      int alphaAt(Offset point) => bytes.getUint8(
        ((point.dy.round() * width) + point.dx.round()) * 4 + 3,
      );
      final row = shownAt(tester, link, 2).dy;
      expect(
        alphaAt(Offset(padding.left / 2, row)),
        0,
        reason: 'clipped to the column',
      );
      expect(
        alphaAt(page.globalToLocal(shownAt(tester, link, 2))),
        greaterThan(0),
        reason: 'the scrolled cell is drawn',
      );
    });

    testWidgets('highlights move with it and hide outside it', (tester) async {
      final (:doc, :column, :pages) = layOut(table);
      final link = cell(column, 'Distribution');
      final node = textNodeOf(link);
      await show(
        tester,
        column,
        [pages.first],
        document: doc,
        highlights: [
          TextHighlight(
            id: 'h',
            range: TextPointRange(TextPoint(node, 0), TextPoint(node, 4)),
            color: const Color(0x80FFE600),
          ),
        ],
      );
      final page = renderPage(tester);
      final scroller = column.scrollers.single;
      expect(page.highlightRects('h'), isEmpty, reason: 'scrolled out');
      expect(
        page.highlightAt(page.globalToLocal(shownAt(tester, link, 1))),
        isNull,
      );
      scroller.scrollTo(scroller.maxOffset);
      await tester.pump();
      final rects = page.highlightRects('h');
      expect(rects, isNotEmpty);
      final shown = page.globalToLocal(shownAt(tester, link, 1));
      expect(rects.any((r) => r.contains(shown)), isTrue);
      expect(page.highlightAt(shown)?.id, 'h');
      for (final rect in rects) {
        expect(rect.right, lessThanOrEqualTo(padding.left + 280));
      }
    });

    testWidgets('selection: what is shown is selected; an edge scrolled away '
        'loses its handle', (tester) async {
      final (:doc, :column, :pages) = layOut(table);
      await show(tester, column, [pages.first], document: doc);
      final page = renderPage(tester);
      final scroller = column.scrollers.single;
      final link = cell(column, 'Distribution');
      scroller.scrollTo(scroller.maxOffset);
      await tester.pump();
      await tester.longPressAt(shownAt(tester, link, 3));
      await tester.pumpAndSettle();
      expect(page.selection?.text, 'Distribution');
      final fragment = page.debugSelectables.firstWhere(
        (s) => s.item == link,
      );
      expect(fragment.value.startSelectionPoint, isNotNull);
      expect(fragment.value.endSelectionPoint, isNotNull);
      final shown = fragment.value.selectionRects.single;
      expect(shown.right, lessThanOrEqualTo(padding.left + 280 + 0.5));

      // Back to the start: the selected cell is out of sight.
      scroller.scrollTo(0);
      await tester.pump();
      expect(page.selection?.text, 'Distribution', reason: 'still selected');
      expect(fragment.value.startSelectionPoint, isNull);
      expect(fragment.value.endSelectionPoint, isNull);
      expect(fragment.value.selectionRects, isEmpty);
      expect(fragment.boundingBoxes, isEmpty);
    });
  });
}
