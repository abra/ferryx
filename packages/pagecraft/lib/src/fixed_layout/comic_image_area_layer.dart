import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'fixed_pages_controller.dart';
import 'comic_image_area.dart';
import 'fixed_pages_view.dart';
import 'repaint_after_build.dart';

/// Saved image areas and the selection draft over one page image.
///
/// Placed by `FixedPagesView.pageOverlayBuilder`, so it is scaled with the
/// page while zoomed; sizes meant in screen pixels are divided by the zoom.
/// A long press starts a draft at the finger and drags it; afterwards a
/// drag inside moves it, a drag from a corner zone resizes it, a tap
/// outside cancels it unless the draft is retained. A long press on a
/// saved area reports that area instead.
class ComicImageAreaLayer extends StatefulWidget {
  const ComicImageAreaLayer({
    super.key,
    required this.page,
    required this.imageRect,
    required this.controller,
    required this.draft,
    this.areas = const [],
    this.onDraftCommitted,
    this.onDraftCancelled,
    this.onDraftAdjustmentChanged,
    this.onAreaPressed,
    this.enabled = true,
  });

  final int page;

  /// Where the image is drawn inside this layer.
  final Rect imageRect;

  final FixedPagesController controller;
  final ComicImageAreaDraft draft;

  /// Saved areas of this page, oldest first; later ones are drawn and hit
  /// on top.
  final List<ComicImageArea> areas;

  /// The draft was created, moved or resized and the finger lifted.
  /// The second argument is where it sits in the whole view, for chrome
  /// that must keep clear of it; null outside a `FixedPagesView`.
  final ComicDraftCommitted? onDraftCommitted;

  /// A tap outside dismissed the draft.
  final VoidCallback? onDraftCancelled;

  /// Whether the primary pointer is moving or resizing the draft. The final
  /// rectangle is committed before this changes back to false.
  final ValueChanged<bool>? onDraftAdjustmentChanged;

  /// A long press on a saved area, with where the area sits in the whole
  /// view (null outside a `FixedPagesView`).
  final ComicAreaPressed? onAreaPressed;

  /// False leaves the areas drawn but takes no input (text pages).
  final bool enabled;

  @override
  State<ComicImageAreaLayer> createState() => _ComicImageAreaLayerState();
}

/// A committed draft: its rectangle in fractions of the image and, when
/// the layer sits in a `FixedPagesView`, in fractions of the view.
typedef ComicDraftCommitted = void Function(Rect rect, Rect? viewportRect);

/// A pressed saved area and where it sits in the whole view.
typedef ComicAreaPressed =
    void Function(ComicImageArea area, Rect? viewportRect);

