import 'package:meta/meta.dart';

import '../epubcfi/fake_cfi.dart';

/// Which half of a spread a page sits on.
enum SpreadSide { left, right, center }

/// Two facing pages, or one page alone.
///
/// Comics carry no `page-spread-*` hints, so pages pair up in reading
/// order as `fixed-layout.js` pairs sections without hints: left then
/// right for left-to-right books, right then left for right-to-left ones.
@immutable
class PageSpread {
  const PageSpread({this.left, this.right, this.center})
    : assert(center == null || (left == null && right == null));

  final int? left;
  final int? right;
  final int? center;

  /// Pages in reading order.
  List<int> pagesInReadingOrder({required bool rtl}) => [
    ?center,
    if (rtl) ...[?right, ?left] else ...[?left, ?right],
  ];

  bool contains(int page) => left == page || right == page || center == page;

  SpreadSide? sideOf(int page) => page == center
      ? SpreadSide.center
      : page == left
      ? SpreadSide.left
      : page == right
      ? SpreadSide.right
      : null;

  @override
  bool operator ==(Object other) =>
      other is PageSpread &&
      other.left == left &&
      other.right == right &&
      other.center == center;

  @override
  int get hashCode => Object.hash(left, right, center);

  @override
  String toString() =>
      'PageSpread(left: $left, right: $right, center: $center)';
}

/// Groups [pageCount] pages into spreads.
List<PageSpread> comicSpreads(int pageCount, {required bool rtl}) {
  final spreads = <PageSpread>[];
  for (var page = 0; page < pageCount; page += 2) {
    final next = page + 1 < pageCount ? page + 1 : null;
    spreads.add(
      rtl
          ? PageSpread(right: page, left: next)
          : PageSpread(left: page, right: next),
    );
  }
  return spreads;
}

/// Whether a viewport shows one page at a time.
///
/// The 1.2 ratio comes from `fixed-layout.js` (and Readest): a device only
/// slightly taller than wide, such as an unfolded foldable, still shows a
/// two-page spread.
bool isSinglePageViewport(double width, double height) =>
    width > 0 && height > 0 && height > width * 1.2;

/// Where the reader is: a spread, and the half it shows when only one
/// half fits.
@immutable
class SpreadLocation {
  const SpreadLocation({required this.spreadIndex, required this.side});

  final int spreadIndex;
  final SpreadSide side;

  @override
  bool operator ==(Object other) =>
      other is SpreadLocation &&
      other.spreadIndex == spreadIndex &&
      other.side == side;

  @override
  int get hashCode => Object.hash(spreadIndex, side);

  @override
  String toString() => 'SpreadLocation($spreadIndex, ${side.name})';
}

/// Navigation over the spreads of one comic, with the rules of
/// `fixed-layout.js`: a turn moves within the spread first when the
/// viewport shows one page, then to the neighbouring spread, entering it
/// from the side the reader came from.
class SpreadLayout {
  SpreadLayout({required this.pageCount, required this.rtl})
    : spreads = List.unmodifiable(comicSpreads(pageCount, rtl: rtl));

  final int pageCount;
  final bool rtl;
  final List<PageSpread> spreads;

  SpreadLocation locationOfPage(int page) {
    RangeError.checkValidIndex(page, null, 'page', pageCount);
    final spreadIndex = page ~/ 2;
    return SpreadLocation(
      spreadIndex: spreadIndex,
      side: spreads[spreadIndex].sideOf(page)!,
    );
  }

  /// The page a location reports as its position: the shown half, or the
  /// other one when that half is empty.
  int pageAt(SpreadLocation location) {
    final spread = spreads[location.spreadIndex];
    if (spread.center != null) return spread.center!;
    return switch (location.side) {
      SpreadSide.left => spread.left ?? spread.right!,
      _ => spread.right ?? spread.left!,
    };
  }

  /// Pages on screen: both halves, or the one shown in single-page mode.
  List<int> visiblePages(SpreadLocation location, {required bool singlePage}) {
    final spread = spreads[location.spreadIndex];
    if (singlePage || spread.center != null) return [pageAt(location)];
    return spread.pagesInReadingOrder(rtl: rtl);
  }

  /// The location after a forward turn, or null at the end.
  SpreadLocation? next(SpreadLocation location, {required bool singlePage}) =>
      _turn(location, forward: true, singlePage: singlePage);

  /// The location after a backward turn, or null at the start.
  SpreadLocation? previous(
    SpreadLocation location, {
    required bool singlePage,
  }) => _turn(location, forward: false, singlePage: singlePage);

  bool atStart(SpreadLocation location, {required bool singlePage}) =>
      previous(location, singlePage: singlePage) == null;

  bool atEnd(SpreadLocation location, {required bool singlePage}) =>
      next(location, singlePage: singlePage) == null;

  SpreadLocation? _turn(
    SpreadLocation location, {
    required bool forward,
    required bool singlePage,
  }) {
    final toRight = forward != rtl;
    final spread = spreads[location.spreadIndex];
    if (singlePage && spread.center == null) {
      // The other half of the same spread comes first, when it exists.
      if (toRight && location.side == SpreadSide.left && spread.right != null) {
        return SpreadLocation(
          spreadIndex: location.spreadIndex,
          side: SpreadSide.right,
        );
      }
      if (!toRight &&
          location.side == SpreadSide.right &&
          spread.left != null) {
        return SpreadLocation(
          spreadIndex: location.spreadIndex,
          side: SpreadSide.left,
        );
      }
    }
    final target = location.spreadIndex + (forward ? 1 : -1);
    if (target < 0 || target >= spreads.length) return null;
    final entering = spreads[target];
    final side = entering.center != null
        ? SpreadSide.center
        : toRight
        ? SpreadSide.left
        : SpreadSide.right;
    return SpreadLocation(spreadIndex: target, side: side);
  }
}

/// The position numbers the app shows for a comic page, as the WebView
/// reader reports them: every page is a section of size 1, so the fraction
/// is `(page + 1) / pageCount`, the chapter counter is the page counter,
/// and the byte-based book locations collapse to one.
@immutable
class FixedPagePosition {
  const FixedPagePosition({required this.page, required this.pageCount})
    : assert(page >= 0 && page < pageCount);

  final int page;
  final int pageCount;

  String get cfi => fakeCfiFromIndex(page);

  double get fraction => (page + 1) / pageCount;

  int get chapterCurrentPage => page;

  int get chapterTotalPages => pageCount;

  /// `floor(page / 1500)`: zero for any comic shorter than 1500 pages.
  int get bookCurrentPage => page ~/ _bytesPerLocation;

  /// `ceil(pageCount / 1500)`: one for any comic shorter than 1500 pages.
  int get bookTotalPages =>
      (pageCount + _bytesPerLocation - 1) ~/ _bytesPerLocation;

  int get sizeTotal => pageCount;

  static const _bytesPerLocation = 1500;

  @override
  bool operator ==(Object other) =>
      other is FixedPagePosition &&
      other.page == page &&
      other.pageCount == pageCount;

  @override
  int get hashCode => Object.hash(page, pageCount);
}
