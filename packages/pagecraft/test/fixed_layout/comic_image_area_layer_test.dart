import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

Future<_AreaPixels> _paintLayer(
  WidgetTester tester, {
  Color background = const Color(0xFF204080),
  bool artworkStripe = true,
  bool savedTextSample = false,
}) async {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(ComicImageAreaLayer),
      matching: find.byType(CustomPaint),
    ),
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(background, BlendMode.src);
  if (artworkStripe) {
    canvas.drawRect(
      const Rect.fromLTWH(200, 75, 10, 450),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }
  if (savedTextSample) {
    canvas
      ..drawRect(
        const Rect.fromLTWH(80, 120, 45, 67.5),
        Paint()..color = const Color(0xFFFFFFFF),
      )
      ..drawRect(
        const Rect.fromLTWH(90, 130, 10, 30),
        Paint()..color = const Color(0xFF000000),
      )
      ..drawRect(
        const Rect.fromLTWH(105, 130, 4, 30),
        Paint()..color = const Color(0xFF202020),
      );
  }
  paint.painter!.paint(canvas, const Size(400, 600));
  final picture = recorder.endRecording();
  try {
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(400, 600);
      try {
        return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      } finally {
        image.dispose();
      }
    });
    return _AreaPixels(bytes!, paint.painter!);
  } finally {
    picture.dispose();
  }
}

class _AreaPixels {
  _AreaPixels(this.bytes, this.painter);

  final ByteData bytes;
  final CustomPainter painter;

  Color at(int x, int y) {
    final offset = (y * 400 + x) * 4;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }
}