class _ComicImageAreaLayerState extends State<ComicImageAreaLayer>
    with RepaintAfterBuild {
  _Edit? _edit;
  bool _adjusting = false;
  bool _longPressEditing = false;
  final _pointers = <int>{};

  ComicImageAreaDraft get _draft => widget.draft;

  bool get _hasDraftHere => _draft.isActive && _draft.page == widget.page;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_onDraftChanged);
  }

  @override
  void didUpdateWidget(ComicImageAreaLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft ||
        oldWidget.page != widget.page ||
        (oldWidget.enabled && !widget.enabled)) {
      _edit = null;
      _longPressEditing = false;
      if (_adjusting) {
        _adjusting = false;
        oldWidget.onDraftAdjustmentChanged?.call(false);
      }
      for (final pointer in _pointers) {
        oldWidget.draft.untrackPointer(pointer);
      }
      _pointers.clear();
    }
    if (oldWidget.draft != widget.draft) {
      oldWidget.draft.removeListener(_onDraftChanged);
      widget.draft.addListener(_onDraftChanged);
    }
  }

  @override
  void dispose() {
    _draft.removeListener(_onDraftChanged);
    _finishEdit(commit: false);
    for (final pointer in _pointers) {
      _draft.untrackPointer(pointer);
    }
    super.dispose();
  }

  void _onDraftChanged() {
    if (!_hasDraftHere) _finishEdit(commit: false);
    repaint();
  }

  void _onPointerDown(PointerEvent event) {
    _pointers.add(event.pointer);
    _draft.trackPointer(event.pointer);
  }

  void _onPointerEnd(PointerEvent event) {
    if (_draft.isPrimaryPointer(event.pointer)) _finishEdit();
    _pointers.remove(event.pointer);
    _draft.untrackPointer(event.pointer);
  }

  void _setAdjusting(bool value) {
    if (_adjusting == value) return;
    _adjusting = value;
    widget.onDraftAdjustmentChanged?.call(value);
  }

  // Coordinates.

  Offset _toImage(Offset local) => Offset(
    (local.dx - widget.imageRect.left) / widget.imageRect.width,
    (local.dy - widget.imageRect.top) / widget.imageRect.height,
  );

  Offset _deltaToImage(Offset delta) => Offset(
    delta.dx / widget.imageRect.width,
    delta.dy / widget.imageRect.height,
  );

  Rect _toLayer(Rect rect) => Rect.fromLTWH(
    widget.imageRect.left + rect.left * widget.imageRect.width,
    widget.imageRect.top + rect.top * widget.imageRect.height,
    rect.width * widget.imageRect.width,
    rect.height * widget.imageRect.height,
  );

  Rect? get _layerBounds {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? Offset.zero & box.size : null;
  }

  // Long press: a new draft, or a saved area.

  void _onLongPressStart(LongPressStartDetails details) {
    if (_hasDraftHere) {
      _longPressEditing = true;
      _edit = _editAt(details.localPosition);
      if (_edit != null) _setAdjusting(true);
      return;
    }
    if (_draft.isActive) return;
    final point = _toImage(details.localPosition);
    if (point.dx < 0 || point.dx > 1 || point.dy < 0 || point.dy > 1) return;
    final area = ComicImageAreaGeometry.areaAt(point, [
      for (final area in widget.areas)
        if (area.page == widget.page) area,
    ]);
    if (area != null) {
      widget.onAreaPressed?.call(area, _viewportRectOf(area.rect));
      return;
    }
    final rect = ComicImageAreaGeometry.draftAt(point);
    _longPressEditing = true;
    _setAdjusting(true);
    _draft.start(widget.page, rect);
    widget.controller.lockInput(true);
    _edit = _Edit(
      mode: _EditMode.move,
      start: details.localPosition,
      startRect: rect,
    );
    _commit(rect);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    _updateEdit(details.localPosition);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _finishEdit();
  }

  void _onLongPressCancel() {
    if (_longPressEditing) _finishEdit();
  }

  // After release: move from inside, resize from a corner, cancel outside.

  void _onPanDown(DragDownDetails details) {
    if (!_hasDraftHere) return;
    _edit = _editAt(details.localPosition);
  }

  _Edit? _editAt(Offset point) {
    final drawn = _toLayer(_draft.rect!);
    final handle = ComicImageAreaGeometry.handleAt(
      point,
      drawn,
      widget.controller.zoomScale,
      bounds: _layerBounds,
    );
    if (handle != null) {
      return _Edit(
        mode: _EditMode.resize,
        handle: handle,
        start: point,
        startRect: _draft.rect!,
      );
    } else if (drawn.contains(point)) {
      return _Edit(
        mode: _EditMode.move,
        start: point,
        startRect: _draft.rect!,
      );
    }
    return null;
  }

  void _onPanStart(DragStartDetails details) {
    if (_edit != null && _hasDraftHere) _setAdjusting(true);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _updateEdit(details.localPosition);
  }

  void _onPanEnd(DragEndDetails details) {
    _finishEdit();
  }

  void _onPanCancel() {
    if (!_longPressEditing) _finishEdit();
  }

  void _onTapUp(TapUpDetails details) {
    if (!_draft.isActive || _draft.hasMultiplePointers) return;
    if (_hasDraftHere &&
        (_toLayer(_draft.rect!).contains(details.localPosition) ||
            ComicImageAreaGeometry.handleAt(
                  details.localPosition,
                  _toLayer(_draft.rect!),
                  widget.controller.zoomScale,
                  bounds: _layerBounds,
                ) !=
                null)) {
      return;
    }
    if (_draft.retained) return;
    _draft.clear();
    widget.controller.lockInput(false);
    widget.onDraftCancelled?.call();
  }

  void _updateEdit(Offset local) {
    final edit = _edit;
    if (edit == null || !_hasDraftHere) return;
    final delta = _deltaToImage(local - edit.start);
    final rect = switch (edit.mode) {
      _EditMode.move => ComicImageAreaGeometry.move(edit.startRect, delta),
      _EditMode.resize => ComicImageAreaGeometry.resize(
        edit.startRect,
        edit.handle!,
        delta,
      ),
    };
    _draft.update(rect);
  }

  void _finishEdit({bool commit = true}) {
    final rect = commit && _adjusting && _hasDraftHere ? _draft.rect : null;
    _edit = null;
    _longPressEditing = false;
    if (rect != null) _commit(rect);
    _setAdjusting(false);
  }

  void _commit(Rect rect) {
    widget.onDraftCommitted?.call(rect, _viewportRectOf(rect));
  }

  Rect? _viewportRectOf(Rect rect) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return null;
    return FixedPagesViewportScope.fractionsOf(context, _toLayer(rect), box);
  }

  @override
  Widget build(BuildContext context) {
    final zoomScale = widget.controller.zoomScale;
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    final painter = _ImageAreaPainter(
      imageRect: widget.imageRect,
      areas: [
        for (final area in widget.areas)
          if (area.page == widget.page) area,
      ],
      draft: _hasDraftHere ? _draft.rect : null,
      hasDraft: _draft.isActive,
      draftColor: _draft.color,
      draftOpacity: _draft.opacity,
      zoomScale: zoomScale,
    );
    if (!widget.enabled) return CustomPaint(painter: painter);
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        _AreaLongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _AreaLongPressGestureRecognizer
            >(
              _AreaLongPressGestureRecognizer.new,
              (recognizer) {
                recognizer.canTrackPointer = (pointer) =>
                    _draft.isPrimaryPointer(pointer) &&
                    (!_draft.isActive || _hasDraftHere);
                recognizer.canStart = () =>
                    _hasDraftHere || !_draft.hasMultiplePointers;
                recognizer
                  ..gestureSettings = gestureSettings
                  ..onLongPressStart = _onLongPressStart
                  ..onLongPressMoveUpdate = _onLongPressMoveUpdate
                  ..onLongPressEnd = _onLongPressEnd
                  ..onLongPressCancel = _onLongPressCancel;
              },
            ),
        // Keep instances stable when a long press creates/clears a draft.
        // Before selection, the filters never enter the page-swipe arena.
        _AreaPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_AreaPanGestureRecognizer>(
              _AreaPanGestureRecognizer.new,
              (recognizer) {
                recognizer.canTrackPointer = (pointer) =>
                    _hasDraftHere && _draft.isPrimaryPointer(pointer);
                recognizer
                  ..gestureSettings = gestureSettings
                  ..onDown = _onPanDown
                  ..onStart = _onPanStart
                  ..onUpdate = _onPanUpdate
                  ..onEnd = _onPanEnd
                  ..onCancel = _onPanCancel;
              },
            ),
        _AreaTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_AreaTapGestureRecognizer>(
              _AreaTapGestureRecognizer.new,
              (recognizer) {
                recognizer.canTrackPointer = (pointer) =>
                    _draft.isActive && _draft.isPrimaryPointer(pointer);
                recognizer
                  ..gestureSettings = gestureSettings
                  ..onTapUp = _onTapUp;
              },
            ),
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerEnd,
        onPointerCancel: _onPointerEnd,
        onPointerPanZoomStart: _onPointerDown,
        onPointerPanZoomEnd: _onPointerEnd,
        child: CustomPaint(painter: painter, child: const SizedBox.expand()),
      ),
    );
  }
}

