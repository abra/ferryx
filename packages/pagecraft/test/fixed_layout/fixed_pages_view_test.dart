import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pagecraft/all_formats.dart';

import 'package:pagecraft/testing.dart';

void main() {
  const portrait = Size(390, 844);
  const landscape = Size(844, 390);

  late FakeComicSource source;
  late FixedPagesController controller;
  late List<Offset> taps;

  setUp(() {
    source = FakeComicSource([
      for (var i = 0; i < 5; i++)
        encodeSolidPng(
          600,
          900,
          rgba: [0xC0392BFF, 0x27AE60FF, 0x2980B9FF, 0xF1C40FFF, 0x8E44ADFF][i],
        ),
    ]);
    taps = [];
  });

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  Future<void> pumpView(
    WidgetTester tester, {
    Size size = portrait,
    bool rtl = false,
    int initialPage = 0,
    bool reduceMotion = false,
    Axis axis = Axis.horizontal,
    PageTurnAnimation pageTurnAnimation = PageTurnAnimation.cover,
    ValueNotifier<PageTurnAnimation>? animation,
    bool keepController = false,
    bool capture = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (!keepController) {
      controller = FixedPagesController(
        pageCount: source.pageCount,
        rtl: rtl,
        initialPage: initialPage,
      );
      addTearDown(controller.dispose);
    }
    final selectedAnimation = animation ?? ValueNotifier(pageTurnAnimation);
    if (animation == null) addTearDown(selectedAnimation.dispose);
    final view = MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<PageTurnAnimation>(
          valueListenable: selectedAnimation,
          builder: (context, value, _) => FixedPagesView(
            pages: ComicPages(source),
            controller: controller,
            onTap: taps.add,
            axis: axis,
            pageTurnAnimation: value,
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      capture
          ? RepaintBoundary(
              key: const ValueKey('fixedPagesTestBoundary'),
              child: view,
            )
          : view,
    );
    await tester.pump();
  }

  /// Decodes the pages on screen so frames have images and sizes.
  Future<void> decodeVisible(
    WidgetTester tester, {
    required double frameWidth,
  }) async {
    final context = tester.element(find.byType(FixedPagesView));
    await tester.runAsync(() async {
      for (final page in controller.visiblePages) {
        await precacheImage(
          ComicPageImage(
            source: source,
            pageIndex: page,
            targetWidth: frameWidth.ceil(),
          ),
          context,
          // A page that cannot be decoded is part of some tests.
          onError: (_, _) {},
        );
      }
    });
    await tester.pump();
    await tester.pump();
  }

  /// Waits for every visible frame to hold its image: frames decode at
  /// their own width, so precaching a guessed width leaves a race.
  Future<void> settleFrames(WidgetTester tester) async {
    final frames = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is FixedPagePainter,
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        await tester.pump();
        if (frames.evaluate().length >= controller.visiblePages.length) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
  }

  Finder pageLabel(int page) => find.bySemanticsLabel('Page $page of 5');

  Finder pageFrame(int page) => find.byWidgetPredicate(
    (widget) =>
        widget is Semantics && widget.properties.label == 'Page $page of 5',
  );

  group('layout', () {
    testWidgets('portrait shows one page, landscape a spread', (tester) async {
      await pumpView(tester);
      expect(pageLabel(1), findsOneWidget);
      expect(pageLabel(2), findsNothing);
      expect(controller.singlePage, isTrue);

      tester.view.physicalSize = landscape;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: landscape),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FixedPagesView(
              pages: ComicPages(source),
              controller: controller,
              onTap: taps.add,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(controller.singlePage, isFalse);
      expect(pageLabel(1), findsOneWidget);
      expect(pageLabel(2), findsOneWidget);
    });

    testWidgets('a rotation keeps the page and resets zoom', (tester) async {
      await pumpView(tester, initialPage: 3);
      controller.reportZoomScale(2);
      tester.view.physicalSize = landscape;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: landscape),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FixedPagesView(
              pages: ComicPages(source),
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.page, 3);
      expect(controller.isZoomed, isFalse);
      expect(pageLabel(3), findsOneWidget);
      expect(pageLabel(4), findsOneWidget);
    });

    testWidgets('a page that fails to load is a placeholder, the rest show', (
      tester,
    ) async {
      source.pages[1] = Uint8List.fromList(List.filled(32, 7));
      await pumpView(tester, initialPage: 1);
      await decodeVisible(tester, frameWidth: 390);
      expect(
        find.bySemanticsLabel('Page 2 could not be shown'),
        findsOneWidget,
      );
      controller.next();
      await tester.pumpAndSettle();
      await decodeVisible(tester, frameWidth: 390);
      expect(pageLabel(3), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is FixedPagePainter,
        ),
        findsWidgets,
      );
    });

    testWidgets('frames decode at the frame width in device pixels', (
      tester,
    ) async {
      await pumpView(tester);
      await decodeVisible(tester, frameWidth: 390);
      final image =
          (tester
                      .widget<CustomPaint>(
                        find
                            .byWidgetPredicate(
                              (w) =>
                                  w is CustomPaint &&
                                  w.painter is FixedPagePainter,
                            )
                            .first,
                      )
                      .painter
                  as FixedPagePainter)
              .image;
      expect(image.width, 390);
      expect(image.height, 585);
    });
  });

  group('turning', () {
    for (final axis in Axis.values) {
      for (final rtl in [false, true]) {
        for (final forward in [false, true]) {
          testWidgets(
            'slide moves adjacent pages together: $axis, RTL $rtl, forward $forward',
            (tester) async {
              await pumpView(
                tester,
                axis: axis,
                rtl: rtl,
                initialPage: 1,
                pageTurnAnimation: PageTurnAnimation.slide,
              );
              final resting = tester.getRect(pageFrame(2));
              if (forward) {
                controller.next();
              } else {
                controller.previous();
              }
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 70));
              final oldPage = tester.getRect(pageFrame(2));
              final newPage = tester.getRect(pageFrame(forward ? 3 : 1));
              final baseline = axis == Axis.horizontal
                  ? resting.left
                  : resting.top;
              final outgoing =
                  (axis == Axis.horizontal ? oldPage.left : oldPage.top) -
                  baseline;
              final incoming =
                  (axis == Axis.horizontal ? newPage.left : newPage.top) -
                  baseline;
              final extent = axis == Axis.horizontal
                  ? portrait.width
                  : portrait.height;
              final sign =
                  (forward ? 1.0 : -1.0) *
                  (axis == Axis.horizontal && rtl ? -1.0 : 1.0);
              expect(incoming * sign, inExclusiveRange(0, extent));
              expect(outgoing * sign, inExclusiveRange(-extent, 0));
              expect((incoming - outgoing) * sign, closeTo(extent, 0.000001));
              await tester.pumpAndSettle();
              expect(controller.page, forward ? 2 : 0);
              expect(tester.takeException(), isNull);
            },
          );
        }

        testWidgets('a cancelled slide returns to its page: $axis, RTL $rtl', (
          tester,
        ) async {
          await pumpView(
            tester,
            axis: axis,
            rtl: rtl,
            initialPage: 1,
            pageTurnAnimation: PageTurnAnimation.slide,
          );
          final resting = tester.getRect(pageFrame(2));
          final sign = axis == Axis.horizontal && rtl ? 1.0 : -1.0;
          final direction = axis == Axis.horizontal
              ? Offset(sign, 0)
              : Offset(0, sign);
          final gesture = await tester.startGesture(
            portrait.center(Offset.zero),
          );
          await gesture.moveBy(direction * 25);
          await gesture.moveBy(direction * 100);
          await tester.pump();
          expect(
            (tester.getTopLeft(pageFrame(2)) - resting.topLeft).distance,
            greaterThan(0),
            reason: 'the old page moves with a slide',
          );
          await gesture.cancel();
          await tester.pumpAndSettle();
          expect(controller.page, 1);
          expect(
            (tester.getTopLeft(pageFrame(2)) - resting.topLeft).distance,
            lessThan(0.000001),
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('animation changes preserve the current page and zoom', (
      tester,
    ) async {
      final animation = ValueNotifier(PageTurnAnimation.cover);
      addTearDown(animation.dispose);
      await pumpView(tester, initialPage: 1, animation: animation);
      await decodeVisible(tester, frameWidth: portrait.width);
      final pageElement = pageFrame(2).evaluate().single;
      final pageRender = tester.renderObject(pageFrame(2));
      controller.reportZoomScale(2);
      await tester.pump();
      final epoch = controller.zoomEpoch;
      for (final value in [PageTurnAnimation.slide, PageTurnAnimation.cover]) {
        animation.value = value;
        await tester.pump();
        expect(controller.page, 1);
        expect(controller.isZoomed, isTrue);
        expect(controller.zoomEpoch, epoch);
        expect(pageFrame(2).evaluate().single, same(pageElement));
        expect(tester.renderObject(pageFrame(2)), same(pageRender));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('an active cover finishes before a changed animation applies', (
      tester,
    ) async {
      final animation = ValueNotifier(PageTurnAnimation.cover);
      addTearDown(animation.dispose);
      await pumpView(tester, initialPage: 1, animation: animation);
      final resting = tester.getRect(pageFrame(2));
      controller.next();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final before = tester.getRect(pageFrame(2));
      expect(before, resting);
      animation.value = PageTurnAnimation.slide;
      await tester.pump();
      expect(
        tester.getRect(pageFrame(2)),
        before,
        reason: 'the running cover keeps its strategy',
      );
      await tester.pumpAndSettle();
      final nextRest = tester.getRect(pageFrame(3));
      controller.next();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.getRect(pageFrame(3)).left, lessThan(nextRest.left));
      await tester.pumpAndSettle();
      expect(controller.page, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion skips the selected slide', (tester) async {
      await pumpView(
        tester,
        reduceMotion: true,
        pageTurnAnimation: PageTurnAnimation.slide,
      );
      controller.goToPage(3);
      await tester.pump();
      await tester.pump();
      expect(pageLabel(4), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    for (final axis in Axis.values) {
      for (final rtl in [false, true]) {
        for (final forward in [false, true]) {
          testWidgets(
            'cover keeps the outgoing page still: $axis, RTL $rtl, forward $forward',
            (tester) async {
              await pumpView(tester, axis: axis, rtl: rtl, initialPage: 1);
              final before = tester.getRect(pageFrame(2));
              if (forward) {
                controller.next();
              } else {
                controller.previous();
              }
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 70));
              expect(tester.getRect(pageFrame(2)), before);
              final incoming = tester.getRect(pageFrame(forward ? 3 : 1));
              final movement = axis == Axis.horizontal
                  ? incoming.left
                  : incoming.top;
              final extent = axis == Axis.horizontal
                  ? portrait.width
                  : portrait.height;
              final sign =
                  (forward ? 1 : -1) *
                  (axis == Axis.horizontal && rtl ? -1 : 1);
              expect(movement * sign, greaterThan(0));
              expect(movement.abs(), lessThan(extent));
              await tester.pumpAndSettle();
              expect(controller.page, forward ? 2 : 0);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    for (final axis in Axis.values) {
      for (final rtl in [false, true]) {
        testWidgets(
          'a cancelled cover swipe returns to rest: $axis, RTL $rtl',
          (
            tester,
          ) async {
            await pumpView(tester, axis: axis, rtl: rtl, initialPage: 1);
            final before = tester.getRect(pageFrame(2));
            final sign = axis == Axis.horizontal && rtl ? 1.0 : -1.0;
            final direction = axis == Axis.horizontal
                ? Offset(sign, 0)
                : const Offset(0, -1);
            final gesture = await tester.startGesture(
              portrait.center(Offset.zero),
            );
            await gesture.moveBy(direction * 25);
            await gesture.moveBy(direction * 100);
            await tester.pump();
            expect(
              (tester.getTopLeft(pageFrame(2)) - before.topLeft).distance,
              lessThan(0.000001),
            );
            expect(controller.page, 1);
            await gesture.cancel();
            await tester.pumpAndSettle();
            expect(controller.page, 1);
            expect(
              (tester.getTopLeft(pageFrame(2)) - before.topLeft).distance,
              lessThan(0.000001),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    for (final axis in Axis.values) {
      for (final forward in [false, true]) {
        testWidgets(
          'incoming page paints over the old one: $axis, forward $forward',
          (
            tester,
          ) async {
            await pumpView(tester, initialPage: 1, capture: true, axis: axis);
            await decodeVisible(tester, frameWidth: portrait.width);
            if (forward) {
              controller.next();
            } else {
              controller.previous();
            }
            await tester.pump();
            await decodeVisible(tester, frameWidth: portrait.width);
            await tester.pump(const Duration(milliseconds: 70));
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('fixedPagesTestBoundary')),
            );
            final pixels = await tester.runAsync(() async {
              final image = await boundary.toImage();
              try {
                return (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!.buffer.asUint8List();
              } finally {
                image.dispose();
              }
            });
            final first = axis == Axis.horizontal
                ? const Offset(20, 422)
                : const Offset(195, 200);
            final second = axis == Axis.horizontal
                ? const Offset(370, 422)
                : const Offset(195, 644);
            final left =
                (portrait.width.toInt() * first.dy.toInt() + first.dx.toInt()) *
                4;
            final right =
                (portrait.width.toInt() * second.dy.toInt() +
                    second.dx.toInt()) *
                4;
            expect(
              pixels!.sublist(left, left + 4),
              forward ? [0x27, 0xAE, 0x60, 0xFF] : [0xC0, 0x39, 0x2B, 0xFF],
            );
            expect(
              pixels.sublist(right, right + 4),
              forward ? [0x29, 0x80, 0xB9, 0xFF] : [0x27, 0xAE, 0x60, 0xFF],
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('a swipe turns the page and reports it as a turn', (
      tester,
    ) async {
      await pumpView(tester);
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(controller.lastRelocationReason, PageRelocationReason.page);
      await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(controller.page, 0);
    });

    // The zoom viewer's scale recognizer sits deeper than the PageView and
    // claims a pointer once one event moves it past the pan slop; a flick
    // whose events outrun that slop must still turn the page. The first
    // event only starts the drag, so the travel stays past half a page.
    for (final step in [20.0, 40.0, 80.0]) {
      testWidgets('a flick moving $step px per event turns the page', (
        tester,
      ) async {
        await pumpView(tester);
        final gesture = await tester.startGesture(const Offset(300, 400));
        for (var moved = 0.0; moved < 320; moved += step) {
          await gesture.moveBy(Offset(-step, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(controller.page, 1);
        expect(controller.lastRelocationReason, PageRelocationReason.page);
      });
    }

    testWidgets('a flick in a right-to-left comic goes the other way', (
      tester,
    ) async {
      await pumpView(tester, rtl: true, initialPage: 1);
      final gesture = await tester.startGesture(const Offset(300, 400));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(-60, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.page, 0);
    });

    testWidgets('a vertical axis turns pages up and down, not sideways', (
      tester,
    ) async {
      await pumpView(tester, axis: Axis.vertical);
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(controller.page, 0, reason: 'sideways swipes do nothing');
      // Test pointer events carry no time, so there is no fling; the
      // travel itself must pass half the page.
      final gesture = await tester.startGesture(const Offset(195, 700));
      for (var i = 0; i < 9; i++) {
        await gesture.moveBy(const Offset(0, -60));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      await tester.fling(find.byType(PageView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();
      expect(controller.page, 0);
      // Edge taps keep their left and right zones.
      await tester.tapAt(const Offset(351, 422));
      await tester.pump();
      expect(taps.last.dx, closeTo(0.9, 0.001));
    });

    testWidgets('switching the axis keeps the page and turns the new way', (
      tester,
    ) async {
      await pumpView(tester, axis: Axis.vertical);
      await tester.fling(find.byType(PageView), const Offset(0, -300), 1000);
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      await pumpView(tester, axis: Axis.horizontal, keepController: true);
      await tester.pumpAndSettle();
      expect(controller.page, 1, reason: 'the page survives the switch');
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(controller.page, 2);
      await tester.fling(find.byType(PageView), const Offset(0, -300), 1000);
      await tester.pumpAndSettle();
      expect(controller.page, 2, reason: 'vertical swipes are over');
    });

    testWidgets('a right-to-left comic ignores reading direction vertically', (
      tester,
    ) async {
      await pumpView(tester, rtl: true, axis: Axis.vertical);
      await tester.fling(find.byType(PageView), const Offset(0, -300), 1000);
      await tester.pumpAndSettle();
      expect(
        controller.page,
        1,
        reason: 'up is forward whatever the direction',
      );
    });

    testWidgets('a right-to-left comic swipes the other way', (tester) async {
      await pumpView(tester, rtl: true);
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(controller.page, 0, reason: 'leftward is backward at the start');
      await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(controller.page, 1);
    });

    testWidgets('the controller moves the view', (tester) async {
      await pumpView(tester);
      controller.next();
      await tester.pumpAndSettle();
      expect(pageLabel(2), findsOneWidget);
      expect(pageLabel(1), findsNothing);
      controller.goToPage(4);
      await tester.pumpAndSettle();
      expect(pageLabel(5), findsOneWidget);
      expect(controller.lastRelocationReason, PageRelocationReason.navigation);
      controller.previous();
      await tester.pumpAndSettle();
      expect(pageLabel(4), findsOneWidget);
    });

    testWidgets('reduced motion jumps without animating', (tester) async {
      await pumpView(tester, reduceMotion: true);
      controller.goToPage(3);
      await tester.pump();
      await tester.pump();
      expect(pageLabel(4), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a swipe in a spread lands on the half nearest the reader', (
      tester,
    ) async {
      await pumpView(tester, size: landscape);
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();
      expect(controller.visiblePages, [2, 3]);
      expect(controller.page, 2);
    });
  });

  group('taps', () {
    testWidgets('edge taps reach the host at once as fractions', (
      tester,
    ) async {
      await pumpView(tester);
      await tester.tapAt(const Offset(39, 422));
      await tester.pump();
      expect(taps, [const Offset(0.1, 0.5)]);
      await tester.tapAt(const Offset(351, 422));
      await tester.pump();
      expect(taps.last.dx, closeTo(0.9, 0.001));
      // Two quick edge taps are two taps, never a zoom.
      await tester.tapAt(const Offset(39, 422));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(39, 422));
      await tester.pump();
      expect(taps, hasLength(4));
      expect(controller.isZoomed, isFalse);
    });

    testWidgets('a centre tap waits for the double-tap window', (tester) async {
      await pumpView(tester);
      await tester.tapAt(const Offset(195, 422));
      await tester.pump(const Duration(milliseconds: 200));
      expect(taps, isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
      expect(taps, [const Offset(0.5, 0.5)]);
    });

    testWidgets(
      'a double tap zooms in at the point and back out, without taps',
      (tester) async {
        await pumpView(tester);
        await tester.tapAt(const Offset(195, 300));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(const Offset(200, 310));
        await tester.pump(const Duration(milliseconds: 400));
        expect(taps, isEmpty);
        expect(controller.isZoomed, isTrue);
        expect(controller.zoomScale, FixedPagesView.doubleTapScale);
        final zoom = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(
          zoom.transformationController!.value.getMaxScaleOnAxis(),
          FixedPagesView.doubleTapScale,
        );

        await tester.tapAt(const Offset(195, 300));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(const Offset(195, 300));
        await tester.pump(const Duration(milliseconds: 400));
        expect(taps, isEmpty);
        expect(controller.isZoomed, isFalse);
        expect(zoom.transformationController!.value, Matrix4.identity());
      },
    );

    testWidgets('two centre taps outside the window are two taps', (
      tester,
    ) async {
      await pumpView(tester);
      await tester.tapAt(const Offset(195, 422));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(195, 422));
      await tester.pump(const Duration(milliseconds: 300));
      expect(taps, hasLength(2));
      expect(controller.isZoomed, isFalse);
    });

    testWidgets('a far second tap fires the first and waits on the second', (
      tester,
    ) async {
      await pumpView(tester);
      await tester.tapAt(const Offset(150, 300));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(240, 500));
      await tester.pump();
      expect(taps, [Offset(150 / 390, 300 / 844)]);
      await tester.pump(const Duration(milliseconds: 300));
      expect(taps, hasLength(2));
      expect(controller.isZoomed, isFalse);
    });

    testWidgets(
      'while zoomed every tap is a centre tap and swipes do not turn',
      (tester) async {
        await pumpView(tester);
        await tester.tapAt(const Offset(195, 422));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(const Offset(195, 422));
        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.isZoomed, isTrue);

        await tester.tapAt(const Offset(39, 422));
        await tester.pump();
        expect(taps, isEmpty, reason: 'no edge zones while zoomed');
        await tester.pump(const Duration(milliseconds: 300));
        expect(taps, [const Offset(0.5, 0.5)]);

        await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
        await tester.pumpAndSettle();
        expect(controller.page, 0);
      },
    );

    testWidgets('a turn cancels a pending tap and resets zoom', (tester) async {
      await pumpView(tester);
      await tester.tapAt(const Offset(195, 422));
      controller.next();
      await tester.pumpAndSettle();
      expect(taps, isEmpty);
      expect(controller.page, 1);

      await tester.tapAt(const Offset(195, 422));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(195, 422));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.isZoomed, isTrue);
      controller.next();
      await tester.pumpAndSettle();
      expect(controller.isZoomed, isFalse);
      for (final zoom in tester.widgetList<InteractiveViewer>(
        find.byType(InteractiveViewer),
      )) {
        expect(zoom.transformationController!.value, Matrix4.identity());
      }
    });

    testWidgets('locked input swallows taps', (tester) async {
      await pumpView(tester);
      controller.lockInput(true);
      await tester.pump();
      await tester.tapAt(const Offset(39, 422));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, isEmpty);
    });
  });

  group('readiness', () {
    testWidgets('reports the first page shown once its image arrives', (
      tester,
    ) async {
      final shown = <int>[];
      tester.view.physicalSize = portrait;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      controller = FixedPagesController(
        pageCount: source.pageCount,
        rtl: false,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: portrait),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FixedPagesView(
              pages: ComicPages(source),
              controller: controller,
              onPageShown: shown.add,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(shown, isEmpty, reason: 'nothing decoded yet');
      await decodeVisible(tester, frameWidth: 390);
      expect(shown, [0], reason: 'the prefetched neighbour is not reported');
      // A sharper re-decode of the same page is not a new page.
      controller.reportZoomScale(2);
      await tester.pump();
      await decodeVisible(tester, frameWidth: 780);
      expect(shown, [0]);
    });
  });

  group('FixedPagesViewportScope', () {
    testWidgets('maps a frame rectangle to fractions of the view', (
      tester,
    ) async {
      Rect? reported;
      tester.view.physicalSize = portrait;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      controller = FixedPagesController(
        pageCount: source.pageCount,
        rtl: false,
      );
      addTearDown(controller.dispose);
      final draft = ComicImageAreaDraft();
      addTearDown(draft.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: portrait),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FixedPagesView(
              pages: ComicPages(source),
              controller: controller,
              pageOverlayBuilder: (context, page, imageRect) =>
                  ComicImageAreaLayer(
                    page: page,
                    imageRect: imageRect,
                    controller: controller,
                    draft: draft,
                    onDraftCommitted: (_, viewport) => reported = viewport,
                  ),
            ),
          ),
        ),
      );
      await tester.pump();
      await decodeVisible(tester, frameWidth: 390);
      // The 600×900 page fills the 390-wide frame: 390×585, centred in 844.
      await tester.longPressAt(const Offset(195, 422));
      await tester.pump(const Duration(milliseconds: 300));
      expect(draft.isActive, isTrue);
      final rect = draft.rect!;
      final imageTop = (844 - 585) / 2;
      expect(reported, isNotNull);
      expect(reported!.left, closeTo(rect.left * 390 / 390, 1e-6));
      expect(reported!.top, closeTo((imageTop + rect.top * 585) / 844, 1e-6));
      expect(reported!.width, closeTo(rect.width * 390 / 390, 1e-6));
      expect(reported!.height, closeTo(rect.height * 585 / 844, 1e-6));
    });
  });

  group('zoomMatrixAt', () {
    test('keeps the tapped point in place and the page over the viewport', () {
      const viewport = Size(390, 844);
      final centre = zoomMatrixAt(
        const Offset(195, 422),
        scale: 2.5,
        viewport: viewport,
      );
      expect(centre.getMaxScaleOnAxis(), 2.5);
      final moved = MatrixUtils.transformPoint(centre, const Offset(195, 422));
      expect(moved.dx, closeTo(195, 0.001));
      expect(moved.dy, closeTo(422, 0.001));

      final corner = zoomMatrixAt(
        const Offset(5, 5),
        scale: 2.5,
        viewport: viewport,
      );
      final origin = MatrixUtils.transformPoint(corner, Offset.zero);
      expect(
        origin.dx,
        lessThanOrEqualTo(0),
        reason: 'the page still covers the top-left',
      );
      expect(origin.dy, lessThanOrEqualTo(0));
      final cornerPoint = MatrixUtils.transformPoint(
        corner,
        const Offset(5, 5),
      );
      expect(cornerPoint.dx, closeTo(5, 0.001));
      final edge = zoomMatrixAt(
        const Offset(0, 0),
        scale: 2.5,
        viewport: viewport,
      );
      expect(MatrixUtils.transformPoint(edge, Offset.zero), Offset.zero);
      final far = zoomMatrixAt(
        const Offset(389, 843),
        scale: 2.5,
        viewport: viewport,
      );
      final bottomRight = MatrixUtils.transformPoint(
        far,
        const Offset(390, 844),
      );
      expect(
        bottomRight.dx,
        greaterThanOrEqualTo(390),
        reason: 'covers the viewport',
      );
      expect(bottomRight.dy, greaterThanOrEqualTo(844));
      final farPoint = MatrixUtils.transformPoint(far, const Offset(389, 843));
      expect(farPoint.dx, closeTo(389, 0.001));
      expect(farPoint.dy, closeTo(843, 0.001));
    });
  });

  group('goldens', () {
    testWidgets('portrait page', (tester) async {
      await pumpView(tester);
      await settleFrames(tester);
      await expectLater(
        find.byType(FixedPagesView),
        matchesGoldenFile('goldens/comic_pages_portrait.png'),
      );
    });

    testWidgets('landscape spread, left to right', (tester) async {
      await pumpView(tester, size: landscape, initialPage: 2);
      await settleFrames(tester);
      await expectLater(
        find.byType(FixedPagesView),
        matchesGoldenFile('goldens/comic_pages_spread_ltr.png'),
      );
    });

    testWidgets('landscape spread, right to left', (tester) async {
      await pumpView(tester, size: landscape, rtl: true, initialPage: 2);
      await settleFrames(tester);
      await expectLater(
        find.byType(FixedPagesView),
        matchesGoldenFile('goldens/comic_pages_spread_rtl.png'),
      );
    });

    testWidgets('a lone last page in a spread is centred', (tester) async {
      await pumpView(tester, size: landscape, initialPage: 4);
      await settleFrames(tester);
      await expectLater(
        find.byType(FixedPagesView),
        matchesGoldenFile('goldens/comic_pages_spread_lone.png'),
      );
    });
  });
}
