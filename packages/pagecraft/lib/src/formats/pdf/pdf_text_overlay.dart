import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoTheme;
import 'package:flutter/cupertino.dart' show cupertinoTextSelectionControls;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:native_text_selection/native_text_selection.dart';

import 'pdf_text_layer.dart';
import '../../fixed_layout/comic_image_area.dart';
import '../../fixed_layout/fixed_pages_controller.dart';
import '../../fixed_layout/fixed_pages_view.dart';
import 'pdf_text_selection.dart';
import '../../fixed_layout/repaint_after_build.dart';

/// Text on one PDF page: saved highlights, the search hit, and the
/// selection with its handles, over the page image.
///
/// Placed by `FixedPagesView.pageOverlayBuilder`, so it is scaled with the
/// page while zoomed; sizes meant in screen pixels are divided by the
/// zoom. A long press (280 ms, as image areas) on a word selects it and
/// drags its end over the text. After release, supported mobile hosts use
/// system controls through [NativeSelectionSurface]. Flutter fallback handles
/// use 48 px targets and move an endpoint by grapheme. A tap outside clears
/// the selection, and a tap on a
/// saved highlight reports it. The page's text
/// comes as a [PdfTextLayer]; until it is loaded the overlay only draws
/// what it is given.
class PdfTextOverlay extends StatefulWidget {
  const PdfTextOverlay({
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
    this.darkPage = false,
    this.enabled = true,
  });

  final int page;

  /// Where the whole page is drawn inside this layer.
  final Rect imageRect;

  /// The page's display size in points, the unit of [PdfTextLayer] boxes.
  final double pageWidth;
  final double pageHeight;

  final FixedPagesController controller;
  final PdfTextSelection selection;
  final PdfTextLayer? layer;

  /// Saved highlights of this page, oldest first.
  final List<PdfTextHighlight> highlights;

  /// The search hit to mark on this page.
  final PdfTextRange? searchMark;
  final Color searchMarkColor;

  /// The selection was made or its end moved and the finger lifted, with
  /// where it sits in the whole view (null outside a `FixedPagesView`).
  final PdfSelectionChanged? onSelectionChanged;

  /// Hides host actions while adjusting, then restores them after the final
  /// [onSelectionChanged] payload. Cancellation keeps the current range.
  final ValueChanged<bool>? onSelectionDragChanged;

  /// Opaque handle accent, independent of highlight preview colours.
  final Color? handleColor;

  /// The rendered page has light ink on dark paper. This describes the page,
  /// independently of the app theme or a highlight's preview colour.
  final bool darkPage;

  /// A tap outside dismissed the selection.
  final VoidCallback? onSelectionCleared;

  /// A tap on a saved highlight, with where it sits in the whole view.
  final PdfHighlightPressed? onHighlightPressed;

  /// False leaves everything drawn but takes no input.
  final bool enabled;

  /// Touch target of a selection handle, in screen pixels.
  static const handleTarget = 48.0;

  @override
  State<PdfTextOverlay> createState() => _PdfTextOverlayState();
}

typedef PdfSelectionChanged =
    void Function(PdfTextRange range, Rect? viewportRect);

typedef PdfHighlightPressed =
    void Function(PdfTextHighlight highlight, Rect? viewportRect);

enum _Drag { selecting, startHandle, endHandle }

