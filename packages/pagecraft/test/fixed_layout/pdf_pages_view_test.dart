import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pagecraft/all_formats.dart';
import 'package:pagecraft/testing.dart';

const fixtures = 'test/fixtures/pdf';
const portrait = Size(390, 844);
const night = PageColors(
  background: Color(0xFF0F1115),
  foreground: Color(0xFFBCC1CA),
  dark: true,
);

void main() {
  late PdfBook book;
  late FixedPagesController controller;

  setUpAll(() async {
    await preparePdfEngineForTests();
    book = await PdfBook.open('$fixtures/text_lines.pdf');
  });

  tearDownAll(() => book.close());

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  final boundaryKey = GlobalKey();

  Future<void> pumpView(
    WidgetTester tester, {
    VisibleRectOf? visibleRectOf,
    PageColors? pageColors,
    PageOverlayBuilder? overlay,
    double devicePixelRatio = 1,
  }) async {
    tester.view.physicalSize = portrait * devicePixelRatio;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    controller = FixedPagesController(pageCount: book.pageCount, rtl: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: portrait,
          devicePixelRatio: devicePixelRatio,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: boundaryKey,
            child: FixedPagesView(
              pages: PdfPages(book),
              controller: controller,
              visibleRectOf: visibleRectOf,
              pageColors: pageColors,
              pageOverlayBuilder: overlay,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder frames() => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is FixedPagePainter,
  );

  FixedPagePainter painter(WidgetTester tester) =>
      tester.widget<CustomPaint>(frames().first).painter as FixedPagePainter;

  /// pdfium renders on the real event loop; pump until the frame has it.
  Future<void> settle(
    WidgetTester tester, {
    bool Function(FixedPagePainter painter)? until,
  }) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (frames().evaluate().isEmpty) continue;
        if (until == null || until(painter(tester))) break;
      }
    });
    await tester.pump();
  }

  Future<ui.Color> pixelAt(WidgetTester tester, int x, int y) async {
    late ui.Color color;
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (y * image.width + x) * 4;
      color = Color.fromARGB(
        255,
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      );
      image.dispose();
    });
    return color;
  }

  test('PdfPages knows every page size before it is drawn', () {
    final pages = PdfPages(book);
    expect(pages.pageCount, 1);
    expect(pages.pageAspect(0), closeTo(612 / 792, 1e-9));
    expect(pages, PdfPages(book));
    expect(
      pages.pageImage(0, targetWidth: 300),
      PdfPageImage(book: book, pageIndex: 0, targetWidth: 300),
    );
    expect(
      pages.pageTile(
        0,
        fullWidth: 800,
        region: (x: 0, y: 0, width: 10, height: 10),
      ),
      isA<PdfPageTile>(),
    );
    expect(
      ComicPages(FakeComicSource([])).pageTile(
        0,
        fullWidth: 800,
        region: (x: 0, y: 0, width: 10, height: 10),
      ),
      isNull,
    );
  });

  testWidgets('renders the page at the frame width and paints white paper', (
    tester,
  ) async {
    await pumpView(tester);
    await settle(tester);
    final image = painter(tester).image;
    expect(image.width, 390);
    expect(image.height, 505);
    // The page is centred in the 844 tall view: paper at the middle,
    // background above it.
    final paper = await pixelAt(tester, 300, 422);
    expect(paper.r, greaterThan(0.98));
    final above = await pixelAt(tester, 195, 20);
    expect(above.r, lessThan(0.02));
  });

  testWidgets('a margin crop fits the visible part and renders it denser', (
    tester,
  ) async {
    Rect? overlayRect;
    await pumpView(
      tester,
      visibleRectOf: (_) => const Rect.fromLTWH(0.1, 0.05, 0.8, 0.6),
      overlay: (context, page, imageRect) {
        overlayRect = imageRect;
        return const SizedBox.shrink();
      },
    );
    await settle(tester);
    final image = painter(tester).image;
    expect(image.width, (390 / 0.8).ceil());
    // The whole page's rect extends past the frame on the left.
    expect(overlayRect, isNotNull);
    expect(overlayRect!.left, lessThan(0));
    expect(overlayRect!.width, closeTo(390 / 0.8, 1));
    // The crop keeps the ink; ink starts at 72 pt = 11.7 % of the width,
    // which the 10 % crop leaves visible near the left edge.
    final ink = await pixelAt(tester, 12, 422 - 165);
    expect(ink.r, lessThan(0.98));
  });

  testWidgets('a crop measured later decodes the page denser', (
    tester,
  ) async {
    // The reader measures margins after the page shows and rebuilds the
    // view with the same function.
    Rect? crop;
    Rect? cropOf(int _) => crop;
    tester.view.physicalSize = portrait;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller = FixedPagesController(pageCount: book.pageCount, rtl: false);
    addTearDown(controller.dispose);
    final pages = PdfPages(book);
    final rebuild = ValueNotifier(0);
    addTearDown(rebuild.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: portrait),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder(
            valueListenable: rebuild,
            builder: (_, _, _) => FixedPagesView(
              pages: pages,
              controller: controller,
              visibleRectOf: cropOf,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await settle(tester);
    expect(painter(tester).image.width, 390);

    crop = const Rect.fromLTWH(0.1, 0.05, 0.8, 0.6);
    rebuild.value++;
    await settle(tester, until: (p) => p.image.width != 390);
    expect(painter(tester).image.width, (390 / 0.8).ceil());
    expect(painter(tester).visible, crop);
  });

  testWidgets('theme colours recolour the paper', (tester) async {
    await pumpView(tester, pageColors: night);
    await settle(tester);
    final paper = await pixelAt(tester, 300, 422);
    expect((paper.r * 255).round(), closeTo(0x0F, 3));
    expect((paper.g * 255).round(), closeTo(0x11, 3));
    expect((paper.b * 255).round(), closeTo(0x15, 3));
  });

  testWidgets('a theme change recolours pages already on screen', (
    tester,
  ) async {
    await pumpView(tester);
    await settle(tester);
    final before = await pixelAt(tester, 300, 422);
    expect((before.r * 255).round(), greaterThan(0xF0), reason: 'white paper');
    await pumpView(tester, pageColors: night);
    await tester.pump();
    final after = await pixelAt(tester, 300, 422);
    expect((after.r * 255).round(), closeTo(0x0F, 3));
    expect((after.b * 255).round(), closeTo(0x15, 3));
  });

  testWidgets('a tile stays on its part of the page when the page decodes '
      'denser', (tester) async {
    await pumpView(tester);
    await settle(tester);
    await tester.tapAt(const Offset(195, 400));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(195, 400));
    await tester.pump();
    // The zoom decodes the page again, denser, after the first tile.
    await settle(tester, until: (painter) => painter.image.width > 390 * 2);
    await settle(tester);
    final painted = painter(tester);
    final region = painted.tileRegion;
    if (region != null) {
      // Zoomed on the page's middle: the tile is there, in the pixels of
      // the image it is drawn over.
      final centre = (region.left + region.width / 2) / painted.image.width;
      expect(centre, closeTo(0.5, 0.1));
    }
  });

  testWidgets('a double tap zooms and draws a sharp tile of the view', (
    tester,
  ) async {
    // At 3 device pixels per point the zoomed page is past the pixel
    // budget of one render: the page stops short of the screen's density
    // and the view is drawn again as a tile.
    await pumpView(tester, devicePixelRatio: 3);
    await settle(tester);
    final fit = painter(tester).image.width;
    await tester.tapAt(const Offset(195, 400));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(195, 400));
    await tester.pump();
    expect(controller.isZoomed, isTrue);
    await settle(
      tester,
      until: (painter) => painter.image.width > fit && painter.tile != null,
    );
    final painted = painter(tester);
    final tile = painted.tile!;
    final region = painted.tileRegion!;
    expect(
      painted.image.width,
      lessThan(390 * 3 * FixedPagesView.doubleTapScale),
      reason: 'the budget caps the page',
    );
    expect(region.density, greaterThan(1.1));
    expect(tile.width, closeTo(region.width * region.density, 2));
    // Zoomed on the page's middle, in the pixels of the image under it.
    expect(
      (region.left + region.width / 2) / painted.image.width,
      closeTo(0.5, 0.1),
    );
    expect(
      tile.width * tile.height,
      lessThanOrEqualTo(FixedPagesView.maxTilePixels),
    );

    // Back to fit: the tile is dropped.
    await tester.tapAt(const Offset(195, 400));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(195, 400));
    await tester.pump();
    expect(controller.isZoomed, isFalse);
    await settle(tester, until: (painter) => painter.tile == null);
    expect(painter(tester).tile, isNull);
  });
}