/// Extra fingers never join or reject the primary pointer's gesture arena.
mixin _AreaPointerFilter on OneSequenceGestureRecognizer {
  late bool Function(int pointer) canTrackPointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (canTrackPointer(event.pointer)) super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    if (canTrackPointer(event.pointer)) super.addAllowedPointerPanZoom(event);
  }

  @override
  void handleNonAllowedPointer(PointerDownEvent event) {
    // A second button/device must not reject the primary edit's arena.
  }
}

class _AreaLongPressGestureRecognizer extends LongPressGestureRecognizer
    with _AreaPointerFilter {
  _AreaLongPressGestureRecognizer()
    : super(duration: ComicImageAreaGeometry.longPressDuration);

  late bool Function() canStart;

  @override
  void didExceedDeadline() {
    if (!canStart()) {
      resolve(GestureDisposition.rejected);
      return;
    }
    super.didExceedDeadline();
  }
}

class _AreaPanGestureRecognizer extends PanGestureRecognizer
    with _AreaPointerFilter {
  _AreaPanGestureRecognizer() {
    dragStartBehavior = DragStartBehavior.down;
  }
}

class _AreaTapGestureRecognizer extends TapGestureRecognizer
    with _AreaPointerFilter {}

enum _EditMode { move, resize }

class _Edit {
  _Edit({
    required this.mode,
    required this.start,
    required this.startRect,
    this.handle,
  });

