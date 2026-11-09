import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:native_text_selection/native_text_selection.dart';

import 'djvu_text_layer.dart';
import '../../fixed_layout/comic_image_area.dart';
import '../../fixed_layout/fixed_pages_controller.dart';
import '../../fixed_layout/fixed_pages_view.dart';
import 'djvu_text_selection.dart';
import '../../fixed_layout/repaint_after_build.dart';
import '../../text/text_direction.dart';

/// Text on one DjVu page: saved highlights, the search hit, and the
/// selection with its handles, over the page image.
///
/// Placed by `FixedPagesView.pageOverlayBuilder`, so it is scaled with the
/// page while zoomed; sizes meant in screen pixels are divided by the
/// zoom. A long press (280 ms, as image areas) on a word selects it and
/// drags its end over the text. After release, supported mobile hosts use
/// system controls over the same word zones. Flutter fallback handles use
/// 44 px targets and move an endpoint by word. A tap outside clears the
/// selection, and a tap on a
/// saved highlight reports it. The page's text
/// comes from hidden-text word zones, without guessing character positions.
/// Until the [DjvuTextLayer] is loaded the overlay only draws
/// what it is given.
class DjvuTextOverlay extends StatefulWidget {
  const DjvuTextOverlay({
    super.key,
    required this.page,
    required this.imageRect,
    required this.pageWidth,
    required this.pageHeight,
    required this.controller,
    required this.selection,
    this.layer,
    this.highlights = const [],
    this.searchMark,
    this.searchMarkColor = const Color(0x66FFB300),
    this.onSelectionChanged,
    this.onSelectionDragChanged,
    this.onSelectionCleared,
    this.onHighlightPressed,
    this.handleColor,
    this.enabled = true,
  });

  final int page;

  /// Where the whole page is drawn inside this layer.
  final Rect imageRect;

  /// The page's display size in points, the unit of [DjvuTextLayer] boxes.
  final double pageWidth;
  final double pageHeight;

  final FixedPagesController controller;
  final DjvuTextSelection selection;
  final DjvuTextLayer? layer;

  /// Saved highlights of this page, oldest first.
  final List<DjvuTextHighlight> highlights;

  /// The search hit to mark on this page.
  final DjvuTextRange? searchMark;
  final Color searchMarkColor;

  /// The selection was made or its end moved and the finger lifted, with
  /// where it sits in the whole view (null outside a `FixedPagesView`).
  final DjvuSelectionChanged? onSelectionChanged;

  /// The final range is reported before adjustment ends and actions return.
  final ValueChanged<bool>? onSelectionDragChanged;

  /// Handle accent stays independent of the annotation preview fill.
  final Color? handleColor;

  /// A tap outside dismissed the selection.
  final VoidCallback? onSelectionCleared;

  /// A tap on a saved highlight, with where it sits in the whole view.
  final DjvuHighlightPressed? onHighlightPressed;

  /// False leaves everything drawn but takes no input.
  final bool enabled;

  /// Touch target of a selection handle, in screen pixels.
  static const handleTarget = 44.0;

  /// Drawn radius of a handle's knob, in screen pixels.
  static const handleRadius = 6.0;

  @override
  State<DjvuTextOverlay> createState() => _DjvuTextOverlayState();
}

typedef DjvuSelectionChanged =
    void Function(DjvuTextRange range, Rect? viewportRect);

typedef DjvuHighlightPressed =
    void Function(DjvuTextHighlight highlight, Rect? viewportRect);

enum _Drag { selecting, startHandle, endHandle }

