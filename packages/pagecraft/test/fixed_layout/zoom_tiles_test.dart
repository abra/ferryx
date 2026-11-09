import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  // A 1000×1500 page drawn at fit into a 390×585 frame on a 3× screen.
  const page = Rect.fromLTWH(0, 0, 1000, 1500);
  const frame = Rect.fromLTWH(0, 0, 390, 585);
  const viewport = Rect.fromLTWH(0, 0, 390, 844);

  group('sharpenRegion', () {
    test('a page at fit is sharp enough', () {
      expect(
        sharpenRegion(
          frameRect: frame,
          viewport: viewport,
          visible: page,
          baseDensity: 1.17,
          devicePixelRatio: 3,
        ),
        isNull,
      );
    });

    test('a zoomed page wants the visible part at screen density', () {
      // Zoomed 2.5×: the frame is 975 wide and partly off screen.
      final region = sharpenRegion(
        frameRect: const Rect.fromLTWH(-300, -200, 975, 1462.5),
        viewport: viewport,
        visible: page,
        baseDensity: 1.17,
        devicePixelRatio: 3,
      )!;
      expect(region.density, closeTo(2.925, 1e-9));
      expect(region.left, closeTo(300 / 0.975, 1e-9));
      expect(region.top, closeTo(200 / 0.975, 1e-9));
      expect(region.width, closeTo(390 / 0.975, 1e-9));
      expect(region.height, closeTo(844 / 0.975, 1e-9));
    });

    test('a cropped page measures density from the crop', () {
      const crop = Rect.fromLTWH(100, 0, 800, 1200);
      final region = sharpenRegion(
        frameRect: frame,
        viewport: viewport,
        visible: crop,
        baseDensity: 1.17,
        devicePixelRatio: 3,
      );
      expect(region, isNotNull, reason: 'the crop enlarges the page');
      expect(region!.left, 100);
      expect(region.density, closeTo(390 / 800 * 3, 1e-9));
    });

    test('nothing visible means no tile', () {
      expect(
        sharpenRegion(
          frameRect: const Rect.fromLTWH(1000, 0, 975, 1462.5),
          viewport: viewport,
          visible: page,
          baseDensity: 1.17,
          devicePixelRatio: 3,
        ),
        isNull,
      );
    });
  });

  group('tileFor', () {
    const region = TileRegion(
      left: 300,
      top: 200,
      width: 400,
      height: 800,
      density: 3,
    );

    test('adds the pan margin on whole pixels, clamped to the page', () {
      final tile = tileFor(
        region,
        pageWidth: 1000,
        pageHeight: 1500,
        maxPixels: 6000000,
      );
      expect(tile.left, 220);
      expect(tile.top, 40);
      expect(tile.right, 780);
      expect(tile.bottom, 1160);
      expect(tile.density, 3);
      final atEdge = tileFor(
        const TileRegion(left: 0, top: 0, width: 400, height: 800, density: 3),
        pageWidth: 1000,
        pageHeight: 1500,
        maxPixels: 6000000,
      );
      expect(atEdge.left, 0);
      expect(atEdge.top, 0);
    });

    test('drops the margin, then density, to fit the pixel budget', () {
      final noMargin = tileFor(
        region,
        pageWidth: 1000,
        pageHeight: 1500,
        maxPixels: 3000000,
      );
      expect(noMargin.width, 400);
      expect(noMargin.height, 800);
      expect(
        noMargin.density,
        closeTo(3, 1e-9),
        reason: '320000 × 9 = 2.88 Mpx fits',
      );
      final softer = tileFor(
        region,
        pageWidth: 1000,
        pageHeight: 1500,
        maxPixels: 1000000,
      );
      expect(softer.width, 400);
      expect(softer.density, closeTo(1.7678, 1e-3));
    });
  });

  group('tileCovers', () {
    const tile = TileRegion(
      left: 220,
      top: 40,
      width: 560,
      height: 1120,
      density: 3,
    );

    test('a tile serves regions inside it at near density', () {
      expect(
        tileCovers(
          tile,
          const TileRegion(
            left: 300,
            top: 200,
            width: 400,
            height: 800,
            density: 3,
          ),
        ),
        isTrue,
      );
      expect(
        tileCovers(
          tile,
          const TileRegion(
            left: 300,
            top: 200,
            width: 400,
            height: 800,
            density: 3.1,
          ),
        ),
        isTrue,
      );
      expect(
        tileCovers(
          tile,
          const TileRegion(
            left: 300,
            top: 200,
            width: 400,
            height: 800,
            density: 3.5,
          ),
        ),
        isFalse,
      );
      expect(
        tileCovers(
          tile,
          const TileRegion(
            left: 100,
            top: 200,
            width: 400,
            height: 800,
            density: 3,
          ),
        ),
        isFalse,
      );
      expect(
        tileCovers(
          null,
          const TileRegion(left: 0, top: 0, width: 1, height: 1, density: 1),
        ),
        isFalse,
      );
      expect(tileCovers(tile, null), isFalse);
    });
  });
}
