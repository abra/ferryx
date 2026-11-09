import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  const portrait = Size(390, 844);
  const landscape = Size(844, 390);

  FixedPagesController controller({
    int pages = 5,
    bool rtl = false,
    int initial = 0,
  }) {
    final c = FixedPagesController(
      pageCount: pages,
      rtl: rtl,
      initialPage: initial,
    );
    addTearDown(c.dispose);
    return c;
  }

  test('opens on the initial page in single-page mode', () {
    final c = controller(initial: 3);
    expect(c.page, 3);
    expect(c.singlePage, isTrue);
    expect(c.unitCount, 5);
    expect(c.unit, 3);
    expect(c.visiblePages, [3]);
    expect(c.position, const FixedPagePosition(page: 3, pageCount: 5));
    expect(c.lastRelocationReason, isNull);
    expect(c.isZoomed, isFalse);
  });

  test('next and previous turn pages and report the reason', () {
    final c = controller();
    var notified = 0;
    c.addListener(() => notified++);
    expect(c.next(), isTrue);
    expect(c.page, 1);
    expect(c.lastRelocationReason, PageRelocationReason.page);
    expect(c.previous(), isTrue);
    expect(c.page, 0);
    expect(c.previous(), isFalse);
    expect(c.atStart, isTrue);
    expect(notified, 2);
    for (var i = 0; i < 4; i++) {
      c.next();
    }
    expect(c.next(), isFalse);
    expect(c.atEnd, isTrue);
  });

  test('a landscape viewport switches to spreads and keeps the page', () async {
    final c = controller(initial: 3);
    var notified = 0;
    c.addListener(() => notified++);
    c.attachViewport(landscape);
    expect(c.singlePage, isFalse);
    expect(c.unitCount, 3);
    expect(c.unit, 1);
    expect(c.page, 3);
    expect(c.visiblePages, [2, 3]);
    expect(notified, 0, reason: 'reported from layout, so notified later');
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1);
    c.attachViewport(landscape);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1, reason: 'same mode, no notification');
    c.attachViewport(portrait);
    expect(c.singlePage, isTrue);
    expect(c.unit, 3);
  });

  test('a viewport change after dispose notifies nobody', () async {
    final c = FixedPagesController(pageCount: 2, rtl: false);
    c.attachViewport(landscape);
    c.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('a swipe to a unit lands on the half nearest the reader', () {
    final c = controller()..attachViewport(landscape);
    c.showUnit(1);
    expect(
      c.location,
      const SpreadLocation(spreadIndex: 1, side: SpreadSide.left),
    );
    expect(c.page, 2);
    expect(c.lastRelocationReason, PageRelocationReason.page);
    c.showUnit(0);
    expect(
      c.location,
      const SpreadLocation(spreadIndex: 0, side: SpreadSide.right),
    );
    expect(c.page, 1);
    c.showUnit(2);
    // A lone last page sits on the left in a left-to-right book.
    expect(
      c.location,
      const SpreadLocation(spreadIndex: 2, side: SpreadSide.left),
    );
    expect(c.page, 4);

    final rtl = controller(rtl: true)..attachViewport(landscape);
    rtl.showUnit(1);
    expect(
      rtl.location,
      const SpreadLocation(spreadIndex: 1, side: SpreadSide.right),
    );
    expect(rtl.page, 2);

    final single = controller();
    single.showUnit(4);
    expect(single.page, 4);
    var notified = 0;
    single.addListener(() => notified++);
    single.showUnit(4);
    expect(notified, 0, reason: 'already there');
  });

  test('jumps by page, CFI and fraction report navigation', () {
    final c = controller(pages: 10);
    c.goToPage(7);
    expect(c.page, 7);
    expect(c.lastRelocationReason, PageRelocationReason.navigation);

    expect(c.goToCfi('epubcfi(/6/6)'), isTrue);
    expect(c.page, 2);
    expect(c.goToCfi('epubcfi(/6/40)'), isFalse, reason: 'page 19 of 10');
    expect(c.goToCfi('epubcfi(/4/2)'), isFalse);
    expect(c.page, 2);

    c.goToFraction(0);
    expect(c.page, 0);
    c.goToFraction(1);
    expect(c.page, 9);
    c.goToFraction(0.35);
    expect(c.page, 3);
    c.goToFraction(0.3);
    expect(c.page, 3, reason: 'the fraction a page reports opens that page');
    c.goToFraction(0.29);
    expect(c.page, 2);
    c.goToFraction(1.5);
    expect(c.page, 9);
    expect(() => c.goToPage(10), throwsRangeError);
  });

  test('every move resets zoom and bumps the epoch', () {
    final c = controller();
    final epoch = c.zoomEpoch;
    c.reportZoomScale(2.5);
    expect(c.isZoomed, isTrue);
    expect(c.zoomScale, 2.5);
    c.next();
    expect(c.isZoomed, isFalse);
    expect(c.zoomEpoch, epoch + 1);
    c.reportZoomScale(3);
    c.attachViewport(landscape);
    expect(c.isZoomed, isFalse);
    expect(c.zoomEpoch, epoch + 2);
    c.reportZoomScale(3);
    c.resetZoom();
    expect(c.isZoomed, isFalse);
    expect(c.zoomEpoch, epoch + 3);
  });

  test('zoom reports notify only when the zoomed state flips', () {
    final c = controller();
    var notified = 0;
    c.addListener(() => notified++);
    c.reportZoomScale(1.005);
    expect(c.isZoomed, isFalse);
    expect(notified, 0);
    c.reportZoomScale(1.5);
    expect(notified, 1);
    c.reportZoomScale(2);
    expect(notified, 1);
    c.reportZoomScale(1);
    expect(notified, 2);
  });

  test('input lock is a notifying flag', () {
    final c = controller();
    var notified = 0;
    c.addListener(() => notified++);
    c.lockInput(true);
    c.lockInput(true);
    expect(c.inputLocked, isTrue);
    expect(notified, 1);
    c.lockInput(false);
    expect(notified, 2);
  });

  test('prefetch covers the neighbours of what is visible', () {
    final c = controller(pages: 6);
    expect(c.pagesToPrefetch, [1]);
    c.goToPage(2);
    expect(c.pagesToPrefetch, [1, 3]);
    c.goToPage(5);
    expect(c.pagesToPrefetch, [4]);
    c.attachViewport(landscape);
    expect(c.visiblePages, [4, 5]);
    expect(c.pagesToPrefetch, [3]);
    c.goToPage(2);
    expect(c.pagesToPrefetch, [1, 4]);
  });
}
