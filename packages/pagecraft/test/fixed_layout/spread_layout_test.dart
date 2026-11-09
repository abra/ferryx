import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  group('comicSpreads', () {
    test('pairs pages left then right for left-to-right books', () {
      expect(comicSpreads(5, rtl: false), const [
        PageSpread(left: 0, right: 1),
        PageSpread(left: 2, right: 3),
        PageSpread(left: 4),
      ]);
    });

    test('pairs pages right then left for right-to-left books', () {
      expect(comicSpreads(4, rtl: true), const [
        PageSpread(right: 0, left: 1),
        PageSpread(right: 2, left: 3),
      ]);
      expect(comicSpreads(1, rtl: true), const [PageSpread(right: 0)]);
    });

    test('a spread knows its pages in reading order', () {
      const spread = PageSpread(right: 0, left: 1);
      expect(spread.pagesInReadingOrder(rtl: true), [0, 1]);
      expect(
        const PageSpread(left: 0, right: 1).pagesInReadingOrder(rtl: false),
        [0, 1],
      );
      expect(const PageSpread(center: 7).pagesInReadingOrder(rtl: false), [7]);
      expect(spread.sideOf(1), SpreadSide.left);
      expect(spread.sideOf(9), isNull);
      expect(spread.contains(0), isTrue);
      expect(spread.toString(), 'PageSpread(left: 1, right: 0, center: null)');
    });
  });

  group('isSinglePageViewport', () {
    test('needs a height above 1.2 widths', () {
      expect(isSinglePageViewport(390, 844), isTrue);
      expect(isSinglePageViewport(844, 390), isFalse);
      expect(isSinglePageViewport(800, 960), isFalse, reason: 'exactly 1.2');
      expect(isSinglePageViewport(800, 961), isTrue);
      expect(isSinglePageViewport(0, 100), isFalse, reason: 'not laid out yet');
    });
  });

  group('SpreadLayout', () {
    final ltr = SpreadLayout(pageCount: 5, rtl: false);
    final rtl = SpreadLayout(pageCount: 5, rtl: true);

    test('locates a page in its spread and reports it back', () {
      expect(
        ltr.locationOfPage(3),
        const SpreadLocation(spreadIndex: 1, side: SpreadSide.right),
      );
      expect(
        rtl.locationOfPage(3),
        const SpreadLocation(spreadIndex: 1, side: SpreadSide.left),
      );
      expect(ltr.pageAt(ltr.locationOfPage(3)), 3);
      expect(
        ltr.pageAt(
          const SpreadLocation(spreadIndex: 2, side: SpreadSide.right),
        ),
        4,
        reason: 'a missing half falls back to the other',
      );
      expect(() => ltr.locationOfPage(5), throwsRangeError);
    });

    test('single-page mode turns through both halves of every spread', () {
      var location = ltr.locationOfPage(0);
      final pages = <int>[ltr.pageAt(location)];
      while (true) {
        final next = ltr.next(location, singlePage: true);
        if (next == null) break;
        location = next;
        pages.add(ltr.pageAt(location));
      }
      expect(pages, [0, 1, 2, 3, 4]);
      expect(ltr.atEnd(location, singlePage: true), isTrue);

      final back = <int>[];
      while (true) {
        final previous = ltr.previous(location, singlePage: true);
        if (previous == null) break;
        location = previous;
        back.add(ltr.pageAt(location));
      }
      expect(back, [3, 2, 1, 0]);
      expect(ltr.atStart(location, singlePage: true), isTrue);
    });

    test(
      'single-page mode in a right-to-left book reads pages in order too',
      () {
        var location = rtl.locationOfPage(0);
        final pages = <int>[rtl.pageAt(location)];
        SpreadLocation? next;
        while ((next = rtl.next(location, singlePage: true)) != null) {
          location = next!;
          pages.add(rtl.pageAt(location));
        }
        expect(pages, [0, 1, 2, 3, 4]);
      },
    );

    test('spread mode turns whole spreads and stays bounded', () {
      // The WebView test: four forward turns on a five-page comic in
      // landscape end on page 4; four back turns show pages 0 and 1.
      for (final layout in [ltr, rtl]) {
        var location = layout.locationOfPage(0);
        for (var i = 0; i < 4; i++) {
          location = layout.next(location, singlePage: false) ?? location;
        }
        expect(layout.pageAt(location), 4, reason: 'rtl=${layout.rtl}');
        expect(layout.atEnd(location, singlePage: false), isTrue);
        for (var i = 0; i < 4; i++) {
          location = layout.previous(location, singlePage: false) ?? location;
        }
        expect(layout.visiblePages(location, singlePage: false), [0, 1]);
        expect(layout.atStart(location, singlePage: false), isTrue);
      }
    });

    test('entering a spread lands on the half nearest the reader', () {
      // Forward in LTR lands on the left half; backward on the right half.
      final forward = ltr.next(ltr.locationOfPage(1), singlePage: true)!;
      expect(forward.side, SpreadSide.left);
      expect(ltr.pageAt(forward), 2);
      final backward = ltr.previous(ltr.locationOfPage(2), singlePage: true)!;
      expect(backward.side, SpreadSide.right);
      expect(ltr.pageAt(backward), 1);
      // In RTL the roles swap.
      final rtlForward = rtl.next(rtl.locationOfPage(1), singlePage: true)!;
      expect(rtlForward.side, SpreadSide.right);
      expect(rtl.pageAt(rtlForward), 2);
    });

    test('a lone last page is centred and shown alone in spread mode', () {
      final location = ltr.locationOfPage(4);
      expect(ltr.visiblePages(location, singlePage: false), [4]);
      expect(ltr.visiblePages(ltr.locationOfPage(2), singlePage: false), [
        2,
        3,
      ]);
      expect(rtl.visiblePages(rtl.locationOfPage(2), singlePage: false), [
        2,
        3,
      ]);
      expect(ltr.visiblePages(ltr.locationOfPage(3), singlePage: true), [3]);
    });

    test('a one-page comic is both start and end', () {
      final single = SpreadLayout(pageCount: 1, rtl: false);
      final location = single.locationOfPage(0);
      expect(single.atStart(location, singlePage: true), isTrue);
      expect(single.atEnd(location, singlePage: true), isTrue);
      expect(single.atEnd(location, singlePage: false), isTrue);
      expect(single.next(location, singlePage: true), isNull);
    });
  });

  group('FixedPagePosition', () {
    test('reports the numbers the WebView reader reports', () {
      final position = FixedPagePosition(page: 2, pageCount: 10);
      expect(position.cfi, 'epubcfi(/6/6)');
      expect(position.fraction, 0.3);
      expect(position.chapterCurrentPage, 2);
      expect(position.chapterTotalPages, 10);
      expect(position.bookCurrentPage, 0);
      expect(position.bookTotalPages, 1);
      expect(position.sizeTotal, 10);
      expect(FixedPagePosition(page: 9, pageCount: 10).fraction, 1);
      expect(FixedPagePosition(page: 0, pageCount: 1).fraction, 1);
      expect(FixedPagePosition(page: 1500, pageCount: 3001).bookCurrentPage, 1);
      expect(FixedPagePosition(page: 0, pageCount: 3001).bookTotalPages, 3);
      expect(position, FixedPagePosition(page: 2, pageCount: 10));
      expect(
        position.hashCode,
        FixedPagePosition(page: 2, pageCount: 10).hashCode,
      );
    });

    test('rejects pages outside the comic', () {
      expect(
        () => FixedPagePosition(page: 3, pageCount: 3),
        throwsAssertionError,
      );
    });
  });
}