void main() {
  // The layer fills a 400×600 box; the image sits in the middle 300×450.
  const layerSize = Size(400, 600);
  const imageRect = Rect.fromLTWH(50, 75, 300, 450);
  const press = Duration(milliseconds: 300);

  late FixedPagesController controller;
  late ComicImageAreaDraft draft;
  late List<Rect> committed;
  late List<ComicImageArea> pressedAreas;
  var cancelled = 0;

  setUp(() {
    controller = FixedPagesController(pageCount: 3, rtl: false);
    draft = ComicImageAreaDraft();
    committed = [];
    pressedAreas = [];
    cancelled = 0;
  });

  tearDown(() {
    controller.dispose();
    draft.dispose();
  });

  Future<void> pumpLayer(
    WidgetTester tester, {
    List<ComicImageArea> areas = const [],
    bool enabled = true,
    int page = 0,
    Widget? after,
    ValueChanged<bool>? onAdjustmentChanged,
    double zoom = 1,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.fromSize(
              size: layerSize,
              child: Transform.scale(
                scale: zoom,
                child: ComicImageAreaLayer(
                  page: page,
                  imageRect: imageRect,
                  controller: controller,
                  draft: draft,
                  areas: areas,
                  enabled: enabled,
                  onDraftCommitted: (rect, _) => committed.add(rect),
                  onDraftCancelled: () => cancelled++,
                  onDraftAdjustmentChanged: onAdjustmentChanged,
                  onAreaPressed: (area, _) => pressedAreas.add(area),
                ),
              ),
            ),
            ?after,
          ],
        ),
      ),
    );
  }

  Color draftColorOnScreen(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byType(ComicImageAreaLayer),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    return (paint.painter as dynamic).draftColor as Color;
  }

  Offset layerPoint(WidgetTester tester, Offset local) => tester
      .renderObject<RenderBox>(find.byType(ComicImageAreaLayer))
      .localToGlobal(local);

  /// Fractions of the image for a layer-local point.
  Offset imagePoint(Offset local) => Offset(
    (local.dx - imageRect.left) / imageRect.width,
    (local.dy - imageRect.top) / imageRect.height,
  );

  testWidgets('a long press creates a draft at the finger and locks input', (
    tester,
  ) async {
    await pumpLayer(tester);
    const local = Offset(200, 300);
    final gesture = await tester.startGesture(layerPoint(tester, local));
    await tester.pump(const Duration(milliseconds: 200));
    expect(draft.isActive, isFalse, reason: 'shorter than the long press');
    await tester.pump(const Duration(milliseconds: 100));
    expect(draft.isActive, isTrue);
    expect(draft.page, 0);
    expect(draft.rect!.center.dx, closeTo(imagePoint(local).dx, 1e-6));
    expect(draft.rect!.center.dy, closeTo(imagePoint(local).dy, 1e-6));
    expect(controller.inputLocked, isTrue);
    expect(committed, hasLength(1));

    // Still holding: the draft follows the finger, then commits on release.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(
      draft.rect!.center.dx,
      closeTo(imagePoint(const Offset(230, 300)).dx, 1e-6),
    );
    await gesture.up();
    await tester.pump();
    expect(committed, hasLength(2));
    expect(committed.last, draft.rect);
  });

  testWidgets('outside a pages view the commit carries no viewport rect', (
    tester,
  ) async {
    Rect? viewport = const Rect.fromLTWH(1, 1, 1, 1);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: layerSize,
            child: ComicImageAreaLayer(
              page: 0,
              imageRect: imageRect,
              controller: controller,
              draft: draft,
              onDraftCommitted: (_, rect) => viewport = rect,
            ),
          ),
        ),
      ),
    );
    await tester.longPressAt(layerPoint(tester, const Offset(200, 300)));
    await tester.pump(press);
    expect(draft.isActive, isTrue);
    expect(viewport, isNull);
  });

  testWidgets('a long press outside the image does nothing', (tester) async {
    await pumpLayer(tester);
    await tester.longPressAt(layerPoint(tester, const Offset(10, 10)));
    await tester.pump(press);
    expect(draft.isActive, isFalse);
    expect(controller.inputLocked, isFalse);
  });

  testWidgets('after release a drag inside moves and a corner drag resizes', (
    tester,
  ) async {
    await pumpLayer(tester);
    await tester.longPressAt(layerPoint(tester, const Offset(200, 300)));
    await tester.pump(press);
    final created = draft.rect!;

    // Move from the middle.
    final centre = layerPoint(
      tester,
      imageRect.topLeft +
          Offset(
            created.center.dx * imageRect.width,
            created.center.dy * imageRect.height,
          ),
    );
    await tester.dragFrom(centre, const Offset(-30, 15));
    await tester.pump();
    expect(draft.rect!.size, created.size);
    expect(
      draft.rect!.left,
      closeTo(created.left - 30 / imageRect.width, 1e-6),
    );
    expect(draft.rect!.top, closeTo(created.top + 15 / imageRect.height, 1e-6));
    expect(committed, hasLength(3));

    // Resize from the bottom-right corner zone.
    final moved = draft.rect!;
    final corner = layerPoint(
      tester,
      imageRect.topLeft +
          Offset(
            moved.right * imageRect.width - 4,
            moved.bottom * imageRect.height - 4,
          ),
    );
    await tester.dragFrom(corner, const Offset(30, 30));
    await tester.pump();
    expect(draft.rect!.topLeft, moved.topLeft);
    expect(
      draft.rect!.width,
      closeTo(moved.width + 30 / imageRect.width, 1e-6),
    );
    expect(
      draft.rect!.height,
      closeTo(moved.height + 30 / imageRect.height, 1e-6),
    );
    expect(committed, hasLength(4));
  });

  for (final corner in [false, true]) {
    testWidgets(
      'a slow hold still ${corner ? 'resizes' : 'moves'} an existing draft',
      (tester) async {
        final phases = <bool>[];
        await pumpLayer(tester, onAdjustmentChanged: phases.add);
        draft.start(0, const Rect.fromLTWH(0.3, 0.3, 0.4, 0.3));
        await tester.pump();
        final before = draft.rect!;
        final point = corner
            ? imageRect.topLeft +
                  Offset(
                    before.right * imageRect.width - 2,
                    before.bottom * imageRect.height - 2,
                  )
            : imageRect.topLeft +
                  Offset(
                    before.center.dx * imageRect.width,
                    before.center.dy * imageRect.height,
                  );
        final gesture = await tester.startGesture(layerPoint(tester, point));
        await tester.pump(press);
        expect(phases, [true]);
        await gesture.moveBy(const Offset(30, 20));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(phases, [true, false]);
        expect(committed.last, draft.rect);
        if (corner) {
          expect(draft.rect!.topLeft, before.topLeft);
          expect(draft.rect!.width, greaterThan(before.width));
        } else {
          expect(draft.rect!.width, closeTo(before.width, 1e-9));
          expect(draft.rect!.height, closeTo(before.height, 1e-9));
          expect(
            draft.rect!.left,
            closeTo(before.left + 30 / imageRect.width, 1e-6),
          );
        }
      },
    );
  }

  testWidgets('one accepted move commits before adjustment ends', (
    tester,
  ) async {
    final events = <String>[];
    await pumpLayer(
      tester,
      onAdjustmentChanged: (value) => events.add('$value:${committed.length}'),
    );
    draft.start(0, const Rect.fromLTWH(0.3, 0.3, 0.4, 0.3));
    await tester.pump();
    final before = draft.rect!;
    final centre =
        imageRect.topLeft +
        Offset(
          before.center.dx * imageRect.width,
          before.center.dy * imageRect.height,
        );
    final gesture = await tester.startGesture(layerPoint(tester, centre));
    await gesture.moveBy(const Offset(30, 40));
    await tester.pump();
    expect(events, ['true:0']);
    expect(draft.rect!.left, closeTo(before.left + 30 / imageRect.width, 1e-6));
    await gesture.up();
    await tester.pump();
    expect(events, ['true:0', 'false:1']);
    expect(committed.single, draft.rect);
  });

  testWidgets('a second pointer cannot jump or finish the primary edit', (
    tester,
  ) async {
    final phases = <bool>[];
    await pumpLayer(tester, onAdjustmentChanged: phases.add);
    draft.start(0, const Rect.fromLTWH(0.3, 0.3, 0.4, 0.3));
    await tester.pump();
    final centre = layerPoint(tester, const Offset(200, 278));
    final first = await tester.startGesture(centre, pointer: 1);
    await first.moveBy(const Offset(20, 0));
    await tester.pump();
    final beforeSecond = draft.rect!;
    final second = await tester.startGesture(
      centre + const Offset(80, 0),
      pointer: 2,
    );
    await second.moveBy(const Offset(10, 0));
    await tester.pump(press);
    expect(draft.rect, beforeSecond);
    await second.up();
    await tester.pump();
    expect(phases, [true]);
    await first.moveBy(const Offset(10, 0));
    await tester.pump();
    expect(draft.rect!.left, greaterThan(beforeSecond.left));
    await first.up();
    await tester.pump();
    expect(phases, [true, false]);
    expect(committed.single, draft.rect);
  });

  testWidgets('outside corner taps keep the draft and drags resize at zoom', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.reportZoomScale(2);
    await pumpLayer(tester, zoom: 2);
    draft.start(0, const Rect.fromLTWH(0.3, 0.3, 0.4, 0.3));
    await tester.pump();
    final before = draft.rect!;
    final corner =
        imageRect.topLeft +
        Offset(
          before.right * imageRect.width + 8,
          before.bottom * imageRect.height + 8,
        );
    await tester.tapAt(layerPoint(tester, corner));
    await tester.pump();
    expect(draft.rect, before);
    expect(cancelled, 0);
    final gesture = await tester.startGesture(layerPoint(tester, corner));
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(draft.rect!.topLeft, before.topLeft);
    expect(
      draft.rect!.width,
      closeTo(before.width + 20 / imageRect.width, 1e-6),
    );
    expect(
      draft.rect!.height,
      closeTo(before.height + 20 / imageRect.height, 1e-6),
    );
  });

  testWidgets(
    'pointer cancellation commits current geometry and balances phase',
    (tester) async {
      final phases = <bool>[];
      await pumpLayer(tester, onAdjustmentChanged: phases.add);
      final gesture = await tester.startGesture(
        layerPoint(tester, const Offset(200, 300)),
      );
      await tester.pump(press);
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();
      expect(phases, [true, false]);
      expect(committed, hasLength(2));
      expect(committed.last, draft.rect);
    },
  );

  testWidgets(
    'minimum draft keeps centre movement and outside resize targets',
    (tester) async {
      await pumpLayer(tester);
      draft.start(0, const Rect.fromLTWH(0.4, 0.4, 0.015, 0.015));
      await tester.pump();
      final before = draft.rect!;
      final centre =
          imageRect.topLeft +
          Offset(
            before.center.dx * imageRect.width,
            before.center.dy * imageRect.height,
          );
      await tester.dragFrom(layerPoint(tester, centre), const Offset(30, 20));
      await tester.pump();
      expect(draft.rect!.width, closeTo(before.width, 1e-9));
      expect(draft.rect!.height, closeTo(before.height, 1e-9));
      final moved = draft.rect!;
      final corner =
          imageRect.topLeft +
          Offset(
            moved.right * imageRect.width + 10,
            moved.bottom * imageRect.height + 10,
          );
      await tester.dragFrom(layerPoint(tester, corner), const Offset(30, 30));
      await tester.pump();
      expect(draft.rect!.topLeft, moved.topLeft);
      expect(draft.rect!.width, greaterThan(moved.width));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('incremental resize uses native slop before the zoom ancestor', (
    tester,
  ) async {
    final phases = <bool>[];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          gestureSettings: DeviceGestureSettings(touchSlop: 8),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.fromSize(
              size: layerSize,
              child: InteractiveViewer(
                panEnabled: false,
                scaleEnabled: false,
                child: ComicImageAreaLayer(
                  page: 0,
                  imageRect: imageRect,
                  controller: controller,
                  draft: draft,
                  onDraftCommitted: (rect, _) => committed.add(rect),
                  onDraftAdjustmentChanged: phases.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    const initial = Rect.fromLTWH(0.3, 0.3, 0.4, 0.3);
    draft.start(0, initial);
    controller.lockInput(true);
    await tester.pump();
    final drawn = Rect.fromLTWH(
      imageRect.left + initial.left * imageRect.width,
      imageRect.top + initial.top * imageRect.height,
      initial.width * imageRect.width,
      initial.height * imageRect.height,
    );
    final grips = ComicImageAreaGeometry.gripCenters(
      drawn,
      1,
      bounds: Offset.zero & layerSize,
    );
    final gesture = await tester.startGesture(
      layerPoint(tester, grips.bottomRight),
    );
    await gesture.moveBy(const Offset(12, 16));
    await tester.pump();
    expect(phases, [true]);
    expect(draft.rect!.width, greaterThan(initial.width));
    expect(draft.rect!.height, greaterThan(initial.height));
    await gesture.moveBy(const Offset(20, 30));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(phases, [true, false]);
    expect(committed.last, draft.rect);
    expect(controller.zoomScale, 1);
  });

  testWidgets('all visible grips resize a minimum crop at the image edge', (
    tester,
  ) async {
    final phases = <bool>[];
    await pumpLayer(tester, onAdjustmentChanged: phases.add);
    const initial = Rect.fromLTWH(0, 0, 0.015, 0.015);
    for (final handle in ComicAreaHandle.values) {
      draft.start(0, initial);
      await tester.pump();
      final drawn = Rect.fromLTWH(
        imageRect.left,
        imageRect.top,
        initial.width * imageRect.width,
        initial.height * imageRect.height,
      );
      final centers = ComicImageAreaGeometry.gripCenters(
        drawn,
        1,
        bounds: Offset.zero & layerSize,
      );
      final center = switch (handle) {
        ComicAreaHandle.nw => centers.topLeft,
        ComicAreaHandle.ne => centers.topRight,
        ComicAreaHandle.sw => centers.bottomLeft,
        ComicAreaHandle.se => centers.bottomRight,
      };
      final west = handle == ComicAreaHandle.nw || handle == ComicAreaHandle.sw;
      final north =
          handle == ComicAreaHandle.nw || handle == ComicAreaHandle.ne;
      final gesture = await tester.startGesture(layerPoint(tester, center));
      await gesture.moveBy(Offset(west ? -25 : 25, north ? -25 : 25));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(draft.isActive, isTrue);
      expect(cancelled, 0);
      expect(committed.last, draft.rect);
      if (!west) expect(draft.rect!.width, greaterThan(initial.width));
      if (!north) expect(draft.rect!.height, greaterThan(initial.height));
      expect(phases.length, (handle.index + 1) * 2);
      expect(phases.skip(phases.length - 2), [true, false]);
    }
  });

  testWidgets('spread pages share edit ownership and outside cancellation', (
    tester,
  ) async {
    final phases = <bool>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 600,
            height: 450,
            child: Row(
              children: [
                for (final page in [0, 1])
                  Expanded(
                    child: ComicImageAreaLayer(
                      key: ValueKey('spread-$page'),
                      page: page,
                      imageRect: const Rect.fromLTWH(0, 0, 300, 450),
                      controller: controller,
                      draft: draft,
                      onDraftAdjustmentChanged: phases.add,
                      onDraftCommitted: (rect, _) => committed.add(rect),
                      onDraftCancelled: () => cancelled++,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    draft.start(0, const Rect.fromLTWH(0.3, 0.3, 0.4, 0.3));
    controller.lockInput(true);
    await tester.pump();
    final left = tester
        .renderObject<RenderBox>(find.byKey(const ValueKey('spread-0')))
        .localToGlobal(const Offset(150, 202));
    final right = tester
        .renderObject<RenderBox>(find.byKey(const ValueKey('spread-1')))
        .localToGlobal(const Offset(150, 202));
    final first = await tester.startGesture(left, pointer: 1);
    await first.moveBy(const Offset(20, 0));
    await tester.pump();
    final beforeSecond = draft.rect;
    final second = await tester.startGesture(right, pointer: 2);
    await tester.pump(press);
    await second.moveBy(const Offset(25, 0));
    await tester.pump();
    await second.up();
    await tester.pump();
    expect(draft.page, 0);
    expect(draft.rect, beforeSecond);
    expect(phases, [true]);
    await first.up();
    await tester.pump();
    expect(phases, [true, false]);
    await tester.tapAt(right);
    await tester.pump();
    expect(draft.isActive, isFalse);
    expect(controller.inputLocked, isFalse);
    expect(cancelled, 1);
    await tester.longPressAt(right);
    await tester.pump();
    expect(draft.page, 1);
    expect(controller.inputLocked, isTrue);
    expect(phases, [true, false, true, false]);
  });

  testWidgets('a colour change during build repaints after the frame', (
    tester,
  ) async {
    await pumpLayer(tester);
    await tester.longPressAt(layerPoint(tester, const Offset(200, 300)));
    await tester.pump(press);
    final before = draftColorOnScreen(tester);
    const red = Color(0xFFFF0000);
    expect(before, isNot(red));
    // The app previews a colour from a popup's initState: a sibling built
    // after the layer in the same frame.
    await pumpLayer(
      tester,
      after: Builder(
        builder: (_) {
          draft.setStyle(color: red);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(draftColorOnScreen(tester), red);
    expect(draft.isActive, isTrue);
  });

  testWidgets('a tap outside cancels the draft unless it is retained', (
    tester,
  ) async {
    await pumpLayer(tester);
    await tester.longPressAt(layerPoint(tester, const Offset(200, 300)));
    await tester.pump(press);
    expect(draft.isActive, isTrue);

    draft.retain(true);
    await tester.pump();
    await tester.tapAt(layerPoint(tester, const Offset(60, 85)));
    await tester.pump();
    expect(draft.isActive, isTrue);
    expect(cancelled, 0);

    draft.retain(false);
    await tester.pump();
    await tester.tapAt(layerPoint(tester, const Offset(200, 300)));
    await tester.pump();
    expect(draft.isActive, isTrue, reason: 'a tap inside keeps it');

    await tester.tapAt(layerPoint(tester, const Offset(60, 85)));
    await tester.pump();
    expect(draft.isActive, isFalse);
    expect(cancelled, 1);
    expect(controller.inputLocked, isFalse);
  });

  testWidgets('a long press on a saved area reports the area, topmost first', (
    tester,
  ) async {
    const under = ComicImageArea(
      id: 'a',
      page: 0,
      rect: Rect.fromLTWH(0.1, 0.1, 0.5, 0.5),
      color: Color(0xFF00FF00),
    );
    const over = ComicImageArea(
      id: 'b',
      page: 0,
      rect: Rect.fromLTWH(0.3, 0.3, 0.5, 0.5),
      color: Color(0xFFFF0000),
    );
    const elsewhere = ComicImageArea(
      id: 'c',
      page: 1,
      rect: Rect.fromLTWH(0, 0, 1, 1),
      color: Color(0xFF0000FF),
    );
    await pumpLayer(tester, areas: const [under, over, elsewhere]);

    final inBoth = layerPoint(
      tester,
      imageRect.topLeft + Offset(0.4 * imageRect.width, 0.4 * imageRect.height),
    );
    await tester.longPressAt(inBoth);
    await tester.pump(press);
    expect(pressedAreas, [over]);
    expect(draft.isActive, isFalse);

    final onlyUnder = layerPoint(
      tester,
      imageRect.topLeft +
          Offset(0.15 * imageRect.width, 0.15 * imageRect.height),
    );
    await tester.longPressAt(onlyUnder);
    await tester.pump(press);
    expect(pressedAreas, [over, under]);

    final free = layerPoint(
      tester,
      imageRect.topLeft + Offset(0.9 * imageRect.width, 0.1 * imageRect.height),
    );
    await tester.longPressAt(free);
    await tester.pump(press);
    expect(
      draft.isActive,
      isTrue,
      reason: 'the other page\'s area does not cover this page',
    );
  });

  testWidgets('a disabled layer draws areas but takes no input', (
    tester,
  ) async {
    const area = ComicImageArea(
      id: 'a',
      page: 0,
      rect: Rect.fromLTWH(0.1, 0.1, 0.5, 0.5),
      color: Color(0xFF00FF00),
    );
    await pumpLayer(tester, areas: const [area], enabled: false);
    await tester.longPressAt(layerPoint(tester, const Offset(200, 300)));
    await tester.pump(press);
    expect(draft.isActive, isFalse);
    expect(pressedAreas, isEmpty);
    expect(find.byType(CustomPaint), findsOneWidget);
  });

  testWidgets('a draft on another page dims this page until cancelled', (
    tester,
  ) async {
    await pumpLayer(tester, page: 2);
    final before = await _paintLayer(tester);
    draft.start(0, const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2));
    await tester.pump();
    final dimmed = await _paintLayer(tester);
    expect(dimmed.at(195, 277).b, closeTo(45 / 255, .01));
    expect(dimmed.at(151, 221).b, closeTo(45 / 255, .01));
    expect(dimmed.painter.shouldRepaint(before.painter), isTrue);
    await tester.tapAt(layerPoint(tester, const Offset(60, 85)));
    await tester.pump();
    expect(
      draft.isActive,
      isFalse,
      reason: 'the other page is outside the active draft',
    );
    expect(cancelled, 1);
    final restored = await _paintLayer(tester);
    expect(restored.at(195, 277), const Color(0xFF204080));
    expect(restored.at(151, 221), const Color(0xFF204080));
    expect(restored.painter.shouldRepaint(dimmed.painter), isTrue);
  });

  testWidgets('clearing the draft from the app ends an edit', (tester) async {
    final phases = <bool>[];
    await pumpLayer(tester, onAdjustmentChanged: phases.add);
    final gesture = await tester.startGesture(
      layerPoint(tester, const Offset(200, 300)),
    );
    await tester.pump(press);
    expect(draft.isActive, isTrue);
    draft.clear();
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(draft.isActive, isFalse);
    expect(committed, hasLength(1));
    expect(phases, [true, false]);
  });

  testWidgets(
    'draft keeps artwork visible and distinguishes corner grab areas',
    (
      tester,
    ) async {
      await pumpLayer(
        tester,
        areas: const [
          ComicImageArea(
            id: 'saved',
            page: 0,
            rect: Rect.fromLTWH(.1, .1, .15, .15),
            color: Color(0xFFFFE600),
          ),
        ],
      );
      final before = await _paintLayer(tester, savedTextSample: true);
      final saved = before.at(115, 145);
      expect(
        saved.b,
        closeTo(26 / 255, .01),
        reason: 'saved paper takes a 90% tint',
      );
      expect(before.at(95, 145), const Color(0xFF000000));
      expect(before.at(80, 350), const Color(0xFF204080));
      draft.start(0, const Rect.fromLTWH(.3, .3, .4, .3));
      await tester.pump();
      final pixels = await _paintLayer(tester, savedTextSample: true);
      final center = pixels.at(195, 277);
      final artworkDetail = pixels.at(205, 277);
      final corner = pixels.at(145, 235);
      expect(
        center.b,
        greaterThan(.25),
        reason: 'the center tint stays readable',
      );
      expect(
        center.b,
        lessThan(.30),
        reason: 'the active tint stays visible against unselected artwork',
      );
      expect(
        artworkDetail.b - center.b,
        greaterThan(.25),
        reason: 'fine light/dark artwork contrast survives the selection tint',
      );
      expect(
        center.r - corner.r,
        greaterThan(.15),
        reason: 'the corner region is visibly distinct from the moving center',
      );
      expect(
        pixels.at(140, 277),
        center,
        reason: 'the edge has no extra border',
      );
      expect(pixels.at(80, 350).b, closeTo(45 / 255, .01));
      final dimmedSaved = Color.alphaBlend(
        const Color(0xFF000000).withValues(alpha: .65),
        saved,
      );
      final actualSaved = pixels.at(115, 145);
      expect(actualSaved.r, closeTo(dimmedSaved.r, .01));
      expect(actualSaved.g, closeTo(dimmedSaved.g, .01));
      expect(actualSaved.b, closeTo(dimmedSaved.b, .01));
      draft.clear();
      await tester.pump();
      final restored = await _paintLayer(tester, savedTextSample: true);
      expect(restored.at(80, 350), const Color(0xFF204080));
      expect(restored.at(115, 145), saved);
      expect(restored.at(95, 145), const Color(0xFF000000));
      expect(restored.at(106, 145), before.at(106, 145));
    },
  );

  testWidgets(
    'zero draft opacity leaves interiors and edges unchanged',
    (
      tester,
    ) async {
      await pumpLayer(tester);
      draft.setStyle(opacity: 0);
      draft.start(0, const Rect.fromLTWH(.3, .3, .4, .3));
      await tester.pump();
      final pixels = await _paintLayer(tester);
      expect(pixels.at(195, 277), const Color(0xFF204080));
      expect(pixels.at(151, 221), const Color(0xFF204080));
      expect(pixels.at(140, 277), const Color(0xFF204080));
      expect(pixels.at(156, 227), const Color(0xFF204080));
      expect(pixels.at(80, 350), const Color(0xFF204080));
    },
  );

  testWidgets(
    'saved ink and selected resize controls stay clear across artwork and colors',
    (
      tester,
    ) async {
      for (final selected in const [
        Color(0xFFEED05E),
        Color(0xFF70A6DC),
        Color(0xFF7DCEA6),
        Color(0xFFD67596),
        Color(0xFFA679D2),
      ]) {
        draft.clear();
        await pumpLayer(
          tester,
          areas: [
            ComicImageArea(
              id: 'saved',
              page: 0,
              rect: const Rect.fromLTWH(.1, .1, .15, .15),
              color: selected,
            ),
          ],
        );
        final saved = await _paintLayer(tester, savedTextSample: true);
        final paper = saved.at(115, 145);
        final expectedPaper = Color.alphaBlend(
          selected.withValues(alpha: .90),
          const Color(0xFFFFFFFF),
        );
        expect(paper.r, closeTo(expectedPaper.r, .01));
        expect(paper.g, closeTo(expectedPaper.g, .01));
        expect(paper.b, closeTo(expectedPaper.b, .01));
        expect(
          saved.at(95, 145),
          const Color(0xFF000000),
          reason: 'tint must not wash out black ink',
        );
        final darkInk = saved.at(106, 145);
        expect(darkInk.r, lessThanOrEqualTo(33 / 255));
        expect(darkInk.g, lessThanOrEqualTo(33 / 255));
        expect(darkInk.b, lessThanOrEqualTo(33 / 255));
        expect(
          (paper.computeLuminance() + .05) / .05,
          greaterThan(7),
          reason: 'saved text keeps strong paper/ink contrast in every hue',
        );
        draft.start(0, const Rect.fromLTWH(.3, .3, .4, .3));
        draft.setStyle(color: selected);
        await tester.pump();
        for (final background in const [Color(0xFFF7F7F7), Color(0xFF080808)]) {
          final pixels = await _paintLayer(
            tester,
            background: background,
            artworkStripe: false,
          );
          final center = Color.alphaBlend(
            selected.withValues(alpha: .45),
            background,
          );
          final corner = Color.alphaBlend(
            const Color(0xFF2563EB).withValues(alpha: .85),
            background,
          );
          for (final point in const [
            Offset(195, 277),
            Offset(140, 277),
            Offset(165, 238),
          ]) {
            final actual = pixels.at(point.dx.toInt(), point.dy.toInt());
            expect(
              actual.r,
              closeTo(center.r, .01),
              reason: 'the center keeps the selected color at 45% opacity',
            );
            expect(actual.g, closeTo(center.g, .01));
            expect(actual.b, closeTo(center.b, .01));
          }
          for (final point in const [
            Offset(152, 222),
            Offset(247, 222),
            Offset(152, 332),
            Offset(247, 332),
          ]) {
            final actual = pixels.at(point.dx.toInt(), point.dy.toInt());
            expect(
              actual.r,
              closeTo(1, .01),
              reason: 'white resize arrows stay visible over the blue grips',
            );
            expect(actual.g, closeTo(1, .01));
            expect(actual.b, closeTo(1, .01));
          }
          for (final point in const [
            Offset(145, 235),
            Offset(255, 235),
            Offset(145, 320),
            Offset(255, 320),
          ]) {
            final actual = pixels.at(point.dx.toInt(), point.dy.toInt());
            expect(
              actual.r,
              closeTo(corner.r, .01),
              reason:
                  'blue grips retain 85% opacity regardless of the selected color',
            );
            expect(actual.g, closeTo(corner.g, .01));
            expect(actual.b, closeTo(corner.b, .01));
          }
          final outside = Color.alphaBlend(
            const Color(0xFF000000).withValues(alpha: .65),
            background,
          );
          final actualOutside = pixels.at(139, 277);
          expect(actualOutside.r, closeTo(outside.r, .01));
          expect(actualOutside.g, closeTo(outside.g, .01));
          expect(actualOutside.b, closeTo(outside.b, .01));
        }
        draft.clear();
        await tester.pump();
        final restored = await _paintLayer(tester, savedTextSample: true);
        expect(restored.at(115, 145), paper);
        expect(restored.at(95, 145), const Color(0xFF000000));
        expect(restored.at(106, 145), darkInk);
      }
    },
  );

  group('goldens', () {
    testWidgets('saved areas and a draft with corner grips', (tester) async {
      const area = ComicImageArea(
        id: 'a',
        page: 0,
        rect: Rect.fromLTWH(0.1, 0.1, 0.4, 0.2),
        color: Color(0xFF2ECC71),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.fromSize(
              size: layerSize,
              child: ColoredBox(
                color: const Color(0xFF505050),
                child: ComicImageAreaLayer(
                  page: 0,
                  imageRect: imageRect,
                  controller: controller,
                  draft: draft,
                  areas: const [area],
                ),
              ),
            ),
          ),
        ),
      );
      draft.start(0, const Rect.fromLTWH(0.3, 0.5, 0.4, 0.3));
      await tester.pump();
      await expectLater(
        find.byType(ComicImageAreaLayer),
        matchesGoldenFile('goldens/comic_image_area_layer.png'),
      );
    });
  });
}
