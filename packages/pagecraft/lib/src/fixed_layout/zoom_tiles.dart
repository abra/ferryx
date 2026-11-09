/// Sharp tiles for zoomed pages, as `readflex_page_geometry.js` planned
/// them: a page is drawn at fit; once the screen shows it denser than its
/// bitmap, the visible part is rendered again at screen density and drawn
/// over it. Pure functions; lengths are page pixels at the base render
/// unless a name says otherwise.
library;

import 'dart:math' as math;
import 'dart:ui' show Rect;

/// A page is redrawn sharper once the screen shows it this much denser
/// than its bitmap. Smaller gaps are not visible and would waste renders.
const sharpenThreshold = 1.1;

/// Extra area rendered around the visible part of a zoomed page so short
/// pans stay sharp without another render.
const tileMargin = 0.2;

/// A page area and the density it is drawn at.
class TileRegion {
  const TileRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.density,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  /// Device pixels per page pixel.
  final double density;

  double get right => left + width;
  double get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      other is TileRegion &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height &&
      other.density == density;

  @override
  int get hashCode => Object.hash(left, top, width, height, density);

  @override
  String toString() =>
      'TileRegion($left, $top, ${width}x$height @ ${density.toStringAsFixed(2)})';
}

/// The visible part of a page that the screen shows denser than its
/// bitmap, or null when the bitmap is sharp enough or nothing is visible.
///
/// [frameRect] is the page window on screen and [viewport] the rect that
/// clips it, both in logical pixels; [visible] is the page area shown in
/// the window (the crop, or the whole page) in page pixels; [baseDensity]
/// is bitmap pixels per page pixel.
TileRegion? sharpenRegion({
  required Rect frameRect,
  required Rect viewport,
  required Rect visible,
  required double baseDensity,
  double devicePixelRatio = 1,
}) {
  if (visible.width <= 0 || frameRect.width <= 0) return null;
  final logicalPerPage = frameRect.width / visible.width;
  final density = logicalPerPage * devicePixelRatio;
  if (density <= baseDensity * sharpenThreshold) return null;
  final left = math.max(frameRect.left, viewport.left);
  final top = math.max(frameRect.top, viewport.top);
  final right = math.min(frameRect.right, viewport.right);
  final bottom = math.min(frameRect.bottom, viewport.bottom);
  if (right <= left || bottom <= top) return null;
  return TileRegion(
    left: visible.left + (left - frameRect.left) / logicalPerPage,
    top: visible.top + (top - frameRect.top) / logicalPerPage,
    width: (right - left) / logicalPerPage,
    height: (bottom - top) / logicalPerPage,
    density: density,
  );
}

/// The tile to render for [region]: the region plus a pan margin, clamped
/// to the page and fitted into [maxPixels]. The margin goes first, then
/// density. Edges are whole page pixels.
TileRegion tileFor(
  TileRegion region, {
  required double pageWidth,
  required double pageHeight,
  required int maxPixels,
}) {
  final marginX = region.width * tileMargin;
  final marginY = region.height * tileMargin;
  var rect = _outward(
    region.left - marginX,
    region.top - marginY,
    region.right + marginX,
    region.bottom + marginY,
    pageWidth,
    pageHeight,
  );
  double pixels(Rect r) => r.width * r.height * region.density * region.density;
  if (pixels(rect) > maxPixels) {
    rect = _outward(
      region.left,
      region.top,
      region.right,
      region.bottom,
      pageWidth,
      pageHeight,
    );
  }
  final area = rect.width * rect.height;
  final density = area > 0 && pixels(rect) > maxPixels
      ? math.sqrt(maxPixels / area)
      : region.density;
  return TileRegion(
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
    density: density,
  );
}

/// Whether a rendered [tile] still serves [region] without a new render.
bool tileCovers(TileRegion? tile, TileRegion? region) {
  if (tile == null || region == null) return false;
  const epsilon = 0.5;
  return tile.density >= region.density * 0.95 &&
      tile.left <= region.left + epsilon &&
      tile.top <= region.top + epsilon &&
      tile.right >= region.right - epsilon &&
      tile.bottom >= region.bottom - epsilon;
}

Rect _outward(
  double left,
  double top,
  double right,
  double bottom,
  double width,
  double height,
) {
  final x = math.max(0, left.floor()).toDouble();
  final y = math.max(0, top.floor()).toDouble();
  return Rect.fromLTWH(
    x,
    y,
    math.min(width, right.ceil().toDouble()) - x,
    math.min(height, bottom.ceil().toDouble()) - y,
  );
}
