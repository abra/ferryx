import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// A saved rectangle on a page image, in fractions of the image, as the
/// app stores it (`HighlightImageArea`).
@immutable
class ComicImageArea {
  const ComicImageArea({
    required this.id,
    required this.page,
    required this.rect,
    required this.color,
  });

  final String id;
  final int page;

  /// `x`, `y`, `width`, `height` in `0…1` of the displayed image.
  final Rect rect;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is ComicImageArea &&
      other.id == id &&
      other.page == page &&
      other.rect == rect &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, page, rect, color);
}

/// Corner a draft is resized from.
enum ComicAreaHandle { nw, ne, sw, se }

/// Geometry of image-area drafts. The default and minimum rectangle sizes
/// retain the WebView reader's normalized values (`book.js`).
abstract final class ComicImageAreaGeometry {
  /// A new draft is this big, centred on the press.
  static const defaultWidth = 0.213333;
  static const defaultHeight = 0.146667;

  /// A draft can shrink to this on either side.
  static const minSize = 0.015;

  /// The long press that starts a draft.
  static const longPressDuration = Duration(milliseconds: 280);

  /// Screen pixels for corner grips and their extra hit padding. Touch targets
  /// extend outside the draft, with nearest-corner arbitration where they overlap.
  static const cornerHitPadding = 1.5;
  static const gripLeg = 48.0;
  static const handleTarget = 64.0;
  static const handleOutset = 48.0;

  /// The draft a press at [point] (fractions of the image) creates:
  /// default size, centred, kept inside the image.
  static Rect draftAt(Offset point) {
    final x = (point.dx - defaultWidth / 2).clamp(0.0, 1 - defaultWidth);
    final y = (point.dy - defaultHeight / 2).clamp(0.0, 1 - defaultHeight);
    return Rect.fromLTWH(x, y, defaultWidth, defaultHeight);
  }

  static Rect move(Rect rect, Offset delta) => Rect.fromLTWH(
    (rect.left + delta.dx).clamp(0.0, 1 - rect.width),
    (rect.top + delta.dy).clamp(0.0, 1 - rect.height),
    rect.width,
    rect.height,
  );

