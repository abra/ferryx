import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_text_selection/native_text_selection.dart';
import 'package:pagecraft/djvu.dart';

void main() {
  testWidgets('native word zones retain RTL and an independent handle accent', (
    tester,
  ) async {
    final controller = FixedPagesController(pageCount: 1, rtl: true);
    final selection = DjvuTextSelection();
    addTearDown(controller.dispose);
    addTearDown(selection.dispose);
    final layer = DjvuTextLayer.fromJson(0, {
      'width': 400,
      'height': 600,
      'words': [
        {'text': 'مرحبا', 'x': 260, 'y': 100, 'width': 80, 'height': 30},
        {'text': 'word', 'x': 140, 'y': 100, 'width': 80, 'height': 30},
      ],
    });
    selection.start(0, const DjvuTextRange(0, 5));
    await tester.pumpWidget(
      _OverlayHost(
        controller: controller,
        selection: selection,
        layer: layer,
        onChanged: (_, _) {},
      ),
    );
    var snapshot = tester
        .widget<NativeSelectionSurface>(find.byType(NativeSelectionSurface))
        .snapshot!;
    expect(snapshot.text, layer.text);
    expect(snapshot.boxes, hasLength(2));
    expect(snapshot.boxes.first.direction, TextDirection.rtl);
    expect(snapshot.boxes.first.end, 5);
    expect(snapshot.boxes.last.direction, TextDirection.ltr);
    selection.setColor(const Color(0x66FFB300));
    await tester.pump();
    snapshot = tester
        .widget<NativeSelectionSurface>(find.byType(NativeSelectionSurface))
        .snapshot!;
    expect(snapshot.selectionColor, const Color(0x66FFB300));
    expect(
      snapshot.accent,
      DjvuTextSelection.defaultColor.withValues(alpha: 1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'long press selects a word and handle dragging extends by words',
    (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = FixedPagesController(pageCount: 1, rtl: false);
      addTearDown(controller.dispose);
      final selection = DjvuTextSelection();
      addTearDown(selection.dispose);
      final events = <DjvuTextRange>[];
      final lifecycle = <String>[];
      final layer = DjvuTextLayer.fromJson(0, {
        'width': 400,
        'height': 600,
        'words': [
          {'text': 'First', 'x': 40, 'y': 100, 'width': 80, 'height': 30},
          {'text': 'second', 'x': 140, 'y': 100, 'width': 100, 'height': 30},
          {'text': 'third', 'x': 260, 'y': 100, 'width': 80, 'height': 30},
        ],
      });
      await tester.pumpWidget(
        _OverlayHost(
          controller: controller,
          selection: selection,
          layer: layer,
          onChanged: (range, _) {
            events.add(range);
            lifecycle.add('range:${range.start}:${range.end}');
          },
          onDragChanged: (value) => lifecycle.add('adjusting:$value'),
        ),
      );
      await tester.longPressAt(const Offset(60, 115));
      await tester.pump();
      expect(selection.range, const DjvuTextRange(0, 5));
      expect(events.last, const DjvuTextRange(0, 5));
      expect(controller.inputLocked, isTrue);
      expect(lifecycle, ['adjusting:true', 'range:0:5', 'adjusting:false']);

      // The second handle starts at the selected word's bottom-right corner.
      await tester.dragFrom(const Offset(120, 130), const Offset(180, -15));
      await tester.pump();
      expect(selection.range, const DjvuTextRange(0, 18));
      expect(layer.textOf(selection.range!), 'First second third');
      expect(events.last, const DjvuTextRange(0, 18));
      expect(lifecycle.sublist(3), [
        'adjusting:true',
        'range:0:18',
        'adjusting:false',
      ]);
      await tester.tapAt(const Offset(200, 300));
      await tester.pump();
      expect(selection.isActive, isFalse);
      expect(controller.inputLocked, isFalse);

      // Native controls claim only handle touches. Page taps must still clear
      // selection and release the reader's input lock after native readiness.
      selection.start(0, const DjvuTextRange(0, 5));
      controller.lockInput(true);
      await tester.pump();
      tester
          .widget<NativeSelectionSurface>(find.byType(NativeSelectionSurface))
          .onActiveChanged!(true);
      await tester.pump();
      await tester.tapAt(const Offset(200, 300));
      await tester.pump();
      expect(selection.isActive, isFalse);
      expect(controller.inputLocked, isFalse);
      final cancelled = await tester.startGesture(const Offset(60, 115));
      await tester.pump(const Duration(milliseconds: 350));
      expect(lifecycle.last, 'adjusting:true');
      await cancelled.cancel();
      await tester.pump();
      expect(lifecycle.last, 'adjusting:false');
      expect(selection.range, const DjvuTextRange(0, 5));
      expect(tester.takeException(), isNull);
    },
  );
}

class _OverlayHost extends StatelessWidget {
  const _OverlayHost({
    required this.controller,
    required this.selection,
    required this.layer,
    required this.onChanged,
    this.onDragChanged,
  });

  final FixedPagesController controller;
  final DjvuTextSelection selection;
  final DjvuTextLayer layer;
  final DjvuSelectionChanged onChanged;
  final ValueChanged<bool>? onDragChanged;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox.expand(
      child: DjvuTextOverlay(
        page: 0,
        imageRect: const Rect.fromLTWH(0, 0, 400, 600),
        pageWidth: 400,
        pageHeight: 600,
        controller: controller,
        selection: selection,
        layer: layer,
        onSelectionChanged: onChanged,
        onSelectionDragChanged: onDragChanged,
      ),
    ),
  );
}
