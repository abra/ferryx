import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../epubcfi/fake_cfi.dart';
import 'spread_layout.dart';

/// Why the reader is on its current page, as the app reports it.
enum PageRelocationReason {
  /// A turn: swipe, edge tap, `next`/`previous`.
  page,

  /// A jump: a saved position, the table of contents, the slider.
  navigation,
}

/// Where an image-page document is open: the model behind
/// `FixedPagesView`, usable without it.
///
/// A `ChangeNotifier` like `PageController`: the view listens for the unit
/// to show, the app listens for the position. The view tells the controller
/// its size (which decides single-page or spread mode) and its zoom; the
/// controller tells the view when to reset zoom.
class FixedPagesController extends ChangeNotifier {
  FixedPagesController({
    required int pageCount,
    required bool rtl,
    int initialPage = 0,
  }) : layout = SpreadLayout(pageCount: pageCount, rtl: rtl),
       _location = SpreadLayout(
         pageCount: pageCount,
         rtl: rtl,
       ).locationOfPage(initialPage);

  final SpreadLayout layout;
  SpreadLocation _location;
  bool _singlePage = true;
  double _zoomScale = 1;
  int _zoomEpoch = 0;
  bool _inputLocked = false;
  PageRelocationReason? _lastReason;

  /// Zoom above this is "zoomed": swipes pan and taps no longer turn pages.
  static const zoomedThreshold = 1.01;

  int get pageCount => layout.pageCount;

  bool get rtl => layout.rtl;

  SpreadLocation get location => _location;

  /// The page the position reports.
  int get page => layout.pageAt(_location);

  FixedPagePosition get position =>
      FixedPagePosition(page: page, pageCount: pageCount);

  /// How the current page was reached, null before any move.
  PageRelocationReason? get lastRelocationReason => _lastReason;

  /// One page per screen (portrait) or a two-page spread.
  bool get singlePage => _singlePage;

  List<int> get visiblePages =>
      layout.visiblePages(_location, singlePage: _singlePage);

  bool get atStart => layout.atStart(_location, singlePage: _singlePage);

  bool get atEnd => layout.atEnd(_location, singlePage: _singlePage);

  /// What a `PageView` scrolls through: pages in single-page mode, spreads
  /// otherwise.
  int get unitCount => _singlePage ? pageCount : layout.spreads.length;

  int get unit => _singlePage ? page : _location.spreadIndex;

  double get zoomScale => _zoomScale;

  bool get isZoomed => _zoomScale > zoomedThreshold;

  /// Increments whenever zoom must return to fit: a turn, a jump, a
  /// rotation, [resetZoom]. The view compares it with the last one it
  /// applied.
  int get zoomEpoch => _zoomEpoch;

  /// While an image-area draft is being edited, swipes and taps belong to
  /// it.
  bool get inputLocked => _inputLocked;

  /// Pages the view should keep decoded: the visible ones and their
  /// neighbours in reading order.
  List<int> get pagesToPrefetch {
    final visible = visiblePages;
    final first = visible.reduce(math.min);
    final last = visible.reduce(math.max);
    return [
      if (first > 0) first - 1,
      if (last < pageCount - 1) last + 1,
    ];
  }

  /// Turns forward; false at the end.
  bool next() => _move(layout.next(_location, singlePage: _singlePage));

  /// Turns backward; false at the start.
  bool previous() => _move(layout.previous(_location, singlePage: _singlePage));

  bool _move(SpreadLocation? target) {
    if (target == null) return false;
    _relocate(target, PageRelocationReason.page);
    return true;
  }

  void goToPage(int page) {
    _relocate(layout.locationOfPage(page), PageRelocationReason.navigation);
  }

  /// Opens the page a saved position names; false when [cfi] is not a page
  /// of this comic.
  bool goToCfi(String cfi) {
    final page = fakeCfiToIndex(cfi);
    if (page == null || page >= pageCount) return false;
    goToPage(page);
    return true;
  }

  /// Opens the page at a fraction of the book, as the slider asks: the
  /// inverse of `FixedPagePosition.fraction` with foliate-js's rounding.
  void goToFraction(double fraction) {
    final page = fraction <= 0
        ? 0
        : fraction >= 1
        ? pageCount - 1
        : math.min(pageCount - 1, (fraction * pageCount).floor());
    goToPage(page);
  }

  /// The view scrolled to [unit] itself (a swipe). A forward scroll enters
  /// a spread from the side the reader came from, as a turn does.
  void showUnit(int unit) {
    if (unit == this.unit) return;
    final SpreadLocation target;
    if (_singlePage) {
      target = layout.locationOfPage(unit);
    } else {
      final forward = unit > _location.spreadIndex;
      final spread = layout.spreads[unit];
      final toRight = forward != rtl;
      target = SpreadLocation(
        spreadIndex: unit,
        side: spread.center != null
            ? SpreadSide.center
            : toRight
            ? SpreadSide.left
            : SpreadSide.right,
      );
    }
    _relocate(target, PageRelocationReason.page);
  }

  void _relocate(SpreadLocation target, PageRelocationReason reason) {
    final changed = target != _location;
    _location = target;
    _lastReason = reason;
    _resetZoomState();
    if (changed || reason == PageRelocationReason.navigation) {
      notifyListeners();
    }
  }

  /// The view's size decides the mode; a change keeps the page and resets
  /// zoom, as a rotation does in the WebView reader.
  ///
  /// Called from the view's layout, so listeners hear about a change after
  /// the frame, not in the middle of the build that reported the size.
  void attachViewport(Size size) {
    final singlePage = isSinglePageViewport(size.width, size.height);
    if (singlePage == _singlePage) return;
    _singlePage = singlePage;
    _resetZoomState();
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  /// The view reports its zoom after a gesture.
  void reportZoomScale(double scale) {
    final wasZoomed = isZoomed;
    _zoomScale = scale;
    if (wasZoomed != isZoomed) notifyListeners();
  }

  void resetZoom() {
    _resetZoomState();
    notifyListeners();
  }

  void _resetZoomState() {
    _zoomEpoch++;
    _zoomScale = 1;
  }

  void lockInput(bool locked) {
    if (locked == _inputLocked) return;
    _inputLocked = locked;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
