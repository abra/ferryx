import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pagecraft/all_formats.dart';

/// Two lines of ten-point glyphs on a 200×100 pt page, drawn 1:1 into a
/// 200×100 layer at the origin: "The quick fox" over "jumps over".
PdfTextLayer layer() {
  const lines = ['The quick fox', 'jumps over'];
  final text = lines.join('\n');
  final boxes = <PdfBox>[];
  var line = 0;
  var column = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n') {
      boxes.add(const PdfBox(0, 0, 0, 0));
      line++;
      column = 0;
      continue;
    }
    boxes.add(
      PdfBox(
        column * 10.0,
        20 + line * 20.0,
        column * 10.0 + 10,
        30 + line * 20.0,
      ),
    );
    column++;
  }
  return PdfTextLayer(pageIndex: 0, text: text, charBoxes: boxes);
}

void main() {
  late FixedPagesController controller;
  late PdfTextSelection selection;
  late List<(PdfTextRange, Rect?)> changes;
  late List<String> pressed;
  var cleared = 0;

  setUp(() {
    controller = FixedPagesController(pageCount: 1, rtl: false);
    selection = PdfTextSelection();
    changes = [];
    pressed = [];
    cleared = 0;
  });

  tearDown(() {
    controller.dispose();
    selection.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    List<PdfTextHighlight> highlights = const [],
    PdfTextRange? searchMark,
    bool withLayer = true,
    bool enabled = true,
    Widget? after,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 200,
              height: 100,
              child: PdfTextOverlay(
                page: 0,
                imageRect: const Rect.fromLTWH(0, 0, 200, 100),
                pageWidth: 200,
                pageHeight: 100,
                controller: controller,
                selection: selection,
                layer: withLayer ? layer() : null,
                highlights: highlights,
                searchMark: searchMark,
                enabled: enabled,
                onSelectionChanged: (range, viewport) =>
                    changes.add((range, viewport)),
                onSelectionCleared: () => cleared++,
                onHighlightPressed: (highlight, _) => pressed.add(highlight.id),
              ),
            ),
            ?after,
          ],
        ),
      ),
    );
  }

  Color selectionColorOnScreen(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byType(PdfTextOverlay),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    return (paint.painter as dynamic).selectionColor as Color;
  }

  Offset overlayOrigin(WidgetTester tester) =>
      tester.getTopLeft(find.byType(PdfTextOverlay));

  /// The centre of glyph [column] on [line], in screen coordinates.
  Offset glyph(WidgetTester tester, int line, int column) =>
      overlayOrigin(tester) + Offset(column * 10.0 + 5, 25 + line * 20.0);

  Future<void> longPressAt(WidgetTester tester, Offset at) async {
    final gesture = await tester.startGesture(at);
    await tester.pump(ComicImageAreaGeometry.longPressDuration);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a long press on a word selects it and locks the view', (
    tester,
  ) async {
    await pump(tester);
    await longPressAt(tester, glyph(tester, 0, 6));
    expect(selection.page, 0);
    expect(selection.range, const PdfTextRange(4, 9));
    expect(controller.inputLocked, isTrue);
    expect(changes, hasLength(1));
    expect(changes.single.$1, const PdfTextRange(4, 9));
    expect(changes.single.$2, isNull, reason: 'no FixedPagesView around');
  });

  testWidgets('dragging while pressing extends to insertion boundaries', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(glyph(tester, 0, 6));
    await tester.pump(ComicImageAreaGeometry.longPressDuration);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(overlayOrigin(tester) + const Offset(30, 45));
    await tester.pump();
    expect(
      selection.range,
      const PdfTextRange(4, 17),
      reason: 'quick fox\\njum',
    );
    await gesture.moveTo(overlayOrigin(tester) + const Offset(10, 25));
    await tester.pump();
    expect(
      selection.range,
      const PdfTextRange(1, 9),
      reason: 'backwards keeps the word',
    );
    await gesture.up();
    await tester.pump();
    expect(changes.last.$1, const PdfTextRange(1, 9));
  });

  testWidgets('handles move either end after release', (tester) async {
    await pump(tester);
    await longPressAt(tester, glyph(tester, 0, 6));
    final endHandle = tester.getCenter(
      find.byKey(const ValueKey('pdf-selection-end-handle-0')),
    );
    // Move the caret from x=90 on the first line to x=50 on the second,
    // retaining the offset between the grip and the glyph boundary.
    await tester.dragFrom(endHandle, const Offset(-40, 20));
    await tester.pump();
    expect(selection.range, const PdfTextRange(4, 19));
    final startHandle = tester.getCenter(
      find.byKey(const ValueKey('pdf-selection-start-handle-0')),
    );
    await tester.dragFrom(startHandle, const Offset(-40, 0));
    await tester.pump();
    expect(selection.range, const PdfTextRange(0, 19));
    expect(changes, hasLength(3));
  });

  testWidgets('a drag that starts off both handles moves nothing', (
    tester,
  ) async {
    await pump(tester);
    await longPressAt(tester, glyph(tester, 0, 6));
    final far = overlayOrigin(tester) + const Offset(180, 90);
    await tester.dragFrom(far, const Offset(-100, -60));
    await tester.pump();
    expect(selection.range, const PdfTextRange(4, 9));
    expect(changes, hasLength(1));
  });

  testWidgets('a colour change during build repaints after the frame', (
    tester,
  ) async {
    await pump(tester);
    await longPressAt(tester, glyph(tester, 0, 6));
    expect(selectionColorOnScreen(tester), PdfTextSelection.defaultColor);
    // The app previews a colour from a popup's initState: a sibling built
    // after the overlay in the same frame.
    const red = Color(0x80FF0000);
    await pump(
      tester,
      after: Builder(
        builder: (_) {
          selection.setColor(red);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(selectionColorOnScreen(tester), red);
    expect(selection.isActive, isTrue);
  });

  testWidgets('a tap outside clears, inside keeps', (tester) async {
    await pump(tester);
    await longPressAt(tester, glyph(tester, 0, 6));
    await tester.tapAt(glyph(tester, 0, 5));
    await tester.pump();
    expect(selection.isActive, isTrue, reason: 'inside the selection');
    await tester.tapAt(overlayOrigin(tester) + const Offset(180, 90));
    await tester.pump();
    expect(selection.isActive, isFalse);
    expect(controller.inputLocked, isFalse);
    expect(cleared, 1);
  });

  testWidgets('a tap on a saved highlight reports it', (tester) async {
    await pump(
      tester,
      highlights: const [
        PdfTextHighlight(
          id: 'h1',
          page: 0,
          range: PdfTextRange(14, 19),
          color: Color(0x66FFE600),
        ),
      ],
    );
    await tester.tapAt(glyph(tester, 1, 2));
    await tester.pump();
    expect(pressed, ['h1']);
    await tester.tapAt(glyph(tester, 0, 2));
    await tester.pump();
    expect(pressed, ['h1'], reason: 'plain text takes no taps');
  });

  testWidgets('a long press off the text or without a layer does nothing', (
    tester,
  ) async {
    await pump(tester);
    await longPressAt(tester, overlayOrigin(tester) + const Offset(100, 90));
    expect(selection.isActive, isFalse);
    expect(controller.inputLocked, isFalse);
    await pump(tester, withLayer: false);
    await longPressAt(tester, glyph(tester, 0, 6));
    expect(selection.isActive, isFalse);
  });

  testWidgets('disabled draws but takes no input', (tester) async {
    await pump(tester, enabled: false, searchMark: const PdfTextRange(0, 3));
    await longPressAt(tester, glyph(tester, 0, 6));
    expect(selection.isActive, isFalse);
    expect(find.byType(CustomPaint), findsOneWidget);
  });

  testWidgets('paints highlights, the search mark and the selection', (
    tester,
  ) async {
    await pump(
      tester,
      highlights: const [
        PdfTextHighlight(
          id: 'h1',
          page: 0,
          range: PdfTextRange(14, 19),
          color: Color(0xFFFFE600),
        ),
      ],
      searchMark: const PdfTextRange(0, 3),
    );
    await longPressAt(tester, glyph(tester, 0, 6));
    await expectLater(
      find.byType(PdfTextOverlay),
      matchesGoldenFile('goldens/pdf_text_overlay.png'),
    );
  });
}
