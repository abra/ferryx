import 'dart:async';
import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pagecraft/all_formats.dart';

const container =
    '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';

String chapter(String title, int paragraphs) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body>'
    '<h1>$title</h1><p>Go <a href="b.xhtml">to B</a> now.</p>'
    '${List.generate(paragraphs, (i) => '<p>$title paragraph $i has words enough to wrap twice in a column.</p>').join()}'
    '</body></html>';

/// A table wider than the 200px page that scrolls, among paragraphs.
const wideTable =
    '<table style="margin: 0; border-spacing: 0; overflow-x: auto"><tr>'
    '<td>Configuration</td><td>Coordination</td><td>Distribution</td>'
    '</tr></table>';

Future<EpubTextSource> book({String tableA = ''}) async => EpubTextSource(
  await EpubBook.load(
    MemoryEpubFiles({
      'META-INF/container.xml': utf8.encode(container),
      'OEBPS/content.opf': utf8.encode(
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/>'
        '<manifest>'
        '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>',
      ),
      'OEBPS/a.xhtml': utf8.encode(
        chapter('A', 10).replaceFirst('<h1>', '$tableA<h1>'),
      ),
      'OEBPS/b.xhtml': utf8.encode(chapter('B', 10)),
    }),
  ),
);

const style = BookStyle(fontScale: 10 / 16, lineHeight: 1.5, justify: false);

class _TrackedSelectionControls extends MaterialTextSelectionControls
    with TextSelectionHandleControls {
  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textHeight, [
    VoidCallback? onTap,
  ]) => KeyedSubtree(
    key: ValueKey('coverHandle-${type.name}'),
    child: super.buildHandle(context, type, textHeight, onTap),
  );
}

