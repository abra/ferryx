import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pagecraft/all_formats.dart';

/// An article of [paragraphs] marked as the import marks them: blocks
/// with ids, one sentence each.
String article(int paragraphs) => [
  '<h1 id="block-0" data-rf-block-id="block-0">'
      '<span id="block-0-s0" data-rf-sentence="0">The title</span></h1>',
  for (var i = 1; i <= paragraphs; i++)
    '<p id="block-$i" data-rf-block-id="block-$i">'
        '<span id="block-$i-s0" data-rf-sentence="0">Paragraph $i has '
        'words enough to wrap twice in a narrow column.</span> '
        '<a href="#block-1">back</a></p>',
].join('\n');

String inlineArticle({required bool wrappedPrefix}) => [
  for (var i = 0; i < 80; i++)
    '<p id="block-$i" data-rf-block-id="block-$i">'
        '<span id="block-$i-s0" data-rf-sentence="0">'
        '${wrappedPrefix ? 'The first sentence has enough words to occupy several lines in the article column.' : 'One.'}'
        '</span> '
        '<span id="block-$i-s1" data-rf-sentence="1">'
        '${wrappedPrefix ? 'The second sentence also wraps before the saved sentence begins.' : 'Two.'}'
        '</span> '
        '<span id="block-$i-s2" data-rf-sentence="2">'
        'Target sentence $i has enough words to continue onto another line.'
        '</span></p>',
].join('\n');

const style = BookStyle(fontScale: 10 / 16, lineHeight: 1.5, justify: false);
const settings = TextPageSettings(
  sideMarginPercent: 5,
  topMargin: 20,
  bottomMargin: 30,
);