class _PdfTextOverlayState extends State<PdfTextOverlay>
    with RepaintAfterBuild {
  _Drag? _drag;
  bool _dragging = false;
  int? _fixedOffset;
  int? _movingOffset;
  Offset _dragOffset = Offset.zero;
  final _magnifier = MagnifierController();
  final _magnifierInfo = ValueNotifier(MagnifierInfo.empty);

  /// The character the press started on; the other end follows the finger.
  int? _anchorStart;
  int? _anchorEnd;
  bool _nativeActive = false;
  (PdfTextLayer, Rect)? _nativeGeometryKey;
  List<NativeTextBox> _nativeBoxes = const [];
  int _nativeRevision = 0;
  (Color, Color, bool)? _nativeStyle;

  PdfTextSelection get _selection => widget.selection;

  bool get _hasSelectionHere =>
      _selection.isActive && _selection.page == widget.page;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(PdfTextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    _selection.removeListener(_onSelectionChanged);
    unawaited(_magnifier.hide());
    _magnifierInfo.dispose();
    if (_dragging) widget.onSelectionDragChanged?.call(false);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!_hasSelectionHere) {
      _drag = null;
      _setDragging(false);
      _nativeGeometryKey = null;
      _nativeBoxes = const [];
    }
    repaint();
  }

  void _setDragging(bool value) {
    if (_dragging == value) return;
    _dragging = value;
    if (!value) unawaited(_magnifier.hide());
    widget.onSelectionDragChanged?.call(value);
  }

  // Coordinates: layer pixels ↔ page points.

  double get _scale => widget.imageRect.width / widget.pageWidth;

  Offset _toPage(Offset local) => Offset(
    (local.dx - widget.imageRect.left) / _scale,
    (local.dy - widget.imageRect.top) / _scale,
  );

  Rect _toLayer(PdfBox box) => Rect.fromLTRB(
    widget.imageRect.left + box.left * _scale,
    widget.imageRect.top + box.top * _scale,
    widget.imageRect.left + box.right * _scale,
    widget.imageRect.top + box.bottom * _scale,
  );

  List<Rect> _rectsOf(PdfTextRange range) {
    final layer = widget.layer;
    if (layer == null) return const [];
    return [for (final box in layer.boxesOf(range)) _toLayer(box)];
  }

  Rect? _boundsOf(PdfTextRange range) {
    final rects = _rectsOf(range);
    if (rects.isEmpty) return null;
    return rects.reduce((a, b) => a.expandToInclude(b));
  }

  Rect? _viewportRectOf(PdfTextRange range) {
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
    _movingOffset = word.end;
    _selection.start(widget.page, word);
    widget.controller.lockInput(true);
    _setDragging(true);
    _updateMagnifier(details.localPosition);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    _extendTo(details.localPosition);
    _updateMagnifier(details.localPosition);
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
    final position = layer.positionAt(point.dx, point.dy);
    if (position == null) return;
    final PdfTextRange range;
    if (_drag == _Drag.selecting) {
      range = PdfTextRange(
        math.min(position, _anchorStart!),
        math.max(position, _anchorEnd!),
      );
      _movingOffset = position < _anchorStart! ? range.start : range.end;
    } else {
      if (position == _fixedOffset) return;
      range = PdfTextRange(
        math.min(position, _fixedOffset!),
        math.max(position, _fixedOffset!),
      );
      _movingOffset = position;
    }
    _selection.update(range);
  }

  void _endDrag() {
    if (_drag == null || !_hasSelectionHere) return;
    _drag = null;
    final range = _selection.range!;
    widget.onSelectionChanged?.call(range, _viewportRectOf(range));
    _setDragging(false);
    repaint();
  }

  // After release: a drag from a handle moves that end, a tap outside
  // clears. The nearer handle takes a touch where their targets overlap.

  void _onPanDown(DragDownDetails details) {
    _drag = null;
    if (!_hasSelectionHere) return;
    final layer = widget.layer;
    final range = _selection.range!;
    final startCaret = layer?.caretAt(range.start);
    final endCaret = layer?.caretAt(range.end, upstream: true);
    if (startCaret == null || endCaret == null) return;
    final local = _localPosition(details.globalPosition);
    final start = _handleGeometry(startCaret, true);
    final end = _handleGeometry(endCaret, false);
    final nearStart = start.target.contains(local);
    final nearEnd = end.target.contains(local);
    if (!nearStart && !nearEnd) return;
    final useStart =
        nearStart &&
        (!nearEnd ||
            (local - start.glyph.center).distance <=
                (local - end.glyph.center).distance);
    _drag = useStart ? _Drag.startHandle : _Drag.endHandle;
    _fixedOffset = useStart ? range.end : range.start;
    _movingOffset = useStart ? range.start : range.end;
    final caret = useStart ? startCaret : endCaret;
    _dragOffset = local - _toLayer(caret.box).center;
  }

  Offset _localPosition(Offset global) =>
      (context.findRenderObject()! as RenderBox).globalToLocal(global);

  bool _canLongPressAt(Offset global) {
    if (!_hasSelectionHere) return true;
    final range = _selection.range!;
    final start = widget.layer?.caretAt(range.start);
    final end = widget.layer?.caretAt(range.end, upstream: true);
    final local = _localPosition(global);
    return !(start != null &&
            _handleGeometry(start, true).target.contains(local)) &&
        !(end != null && _handleGeometry(end, false).target.contains(local));
  }

  void _onPanStart(DragStartDetails details) {
    if (_drag == null) return;
    _setDragging(true);
    _updateMagnifier(_localPosition(details.globalPosition));
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_drag == null) return;
    final local = _localPosition(details.globalPosition);
    _extendTo(local - _dragOffset);
    _updateMagnifier(local);
  }

  void _onPanEnd(DragEndDetails details) {
    _endDrag();
  }

  void _onPanCancel() {
    if (_dragging) {
      _endDrag();
    } else {
      _drag = null;
    }
  }

  bool get _cupertino => switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => true,
    _ => false,
  };

  TextSelectionControls get _controls => _cupertino
      ? cupertinoTextSelectionControls
      : materialTextSelectionControls;

  _PdfHandleGeometry _handleGeometry(PdfTextCaret caret, bool start) {
    final rect = _toLayer(caret.box);
    final zoom = widget.controller.zoomScale;
    final height = rect.height * zoom;
    final type = start != caret.isRtl
        ? TextSelectionHandleType.left
        : TextSelectionHandleType.right;
    final size = _controls.getHandleSize(height);
    final anchor = _controls.getHandleAnchor(type, height);
    final glyph = (rect.bottomLeft - anchor / zoom) & (size / zoom);
    return (
      caret: rect,
      glyph: glyph,
      target: Rect.fromCenter(
        center: glyph.center,
        width: math.max(PdfTextOverlay.handleTarget / zoom, glyph.width),
        height: math.max(PdfTextOverlay.handleTarget / zoom, glyph.height),
      ),
      type: type,
      lineHeight: height,
      size: size,
    );
  }

  void _updateMagnifier(Offset local) {
    if (!_dragging || Overlay.maybeOf(context, rootOverlay: true) == null) {
      return;
    }
    final layer = widget.layer;
    final offset = _movingOffset;
    if (layer == null || offset == null) return;
    final caret = layer.caretAt(
      offset,
      upstream: offset == _selection.range?.end,
    );
    if (caret == null) return;
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()!
            as RenderBox;
    final transform = box.getTransformTo(overlay);
    final caretRect = _toLayer(caret.box);
    _magnifierInfo.value = MagnifierInfo(
      globalGesturePosition: MatrixUtils.transformPoint(
        transform,
        Offset(caretRect.center.dx, local.dy),
      ),
      caretRect: MatrixUtils.transformRect(transform, caretRect),
      currentLineBoundaries: MatrixUtils.transformRect(
        transform,
        _toLayer(caret.lineBox),
      ),
      fieldBounds: MatrixUtils.transformRect(transform, Offset.zero & box.size),
    );
    if (_magnifier.shown) return;
    final magnifier = TextMagnifier.adaptiveMagnifierConfiguration
        .magnifierBuilder(context, _magnifier, _magnifierInfo);
    if (magnifier != null) {
      unawaited(_magnifier.show(context: context, builder: (_) => magnifier));
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (!_hasSelectionHere) return;
    final layer = widget.layer;
    final range = _selection.range!;
    final start = layer?.caretAt(range.start);
    final end = layer?.caretAt(range.end, upstream: true);
    if ((start != null &&
            _handleGeometry(
              start,
              true,
            ).target.contains(details.localPosition)) ||
        (end != null &&
            _handleGeometry(
              end,
              false,
            ).target.contains(details.localPosition))) {
      return;
    }
    final bounds = _boundsOf(_selection.range!);
    if (bounds != null && bounds.contains(details.localPosition)) return;
    _selection.clear();
    widget.controller.lockInput(false);
    widget.onSelectionCleared?.call();
  }

  void _onHighlightTap(PdfTextHighlight highlight) {
    widget.onHighlightPressed?.call(
      highlight,
      _viewportRectOf(highlight.range),
    );
  }

  NativeSelectionSnapshot? _nativeSnapshot(Color accent) {
    final layer = widget.layer;
    if (!_hasSelectionHere || layer == null || _drag == _Drag.selecting) {
      return null;
    }
    final key = (layer, widget.imageRect);
    final style = (accent, _selection.color, widget.darkPage);
    if (_nativeStyle != style) {
      _nativeStyle = style;
      _nativeRevision++;
    }
    if (_nativeGeometryKey != key) {
      _nativeGeometryKey = key;
      _nativeRevision++;
      final boxes = <NativeTextBox>[];
      var start = 0;
      for (final character in layer.text.characters) {
        final end = start + character.length;
        Rect? rect;
        for (var index = start; index < end; index++) {
          final box = layer.charBoxes[index];
          if (box.isEmpty) continue;
          final cell = _toLayer(box);
          rect = rect?.expandToInclude(cell) ?? cell;
        }
        if (rect != null && !rect.isEmpty) {
          boxes.add(
            NativeTextBox(
              start: start,
              end: end,
              rect: rect,
              direction: layer.caretAt(start)?.isRtl == true
                  ? TextDirection.rtl
                  : TextDirection.ltr,
            ),
          );
        }
        start = end;
      }
      _nativeBoxes = List.unmodifiable(boxes);
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
    if (selection == null || selection.isCollapsed) {
      _selection.clear();
      widget.controller.lockInput(false);
      widget.onSelectionCleared?.call();
      return;
    }
    final range = PdfTextRange(selection.start, selection.end);
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
    final selecting = _hasSelectionHere;
    final startCaret = selecting
        ? widget.layer?.caretAt(_selection.range!.start)
        : null;
    final endCaret = selecting
        ? widget.layer?.caretAt(_selection.range!.end, upstream: true)
        : null;
    final accent =
        widget.handleColor ?? _selection.baseColor.withValues(alpha: 1);
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
      carets: [
        if (!_nativeActive && startCaret != null) _toLayer(startCaret.box),
        if (!_nativeActive && endCaret != null) _toLayer(endCaret.box),
      ],
      handleColor: accent,
      strokeWidth: 2 / zoomScale,
      darkPage: widget.darkPage,
    );
    if (!widget.enabled) return CustomPaint(painter: painter);
    return NativeSelectionSurface(
      snapshot: _nativeSnapshot(accent),
      onSelectionChanged: _onNativeSelection,
      onActiveChanged: _onNativeActive,
      onAdjusting: _setDragging,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          _PdfLongPressRecognizer:
              GestureRecognizerFactoryWithHandlers<_PdfLongPressRecognizer>(
                () => _PdfLongPressRecognizer(_canLongPressAt),
                (recognizer) => recognizer
                  ..onLongPressStart = _onLongPressStart
                  ..onLongPressMoveUpdate = _onLongPressMoveUpdate
                  ..onLongPressEnd = _onLongPressEnd
                  ..onLongPressCancel = _onLongPressCancel,
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
            if (!_nativeActive && startCaret != null && endCaret != null)
              for (final start in [true, false])
                _PdfSelectionHandle(
                  key: ValueKey(
                    'pdf-selection-${start ? 'start' : 'end'}-handle-${widget.page}',
                  ),
                  geometry: _handleGeometry(
                    start ? startCaret : endCaret,
                    start,
                  ),
                  controls: _controls,
                  color: accent,
                  onPanDown: _onPanDown,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  onPanCancel: _onPanCancel,
                ),
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

class _PdfLongPressRecognizer extends LongPressGestureRecognizer {
  _PdfLongPressRecognizer(this.canStart)
    : super(duration: ComicImageAreaGeometry.longPressDuration);

  final bool Function(Offset global) canStart;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      canStart(event.position) && super.isPointerAllowed(event);
}

typedef _PdfHandleGeometry = ({
  Rect caret,
  Rect glyph,
  Rect target,
  TextSelectionHandleType type,
  double lineHeight,
  Size size,
});

class _PdfSelectionHandle extends StatelessWidget {
  const _PdfSelectionHandle({
    super.key,
    required this.geometry,
    required this.controls,
    required this.color,
    required this.onPanDown,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
  });

  final _PdfHandleGeometry geometry;
  final TextSelectionControls controls;
  final Color color;
  final GestureDragDownCallback onPanDown;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final GestureDragCancelCallback onPanCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: geometry.target,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          PanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                PanGestureRecognizer.new,
                (recognizer) => recognizer
                  // A grip already identifies the intended control. Activate
                  // after 6 screen pixels, rather than a page-pan-sized drag.
                  ..gestureSettings = const DeviceGestureSettings(touchSlop: 3)
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onDown = onPanDown
                  ..onStart = onPanStart
                  ..onUpdate = onPanUpdate
                  ..onEnd = onPanEnd
                  ..onCancel = onPanCancel,
              ),
        },
        child: TextSelectionTheme(
          data: TextSelectionThemeData(selectionHandleColor: color),
          child: CupertinoTheme(
            data: CupertinoTheme.of(
              context,
            ).copyWith(selectionHandleColor: color),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fromRect(
                  rect: geometry.glyph.shift(-geometry.target.topLeft),
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox.fromSize(
                      size: geometry.size,
                      child: Builder(
                        builder: (context) => controls.buildHandle(
                          context,
                          geometry.type,
                          geometry.lineHeight,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    required this.carets,
    required this.handleColor,
    required this.strokeWidth,
    required this.darkPage,
  });

  final List<({List<Rect> rects, Color color})> highlights;
  final List<Rect> searchMark;
  final Color searchMarkColor;
  final List<Rect> selection;
  final Color selectionColor;
  final List<Rect> carets;
  final Color handleColor;
  final double strokeWidth;
  final bool darkPage;

  Paint _markerPaint(Color color, {double maximumDarkAlpha = .60}) => Paint()
    ..color = darkPage && color.a > maximumDarkAlpha
        ? color.withValues(alpha: maximumDarkAlpha)
        : color
    ..blendMode = darkPage ? BlendMode.lighten : BlendMode.multiply;

  @override
  void paint(Canvas canvas, Size size) {
    for (final highlight in highlights) {
      // Blend with the rendered ink instead of covering the page's glyphs.
      final paint = _markerPaint(highlight.color);
      for (final rect in highlight.rects) {
        canvas.drawRect(rect, paint);
      }
    }
    // Search defaults to bright amber rather than a dark-theme marker colour.
    final markPaint = _markerPaint(searchMarkColor, maximumDarkAlpha: .20);
    for (final rect in searchMark) {
      canvas.drawRect(rect, markPaint);
    }
    if (selection.isEmpty) return;
    final selectionPaint = _markerPaint(selectionColor);
    for (final rect in selection) {
      canvas.drawRect(rect, selectionPaint);
    }
    final bar = Paint()
      ..color = handleColor.withValues(alpha: 1)
      ..strokeWidth = strokeWidth;
    for (final caret in carets) {
      canvas.drawLine(caret.topLeft, caret.bottomLeft, bar);
    }
  }

  @override
  bool shouldRepaint(_TextOverlayPainter oldDelegate) =>
      oldDelegate.highlights != highlights ||
      oldDelegate.searchMark != searchMark ||
      oldDelegate.searchMarkColor != searchMarkColor ||
      oldDelegate.selection != selection ||
      oldDelegate.selectionColor != selectionColor ||
      oldDelegate.carets != carets ||
      oldDelegate.handleColor != handleColor ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.darkPage != darkPage;
}
