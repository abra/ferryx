import 'dart:ui' as ui;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoTextMagnifier;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pagecraft/pdf.dart';

const _paperKey = ValueKey('selection-paper');
const _endKey = ValueKey('pdf-selection-end-handle-0');
const _startKey = ValueKey('pdf-selection-start-handle-0');
final _layer = _textLayer();

void main() {
  late FixedPagesController controller;
  late PdfTextSelection selection;
  late List<bool> dragging;

  setUp(() {
    controller = FixedPagesController(pageCount: 1, rtl: false);
    selection = PdfTextSelection()..start(0, const PdfTextRange(4, 9));
    dragging = [];
  });

  tearDown(() {
    controller.dispose();
    selection.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    double zoom = 1,
    bool darkPage = false,
    bool appRtl = false,
    Color? paperColor,
    Color? inkColor,
    Color? markerColor,
  }) async {
    controller.reportZoomScale(zoom);
    await tester.pumpWidget(
      _Page(
        controller,
        selection,
        dragging.add,
        zoom: zoom,
        darkPage: darkPage,
        appRtl: appRtl,
        paperColor: paperColor,
        inkColor: inkColor,
        markerColor: markerColor,
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'horizontal grip movement changes the exact insertion edge',
    (
      tester,
    ) async {
      await pump(tester);
      final grip = tester.getCenter(find.byKey(_endKey));
      await tester.dragFrom(grip, const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(selection.range, const PdfTextRange(4, 12));
      expect(dragging, [true, false]);
      expect(find.byType(TextMagnifier), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a one-glyph iOS adjustment starts without overshooting',
    (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_endKey)),
      );
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(selection.range, const PdfTextRange(4, 10));
      expect(dragging, [true]);
      expect(find.byType(CupertinoTextMagnifier), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(dragging, [true, false]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'phone RTL keeps handles on the document edges and adjusts precisely',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pump(tester, appRtl: true);
      expect(
        Directionality.of(tester.element(find.byType(PdfTextOverlay))),
        TextDirection.rtl,
      );
      final start = find.byKey(_startKey);
      final end = find.byKey(_endKey);
      expect(start.hitTestable(), findsOneWidget);
      expect(end.hitTestable(), findsOneWidget);
      expect(tester.getCenter(start).dx, lessThan(tester.getCenter(end).dx));
      final gesture = await tester.startGesture(tester.getCenter(end));
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(selection.range, const PdfTextRange(4, 10));
      expect(dragging, [true]);
      expect(find.byType(TextMagnifier), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(dragging, [true, false]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'holding a handle before moving keeps its precise drag gesture',
    (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_endKey)),
      );
      await tester.pump(
        ComicImageAreaGeometry.longPressDuration +
            const Duration(milliseconds: 100),
      );
      expect(selection.range, const PdfTextRange(4, 9));
      expect(dragging, isEmpty);
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(selection.range, const PdfTextRange(4, 12));
      expect(dragging, [true]);
      expect(find.byType(TextMagnifier), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(dragging, [true, false]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'an off-centre grip preserves its original touch offset',
    (
      tester,
    ) async {
      await pump(tester);
      final grip = tester.getCenter(find.byKey(_endKey)) + const Offset(10, 8);
      final gesture = await tester.startGesture(grip);
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(selection.range, const PdfTextRange(4, 12));
      final magnifier = tester.widget<TextMagnifier>(
        find.byType(TextMagnifier),
      );
      final info = magnifier.magnifierInfo.value;
      expect(info.globalGesturePosition.dx, info.caretRect.center.dx);
      await gesture.moveTo(grip);
      await tester.pump();
      expect(selection.range, const PdfTextRange(4, 9));
      await gesture.up();
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'dragging across a line gap follows the nearest text line',
    (
      tester,
    ) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_endKey)),
      );
      await gesture.moveBy(const Offset(30, 9));
      await tester.pump();
      expect(selection.range, const PdfTextRange(4, 12));
      await gesture.moveBy(const Offset(-30, 6));
      await tester.pump();
      expect(selection.range, const PdfTextRange(4, 23));
      await gesture.up();
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'crossing a handle and returning keeps the opposite anchor',
    (
      tester,
    ) async {
      await pump(tester);
      final grip = tester.getCenter(find.byKey(_endKey));
      final gesture = await tester.startGesture(grip);
      await gesture.moveTo(grip - const Offset(70, 0));
      await tester.pump();
      expect(selection.range, const PdfTextRange(2, 4));
      await gesture.moveTo(grip - const Offset(20, 0));
      await tester.pump();
      expect(selection.range, const PdfTextRange(4, 7));
      await gesture.up();
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'zoom retains 48px grips and applies screen deltas once',
    (
      tester,
    ) async {
      await pump(tester, zoom: 2);
      for (final key in [_startKey, _endKey]) {
        expect(tester.getRect(find.byKey(key)).size, const Size.square(48));
      }
      final grip = tester.getCenter(find.byKey(_endKey));
      await tester.dragFrom(grip, const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(selection.range, const PdfTextRange(4, 11));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'preview colour does not replace the handle accent',
    (
      tester,
    ) async {
      await pump(tester);
      selection.setColor(const Color(0xFFFF0000));
      await tester.pump();
      final handleTheme = tester.widget<TextSelectionTheme>(
        find.descendant(
          of: find.byKey(_endKey),
          matching: find.byType(TextSelectionTheme),
        ),
      );
      expect(handleTheme.data.selectionHandleColor, Colors.blue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'cancelling a drag restores actions and removes the loupe',
    (
      tester,
    ) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_endKey)),
      );
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump();
      expect(dragging, [true]);
      expect(find.byType(TextMagnifier), findsOneWidget);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(dragging, [true, false]);
      expect(find.byType(TextMagnifier), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'disposing during an iOS drag removes its loupe',
    (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_endKey)),
      );
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump();
      expect(dragging, [true]);
      expect(find.byType(CupertinoTextMagnifier), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await gesture.up();
      await tester.pumpAndSettle();
      expect(dragging, [true, false]);
      expect(find.byType(CupertinoTextMagnifier), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'strong selection and saved markers preserve black glyphs',
    (
      tester,
    ) async {
      selection.setColor(const Color(0xD1FFE600));
      await pump(tester);
      final pixels = await _capturePixels(tester);
      expect(pixels.at(60, 25), Colors.black, reason: 'active selected glyph');
      expect(pixels.at(5, 45), Colors.black, reason: 'saved highlighted glyph');
      expect(
        pixels.at(60, 22),
        isNot(Colors.white),
        reason: 'visible selection',
      );
      expect(
        pixels.at(5, 42),
        isNot(Colors.white),
        reason: 'visible saved marker',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'dark-page markers retain light glyphs and readable contrast',
    (tester) async {
      const pagePairs = [
        (Color(0xFF0F1115), Color(0xFFBCC1CA)),
        (Color(0xFF242830), Color(0xFFABB2BF)),
      ];
      const markers = [
        Color(0xFF63551D),
        Color(0xFF294056),
        Color(0xFF284838),
        Color(0xFF642B3E),
        Color(0xFF472B64),
      ];
      for (final (paper, ink) in pagePairs) {
        for (final color in markers) {
          final marker = color.withValues(alpha: .72);
          selection.setColor(marker);
          await pump(
            tester,
            darkPage: true,
            paperColor: paper,
            inkColor: ink,
            markerColor: marker,
          );
          final pixels = await _capturePixels(tester);
          for (final (glyph, background, unchanged) in [
            (pixels.at(60, 25), pixels.at(60, 22), true),
            (pixels.at(5, 45), pixels.at(5, 42), true),
            (pixels.at(120, 25), pixels.at(120, 22), false),
          ]) {
            if (unchanged) {
              expect(
                glyph,
                ink,
                reason: 'the marker preserves the light glyph',
              );
            } else {
              expect(
                glyph.computeLuminance(),
                greaterThanOrEqualTo(ink.computeLuminance()),
                reason: 'the bright search accent cannot darken the glyph',
              );
            }
            expect(
              background,
              isNot(paper),
              reason: 'the marker remains visible',
            );
            final contrast =
                (glyph.computeLuminance() + .05) /
                (background.computeLuminance() + .05);
            expect(contrast, greaterThanOrEqualTo(4.5));
          }
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

class _Page extends StatelessWidget {
  const _Page(
    this.controller,
    this.selection,
    this.onDrag, {
    this.zoom = 1,
    this.darkPage = false,
    this.appRtl = false,
    this.paperColor,
    this.inkColor,
    this.markerColor,
  });

  final FixedPagesController controller;
  final PdfTextSelection selection;
  final ValueChanged<bool> onDrag;
  final double zoom;
  final bool darkPage;
  final bool appRtl;
  final Color? paperColor;
  final Color? inkColor;
  final Color? markerColor;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(platform: defaultTargetPlatform),
    builder: (context, child) => Directionality(
      textDirection: appRtl ? TextDirection.rtl : TextDirection.ltr,
      child: child!,
    ),
    home: Scaffold(
      body: Center(
        child: Transform.scale(
          scale: zoom,
          child: RepaintBoundary(
            key: _paperKey,
            child: SizedBox(
              width: 200,
              height: 100,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _InkPage(
                      paperColor ??
                          (darkPage ? const Color(0xFF0F1115) : Colors.white),
                      inkColor ??
                          (darkPage ? const Color(0xFFBCC1CA) : Colors.black),
                    ),
                  ),
                  PdfTextOverlay(
                    page: 0,
                    imageRect: const Rect.fromLTWH(0, 0, 200, 100),
                    pageWidth: 200,
                    pageHeight: 100,
                    controller: controller,
                    selection: selection,
                    layer: _layer,
                    handleColor: Colors.blue,
                    darkPage: darkPage,
                    searchMark: darkPage ? const PdfTextRange(10, 13) : null,
                    onSelectionDragChanged: onDrag,
                    highlights: [
                      PdfTextHighlight(
                        id: 'saved',
                        page: 0,
                        range: const PdfTextRange(14, 19),
                        color:
                            markerColor ??
                            (darkPage
                                ? const Color(0xB863551D)
                                : const Color(0xFFFFE600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _InkPage extends CustomPainter {
  const _InkPage(this.paper, this.ink);

  final Color paper;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    canvas.drawRect(const Rect.fromLTWH(0, 24, 130, 2), Paint()..color = ink);
    canvas.drawRect(const Rect.fromLTWH(0, 44, 100, 2), Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_InkPage oldDelegate) =>
      oldDelegate.paper != paper || oldDelegate.ink != ink;
}

class _PagePixels {
  const _PagePixels(this.bytes, this.width);

  final ByteData bytes;
  final int width;

  Color at(int x, int y) {
    final index = (y * width + x) * 4;
    return Color.fromARGB(
      bytes.getUint8(index + 3),
      bytes.getUint8(index),
      bytes.getUint8(index + 1),
      bytes.getUint8(index + 2),
    );
  }
}

Future<_PagePixels> _capturePixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_paperKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return _PagePixels(bytes!, image.width);
    } finally {
      image.dispose();
    }
  }))!;
}

PdfTextLayer _textLayer() {
  const text = 'The quick fox\njumps over';
  final boxes = <PdfBox>[];
  var line = 0;
  var column = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n') {
      boxes.add(const PdfBox(0, 0, 0, 0));
      line++;
      column = 0;
    } else {
      final x = column++ * 10.0;
      final y = 20 + line * 20.0;
      boxes.add(PdfBox(x, y, x + 10, y + 10));
    }
  }
  return PdfTextLayer(pageIndex: 0, text: text, charBoxes: boxes);
}