void main() {
  late BookImageCache images;
  late TextScrollController controller;

  setUp(() => images = BookImageCache(read: (_) async => null));
  tearDown(() => images.dispose());

  Future<void> settle(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(condition(), isTrue, reason: 'timed out');
  }

  Future<void> show(
    WidgetTester tester, {
    int paragraphs = 40,
    Size size = const Size(200, 300),
    TextPoint? Function(ContentDocument)? initialPoint,
    double? initialFraction,
    ValueChanged<Offset>? onTap,
    TextLinkTapCallback? onLinkTap,
    List<TextHighlight> Function(ContentDocument)? highlights,
    ValueChanged<List<Rect>>? onHighlightRects,
    String? html,
    BookStyle bookStyle = style,
    TextPageSettings pageSettings = settings,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller = TextScrollController(
      source: ArticleTextSource.fromHtml(html ?? article(paragraphs)),
      style: bookStyle,
      fonts: const BookFonts(),
      images: images,
      settings: pageSettings,
      initialPoint: initialPoint,
      initialFraction: initialFraction,
    );
    addTearDown(controller.dispose);
    Widget view() => MaterialApp(
      home: TextScrollView(
        controller: controller,
        onTap: onTap,
        onLinkTap: onLinkTap,
        highlights: highlights == null || controller.section == null
            ? const []
            : highlights(controller.section!.prepared.document),
        trackedHighlight: 'tracked',
        onHighlightRects: onHighlightRects,
      ),
    );
    await tester.pumpWidget(view());
    await settle(tester, () => controller.position != null);
    if (highlights != null) {
      await tester.pumpWidget(view());
      await tester.pump();
    }
  }

  testWidgets('the column scrolls between its margins, in slices', (
    tester,
  ) async {
    await show(tester);
    expect(controller.columnLeft, 10, reason: '5% of 200');
    expect(controller.layout.columnWidth, 180);
    final pages = tester
        .renderObjectList<RenderTextColumnPage>(find.byType(TextColumnPage))
        .toList();
    expect(pages, isNotEmpty);
    expect(pages.first.size, const Size(200, 300));
    expect(controller.position!.atStart, isTrue);
    expect(controller.position!.fraction, 0);
    await settle(tester, () => controller.section!.isComplete);
    expect(
      controller.contentHeight,
      greaterThan(controller.section!.column.contentHeight + 49),
      reason: 'the margins above and below',
    );
  });

  testWidgets('the safe area is in the margins once, not added again', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 50, bottom: 30);
    addTearDown(tester.view.resetPadding);
    await show(tester);
    final first = find.byType(TextColumnPage).first;
    expect(tester.getTopLeft(first).dy, 0, reason: 'slices start at the top');
    final page = tester.widget<TextColumnPage>(first);
    expect(page.page.top, -controller.topInset);
  });

  testWidgets('the last slice ends at the bottom margin without a blank tail', (
    tester,
  ) async {
    await show(tester, paragraphs: 37);
    await settle(tester, () => controller.section!.isComplete);
    await tester.pump();
    expect(controller.contentHeight, greaterThan(controller.viewport.height));
    final remainder = controller.contentHeight % controller.viewport.height;
    expect(remainder, greaterThan(0));
    expect(
      controller.scroll.position.maxScrollExtent,
      closeTo(controller.maxScroll, 1e-6),
    );

    await tester.drag(find.byType(TextScrollView), const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.scroll.offset, closeTo(controller.maxScroll, 1e-6));
    expect(controller.position!.atEnd, isTrue);
    final last = find.byType(TextColumnPage).last;
    expect(tester.getSize(last).height, closeTo(remainder, 1e-6));
    expect(
      tester.getBottomRight(last).dy,
      closeTo(controller.viewport.height, 1e-6),
    );
    expect(
      tester.widget<TextColumnPage>(last).page.bottom,
      closeTo(
        controller.section!.column.contentHeight + controller.bottomInset,
        1e-6,
      ),
    );
  });

  testWidgets('a short article has one content-sized slice and no overflow', (
    tester,
  ) async {
    await show(tester, html: '<p>A short article.</p>');
    await settle(tester, () => controller.section!.isComplete);
    await tester.pump();
    expect(controller.contentHeight, lessThan(controller.viewport.height));
    expect(find.byType(TextColumnPage), findsOneWidget);
    expect(
      tester.getSize(find.byType(TextColumnPage)).height,
      closeTo(controller.contentHeight, 1e-6),
    );
    expect(controller.scroll.position.maxScrollExtent, 0);
    expect(controller.position!.atStart, isTrue);
    expect(controller.position!.atEnd, isTrue);
  });

  testWidgets('the share read follows the text laid out after it', (
    tester,
  ) async {
    await show(tester, paragraphs: 400);
    await tester.drag(find.byType(TextScrollView), const Offset(0, -300));
    await tester.pump();
    await settle(tester, () => controller.section!.isComplete);
    await tester.pump();
    final position = controller.position!;
    final max = controller.maxScroll;
    expect(position.fraction, closeTo(controller.scroll.offset / max, 1e-6));
    expect(position.atEnd, isFalse);
  });

  testWidgets('scrolling moves the position: the text at the middle', (
    tester,
  ) async {
    await show(tester);
    final first = controller.position!.point;
    await tester.drag(find.byType(TextScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await settle(tester, () => controller.position!.point != first);
    final position = controller.position!;
    expect(position.atStart, isFalse);
    expect(position.fraction, greaterThan(0));
    final doc = controller.section!.prepared.document;
    expect(doc.comparePoints(position.point!, first!), greaterThan(0));
  });

  testWidgets('opens at a point, centred, or a share of the text', (
    tester,
  ) async {
    await show(
      tester,
      initialPoint: (doc) => TextPoint(doc.elementIndexById('block-30-s0'), 0),
    );
    final doc = controller.section!.prepared.document;
    final point = controller.position!.point!;
    // The point at the middle is in or near block 30.
    final block = doc.elementIndexById('block-30');
    expect(
      (point.node - block).abs(),
      lessThan(20),
      reason: 'at $point, block 30 at $block',
    );
    expect(controller.scroll.offset, greaterThan(0));
    await tester.runAsync(() => controller.goToFraction(1));
    await tester.pump();
    await settle(tester, () => controller.position!.atEnd);
    await tester.runAsync(() => controller.goToFraction(0));
    await tester.pump();
    await settle(tester, () => controller.position!.atStart);
  });

  testWidgets('a new size keeps the text at the middle', (tester) async {
    await show(
      tester,
      initialPoint: (doc) => TextPoint(doc.elementIndexById('block-25-s0'), 0),
    );
    final before = controller.position!.point!;
    tester.view.physicalSize = const Size(320, 300);
    await tester.pump();
    await settle(tester, () => controller.layout.columnWidth == 288);
    await settle(tester, () => controller.position!.point != null);
    final after = controller.position!.point!;
    expect(
      (after.node - before.node).abs(),
      lessThan(12),
      reason: 'from $before to $after',
    );
  });

  for (final wrappedPrefix in [false, true]) {
    testWidgets(
      'keeps an exact inline anchor ${wrappedPrefix ? 'after wrapped text' : 'on a shared line'} until scrolling',
      (tester) async {
        late TextPoint target;
        await show(
          tester,
          size: const Size(1280, 800),
          html: inlineArticle(wrappedPrefix: wrappedPrefix),
          pageSettings: const TextPageSettings(measure: 320),
          initialPoint: (doc) => target = TextPoint(
            doc.elementIndexById('block-40-s2'),
            0,
          ),
        );
        await settle(tester, () => controller.section!.isComplete);
        await tester.pumpAndSettle();

        void expectTargetCentered() {
          final item = controller.section!.column.paragraphs.firstWhere(
            (item) => item.paragraph.box.text.contains('Target sentence 40'),
          );
          final paragraph = item.paragraph;
          final offset = paragraph.box.text.indexOf('Target sentence 40');
          // Use painted glyph bounds, independently of the source locator.
          final glyph = paragraph.boxesFor(offset, offset + 1).single.toRect();
          final line = paragraph.lineAtY(glyph.center.dy);
          final lineTop =
              controller.topInset + item.rect.top + paragraph.lineTop(line);
          expect(
            controller.contentOffsetOf(target),
            closeTo(lineTop, 1e-6),
            reason: 'the locator must resolve the target glyph line',
          );
          expect(
            lineTop - controller.scroll.offset,
            closeTo(controller.viewport.height / 2, 1e-6),
            reason: 'the target glyph line must actually be centred',
          );
          expect(controller.position!.point, target);
        }

        expectTargetCentered();
        expect(controller.position!.atStart, isFalse);
        expect(controller.position!.atEnd, isFalse);

        tester.view.physicalSize = const Size(1000, 1000);
        await tester.pump();
        await settle(tester, () => controller.viewport.height == 1000);
        await tester.pumpAndSettle();
        expectTargetCentered();

        await tester.drag(find.byType(TextScrollView), const Offset(0, -250));
        await tester.pumpAndSettle();
        final point = controller.position!.point!;
        expect(
          controller.section!.prepared.document.comparePoints(point, target),
          greaterThan(0),
        );
        expect(controller.position!.reason, TextScrollReason.scroll);

        await tester.runAsync(() => controller.goToPoint(target));
        await tester.pumpAndSettle();
        expectTargetCentered();
        await tester.runAsync(() => controller.goToFraction(0));
        await tester.pumpAndSettle();
        expect(controller.position!.atStart, isTrue);
        expect(controller.position!.point, isNot(target));
      },
    );
  }

  testWidgets('keeps point navigation when style changes before its frame', (
    tester,
  ) async {
    await show(
      tester,
      size: const Size(1280, 800),
      html: inlineArticle(wrappedPrefix: true),
      pageSettings: const TextPageSettings(measure: 320),
      initialPoint: (doc) => TextPoint(doc.elementIndexById('block-20-s2'), 0),
    );
    await settle(tester, () => controller.section!.isComplete);
    await tester.pumpAndSettle();
    final previous = controller.position!.point;
    final section = controller.section!;
    final target = TextPoint(
      section.prepared.document.elementIndexById('block-40-s2'),
      0,
    );

    await controller.goToPoint(target);
    expect(
      controller.position!.point,
      previous,
      reason: 'the scheduled position frame has not run yet',
    );
    controller.style = style.copyWith(fontScale: 12 / 16);
    await settle(tester, () => controller.section != section);
    await tester.pumpAndSettle();

    expect(controller.position!.point, target);
    expect(controller.position!.reason, TextScrollReason.layout);
    expect(
      controller.contentOffsetOf(target)! - controller.scroll.offset,
      closeTo(controller.viewport.height / 2, 1e-6),
    );
  });

  testWidgets('reports where the tracked highlight is as it scrolls', (
    tester,
  ) async {
    final reports = <List<Rect>>[];
    await show(
      tester,
      highlights: (doc) {
        final text = doc.elementIndexById('block-3-s0') + 1;
        return [
          TextHighlight(
            id: 'tracked',
            range: TextPointRange(TextPoint(text, 0), TextPoint(text, 9)),
            color: const Color(0x80FFFF00),
          ),
        ];
      },
      onHighlightRects: reports.add,
    );
    expect(reports, isNotEmpty);
    final first = reports.last.single;
    expect(first.width, greaterThan(10));
    final before = controller.scroll.offset;
    await tester.drag(find.byType(TextScrollView), const Offset(0, -60));
    await tester.pump();
    final moved = controller.scroll.offset - before;
    expect(moved, greaterThan(20));
    expect(reports.last.single.top, closeTo(first.top - moved, 1));
    // Scrolled out of view: nothing to report.
    await tester.drag(find.byType(TextScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(reports.last, isEmpty);
  });

  testWidgets('taps: a link, else a share of the view', (tester) async {
    final taps = <Offset>[];
    final links = <int>[];
    await show(
      tester,
      onTap: taps.add,
      onLinkTap: (section, link) => links.add(link),
    );
    await tester.tapAt(const Offset(100, 290));
    expect(taps.single.dx, closeTo(0.5, 0.01));
    final page = tester.renderObject<RenderTextColumnPage>(
      find.byType(TextColumnPage).first,
    );
    final column = controller.section!.column;
    final paragraph = column.paragraphs.elementAt(1);
    final text = paragraph.paragraph.box.text;
    final at = text.indexOf('back');
    final box = paragraph.paragraph.boxesFor(at, at + 1).first.toRect();
    final local =
        Offset(controller.columnLeft, controller.topInset) +
        paragraph.rect.topLeft +
        box.center;
    await tester.tapAt(page.localToGlobal(local));
    expect(links, hasLength(1));
  });

  testWidgets('a sideways drag on a wide table scrolls it, and only it', (
    tester,
  ) async {
    await show(
      tester,
      // Articles keep no style attributes: the reader's sheet sets it.
      html:
          '<table><tr><td>Configuration</td><td>Coordination</td>'
          '<td>Distribution</td></tr></table>${article(20)}',
      bookStyle: const BookStyle(
        fontScale: 10 / 16,
        lineHeight: 1.5,
        justify: false,
        readerStyleSheet: 'table { margin: 0; overflow-x: auto }',
      ),
    );
    final scroller = controller.section!.column.scrollers.single;
    final page = tester
        .renderObjectList<RenderTextColumnPage>(
          find.byType(TextColumnPage),
        )
        .first;
    final shown = tester
        .widgetList<TextColumnPage>(
          find.byType(TextColumnPage),
        )
        .first;
    final onTable = page.localToGlobal(
      Offset(
        controller.columnLeft + scroller.viewport.center.dx,
        scroller.viewport.center.dy - shown.page.top,
      ),
    );
    final top = controller.scroll.offset;
    await tester.dragFrom(onTable, const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(scroller.offset.value, greaterThan(20));
    expect(controller.scroll.offset, top, reason: 'the text stays');
    final offset = scroller.offset.value;
    await tester.dragFrom(const Offset(100, 250), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(scroller.offset.value, offset);
  });
}