void main() {
  late BookImageCache images;
  late TextPagesController controller;

  setUp(() => images = BookImageCache(read: (_) async => null));
  tearDown(() => images.dispose());

  /// Lets isolates, slices and frames run until [condition] holds.
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
    Axis axis = Axis.horizontal,
    PageTurnAnimation pageTurnAnimation = PageTurnAnimation.cover,
    ValueNotifier<PageTurnAnimation>? animation,
    bool rtl = false,
    bool reduceMotion = false,
    BookStyle pageStyle = style,
    TextPageSettings settings = const TextPageSettings(
      sideMarginPercent: 0,
      topMargin: 10,
      bottomMargin: 10,
    ),
    Size size = const Size(200, 160),
    ValueChanged<Offset>? onTap,
    TextLinkTapCallback? onLinkTap,
    TextHighlightTapCallback? onHighlightTap,
    TextHighlightsOf? highlightsOf,
    String? trackedHighlight,
    ValueChanged<List<Rect>>? onHighlightRects,
    ValueChanged<TextPagesSelection?>? onSelectionChanged,
    TextSelectionControls? selectionControls,
    bool Function(Offset point)? onSelectionTap,
    ValueChanged<bool>? onSelectionAdjusting,
    SelectableRegionContextMenuBuilder? contextMenuBuilder,
    String tableA = '',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = await tester.runAsync(() => book(tableA: tableA));
    controller = TextPagesController(
      source: source!,
      style: pageStyle,
      fonts: const BookFonts(),
      images: images,
      settings: settings,
      rtl: rtl,
    );
    addTearDown(controller.dispose);
    final selectedAnimation = animation ?? ValueNotifier(pageTurnAnimation);
    if (animation == null) addTearDown(selectedAnimation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, disableAnimations: reduceMotion),
          child: ValueListenableBuilder<PageTurnAnimation>(
            valueListenable: selectedAnimation,
            builder: (context, value, _) => TextPagesView(
              controller: controller,
              axis: axis,
              pageTurnAnimation: value,
              backgroundColor: Color(pageStyle.backgroundColor),
              onTap: onTap,
              onLinkTap: onLinkTap,
              onHighlightTap: onHighlightTap,
              highlightsOf: highlightsOf,
              trackedHighlight: trackedHighlight,
              onHighlightRects: onHighlightRects,
              onSelectionChanged: onSelectionChanged,
              selectionControls: selectionControls,
              onSelectionTap: onSelectionTap,
              onSelectionAdjusting: onSelectionAdjusting,
              contextMenuBuilder: contextMenuBuilder,
            ),
          ),
        ),
      ),
    );
    await settle(
      tester,
      () => find.byType(TextColumnPage).evaluate().isNotEmpty,
    );
    // Neighbours laid out, so swipes can turn.
    await settle(tester, () => controller.spreadAt(1) != null);
  }

  testWidgets('shows the spread the controller is on', (tester) async {
    await show(tester);
    expect(find.byType(TextColumnPage), findsOneWidget);
    final page = tester.renderObject<RenderTextColumnPage>(
      find.byType(TextColumnPage),
    );
    final geometry = controller.geometry!;
    expect(
      tester.getTopLeft(find.byType(TextColumnPage)),
      Offset(geometry.columnLeft(0), 10),
    );
    expect(page.size.width, geometry.columnWidth);
  });

  testWidgets('a new style keeps the old page up until the new one is laid', (
    tester,
  ) async {
    await show(tester);
    TextColumnPage page() =>
        tester.widget<TextColumnPage>(find.byType(TextColumnPage));
    final old = page().column;
    final before = controller.position;
    // A new cascade: sections are prepared again in isolates.
    controller.style = style.copyWith(
      readerStyleSheet: 'p { font-size: 20px !important }',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(page().column, same(old), reason: 'the old page, not a blank');
    expect(old.isDisposed, isFalse);

    await settle(tester, () => page().column != old);
    expect(controller.position?.cfi, isNotNull);
    expect(controller.position?.section, before?.section);
    await tester.pump();
    expect(old.isDisposed, isTrue, reason: 'released once replaced');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a swipe turns the page; a short one springs back', (
    tester,
  ) async {
    await show(tester);
    await tester.drag(find.byType(TextPagesView), const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(controller.position!.spread, 0, reason: 'too short');
    await tester.fling(find.byType(TextPagesView), const Offset(-120, 0), 800);
    await settle(tester, () => controller.position!.spread == 1);
    await tester.pumpAndSettle();
    expect(find.byType(TextColumnPage), findsOneWidget);
    await tester.fling(find.byType(TextPagesView), const Offset(120, 0), 800);
    await settle(tester, () => controller.position!.spread == 0);
  });

  /// Where each page drawn sits along x, by the top of its page in the
  /// column (which spread it is).
  Map<double, double> lefts(WidgetTester tester) => {
    for (final element in find.byType(TextColumnPage).evaluate())
      (element.widget as TextColumnPage).page.top:
          (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dx,
  };

  double topOf(int spread) => controller.layout.laidOut(0)!.pages[spread].top;

  Map<double, double> positions(WidgetTester tester, Axis axis) => {
    for (final element in find.byType(TextColumnPage).evaluate())
      (element.widget as TextColumnPage).page.top: axis == Axis.horizontal
          ? (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dx
          : (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
  };

  group('slide animation', () {
    for (final axis in Axis.values) {
      for (final rtl in [false, true]) {
        for (final forward in [false, true]) {
          testWidgets(
            'both pages move together: $axis, RTL $rtl, forward $forward',
            (tester) async {
              await show(
                tester,
                axis: axis,
                rtl: rtl,
                pageTurnAnimation: PageTurnAnimation.slide,
              );
              await tester.runAsync(controller.next);
              await tester.pumpAndSettle();
              final baseline = axis == Axis.horizontal ? 0.0 : 10.0;
              final extent = axis == Axis.horizontal ? 200.0 : 160.0;
              final entrySign =
                  (forward ? 1.0 : -1.0) *
                  (axis == Axis.horizontal && rtl ? -1.0 : 1.0);
              await tester.runAsync(
                forward ? controller.next : controller.previous,
              );
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 100));
              final at = positions(tester, axis);
              final target = forward ? 2 : 0;
              final incoming = at[topOf(target)]! - baseline;
              final outgoing = at[topOf(1)]! - baseline;
              expect(incoming * entrySign, inExclusiveRange(0, extent));
              expect(outgoing * entrySign, inExclusiveRange(-extent, 0));
              expect(
                (incoming - outgoing) * entrySign,
                closeTo(extent, 0.000001),
                reason: 'slide pages keep touching rather than covering',
              );
              await tester.pumpAndSettle();
              expect(controller.position!.spread, target);
              expect(positions(tester, axis), {topOf(target): baseline});
            },
          );
        }

        testWidgets('a short drag returns both pages: $axis, RTL $rtl', (
          tester,
        ) async {
          await show(
            tester,
            axis: axis,
            rtl: rtl,
            pageTurnAnimation: PageTurnAnimation.slide,
          );
          await tester.runAsync(controller.next);
          await tester.pumpAndSettle();
          final baseline = axis == Axis.horizontal ? 0.0 : 10.0;
          final extent = axis == Axis.horizontal ? 200.0 : 160.0;
          final sign = axis == Axis.horizontal && rtl ? 1.0 : -1.0;
          final direction = axis == Axis.horizontal
              ? Offset(sign, 0)
              : Offset(0, sign);
          final gesture = await tester.startGesture(const Offset(100, 80));
          await gesture.moveBy(
            direction * 25,
            timeStamp: const Duration(milliseconds: 100),
          );
          await tester.pump();
          await gesture.moveBy(
            direction * (extent * 0.15),
            timeStamp: const Duration(milliseconds: 200),
          );
          await tester.pump();
          expect(
            (positions(tester, axis)[topOf(1)]! - baseline) * sign,
            greaterThan(0),
          );
          await gesture.up(timeStamp: const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(controller.position!.spread, 1);
          expect(positions(tester, axis), {topOf(1): baseline});
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('reduced motion skips programmatic slides', (tester) async {
      await show(
        tester,
        reduceMotion: true,
        pageTurnAnimation: PageTurnAnimation.slide,
      );
      await tester.runAsync(controller.next);
      await tester.pump();
      expect(lefts(tester), {topOf(1): 0});
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('changing animation during a turn applies to the next turn', (
      tester,
    ) async {
      final animation = ValueNotifier(PageTurnAnimation.cover);
      addTearDown(animation.dispose);
      await show(tester, animation: animation);
      await tester.runAsync(controller.next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final before = lefts(tester);
      animation.value = PageTurnAnimation.slide;
      await tester.pump();
      expect(
        lefts(tester),
        before,
        reason: 'the running cover keeps its strategy',
      );
      await tester.pumpAndSettle();
      await tester.runAsync(controller.next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        lefts(tester)[topOf(1)],
        lessThan(0),
        reason: 'the next turn slides',
      );
      await tester.pumpAndSettle();
      expect(controller.position!.spread, 2);
    });
  });

  group('a turn by the controller covers the current page', () {
    testWidgets('forward: the next page comes in from the right', (
      tester,
    ) async {
      await show(tester);
      await tester.runAsync(controller.next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final x = lefts(tester);
      expect(x.keys, unorderedEquals([topOf(0), topOf(1)]), reason: 'both');
      expect(x[topOf(1)], inExclusiveRange(0, 200), reason: 'coming in');
      expect(x[topOf(0)], 0, reason: 'the covered page stays still');
      await tester.pumpAndSettle();
      expect(lefts(tester), {topOf(1): 0});
      expect(controller.position!.spread, 1);
    });

    testWidgets('back: the previous page comes in from the left', (
      tester,
    ) async {
      await show(tester);
      await tester.runAsync(controller.next);
      await tester.pumpAndSettle();
      await tester.runAsync(controller.previous);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final x = lefts(tester);
      expect(x.keys, unorderedEquals([topOf(0), topOf(1)]), reason: 'both');
      expect(x[topOf(0)], inExclusiveRange(-200, 0), reason: 'coming in');
      expect(x[topOf(1)], 0, reason: 'the covered page stays still');
      await tester.pumpAndSettle();
      expect(lefts(tester), {topOf(0): 0});
      expect(controller.position!.spread, 0);
    });

    testWidgets('a right-to-left book turns forward to the right', (
      tester,
    ) async {
      await show(tester, rtl: true);
      await tester.runAsync(controller.next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final x = lefts(tester);
      expect(x[topOf(1)], inExclusiveRange(-200, 0), reason: 'coming in');
      expect(x[topOf(0)], 0, reason: 'the covered page stays still');
      await tester.pumpAndSettle();
      await tester.runAsync(controller.previous);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(lefts(tester)[topOf(0)], inExclusiveRange(0, 200));
      await tester.pumpAndSettle();
      expect(lefts(tester), {topOf(0): 0});
    });

    testWidgets('vertical covers arrive from below and above', (tester) async {
      await show(tester, axis: Axis.vertical);
      Map<double, double> tops() => {
        for (final element in find.byType(TextColumnPage).evaluate())
          (element.widget as TextColumnPage).page.top:
              (element.renderObject! as RenderBox)
                  .localToGlobal(Offset.zero)
                  .dy,
      };

      await tester.runAsync(controller.next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tops()[topOf(0)], 10);
      expect(tops()[topOf(1)], inExclusiveRange(10, 170));
      await tester.pumpAndSettle();

      await tester.runAsync(controller.previous);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tops()[topOf(1)], 10);
      expect(tops()[topOf(0)], inExclusiveRange(-150, 10));
      await tester.pumpAndSettle();
      expect(tops(), {topOf(0): 10});
    });

    testWidgets('a newer turn settles on its latest destination', (
      tester,
    ) async {
      await show(tester);
      await tester.runAsync(controller.next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(controller.next);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(controller.position!.spread, 2);
      expect(lefts(tester), {topOf(2): 0});
      expect(find.byType(TextColumnPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a swipe waits for a programmatic cover to finish', (
      tester,
    ) async {
      await show(tester);
      await tester.runAsync(controller.next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final before = lefts(tester);
      expect(before[topOf(1)], inExclusiveRange(0, 200));

      final gesture = await tester.startGesture(const Offset(100, 80));
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      expect(lefts(tester), before, reason: 'the running cover keeps control');
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.position!.spread, 1);
      expect(lefts(tester), {topOf(1): 0});
      expect(tester.takeException(), isNull);
    });
  });

  for (final (name, axis, rtl, pageStyle) in [
    ('light', Axis.horizontal, false, style),
    (
      'dark_rtl',
      Axis.horizontal,
      true,
      style.copyWith(textColor: 0xFFF2F2F2, backgroundColor: 0xFF16181C),
    ),
    ('vertical', Axis.vertical, false, style),
  ]) {
    testWidgets('an opaque cover hides the text beneath: $name', (
      tester,
    ) async {
      await show(tester, axis: axis, rtl: rtl, pageStyle: pageStyle);
      await tester.runAsync(controller.next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byType(TextPagesView),
        matchesGoldenFile('goldens/text_pages_cover_$name.png'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextColumnPage), findsOneWidget);
    }, tags: ['golden']);
  }

  group('a released swipe moves on from where the finger left', () {
    /// A slow drag by [dx] past the touch slop, held at the end: no fling.
    Future<TestGesture> drag(WidgetTester tester, double dx) async {
      final gesture = await tester.startGesture(const Offset(100, 80));
      var time = Duration.zero;
      Future<void> move(double by) async {
        time += const Duration(milliseconds: 100);
        await gesture.moveBy(Offset(by, 0), timeStamp: time);
        await tester.pump();
      }

      final shown = controller.spreadAt(0)!.pages.first.top;
      final incoming = controller.spreadAt(dx < 0 ? 1 : -1)!.pages.first.top;
      await move(dx.sign * 20);
      await move(dx);
      final x = lefts(tester);
      expect(x[shown], 0, reason: 'the covered page stays still');
      expect(
        x[incoming],
        dx + (dx < 0 ? 200 : -200),
        reason: 'the incoming page follows the finger',
      );
      await gesture.up(timeStamp: time + const Duration(milliseconds: 100));
      return gesture;
    }

    testWidgets('forward: the cover continues from the drag position', (
      tester,
    ) async {
      await show(tester);
      await drag(tester, -80);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final x = lefts(tester);
      expect(x[topOf(0)], 0, reason: 'the covered page stays still');
      expect(x[topOf(1)], inExclusiveRange(0, 120));
      await settle(tester, () => controller.position!.spread == 1);
      await tester.pumpAndSettle();
      expect(lefts(tester), {topOf(1): 0});
    });

    testWidgets('back: the cover continues from the drag position', (
      tester,
    ) async {
      await show(tester);
      await tester.runAsync(controller.next);
      await tester.pumpAndSettle();
      await drag(tester, 80);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final x = lefts(tester);
      expect(x[topOf(1)], 0, reason: 'the covered page stays still');
      expect(x[topOf(0)], inExclusiveRange(-120, 0));
      await settle(tester, () => controller.position!.spread == 0);
      await tester.pumpAndSettle();
      expect(lefts(tester), {topOf(0): 0});
    });

    testWidgets('a short one eases back to rest', (tester) async {
      await show(tester);
      await drag(tester, -30);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        lefts(tester)[topOf(0)],
        0,
        reason: 'the current page stays still',
      );
      expect(lefts(tester)[topOf(1)], inExclusiveRange(170, 200));
      await tester.pumpAndSettle();
      expect(lefts(tester), {topOf(0): 0});
      expect(controller.position!.spread, 0);
    });
  });

  testWidgets('reduced motion turns at once', (tester) async {
    await show(tester, reduceMotion: true);
    await tester.runAsync(controller.next);
    await tester.pump();
    expect(find.byType(TextColumnPage), findsOneWidget);
    expect(controller.position!.spread, 1);
  });

  testWidgets('reduced motion cancels a released swipe in one frame', (
    tester,
  ) async {
    await show(tester, reduceMotion: true);
    final gesture = await tester.startGesture(const Offset(100, 80));
    await gesture.moveBy(
      const Offset(-20, 0),
      timeStamp: const Duration(milliseconds: 100),
    );
    await tester.pump();
    await gesture.moveBy(
      const Offset(-30, 0),
      timeStamp: const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect(
      lefts(tester)[topOf(1)],
      170,
      reason: 'a drag still follows the finger',
    );

    await gesture.up(timeStamp: const Duration(milliseconds: 400));
    await tester.pump();
    expect(lefts(tester), {topOf(0): 0});
    expect(controller.position!.spread, 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('taps: links first, then highlights, then the zones', (
    tester,
  ) async {
    final taps = <Offset>[];
    final links = <int>[];
    final highlights = <String>[];
    await show(
      tester,
      onTap: taps.add,
      onLinkTap: (section, link) => links.add(link),
      onHighlightTap: (highlight, rect) => highlights.add(highlight.id),
      highlightsOf: (section) {
        final layout = controller.layout.laidOut(section);
        if (layout == null) return const [];
        final doc = layout.prepared.document;
        // The heading's text.
        final h1 = const TextAnchor.selector('h1').find(doc);
        return [
          TextHighlight(
            id: 'title',
            range: TextPointRange(TextPoint(h1 + 1, 0), TextPoint(h1 + 1, 1)),
            color: const Color(0x80FFE600),
          ),
        ];
      },
    );
    await tester.pump();
    final layout = controller.spreadAt(0)!.layout;
    final texts = layout.column.items.whereType<ColumnText>().toList();
    final origin = tester.getTopLeft(find.byType(TextColumnPage));
    Offset at(ColumnText item, int offset) =>
        origin +
        item.rect.topLeft +
        item.paragraph.boxesFor(offset, offset + 1).first.toRect().center;
    await tester.tapAt(at(texts[1], 4));
    await tester.tapAt(at(texts[0], 0));
    await tester.tapAt(const Offset(100, 150));
    expect(links, hasLength(1));
    expect(
      layout.prepared.document.attributeOf(links.single, 'href'),
      'b.xhtml',
    );
    expect(highlights, ['title']);
    expect(taps.single.dx, closeTo(0.5, 0.01));
    expect(taps.single.dy, closeTo(150 / 160, 0.01));
  });

  testWidgets('reports where the tracked highlight is on the spread', (
    tester,
  ) async {
    final reports = <List<Rect>>[];
    await show(
      tester,
      highlightsOf: (section) {
        final layout = controller.layout.laidOut(section);
        if (layout == null || section != 0) return const [];
        final doc = layout.prepared.document;
        final h1 = const TextAnchor.selector('h1').find(doc);
        return [
          TextHighlight(
            id: 'tracked',
            range: TextPointRange(TextPoint(h1 + 1, 0), TextPoint(h1 + 1, 1)),
            color: const Color(0x80FFE600),
          ),
        ];
      },
      trackedHighlight: 'tracked',
      onHighlightRects: reports.add,
    );
    await tester.pump();
    final origin = tester.getTopLeft(find.byType(TextColumnPage));
    final title = controller
        .spreadAt(0)!
        .layout
        .column
        .items
        .whereType<ColumnText>()
        .first;
    final glyph = title.paragraph.boxesFor(0, 1).first.toRect();
    expect(reports.last.single.left, closeTo(origin.dx + glyph.left, 1));
    // Turned away from: off the spread.
    await tester.runAsync(controller.next);
    await tester.pumpAndSettle();
    expect(reports.last, isEmpty);
  });

  testWidgets('a cover clips tracked highlights to the uncovered page', (
    tester,
  ) async {
    final reports = <List<Rect>>[];
    await show(
      tester,
      trackedHighlight: 'tracked',
      onHighlightRects: reports.add,
      highlightsOf: (section) {
        final layout = controller.layout.laidOut(section);
        if (layout == null || section != 0) return const [];
        final heading = const TextAnchor.selector('h1').find(
          layout.prepared.document,
        );
        return [
          TextHighlight(
            id: 'tracked',
            range: TextPointRange(
              TextPoint(heading + 1, 0),
              TextPoint(heading + 1, 1),
            ),
            color: const Color(0x80FFE600),
          ),
        ];
      },
    );
    await tester.pump();
    final original = reports.last.single;
    expect(original.left, 0);
    expect(original.right, greaterThan(15));

    final gesture = await tester.startGesture(const Offset(180, 80));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-185, 0));
    await tester.pump();
    final incomingLeft = lefts(tester)[topOf(1)]!;
    expect(incomingLeft, closeTo(15, 0.01));
    expect(reports.last.single.left, original.left);
    expect(reports.last.single.right, closeTo(incomingLeft, 0.01));
    expect(reports.last.single.top, original.top);
    expect(reports.last.single.bottom, original.bottom);

    await gesture.up();
    await settle(tester, () => controller.position!.spread == 1);
    await tester.pumpAndSettle();
    expect(reports.last, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical turns go up and down', (tester) async {
    await show(tester, axis: Axis.vertical);
    await tester.fling(find.byType(TextPagesView), const Offset(0, -100), 800);
    await settle(tester, () => controller.position!.spread == 1);
  });

  testWidgets('two columns side by side', (tester) async {
    await show(
      tester,
      size: const Size(400, 160),
      settings: const TextPageSettings(
        sideMarginPercent: 4,
        topMargin: 10,
        bottomMargin: 10,
        maxColumnCount: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextColumnPage), findsNWidgets(2));
    await expectLater(
      find.byType(TextPagesView),
      matchesGoldenFile('goldens/text_pages_two_columns.png'),
    );
  });

  group('a selection follows the reader across pages', () {
    late List<TextPagesSelection?> reported;
    late List<bool> adjusting;

    TextPagesSelection? last() => reported.isEmpty ? null : reported.last;

    Future<void> showSelectable(
      WidgetTester tester, {
      bool Function(Offset point)? onSelectionTap,
      TextSelectionControls? selectionControls,
      ValueNotifier<PageTurnAnimation>? animation,
    }) async {
      reported = [];
      adjusting = [];
      await show(
        tester,
        animation: animation,
        onSelectionChanged: reported.add,
        selectionControls: selectionControls,
        onSelectionTap: onSelectionTap,
        onSelectionAdjusting: adjusting.add,
        // The reader's own menu; the default toolbar would take swipes.
        contextMenuBuilder: (context, state) => const SizedBox.shrink(),
      );
    }

    RenderTextColumnPage shownPage(WidgetTester tester) =>
        tester.renderObject(find.byType(TextColumnPage));

    /// Where character [offset] of [fragment]'s paragraph is on screen.
    Offset charAt(
      WidgetTester tester,
      PageParagraphSelectable fragment,
      int offset,
    ) => shownPage(tester).localToGlobal(
      fragment.origin +
          fragment.item.paragraph
              .boxesFor(offset, offset + 1)
              .first
              .toRect()
              .center,
    );

    /// Long-presses a word in the shown page's last (or first) line.
    Future<TextPointRange> selectWord(
      WidgetTester tester, {
      bool lastLine = true,
    }) async {
      final fragments = shownPage(tester).debugSelectables;
      final fragment = lastLine ? fragments.last : fragments.first;
      await tester.longPressAt(
        charAt(
          tester,
          fragment,
          lastLine ? fragment.end - 4 : fragment.start + 1,
        ),
      );
      await tester.pumpAndSettle();
      final selection = last();
      expect(selection, isNotNull);
      expect(selection!.text.trim(), isNotEmpty);
      expect(selection.text.contains(' '), isFalse, reason: 'one word');
      return selection.range;
    }

    testWidgets('changing animation keeps the live page and selected range', (
      tester,
    ) async {
      final animation = ValueNotifier(PageTurnAnimation.cover);
      addTearDown(animation.dispose);
      await showSelectable(tester, animation: animation);
      final range = await selectWord(tester);
      final pageElement = find.byType(TextColumnPage).evaluate().single;
      final renderPage = shownPage(tester);
      final layout = controller.spreadAt(0)!.layout;
      final position = controller.position;
      for (final value in [PageTurnAnimation.slide, PageTurnAnimation.cover]) {
        animation.value = value;
        await tester.pump();
        expect(
          find.byType(TextColumnPage).evaluate().single,
          same(pageElement),
        );
        expect(shownPage(tester), same(renderPage));
        expect(controller.spreadAt(0)!.layout, same(layout));
        expect(controller.position, same(position));
        expect(last()!.range, range);
        expect(renderPage.selection, isNotNull);
        expect(tester.takeException(), isNull);
      }
    });

    /// Turns and waits until the selection lands on the new spread.
    Future<void> settleTurn(WidgetTester tester, int spread) async {
      await settle(tester, () => controller.position!.spread == spread);
      await tester.pumpAndSettle();
    }

    /// The text of the first line on the shown page, or of its last line.
    String lineText(WidgetTester tester, {required bool first}) {
      final fragments = shownPage(tester).debugSelectables;
      final fragment = first ? fragments.first : fragments.last;
      final paragraph = fragment.item.paragraph;
      final starts = [
        for (var l = 0; l < paragraph.lines.length; l++) paragraph.lineStart(l),
        paragraph.box.text.length,
      ];
      if (first) {
        final next = starts.firstWhere((s) => s > fragment.start);
        return paragraph.box.plainText(fragment.start, next).trim();
      }
      final start = starts.lastWhere((s) => s < fragment.end);
      return paragraph.box.plainText(start, fragment.end).trim();
    }

    testWidgets('a swipe takes it to the next page, as far as its first '
        'line', (tester) async {
      await showSelectable(tester);
      final word = await selectWord(tester);
      final wordText = last()!.text;
      expect(adjusting, isEmpty);

      await tester.fling(
        find.byType(TextPagesView),
        const Offset(-120, 0),
        800,
      );
      await settleTurn(tester, 1);
      final page = shownPage(tester);
      final selection = last()!;
      expect(selection.range.start, word.start, reason: 'the boundary stays');
      expect(page.selection!.end, selection.range.end);
      expect(page.selection!.text, lineText(tester, first: true));
      expect(selection.text, startsWith(wordText));
      expect(selection.text, endsWith(lineText(tester, first: true)));
      expect(selection.bounds, isNotNull);
      expect(adjusting, [true, false]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an edge tap turns with it; a tap elsewhere clears it', (
      tester,
    ) async {
      final taps = <Offset>[];
      await showSelectable(
        tester,
        onSelectionTap: (point) {
          taps.add(point);
          if (point.dx < 0.7) return false;
          unawaited(controller.next());
          return true;
        },
      );
      final word = await selectWord(tester);
      await tester.tapAt(const Offset(190, 80));
      await settleTurn(tester, 1);
      expect(last()!.range.start, word.start);
      expect(shownPage(tester).selection, isNotNull);

      await tester.tapAt(const Offset(100, 80));
      await tester.pumpAndSettle();
      expect(taps, hasLength(2));
      expect(last(), isNull);
      expect(shownPage(tester).selection, isNull);
      expect(controller.position!.spread, 1);
    });

    testWidgets(
      'a cover hides selection handles and cancellation restores them',
      (
        tester,
      ) async {
        await showSelectable(
          tester,
          selectionControls: _TrackedSelectionControls(),
        );
        final range = await selectWord(tester);
        final handles = find.byWidgetPredicate(
          (widget) =>
              widget.key == const ValueKey('coverHandle-left') ||
              widget.key == const ValueKey('coverHandle-right'),
        );
        expect(handles, findsNWidgets(2));

        final gesture = await tester.startGesture(const Offset(100, 80));
        await gesture.moveBy(
          const Offset(-20, 0),
          timeStamp: const Duration(milliseconds: 100),
        );
        await tester.pump();
        await gesture.moveBy(
          const Offset(-30, 0),
          timeStamp: const Duration(milliseconds: 200),
        );
        await tester.pump();
        expect(
          handles,
          findsNothing,
          reason: 'root overlay handles must not cover the incoming page',
        );

        await gesture.up(timeStamp: const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(controller.position!.spread, 0);
        expect(last()!.range, range);
        expect(handles, findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a slow tap or swipe keeps it as a quick one does', (
      tester,
    ) async {
      // A finger that rests first lets the selection area see a tap
      // begin, which it ends by dropping the selection when the view's
      // gesture wins.
      await showSelectable(
        tester,
        onSelectionTap: (point) {
          if (point.dx < 0.7) return false;
          unawaited(controller.next());
          return true;
        },
      );
      final word = await selectWord(tester);
      final edge = await tester.startGesture(const Offset(190, 80));
      await tester.pump(const Duration(milliseconds: 300));
      await edge.up();
      await settleTurn(tester, 1);
      expect(last()!.range.start, word.start);
      expect(shownPage(tester).selection, isNotNull);

      // A slow swipe that springs back keeps the selection where it was.
      final kept = last()!.range;
      final onPage = shownPage(tester).selection;
      // It starts down and aside: the area's tap sees it leave first.
      final swipe = await tester.startGesture(const Offset(100, 80));
      await tester.pump(const Duration(milliseconds: 300));
      await swipe.moveBy(const Offset(-12, 14));
      await tester.pump();
      await swipe.moveBy(const Offset(-10, 0));
      await tester.pump();
      await swipe.up();
      await tester.pumpAndSettle();
      expect(controller.position!.spread, 1);
      expect(last()!.range, kept);
      expect(shownPage(tester).selection, onPage);
      expect(adjusting.last, isFalse);

      // A slow swipe that turns takes it along.
      final turn = await tester.startGesture(const Offset(150, 80));
      await tester.pump(const Duration(milliseconds: 300));
      await turn.moveBy(const Offset(-12, 14));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await turn.moveBy(const Offset(-25, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await turn.up();
      await settleTurn(tester, 2);
      expect(last()!.range.start, word.start);
      expect(shownPage(tester).selection, isNotNull);

      // A slow tap in the middle clears it.
      final middle = await tester.startGesture(const Offset(100, 80));
      await tester.pump(const Duration(milliseconds: 300));
      await middle.up();
      await tester.pumpAndSettle();
      expect(last(), isNull);
      expect(shownPage(tester).selection, isNull);
    });

    testWidgets('a long press on another word selects that one', (
      tester,
    ) async {
      await showSelectable(tester);
      final first = await selectWord(tester);
      // The area drops the old selection under the finger, then selects
      // the pressed word: a paragraph's first word, high on the page.
      final paragraph = shownPage(tester).debugSelectables[2];
      await tester.longPressAt(
        charAt(tester, paragraph, paragraph.start + 1),
      );
      await tester.pumpAndSettle();
      final second = last()!.range;
      expect(second, isNot(first));
      expect(shownPage(tester).selection?.start, second.start);
      expect(shownPage(tester).selection?.end, second.end);
    });

    testWidgets('turning back ends it at the end of its first page', (
      tester,
    ) async {
      await showSelectable(tester);
      final word = await selectWord(tester);
      await tester.fling(
        find.byType(TextPagesView),
        const Offset(-120, 0),
        800,
      );
      await settleTurn(tester, 1);
      await tester.fling(find.byType(TextPagesView), const Offset(120, 0), 800);
      await settleTurn(tester, 0);
      final page = shownPage(tester);
      final fragment = page.debugSelectables.last;
      final selection = last()!;
      expect(selection.range.start, word.start);
      expect(page.selection!.start, word.start);
      expect(
        page.selection!.end,
        fragment.selectedPoints!.end,
        reason: 'to the end of the page',
      );
      expect(fragment.selection!.end, fragment.end);
      expect(selection.range, TextPointRange(word.start, page.selection!.end));
    });

    testWidgets('a turn back from its start takes the last line before it', (
      tester,
    ) async {
      await showSelectable(tester);
      await controller.next();
      await settleTurn(tester, 1);
      final word = await selectWord(tester, lastLine: false);
      await tester.fling(find.byType(TextPagesView), const Offset(120, 0), 800);
      await settleTurn(tester, 0);
      final page = shownPage(tester);
      final selection = last()!;
      expect(selection.range.end, word.end, reason: 'the boundary stays');
      expect(page.selection!.start, selection.range.start);
      expect(page.selection!.text, lineText(tester, first: false));
    });

    testWidgets('it keeps every page it was turned over', (tester) async {
      await showSelectable(tester);
      final word = await selectWord(tester);
      await tester.fling(
        find.byType(TextPagesView),
        const Offset(-120, 0),
        800,
      );
      await settleTurn(tester, 1);
      final second = shownPage(tester).debugSelectables;
      final secondText = [
        for (final fragment in second)
          fragment.item.paragraph.box.plainText(fragment.start, fragment.end),
      ].join('\n');
      await tester.fling(
        find.byType(TextPagesView),
        const Offset(-120, 0),
        800,
      );
      await settleTurn(tester, 2);
      final selection = last()!;
      expect(selection.range.start, word.start);
      expect(
        selection.text.replaceAll(RegExp(r'\s+'), ' '),
        contains(secondText.replaceAll(RegExp(r'\s+'), ' ').trim()),
      );
      expect(shownPage(tester).selection!.text, lineText(tester, first: true));
      // Back over the page between: the selection ends with it.
      await tester.fling(find.byType(TextPagesView), const Offset(120, 0), 800);
      await settleTurn(tester, 1);
      expect(last()!.range.start, word.start);
      final page = shownPage(tester);
      expect(page.debugSelectables.first.selection!.start, second.first.start);
      expect(page.debugSelectables.last.selection!.end, second.last.end);
    });

    testWidgets('moving the edge it came in by starts it over on the page', (
      tester,
    ) async {
      await showSelectable(tester);
      final word = await selectWord(tester);
      await tester.fling(
        find.byType(TextPagesView),
        const Offset(-120, 0),
        800,
      );
      await settleTurn(tester, 1);
      final page = shownPage(tester);
      final fragment = page.debugSelectables.first;
      // As the start handle dragged two characters in would.
      final region =
          SelectionContainer.maybeOf(
                tester.element(find.byType(TextColumnPage)),
              )!
              as SelectionHandler;
      region.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forStart(
          globalPosition: charAt(tester, fragment, fragment.start + 2),
        ),
      );
      await tester.pump();
      final selection = last()!;
      expect(selection.range.start, isNot(word.start));
      expect(
        selection.range,
        TextPointRange(
          page.selection!.start,
          page.selection!.end,
        ),
      );
      expect(selection.text, page.selection!.text);
    });

    testWidgets('a jump or another section drops it', (tester) async {
      await showSelectable(tester);
      await selectWord(tester);
      unawaited(controller.goToSection(1));
      await settle(tester, () => controller.position!.section == 1);
      await tester.pumpAndSettle();
      expect(last(), isNull);
      expect(shownPage(tester).selection, isNull);

      // The last page of the first section, then on into the second.
      unawaited(controller.goToSection(0));
      await settle(tester, () => controller.position!.section == 0);
      await settle(tester, () => controller.position!.spreadCount != null);
      final count = controller.position!.spreadCount!;
      for (var spread = 1; spread < count; spread++) {
        unawaited(controller.next());
        await settle(tester, () => controller.position!.spread == spread);
      }
      await tester.pumpAndSettle();
      await selectWord(tester);
      await tester.fling(
        find.byType(TextPagesView),
        const Offset(-120, 0),
        800,
      );
      await settle(tester, () => controller.position!.section == 1);
      await tester.pumpAndSettle();
      expect(last(), isNull);
      expect(shownPage(tester).selection, isNull);
      expect(adjusting.lastOrNull, isNot(true));
    });
  });

  group('a table wider than the page', () {
    ColumnScroller scroller() =>
        controller.spreadAt(0)!.layout.column.scrollers.single;

    /// The middle of the table, on screen.
    Offset onTable(WidgetTester tester) {
      final page = tester.renderObject<RenderTextColumnPage>(
        find.byType(TextColumnPage),
      );
      final shown = tester.widget<TextColumnPage>(find.byType(TextColumnPage));
      final viewport = scroller().viewport;
      return page.localToGlobal(
        Offset(viewport.center.dx, viewport.center.dy - shown.page.top),
      );
    }

    testWidgets('a swipe on it scrolls it, on and on after a fling; at its '
        'edge the page turns', (tester) async {
      await show(tester, tableA: wideTable);
      final table = scroller();
      expect(table.maxOffset, greaterThan(100));
      await tester.dragFrom(onTable(tester), const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(table.offset.value, greaterThan(20));
      expect(controller.position!.spread, 0, reason: 'the page stays');

      table.scrollTo(0);
      await tester.pump();
      await tester.flingFrom(onTable(tester), const Offset(-80, 0), 1000);
      final released = table.offset.value;
      await tester.pumpAndSettle();
      expect(
        table.offset.value,
        greaterThan(released),
        reason: 'it keeps going after the finger',
      );

      table.scrollTo(table.maxOffset);
      await tester.pump();
      await tester.flingFrom(onTable(tester), const Offset(-120, 0), 800);
      await settle(tester, () => controller.position!.spread == 1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('back at its start, a swipe back turns the page back', (
      tester,
    ) async {
      await show(tester, tableA: wideTable);
      unawaited(controller.next());
      await settle(tester, () => controller.position!.spread == 1);
      unawaited(controller.previous());
      await settle(tester, () => controller.position!.spread == 0);
      await tester.pumpAndSettle();
      final table = scroller();
      table.scrollTo(30);
      await tester.pump();
      // Rightwards: the table scrolls back first.
      await tester.dragFrom(onTable(tester), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(table.offset.value, 0);
      expect(controller.position!.spread, 0);
    });

    testWidgets('pages turning up and down leave sideways drags to it', (
      tester,
    ) async {
      await show(tester, tableA: wideTable, axis: Axis.vertical);
      final table = scroller();
      await tester.dragFrom(onTable(tester), const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(table.offset.value, greaterThan(20));
      expect(controller.position!.spread, 0);
      // Off the table, a sideways drag does nothing.
      final offset = table.offset.value;
      await tester.dragFrom(const Offset(100, 150), const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(table.offset.value, offset);
      expect(controller.position!.spread, 0);
    });
  });
}
