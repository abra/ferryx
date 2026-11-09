/// The printed area of a rendered page, from a small sample of its pixels,
/// and the margin crop that follows from it. Pure functions, ported from
/// `readflex_page_content.js` and `readflex_page_geometry.js`.
library;

/// Long side of the sample a page is downscaled to before detection. The
/// box is only as precise as one sample pixel, so crops add their own
/// padding; 160 px keeps the read-back below 0.1 MiB.
const pageContentSampleSize = 160;

/// Luminance difference from the paper (0–255) that counts as ink. Faint
/// grey rules and light scan noise stay paper; body text is far above it.
const _inkDelta = 28;

/// Scans keep shadows and binding marks along the very edge of the page.
const _edgeFraction = 0.01;

/// Rows and columns need this share of inked samples, or at least two, so
/// isolated specks in a scanned margin do not stretch the box.
const _minInkFraction = 0.01;

/// Space kept between the detected ink and the cropped page edge, as a
/// fraction of the page size.
const contentCropPadding = 0.02;

/// Pages whose ink is narrower than this fraction of the page (a title
/// page, a lone figure) keep the whole page; cropping them would zoom one
/// page far beyond its neighbours.
const minContentCropWidth = 0.5;

/// Byte order of 8-bit pixels.
enum PixelOrder { rgba, bgra }

/// A rectangle with exclusive [right] and [bottom].
class ContentBox {
  const ContentBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  /// The same box in a space [factor] times larger.
  ContentBox scaled(double factor) => ContentBox(
    left: left * factor,
    top: top * factor,
    right: right * factor,
    bottom: bottom * factor,
  );

  @override
  bool operator ==(Object other) =>
      other is ContentBox &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'ContentBox($left, $top, $right, $bottom)';
}

/// Bounding box of the ink on a page sample, in sample pixels, or null for
/// a blank page.
///
/// The paper tone is the median of the ring just inside the ignored edge,
/// so off-white and grey scans work as well as white pages. [pixels] is
/// row-major, four bytes per pixel in [order].
ContentBox? detectContentBox(
  List<int> pixels,
  int width,
  int height, {
  PixelOrder order = PixelOrder.rgba,
}) {
  if (width <= 2 || height <= 2 || pixels.length < width * height * 4) {
    return null;
  }
  final shorter = width < height ? width : height;
  final edge = (shorter * _edgeFraction).round().clamp(1, shorter);
  final x0 = edge;
  final y0 = edge;
  final x1 = width - edge;
  final y1 = height - edge;
  if (x1 <= x0 || y1 <= y0) return null;

  int luminance(int offset) => order == PixelOrder.rgba
      ? (pixels[offset] * 54 +
                pixels[offset + 1] * 183 +
                pixels[offset + 2] * 19) >>
            8
      : (pixels[offset + 2] * 54 +
                pixels[offset + 1] * 183 +
                pixels[offset] * 19) >>
            8;

  final ring = <int>[];
  for (var x = x0; x < x1; x++) {
    ring.add(luminance((y0 * width + x) * 4));
    ring.add(luminance(((y1 - 1) * width + x) * 4));
  }
  for (var y = y0 + 1; y < y1 - 1; y++) {
    ring.add(luminance((y * width + x0) * 4));
    ring.add(luminance((y * width + x1 - 1) * 4));
  }
  final paper = _median(ring);

  final rows = List<int>.filled(height, 0);
  final columns = List<int>.filled(width, 0);
  for (var y = y0; y < y1; y++) {
    var offset = (y * width + x0) * 4;
    for (var x = x0; x < x1; x++, offset += 4) {
      if ((luminance(offset) - paper).abs() > _inkDelta) {
        rows[y]++;
        columns[x]++;
      }
    }
  }
  final minRowInk = _atLeastTwo(((x1 - x0) * _minInkFraction).round());
  final minColumnInk = _atLeastTwo(((y1 - y0) * _minInkFraction).round());
  var top = y0;
  while (top < y1 && rows[top] < minRowInk) {
    top++;
  }
  if (top == y1) return null;
  var bottom = y1;
  while (bottom > top && rows[bottom - 1] < minRowInk) {
    bottom--;
  }
  var left = x0;
  while (left < x1 && columns[left] < minColumnInk) {
    left++;
  }
  var right = x1;
  while (right > left && columns[right - 1] < minColumnInk) {
    right--;
  }
  if (right <= left) return null;
  // One sample pixel of slack covers ink that the downscale blended away.
  return ContentBox(
    left: (left - 1).clamp(0, width).toDouble(),
    top: (top - 1).clamp(0, height).toDouble(),
    right: (right + 1).clamp(0, width).toDouble(),
    bottom: (bottom + 1).clamp(0, height).toDouble(),
  );
}

/// Crop that removes blank page margins around [content].
///
/// Horizontal margins follow the ink. The height then grows to the aspect
/// of the available box, anchored at the top of the ink, so a page with
/// less text keeps the text size and the top edge of a full page. Returns
/// null when the crop would keep the whole page or the page is too sparse.
/// All lengths are page units; [availableWidth] and [availableHeight] are
/// the box the page is fitted into.
ContentBox? contentCrop({
  required ContentBox? content,
  required double width,
  required double height,
  required double availableWidth,
  required double availableHeight,
}) {
  if (content == null || width <= 0 || height <= 0) return null;
  final left = (content.left - width * contentCropPadding).clamp(0.0, width);
  final right = (content.right + width * contentCropPadding).clamp(0.0, width);
  final cropWidth = right - left;
  if (cropWidth < width * minContentCropWidth) return null;

  final inkTop = (content.top - height * contentCropPadding).clamp(0.0, height);
  final inkBottom = (content.bottom + height * contentCropPadding).clamp(
    inkTop,
    height,
  );
  final aspect = availableWidth > 0 && availableHeight > 0
      ? availableHeight / availableWidth
      : 0.0;
  final inkHeight = inkBottom - inkTop;
  final wanted = cropWidth * aspect;
  final cropHeight = (inkHeight > wanted ? inkHeight : wanted).clamp(
    0.0,
    height,
  );
  // Shift up instead of running past the bottom edge.
  final top = inkTop < height - cropHeight ? inkTop : height - cropHeight;
  final bottom = top + cropHeight;
  if (left < 1 && top < 1 && right > width - 1 && bottom > height - 1) {
    return null;
  }
  return ContentBox(left: left, top: top, right: right, bottom: bottom);
}

int _median(List<int> values) {
  if (values.isEmpty) return 255;
  values.sort();
  return values[values.length >> 1];
}

int _atLeastTwo(int value) => value < 2 ? 2 : value;