  static Rect resize(Rect rect, ComicAreaHandle handle, Offset delta) {
    var left = rect.left;
    var top = rect.top;
    var right = rect.right;
    var bottom = rect.bottom;
    final west = handle == ComicAreaHandle.nw || handle == ComicAreaHandle.sw;
    final north = handle == ComicAreaHandle.nw || handle == ComicAreaHandle.ne;
    if (west) {
      left = (left + delta.dx).clamp(0.0, right - minSize);
    } else {
      right = (right + delta.dx).clamp(left + minSize, 1.0);
    }
    if (north) {
      top = (top + delta.dy).clamp(0.0, bottom - minSize);
    } else {
      bottom = (bottom + delta.dy).clamp(top + minSize, 1.0);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Side of a corner's touch square in layer pixels, independent of crop size.
  static double handleSize(Size drawnSize, double zoomScale) =>
      handleTarget / zoomScale;

  /// Each diagonal cuts off a right triangle, without touching its opposite.
  static double gripLegLength(Size drawnSize, double zoomScale) =>
      math.min(gripLeg / zoomScale, drawnSize.shortestSide * .45);

  /// Midpoints along the four corner bisectors, in layer coordinates.
  static Rect gripCenters(Rect drawn, double zoomScale, {Rect? bounds}) =>
      drawn.deflate(gripLegLength(drawn.size, zoomScale) / 4);

  /// The nearest corner target under [point], or null for the central move
  /// region. Optional page-frame [bounds] shift targets inward at page edges.
  static ComicAreaHandle? handleAt(
    Offset point,
    Rect drawn,
    double zoomScale, {
    Rect? bounds,
  }) {
    final size = handleSize(drawn.size, zoomScale);
    final leg = gripLegLength(drawn.size, zoomScale);
    final padding = math.min(
      cornerHitPadding / zoomScale,
      drawn.shortestSide / 10,
    );
    for (final handle in ComicAreaHandle.values) {
      final west = handle == ComicAreaHandle.nw || handle == ComicAreaHandle.sw;
      final north =
          handle == ComicAreaHandle.nw || handle == ComicAreaHandle.ne;
      final dx = west ? point.dx - drawn.left : drawn.right - point.dx;
      final dy = north ? point.dy - drawn.top : drawn.bottom - point.dy;
      if (dx >= -precisionErrorTolerance &&
          dy >= -precisionErrorTolerance &&
          dx + dy <= leg + precisionErrorTolerance) {
        return handle;
      }
    }
    final centre = Rect.fromCenter(
      center: drawn.center,
      width: drawn.width / 2,
      height: drawn.height / 2,
    );
    if (centre.contains(point)) return null;
    final outset = handleOutset / zoomScale;
    final inset = size - outset;
    ComicAreaHandle? nearest;
    var distance = double.infinity;
    for (final handle in ComicAreaHandle.values) {
      final west = handle == ComicAreaHandle.nw || handle == ComicAreaHandle.sw;
      final north =
          handle == ComicAreaHandle.nw || handle == ComicAreaHandle.ne;
      final corner = Offset(
        west ? drawn.left : drawn.right,
        north ? drawn.top : drawn.bottom,
      );
      var target = Rect.fromLTWH(
        corner.dx - (west ? outset : inset),
        corner.dy - (north ? outset : inset),
        size,
        size,
      );
      if (bounds != null) {
        final width = math.min(size, bounds.width);
        final height = math.min(size, bounds.height);
        target = Rect.fromLTWH(
          target.left.clamp(bounds.left, bounds.right - width),
          target.top.clamp(bounds.top, bounds.bottom - height),
          width,
          height,
        );
      }
      final candidate = (point - corner).distanceSquared;
      final dx = west ? point.dx - corner.dx : corner.dx - point.dx;
      final dy = north ? point.dy - corner.dy : corner.dy - point.dy;
      final paddedTriangle =
          dx >= -precisionErrorTolerance &&
          dy >= -precisionErrorTolerance &&
          dx + dy <= leg + 2 * padding + precisionErrorTolerance;
      if ((target.contains(point) || paddedTriangle) && candidate < distance) {
        nearest = handle;
        distance = candidate;
      }
    }
    return nearest;
  }

  /// The topmost saved area under [point] (fractions), or null.
  static ComicImageArea? areaAt(Offset point, List<ComicImageArea> areas) {
    for (final area in areas.reversed) {
      if (area.rect.contains(point)) return area;
    }
    return null;
  }
}

/// The image-area selection being made: which page, where, and whether a
/// sheet above it is keeping it alive.
///
/// Owned by the app for the whole reader like a `TextEditingController`;
/// `ComicImageAreaLayer` edits it and `FixedPagesView` locks input while
/// it exists. The app saves it or clears it.
class ComicImageAreaDraft extends ChangeNotifier {
  int? _page;
  Rect? _rect;
  bool _retained = false;
  Color _color = const Color(0xFFFFE600);
  double _opacity = 0.45;
  final _pointers = <int>{};
  int? _primaryPointer;
  bool _multiplePointers = false;

  /// Page layers share pointer ownership so touching the other half of a
  /// spread cannot replace or move an edit already in progress.
  void trackPointer(int pointer) {
    if (_pointers.isEmpty) {
      _primaryPointer = pointer;
      _multiplePointers = false;
    }
    _pointers.add(pointer);
    if (_pointers.length > 1) _multiplePointers = true;
  }

  void untrackPointer(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty) _primaryPointer = null;
  }

  /// Only the first pointer in a sequence may create or adjust a draft.
  bool isPrimaryPointer(int pointer) => _primaryPointer == pointer;

  /// Remains true until a fresh sequence, even after extra fingers lift.
  bool get hasMultiplePointers => _multiplePointers;

  int? get page => _page;

  Rect? get rect => _rect;

  bool get isActive => _rect != null;

  /// While retained, taps outside the draft do not dismiss it.
  bool get retained => _retained;

  Color get color => _color;

  double get opacity => _opacity;

  void start(int page, Rect rect) {
    _page = page;
    _rect = rect;
    notifyListeners();
  }

  void update(Rect rect) {
    if (_rect == null || rect == _rect) return;
    _rect = rect;
    notifyListeners();
  }

  void clear() {
    if (_rect == null) return;
    _page = null;
    _rect = null;
    _retained = false;
    notifyListeners();
  }

  void retain(bool retained) {
    if (_retained == retained) return;
    _retained = retained;
    notifyListeners();
  }

  /// The colour and opacity the draft is drawn with, from the app's
  /// highlight palette.
  void setStyle({Color? color, double? opacity}) {
    final newColor = color ?? _color;
    final newOpacity = opacity ?? _opacity;
    if (newColor == _color && newOpacity == _opacity) return;
    _color = newColor;
    _opacity = newOpacity;
    notifyListeners();
  }
}