class _DjvuTextOverlayState extends State<DjvuTextOverlay>
    with RepaintAfterBuild {
  _Drag? _drag;

  /// The character the press started on; the other end follows the finger.
  int? _anchorStart;
  int? _anchorEnd;
  bool _nativeActive = false;
  bool _adjusting = false;
  (DjvuTextLayer, Rect)? _nativeGeometryKey;
  List<NativeTextBox> _nativeBoxes = const [];
  int _nativeRevision = 0;
  (Color, Color)? _nativeStyle;

  DjvuTextSelection get _selection => widget.selection;

  bool get _hasSelectionHere =>
      _selection.isActive && _selection.page == widget.page;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(DjvuTextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    _selection.removeListener(_onSelectionChanged);
    if (_adjusting) widget.onSelectionDragChanged?.call(false);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!_hasSelectionHere) {
      _drag = null;
      _setAdjusting(false);
      _nativeGeometryKey = null;
      _nativeBoxes = const [];
    }
    repaint();
  }

  void _setAdjusting(bool value) {
    if (_adjusting == value) return;
    _adjusting = value;
    widget.onSelectionDragChanged?.call(value);
  }

  // Coordinates: layer pixels ↔ page points.

  double get _scale => widget.imageRect.width / widget.pageWidth;

  Offset _toPage(Offset local) => Offset(
    (local.dx - widget.imageRect.left) / _scale,
    (local.dy - widget.imageRect.top) / _scale,
  );

  Rect _toLayer(Rect box) => Rect.fromLTRB(
    widget.imageRect.left + box.left * _scale,
    widget.imageRect.top + box.top * _scale,
    widget.imageRect.left + box.right * _scale,
    widget.imageRect.top + box.bottom * _scale,
  );

  List<Rect> _rectsOf(DjvuTextRange range) {
    final layer = widget.layer;
    if (layer == null) return const [];
    return [for (final box in layer.boxesOf(range)) _toLayer(box)];
  }

  Rect? _boundsOf(DjvuTextRange range) {
    final rects = _rectsOf(range);
    if (rects.isEmpty) return null;
    return rects.reduce((a, b) => a.expandToInclude(b));
  }

  Rect? _viewportRectOf(DjvuTextRange range) {
    final bounds = _boundsOf(range);
    final box = context.findRenderObject();
    if (bounds == null || box is! RenderBox) return null;
    return FixedPagesViewportScope.fractionsOf(context, bounds, box);
  }

  // Long press: select the word under the finger and drag over the text.

  void _onLongPressStart(LongPressStartDetails details) {
    final layer = widget.layer;
    if (layer == null) return;
    final point = _toPage(details.localPosition);
    final word = layer.wordAtPoint(point.dx, point.dy);
    if (word == null) return;
    _anchorStart = word.start;
    _anchorEnd = word.end;
    _drag = _Drag.selecting;
    _setAdjusting(true);
    _selection.start(widget.page, word);
    widget.controller.lockInput(true);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    _extendTo(details.localPosition);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _endDrag();
  }

  void _onLongPressCancel() {
    if (_drag == _Drag.selecting) _endDrag();
  }

  void _extendTo(Offset local) {
    final layer = widget.layer;
    if (_drag == null || layer == null || !_hasSelectionHere) return;
    final point = _toPage(local);
    final word = layer.wordAtPoint(point.dx, point.dy);
    if (word == null) return;
    final index = word.start;
    final current = _selection.range!;
    final range = switch (_drag!) {
      _Drag.selecting =>
        index < _anchorStart!
            ? DjvuTextRange(word.start, _anchorEnd!)
            : DjvuTextRange(_anchorStart!, word.end),
      _Drag.startHandle =>
        index < current.end
            ? DjvuTextRange(word.start, current.end)
            : DjvuTextRange(layer.wordAt(current.end - 1)!.start, word.end),
      _Drag.endHandle =>
        word.end > current.start
            ? DjvuTextRange(current.start, word.end)
            : DjvuTextRange(word.start, layer.wordAt(current.start)!.end),
    };
    _selection.update(range);
  }

  void _endDrag() {
    if (_drag == null || !_hasSelectionHere) return;
    _drag = null;
    repaint();
    final range = _selection.range!;
    widget.onSelectionChanged?.call(range, _viewportRectOf(range));
    _setAdjusting(false);
  }

  // After release: a drag from a handle moves that end, a tap outside
  // clears. The nearer handle takes a touch where their targets overlap.

  void _onPanDown(DragDownDetails details) {
    _drag = null;
    if (!_hasSelectionHere) return;
    final rects = _rectsOf(_selection.range!);
    if (rects.isEmpty) return;
    final radius =
        DjvuTextOverlay.handleTarget / 2 / widget.controller.zoomScale;
    final start = (details.localPosition - rects.first.bottomLeft).distance;
    final end = (details.localPosition - rects.last.bottomRight).distance;
    if (start > radius && end > radius) return;
    _drag = start <= end ? _Drag.startHandle : _Drag.endHandle;
    _setAdjusting(true);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _extendTo(details.localPosition);
  }

  void _onPanEnd(DragEndDetails details) {
    _endDrag();
  }

  void _onPanCancel() {
    if (_drag == _Drag.startHandle || _drag == _Drag.endHandle) _endDrag();
  }

  void _onTapUp(TapUpDetails details) {
    if (!_hasSelectionHere) return;
    final bounds = _boundsOf(_selection.range!);
    if (bounds != null && bounds.contains(details.localPosition)) return;
    _selection.clear();
    widget.controller.lockInput(false);
    widget.onSelectionCleared?.call();
  }

  void _onHighlightTap(DjvuTextHighlight highlight) {
    widget.onHighlightPressed?.call(
      highlight,
      _viewportRectOf(highlight.range),
    );
  }

  NativeSelectionSnapshot? _nativeSnapshot() {
    final layer = widget.layer;
    if (!_hasSelectionHere || layer == null || _drag == _Drag.selecting) {
      return null;
    }
    final key = (layer, widget.imageRect);
    final accent =
        widget.handleColor ??
        DjvuTextSelection.defaultColor.withValues(alpha: 1);
    final style = (_selection.color, accent);
    if (_nativeStyle != style) {
      _nativeStyle = style;
      _nativeRevision++;
    }
    if (_nativeGeometryKey != key) {
      _nativeGeometryKey = key;
      _nativeRevision++;
      _nativeBoxes = List.unmodifiable([
        for (final word in layer.words)
          if (!word.box.isEmpty)
            NativeTextBox(
              start: word.start,
              end: word.end,
              rect: _toLayer(word.box),
              direction: textCellIsRtl(word.text) == true
                  ? TextDirection.rtl
                  : TextDirection.ltr,
            ),
      ]);
    }
    final range = _selection.range!;
    return NativeSelectionSnapshot(
      revision: _nativeRevision,
      text: layer.text,
      boxes: _nativeBoxes,
      selection: TextSelection(
        baseOffset: range.start,
        extentOffset: range.end,
      ),
      accent: accent,
      selectionColor: _selection.color,
    );
  }

  void _onNativeSelection(TextSelection? selection) {
    final layer = widget.layer;
    if (selection == null || selection.isCollapsed || layer == null) {
      _selection.clear();
      widget.controller.lockInput(false);
      widget.onSelectionCleared?.call();
      return;
    }
    final start = layer.wordAt(selection.start);
    final end = layer.wordAt(selection.end - 1);
    if (start == null || end == null) return;
    final range = DjvuTextRange(start.start, end.end);
    _selection.update(range);
    widget.onSelectionChanged?.call(range, _viewportRectOf(range));
  }

  void _onNativeActive(bool active) {
    if (_nativeActive == active) return;
    _nativeActive = active;
    repaint();
  }

  @override
  Widget build(BuildContext context) {
    final zoomScale = widget.controller.zoomScale;
    final highlights = [
      for (final highlight in widget.highlights)
        if (highlight.page == widget.page) highlight,
    ];
    final selectionRects = _hasSelectionHere
        ? _rectsOf(_selection.range!)
        : const <Rect>[];
    final painter = _TextOverlayPainter(
      highlights: [
        for (final highlight in highlights)
          (rects: _rectsOf(highlight.range), color: highlight.color),
      ],
      searchMark: widget.searchMark == null
          ? const []
          : _rectsOf(widget.searchMark!),
      searchMarkColor: widget.searchMarkColor,
      selection: _nativeActive ? const [] : selectionRects,
      selectionColor: _selection.color,
      handleRadius: DjvuTextOverlay.handleRadius / zoomScale,
    );
    if (!widget.enabled) return CustomPaint(painter: painter);
    final selecting = _hasSelectionHere;
    return NativeSelectionSurface(
      snapshot: _nativeSnapshot(),
      onSelectionChanged: _onNativeSelection,
      onActiveChanged: _onNativeActive,
      onAdjusting: _setAdjusting,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: ComicImageAreaGeometry.longPressDuration,
                ),
                (recognizer) => recognizer
                  ..onLongPressStart = _onLongPressStart
                  ..onLongPressMoveUpdate = _onLongPressMoveUpdate
                  ..onLongPressEnd = _onLongPressEnd
                  ..onLongPressCancel = _onLongPressCancel,
              ),
          // Drags and taps compete with page swipes only while a selection
          // is up: then a drag from a handle and a tap outside belong to it.
          if (selecting && !_nativeActive)
            PanGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                  PanGestureRecognizer.new,
                  (recognizer) => recognizer
                    ..onDown = _onPanDown
                    ..onUpdate = _onPanUpdate
                    ..onEnd = _onPanEnd
                    ..onCancel = _onPanCancel,
                ),
          if (selecting)
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (recognizer) => recognizer..onTapUp = _onTapUp,
                ),
        },
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            CustomPaint(painter: painter, child: const SizedBox.expand()),
            // Saved highlights take taps only where they are drawn.
            if (!selecting)
              for (final highlight in highlights)
                for (final rect in _rectsOf(highlight.range))
                  Positioned.fromRect(
                    rect: rect,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _onHighlightTap(highlight),
                      child: const SizedBox.expand(),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _TextOverlayPainter extends CustomPainter {
  const _TextOverlayPainter({
    required this.highlights,
    required this.searchMark,
    required this.searchMarkColor,
    required this.selection,
    required this.selectionColor,
    required this.handleRadius,
  });

  final List<({List<Rect> rects, Color color})> highlights;
  final List<Rect> searchMark;
  final Color searchMarkColor;
  final List<Rect> selection;
  final Color selectionColor;
  final double handleRadius;

  @override
  void paint(Canvas canvas, Size size) {
    for (final highlight in highlights) {
      final paint = Paint()..color = highlight.color;
      for (final rect in highlight.rects) {
        canvas.drawRect(rect, paint);
      }
    }
    final markPaint = Paint()..color = searchMarkColor;
    for (final rect in searchMark) {
      canvas.drawRect(rect, markPaint);
    }
    if (selection.isEmpty) return;
    final selectionPaint = Paint()..color = selectionColor;
    for (final rect in selection) {
      canvas.drawRect(rect, selectionPaint);
    }
    final knob = Paint()..color = selectionColor.withValues(alpha: 1);
    final bar = Paint()
      ..color = knob.color
      ..strokeWidth = handleRadius / 3;
    final first = selection.first;
    final last = selection.last;
    canvas.drawLine(first.topLeft, first.bottomLeft, bar);
    canvas.drawCircle(first.bottomLeft, handleRadius, knob);
    canvas.drawLine(last.topRight, last.bottomRight, bar);
    canvas.drawCircle(last.bottomRight, handleRadius, knob);
  }

  @override
  bool shouldRepaint(_TextOverlayPainter oldDelegate) =>
      oldDelegate.highlights != highlights ||
      oldDelegate.searchMark != searchMark ||
      oldDelegate.searchMarkColor != searchMarkColor ||
      oldDelegate.selection != selection ||
      oldDelegate.selectionColor != selectionColor ||
      oldDelegate.handleRadius != handleRadius;
}