  final _EditMode mode;
  final ComicAreaHandle? handle;
  final Offset start;
  final Rect startRect;
}

class _ImageAreaPainter extends CustomPainter {
  _ImageAreaPainter({
    required this.imageRect,
    required this.areas,
    required this.draft,
    required this.hasDraft,
    required this.draftColor,
    required this.draftOpacity,
    required this.zoomScale,
  });

  final Rect imageRect;
  final List<ComicImageArea> areas;
  final Rect? draft;
  // Other pages in a spread dim while the shared draft is active.
  final bool hasDraft;
  final Color draftColor;
  final double draftOpacity;
  final double zoomScale;

  Rect _toLayer(Rect rect) => Rect.fromLTWH(
    imageRect.left + rect.left * imageRect.width,
    imageRect.top + rect.top * imageRect.height,
    rect.width * imageRect.width,
    rect.height * imageRect.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(imageRect);
    for (final area in areas) {
      canvas.drawRect(
        _toLayer(area.rect),
        Paint()
          ..color = area.color.withValues(alpha: 0.90)
          ..blendMode = BlendMode.multiply,
      );
    }
    final draft = this.draft;
    if (hasDraft) {
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(imageRect);
      if (draft != null) outside.addRect(_toLayer(draft));
      canvas.drawPath(
        outside,
        Paint()
          ..color = const Color(0xFF000000).withValues(
            alpha: (draftOpacity * 2).clamp(0.0, .65),
          ),
      );
    }
    if (draft != null) {
      _paintDraft(canvas, _toLayer(draft));
    }
    canvas.restore();
  }

  void _paintDraft(Canvas canvas, Rect drawn) {
    final leg = ComicImageAreaGeometry.gripLegLength(drawn.size, zoomScale);
    final gripCenters = ComicImageAreaGeometry.gripCenters(drawn, zoomScale);
    final markLength = math.min(20 / zoomScale, leg * .44);
    final corners = Path();
    final marks = Path();
    for (final (dx, dy) in const [(1, 1), (-1, 1), (1, -1), (-1, -1)]) {
      final corner = Offset(
        dx > 0 ? drawn.left : drawn.right,
        dy > 0 ? drawn.top : drawn.bottom,
      );
      corners
        ..moveTo(corner.dx, corner.dy)
        ..lineTo(corner.dx + dx * leg, corner.dy)
        ..lineTo(corner.dx, corner.dy + dy * leg)
        ..close();
      final gripCenter = Offset(
        dx > 0 ? gripCenters.left : gripCenters.right,
        dy > 0 ? gripCenters.top : gripCenters.bottom,
      );
      final axis = Offset(dx.toDouble(), dy.toDouble()) / math.sqrt2;
      final normal = Offset(-axis.dy, axis.dx);
      var first = true;
      for (final (x, y) in const [
        (-.5, 0.0),
        (-.28, -.22),
        (-.28, -.06),
        (.28, -.06),
        (.28, -.22),
        (.5, 0.0),
        (.28, .22),
        (.28, .06),
        (-.28, .06),
        (-.28, .22),
      ]) {
        final point =
            gripCenter + axis * (x * markLength) + normal * (y * markLength);
        if (first) {
          marks.moveTo(point.dx, point.dy);
          first = false;
        } else {
          marks.lineTo(point.dx, point.dy);
        }
      }
      marks.close();
    }
    // Resize controls keep their contrast over artwork; only the grips fade slightly.
    final centre = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(drawn)
      ..addPath(corners, Offset.zero);
    canvas.drawPath(
      centre,
      Paint()..color = draftColor.withValues(alpha: draftOpacity),
    );
    final controlOpacity = (draftOpacity * 3).clamp(0.0, 1.0);
    canvas.drawPath(
      corners,
      Paint()
        ..color = const Color(
          0xFF2563EB,
        ).withValues(alpha: controlOpacity * .85),
    );
    canvas.drawPath(
      marks,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: controlOpacity),
    );
  }

  @override
  bool shouldRepaint(_ImageAreaPainter oldDelegate) =>
      oldDelegate.imageRect != imageRect ||
      oldDelegate.draft != draft ||
      oldDelegate.hasDraft != hasDraft ||
      oldDelegate.draftColor != draftColor ||
      oldDelegate.draftOpacity != draftOpacity ||
      oldDelegate.zoomScale != zoomScale ||
      !_sameAreas(oldDelegate.areas, areas);

  static bool _sameAreas(List<ComicImageArea> a, List<ComicImageArea> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
