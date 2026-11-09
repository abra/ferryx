import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

Matcher rectCloseTo(Rect expected) => predicate<Rect>(
  (rect) =>
      (rect.left - expected.left).abs() < 1e-9 &&
      (rect.top - expected.top).abs() < 1e-9 &&
      (rect.right - expected.right).abs() < 1e-9 &&
      (rect.bottom - expected.bottom).abs() < 1e-9,
  'a rect within 1e-9 of $expected',
);

void main() {
  group('ComicImageAreaGeometry', () {
    test('a draft is the default size centred on the press', () {
      final rect = ComicImageAreaGeometry.draftAt(const Offset(0.5, 0.5));
      expect(rect.width, closeTo(ComicImageAreaGeometry.defaultWidth, 1e-9));
      expect(rect.height, closeTo(ComicImageAreaGeometry.defaultHeight, 1e-9));
      expect(rect.center.dx, closeTo(0.5, 1e-9));
      expect(rect.center.dy, closeTo(0.5, 1e-9));
    });

    test('a draft near an edge stays inside the image', () {
      final corner = ComicImageAreaGeometry.draftAt(const Offset(0.01, 0.99));
      expect(corner.left, 0);
      expect(corner.bottom, closeTo(1, 1e-9));
      final right = ComicImageAreaGeometry.draftAt(const Offset(1, 0));
      expect(right.right, closeTo(1, 1e-9));
      expect(right.top, 0);
    });

    test('moving clamps to the image', () {
      const rect = Rect.fromLTWH(0.4, 0.4, 0.2, 0.1);
      expect(
        ComicImageAreaGeometry.move(rect, const Offset(0.1, -0.1)),
        rectCloseTo(const Rect.fromLTWH(0.5, 0.3, 0.2, 0.1)),
      );
      final clamped = ComicImageAreaGeometry.move(rect, const Offset(5, 5));
      expect(clamped.right, closeTo(1, 1e-9));
      expect(clamped.bottom, closeTo(1, 1e-9));
      expect(clamped.size, rect.size);
      expect(
        ComicImageAreaGeometry.move(rect, const Offset(-5, -5)).topLeft,
        Offset.zero,
      );
    });

    test(
      'resizing from each corner keeps the opposite corner and a minimum size',
      () {
        const rect = Rect.fromLTWH(0.4, 0.4, 0.2, 0.2);
        final se = ComicImageAreaGeometry.resize(
          rect,
          ComicAreaHandle.se,
          const Offset(0.1, 0.1),
        );
        expect(se, rectCloseTo(const Rect.fromLTRB(0.4, 0.4, 0.7, 0.7)));
        final nw = ComicImageAreaGeometry.resize(
          rect,
          ComicAreaHandle.nw,
          const Offset(-0.1, -0.1),
        );
        expect(nw, rectCloseTo(const Rect.fromLTRB(0.3, 0.3, 0.6, 0.6)));
        final ne = ComicImageAreaGeometry.resize(
          rect,
          ComicAreaHandle.ne,
          const Offset(0.1, -0.1),
        );
        expect(ne, rectCloseTo(const Rect.fromLTRB(0.4, 0.3, 0.7, 0.6)));
        final sw = ComicImageAreaGeometry.resize(
          rect,
          ComicAreaHandle.sw,
          const Offset(-0.1, 0.1),
        );
        expect(sw, rectCloseTo(const Rect.fromLTRB(0.3, 0.4, 0.6, 0.7)));

        final collapsed = ComicImageAreaGeometry.resize(
          rect,
          ComicAreaHandle.se,
          const Offset(-1, -1),
        );
        expect(collapsed.width, closeTo(ComicImageAreaGeometry.minSize, 1e-9));
        expect(collapsed.height, closeTo(ComicImageAreaGeometry.minSize, 1e-9));
        expect(collapsed.topLeft, rect.topLeft);
        final overflow = ComicImageAreaGeometry.resize(
          rect,
          ComicAreaHandle.se,
          const Offset(5, 5),
        );
        expect(overflow.bottomRight, const Offset(1, 1));
      },
    );

    test('corner zones retain their screen size for small drafts and zoom', () {
      expect(ComicImageAreaGeometry.handleSize(const Size(400, 300), 1), 64);
      expect(ComicImageAreaGeometry.handleSize(const Size(400, 300), 2), 32);
      expect(
        ComicImageAreaGeometry.handleSize(const Size(100, 300), 1),
        64,
        reason: 'targets must not shrink with the selected rectangle',
      );
    });

    test('handleAt finds the corner under a point and nothing elsewhere', () {
      const drawn = Rect.fromLTWH(100, 100, 300, 200);
      expect(
        ComicImageAreaGeometry.handleAt(const Offset(110, 110), drawn, 1),
        ComicAreaHandle.nw,
      );
      expect(
        ComicImageAreaGeometry.handleAt(const Offset(390, 110), drawn, 1),
        ComicAreaHandle.ne,
      );
      expect(
        ComicImageAreaGeometry.handleAt(const Offset(110, 290), drawn, 1),
        ComicAreaHandle.sw,
      );
      expect(
        ComicImageAreaGeometry.handleAt(const Offset(390, 290), drawn, 1),
        ComicAreaHandle.se,
      );
      expect(
        ComicImageAreaGeometry.handleAt(const Offset(250, 200), drawn, 1),
        isNull,
      );
      expect(
        ComicImageAreaGeometry.handleAt(const Offset(50, 50), drawn, 1),
        isNull,
      );
      // Zoomed in, the zones shrink on the page so they stay 64 px on screen.
      expect(
        ComicImageAreaGeometry.handleAt(const Offset(113, 113), drawn, 1),
        ComicAreaHandle.nw,
      );
      expect(
        ComicImageAreaGeometry.handleAt(const Offset(113, 113), drawn, 2),
        isNull,
      );
    });

    test(
      'outside targets choose the nearest corner and preserve centre moves',
      () {
        const drawn = Rect.fromLTWH(100, 100, 6, 9);
        for (final zoom in [1.0, 2.5, 4.0]) {
          expect(
            ComicImageAreaGeometry.handleSize(drawn.size, zoom) * zoom,
            64,
          );
          expect(
            ComicImageAreaGeometry.handleAt(
              drawn.topLeft - Offset(20 / zoom, 20 / zoom),
              drawn,
              zoom,
            ),
            ComicAreaHandle.nw,
          );
          expect(
            ComicImageAreaGeometry.handleAt(drawn.center, drawn, zoom),
            isNull,
            reason: 'even overlapping targets leave the centre movable',
          );
          expect(
            ComicImageAreaGeometry.handleAt(
              Offset(drawn.center.dx, drawn.top - 10 / zoom),
              drawn,
              zoom,
            ),
            ComicAreaHandle.nw,
            reason: 'equal distances use a deterministic corner order',
          );
        }
      },
    );

    test('edge targets shift inside the page frame instead of shrinking', () {
      const bounds = Rect.fromLTWH(0, 0, 390, 844);
      expect(
        ComicImageAreaGeometry.handleAt(
          const Offset(30, 90),
          const Rect.fromLTWH(0, 100, 80, 100),
          1,
          bounds: bounds,
        ),
        ComicAreaHandle.nw,
      );
      expect(
        ComicImageAreaGeometry.handleAt(
          const Offset(360, 90),
          const Rect.fromLTWH(310, 100, 80, 100),
          1,
          bounds: bounds,
        ),
        ComicAreaHandle.ne,
      );
    });

    test('visible triangles stay distinct and accept their whole region', () {
      const bounds = Rect.fromLTWH(0, 0, 390, 844);
      const crops = [
        Rect.fromLTWH(100, 150, 83, 86),
        Rect.fromLTWH(100, 150, 6, 9),
        Rect.fromLTWH(0, 0, 6, 9),
        Rect.fromLTWH(384, 835, 6, 9),
        Rect.fromLTWH(0, 0, 390, 844),
      ];
      for (final zoom in [1.0, 2.5, 4.0]) {
        for (final drawn in crops) {
          final leg = ComicImageAreaGeometry.gripLegLength(drawn.size, zoom);
          expect(leg * zoom, lessThanOrEqualTo(48));
          expect(leg, lessThanOrEqualTo(drawn.shortestSide * .45));
          final positions = ComicImageAreaGeometry.gripCenters(
            drawn,
            zoom,
            bounds: bounds,
          );
          final centers = [
            positions.topLeft,
            positions.topRight,
            positions.bottomLeft,
            positions.bottomRight,
          ];
          expect(centers.toSet(), hasLength(4));
          for (final handle in ComicAreaHandle.values) {
            final center = centers[handle.index];
            expect(drawn.contains(center), isTrue);
            expect(bounds.contains(center), isTrue);
            final west =
                handle == ComicAreaHandle.nw || handle == ComicAreaHandle.sw;
            final north =
                handle == ComicAreaHandle.nw || handle == ComicAreaHandle.ne;
            final corner = Offset(
              west ? drawn.left : drawn.right,
              north ? drawn.top : drawn.bottom,
            );
            final diagonalMidpoint =
                corner +
                Offset((west ? 1 : -1) * leg / 2, (north ? 1 : -1) * leg / 2);
            expect(
              (center - corner).distance,
              closeTo((diagonalMidpoint - center).distance, 1e-9),
              reason: 'the long arrow has equal clearance along the bisector',
            );
            expect(
              (center.dx - corner.dx).abs(),
              closeTo((center.dy - corner.dy).abs(), 1e-9),
            );
            expect(
              ComicImageAreaGeometry.handleAt(
                center,
                drawn,
                zoom,
                bounds: bounds,
              ),
              handle,
            );
            for (final local in const [
              Offset.zero,
              Offset(1, 0),
              Offset(0, 1),
              Offset(0.49, 0.49),
              Offset(1 / 3, 1 / 3),
            ]) {
              expect(
                ComicImageAreaGeometry.handleAt(
                  corner +
                      Offset(
                        (west ? 1 : -1) * local.dx * leg,
                        (north ? 1 : -1) * local.dy * leg,
                      ),
                  drawn,
                  zoom,
                  bounds: bounds,
                ),
                handle,
                reason: '$handle on $drawn at $zoom must match its triangle',
              );
            }
            final padding = (1.5 / zoom).clamp(0.0, drawn.shortestSide / 10);
            expect(
              ComicImageAreaGeometry.handleAt(
                corner +
                    Offset(
                      (west ? 1 : -1) * (leg / 2 + padding / 2),
                      (north ? 1 : -1) * (leg / 2 + padding / 2),
                    ),
                drawn,
                zoom,
                bounds: bounds,
              ),
              handle,
              reason: 'hit padding also accepts the edge of the corner grip',
            );
          }
          for (final local in const [
            Offset(.5, .5),
            Offset(.26, .26),
            Offset(.74, .26),
            Offset(.26, .74),
            Offset(.74, .74),
          ]) {
            expect(
              ComicImageAreaGeometry.handleAt(
                drawn.topLeft +
                    Offset(local.dx * drawn.width, local.dy * drawn.height),
                drawn,
                zoom,
                bounds: bounds,
              ),
              isNull,
              reason: 'crop $drawn at $zoom retains its central move region',
            );
          }
          if (drawn.width == 6 && drawn.height == 9) {
            expect(
              ComicImageAreaGeometry.handleAt(
                Offset(drawn.center.dx, drawn.top),
                drawn,
                zoom,
                bounds: bounds,
              ),
              ComicAreaHandle.nw,
              reason: 'overlapping padding uses stable nearest-corner ties',
            );
            expect(
              ComicImageAreaGeometry.handleAt(
                Offset(drawn.center.dx + .01, drawn.top),
                drawn,
                zoom,
                bounds: bounds,
              ),
              ComicAreaHandle.ne,
              reason: 'padding must not steal the nearer opposite corner',
            );
          }
        }
      }
    });

    test('areaAt returns the topmost saved area', () {
      const under = ComicImageArea(
        id: 'a',
        page: 0,
        rect: Rect.fromLTWH(0, 0, 0.5, 0.5),
        color: Color(0xFF00FF00),
      );
      const over = ComicImageArea(
        id: 'b',
        page: 0,
        rect: Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
        color: Color(0xFFFF0000),
      );
      expect(
        ComicImageAreaGeometry.areaAt(const Offset(0.3, 0.3), [under, over]),
        over,
      );
      expect(
        ComicImageAreaGeometry.areaAt(const Offset(0.1, 0.1), [under, over]),
        under,
      );
      expect(
        ComicImageAreaGeometry.areaAt(const Offset(0.9, 0.9), [under, over]),
        isNull,
      );
      expect(under, isNot(over));
      expect(
        under.hashCode,
        const ComicImageArea(
          id: 'a',
          page: 0,
          rect: Rect.fromLTWH(0, 0, 0.5, 0.5),
          color: Color(0xFF00FF00),
        ).hashCode,
      );
    });
  });

  group('ComicImageAreaDraft', () {
    test('starts, updates, retains and clears with notifications', () {
      final draft = ComicImageAreaDraft();
      addTearDown(draft.dispose);
      var notified = 0;
      draft.addListener(() => notified++);
      expect(draft.isActive, isFalse);
      draft.update(const Rect.fromLTWH(0, 0, 0.1, 0.1));
      expect(notified, 0, reason: 'nothing to update');

      draft.start(2, const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2));
      expect(draft.isActive, isTrue);
      expect(draft.page, 2);
      expect(notified, 1);
      draft.update(const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2));
      expect(notified, 1, reason: 'same rect');
      draft.update(const Rect.fromLTWH(0.2, 0.1, 0.2, 0.2));
      expect(notified, 2);
      draft.retain(true);
      draft.retain(true);
      expect(draft.retained, isTrue);
      expect(notified, 3);
      draft.clear();
      expect(draft.isActive, isFalse);
      expect(draft.page, isNull);
      expect(draft.retained, isFalse, reason: 'clearing forgets retention');
      expect(notified, 4);
      draft.clear();
      expect(notified, 4);
    });

    test('style changes notify only when something changes', () {
      final draft = ComicImageAreaDraft();
      addTearDown(draft.dispose);
      var notified = 0;
      draft.addListener(() => notified++);
      expect(draft.color, const Color(0xFFFFE600));
      expect(draft.opacity, 0.45);
      draft.setStyle(color: const Color(0xFFFFE600), opacity: 0.45);
      expect(notified, 0);
      draft.setStyle(color: const Color(0xFF00AAFF));
      expect(draft.color, const Color(0xFF00AAFF));
      expect(draft.opacity, 0.45);
      expect(notified, 1);
      draft.setStyle(opacity: 0.5);
      expect(notified, 2);
    });
  });
}
