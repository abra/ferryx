import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show SelectionEdgeUpdateEvent, SelectionHandler;
import 'package:flutter/scheduler.dart';
import 'package:native_text_selection/native_text_selection.dart';

import '../document/text_point.dart';
import '../layout/book_image_cache.dart';
import '../layout/column_scroller.dart';
import '../layout/text_page.dart';
import '../layout/text_page_highlights.dart';
import '../page_turn/page_turn_animation.dart';
import '../page_turn/page_turn_decoration.dart';
import '../page_turn/page_turn_frame.dart';
import '../page_turn/page_turn_layer.dart';
import 'text_book_layout.dart';
import 'text_page_geometry.dart';
import 'text_native_selection.dart';
import 'scroller_gestures.dart';
import 'text_pages_controller.dart';
import 'text_selection_details.dart';

/// A tap on a link: the section it is in and its `<a>` element.
typedef TextLinkTapCallback =
    void Function(TextSectionLayout section, int link);

/// A tap on a highlight, with where it is drawn in the view.
typedef TextHighlightTapCallback =
    void Function(TextHighlight highlight, Rect rect);

/// The highlights to draw on section [section]'s pages.
typedef TextHighlightsOf = List<TextHighlight> Function(int section);

/// What is selected on the spread shown: its document range in
/// [section], the text as shown, and the box around it in the view.
class TextPagesSelection {
  const TextPagesSelection({
    required this.section,
    required this.range,
    required this.text,
    required this.bounds,
  });

  final TextSectionLayout section;
  final TextPointRange range;
  final String text;
  final Rect? bounds;
}

/// The pages of a text book: the spread [controller] shows, turned by
/// swipes along [axis] (the neighbour follows the finger) or by
/// the controller (animated unless [animateTurns] is false or the
/// platform asks for reduced motion). [pageTurnAnimation] selects the visual
/// transition independently of the axis and pagination.
///
/// Taps go to a link under them ([onLinkTap]), then a highlight
/// ([onHighlightTap]), then [onTap] as fractions of the view, which the
/// reader maps to its tap zones. With [selectable], the spread shown is a
/// selection area. Native iOS/Android controls adjust its geometry when the
/// platform adapter accepts it; other hosts retain Flutter controls.
///
/// A selection follows the reader through the section, as it did in the
/// WebView reader: a turn by one spread (a swipe, the controller, or a
/// tap [onSelectionTap] turns into) keeps the selection's boundary behind
/// the reader and takes its other edge onto the new spread, to the end
/// of its first line (or, turning back, the start of its last line).
/// Turning back toward that boundary takes the spread whole, and on the
/// boundary's own spread the selection ends at it. Moving the edge at the
/// spread's side leaves the spread's part alone selected. Any other tap,
/// or a jump, clears the selection. [onSelectionAdjusting] is true while
/// the page moves under a selection.
///
/// A table wider than the page scrolls sideways under a horizontal
/// drag that starts on it, until its edge: a swipe on a table already at
/// its edge that way turns the page.
///
/// [onHighlightRects] hears where highlight [trackedHighlight] is drawn
/// on the spread shown, in the view, after each frame that moves it.
class TextPagesView extends StatefulWidget {
  const TextPagesView({
    super.key,
    required this.controller,
    this.axis = Axis.horizontal,
    this.pageTurnAnimation = PageTurnAnimation.cover,
    this.animateTurns = true,
    this.turnDuration = const Duration(milliseconds: 250),
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.onTap,
    this.onLinkTap,
    this.onHighlightTap,
    this.highlightsOf,
    this.selectable = true,
    this.selectionControls,
    this.contextMenuBuilder,
    this.onSelectionChanged,
    this.onSelectionTap,
    this.onSelectionAdjusting,
    this.trackedHighlight,
    this.onHighlightRects,
  });

  final TextPagesController controller;
  final Axis axis;
  final PageTurnAnimation pageTurnAnimation;
  final bool animateTurns;
  final Duration turnDuration;
  final Color backgroundColor;
  final ValueChanged<Offset>? onTap;
  final TextLinkTapCallback? onLinkTap;
  final TextHighlightTapCallback? onHighlightTap;
  final TextHighlightsOf? highlightsOf;
  final bool selectable;

  /// Controls for the Flutter fallback; platform-adaptive when null.
  final TextSelectionControls? selectionControls;

  /// Flutter's adaptive toolbar when null.
  /// Native-mode custom actions dismiss it with
  /// [ContextMenuController.removeAny] or clear the selection.
  final SelectableRegionContextMenuBuilder? contextMenuBuilder;
  final ValueChanged<TextPagesSelection?>? onSelectionChanged;

  /// A tap while text is selected, as fractions of the view: true when it
  /// turned the page (the reader's edge zones), which the selection then
  /// follows; otherwise the tap clears the selection.
  final bool Function(Offset point)? onSelectionTap;

  /// True while the page moves under a selection (a swipe, a turn taking
  /// it to another spread), false once it settles or is gone.
  final ValueChanged<bool>? onSelectionAdjusting;
  final String? trackedHighlight;
  final ValueChanged<List<Rect>>? onHighlightRects;

  /// A swipe further than this share of the view, or faster than
  /// [flingVelocity], turns the page.
  static const turnThreshold = 0.25;
  static const flingVelocity = 500.0;

  @override
  State<TextPagesView> createState() => _TextPagesViewState();
}

class _TextPagesViewState extends State<TextPagesView>
    with TickerProviderStateMixin {
  /// Drives [_offset], which runs from -1 to 1: a bounded controller
  /// (0 to 1) would clamp every turn that moves the spread forward to rest
  /// and skip it.
  late final AnimationController _turn = AnimationController.unbounded(
    vsync: this,
  );
  final _selectionKey = GlobalKey<SelectionAreaState>();
  late final _tableDrag = ScrollerDrag(this);

  /// A drag began on a table: whether it scrolls the table is known at
  /// its first move.
  bool _tableDragDecided = false;
  final _columnKeys = <GlobalKey>[];
  Size _viewport = Size.zero;

  /// The spread shown when the last frame was built, and the one an
  /// animated turn leaves.
  TextSpread? _shown;
  TextSpread? _leaving;

  /// Where the shown spread sits along the axis, as a share of the view:
  /// 0 at rest, -1 turned forward out of view.
  double _offset = 0;
  PageTurnAnimation? _activeAnimation;
  double _entrySide = 1;
  bool _dragging = false;

  /// A swipe's turn is being finished: the controller's report of it is
  /// already on screen.
  bool _committing = false;
  int _selectionClears = 0;

  /// What was last reported selected, and its part on the spread shown.
  TextPagesSelection? _selection;
  TextPointRange? _onSpread;

  bool get _hasSelection => _selection != null;

  /// The selection's boundary on a spread the reader turned away from.
  _CarriedSelection? _carry;

  /// A turn took the selection to a spread it has not landed on yet.
  bool _carryPending = false;
  bool _adjusting = false;
  bool _selectionControlsHidden = false;

  /// Fingers down on the pages.
  int _pointers = 0;

  /// The selection area dropped its selection under a finger, which its
  /// tap recognizer does when a gesture of this view wins over it: the
  /// gesture decides whether the selection goes.
  bool _droppedUnderFinger = false;

  /// The selection area is being told what to select.
  bool _selecting = false;

  /// The selection area's own container: where edge events go, and whose
  /// geometry changes whenever the selection does.
  SelectionHandler? _region;

  late final _nativeSelection = TextNativeSelectionController(
    pages: () => _pages,
    viewport: () => context,
    region: () => _region,
    selectionState: () => _selectableRegion,
    contextMenuBuilder: () => widget.contextMenuBuilder,
    onChanged: _syncSelection,
    onClear: _clearSelection,
  );
  bool _nativeAdjusting = false;

  TextPagesController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _nativeSelection.addListener(_onNativeChanged);
    _controller.addListener(_onController);
    _turn
      ..addListener(() => setState(() => _offset = _turn.value))
      ..addStatusListener((status) {
        // A turn by the controller ends: the old spread is gone.
        if (status.isCompleted && _leaving != null && mounted) {
          setState(() {
            _leaving = null;
            _activeAnimation = null;
          });
          _scheduleLanding();
        }
      });
  }

  @override
  void didUpdateWidget(TextPagesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _shown = null;
    }
  }

  /// Where [TextPagesView.trackedHighlight] was last reported.
  List<Rect> _trackedRects = const [];
  bool _trackScheduled = false;

  /// Reports where the tracked highlight is after this frame.
  void _scheduleTracking() {
    if (_trackScheduled || widget.onHighlightRects == null) return;
    _trackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trackScheduled = false;
      if (!mounted) return;
      final rects = _rectsOf(widget.trackedHighlight);
      if (listEquals(rects, _trackedRects)) return;
      _trackedRects = rects;
      widget.onHighlightRects?.call(rects);
    });
  }

  /// Where highlight [id] is drawn on the spread shown, in the view.
  List<Rect> _rectsOf(String? id) {
    final view = context.findRenderObject();
    if (id == null || view is! RenderBox || !view.hasSize) return const [];
    final bounds = _visibleShownRect(view.size);
    return [
      for (final key in _columnKeys)
        if (key.currentContext?.findRenderObject()
            case final RenderTextColumnPage page when page.attached)
          for (final rect in page.highlightRects(id))
            if (MatrixUtils.transformRect(
                  page.getTransformTo(view),
                  rect,
                ).intersect(bounds)
                case final inView when !inView.isEmpty)
              inView,
    ];
  }

  @override
  void dispose() {
    _nativeSelection.dispose();
    _controller.removeListener(_onController);
    _setRegion(null);
    _tableDrag.dispose();
    _turn.dispose();
    super.dispose();
  }

  bool get _reducedMotion =>
      !widget.animateTurns ||
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// The axis direction "forward" moves the spread: left (or right for a
  /// right-to-left book), or up.
  double get _forwardSign =>
      widget.axis == Axis.horizontal && _controller.rtl ? 1 : -1;

  PageTurnFrame get _turnFrame {
    final animation = _activeAnimation ?? widget.pageTurnAnimation;
    final leaving = _leaving;
    if (leaving != null && !leaving.layout.isDisposed) {
      return PageTurnFrame.active(
        animation: animation,
        axis: widget.axis,
        incomingOffset: _offset,
        entrySide: _entrySide,
      );
    }
    final idle = PageTurnFrame.idle(animation: animation, axis: widget.axis);
    if (_offset == 0) return idle;
    final toward = _offset * _forwardSign > 0 ? 1 : -1;
    if (_controller.spreadAt(toward) == null) return idle;
    return PageTurnFrame.active(
      animation: animation,
      axis: widget.axis,
      incomingOffset: _offset - _forwardSign * toward,
      entrySide: -_forwardSign * toward,
    );
  }

  Rect _visibleShownRect(Size size) => _turnFrame.visibleRect(
    _leaving == null ? PageTurnRole.outgoing : PageTurnRole.incoming,
    size,
  );

  void _onController() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // A change during a frame (the tree being torn down): after it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onController());
      return;
    }
    if (_controller.selectionClears != _selectionClears) {
      _selectionClears = _controller.selectionClears;
      if (_hasSelection) _clearSelection();
    }
    final next = _controller.spreadAt(0);
    final previous = _shown;
    final position = _controller.position;
    final turned =
        previous != null &&
        next != null &&
        !_dragging &&
        !_committing &&
        position?.reason == TextRelocationReason.page &&
        !previous.layout.isDisposed &&
        !_reducedMotion &&
        (previous.section != next.section || previous.spread != next.spread);
    setState(() {
      if (turned) {
        final forward =
            next.section > previous.section ||
            (next.section == previous.section && next.spread > previous.spread);
        _leaving = previous;
        _activeAnimation = widget.pageTurnAnimation;
        // The new spread comes in from the side the old one leaves to.
        _entrySide = forward ? -_forwardSign : _forwardSign;
        _turn.value = _entrySide;
        _offset = _turn.value;
        unawaited(
          _turn.animateTo(
            0,
            duration: widget.turnDuration,
            curve: Curves.easeOut,
          ),
        );
      }
      _shown = next;
    });
    if (_hasSelection &&
        (previous?.layout != next?.layout ||
            previous?.spread != next?.spread) &&
        !_carrySelection(previous, next, position?.reason)) {
      _clearSelection();
    }
  }

  // A selection across pages.

  void _setRegion(SelectionHandler? region) {
    if (identical(region, _region)) return;
    _region?.removeListener(_onRegionChanged);
    _region = region;
    region?.addListener(_onRegionChanged);
  }

  void _onRegionChanged() {
    if (!mounted || _carryPending || _selecting || _nativeSelection.selecting) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onRegionChanged());
      return;
    }
    _syncSelection();
  }

  void _setAdjusting(bool value) {
    if (_adjusting == value) return;
    _adjusting = value;
    widget.onSelectionAdjusting?.call(value);
  }

  void _onNativeChanged() {
    if (mounted) setState(() {});
  }

  void _onNativeAdjusting(bool value) {
    _nativeSelection.setAdjusting(value);
    _nativeAdjusting = value;
    _setAdjusting(value);
  }

  SelectableRegionState? get _selectableRegion =>
      _selectionKey.currentState?.selectableRegion;

  void _clearSelection() {
    final had = _hasSelection;
    _carryPending = false;
    _carry = null;
    _selection = null;
    _selectionControlsHidden = false;
    _onSpread = null;
    _selectableRegion?.clearSelection();
    _nativeSelection.refresh();
    _setAdjusting(false);
    if (had) widget.onSelectionChanged?.call(null);
  }

  /// Takes the selection along a turn from [previous] to [next]: false
  /// when it cannot follow (another section, a jump, a new layout).
  bool _carrySelection(
    TextSpread? previous,
    TextSpread? next,
    TextRelocationReason? reason,
  ) {
    final selection = _selection;
    if (selection == null ||
        previous == null ||
        next == null ||
        reason != TextRelocationReason.page ||
        !identical(previous.layout, next.layout) ||
        !identical(selection.section, next.layout) ||
        (next.spread - previous.spread).abs() != 1) {
      return false;
    }
    final forward = next.spread > previous.spread;
    final carry = _carry;
    if (carry != null && identical(carry.layout, next.layout)) {
      carry
        ..forward = forward
        ..spread = null;
    } else {
      // The edge on the side the reader leaves stays.
      _carry = _CarriedSelection(
        next.layout,
        forward ? selection.range.start : selection.range.end,
        forward: forward,
      );
    }
    _droppedUnderFinger = false;
    if (!_carryPending) {
      _carryPending = true;
      _onSpread = null;
      _setAdjusting(true);
      // The pages show another spread: nothing of it is selected yet.
      _selectableRegion?.clearSelection();
    }
    _scheduleLanding();
    return true;
  }

  /// Lands the selection a frame after the spread's pages are built: they
  /// hand their paragraphs to the selection area after the frame they are
  /// built in.
  void _scheduleLanding() {
    if (!_carryPending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_carryPending) return;
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => _landCarry())
        ..scheduleFrame();
    });
  }

  /// Selects the carried selection's part of the spread shown, once the
  /// turn is over.
  void _landCarry() {
    if (!mounted || !_carryPending) return;
    // Scheduled again when the turn settles.
    if (_leaving != null || _dragging || _committing || _offset != 0) return;
    final carry = _carry;
    final shown = _shown;
    final region = _selectableRegion;
    if (carry == null ||
        shown == null ||
        region == null ||
        !identical(carry.layout, shown.layout)) {
      _clearSelection();
      return;
    }
    // The spread whole, to cut down from; with Flutter's selection handles.
    region.selectAll(SelectionChangedCause.toolbar);
    final whole = _spreadSelection()?.range;
    if (whole == null) {
      // Nothing to select here, such as a picture: the selection waits
      // for the next turn, its menu where it can go.
      region.clearSelection();
      _carryPending = false;
      final selection = _selection!;
      widget.onSelectionChanged?.call(
        TextPagesSelection(
          section: selection.section,
          range: selection.range,
          text: selection.text,
          bounds: null,
        ),
      );
      _setAdjusting(false);
      return;
    }
    final doc = carry.layout.prepared.document;
    final pages = _pages.toList();
    final anchor = carry.anchor;
    final forward = carry.forward;
    if (doc.comparePoints(anchor, whole.start) > 0 &&
        doc.comparePoints(anchor, whole.end) < 0) {
      // On the boundary's own spread: from it to the edge the reader came
      // from, this spread's alone.
      for (final page in pages) {
        final at = page.selectionEdgeAt(anchor, isEnd: forward);
        if (at == null) continue;
        _moveEdge(page, at, isEnd: forward);
        break;
      }
      _carry = null;
    } else {
      final away = forward == doc.comparePoints(anchor, whole.start) <= 0;
      if (away) {
        // Into the spread as far as its first (or last) line; the spread
        // whole when the reader turns back toward the boundary.
        for (final page in forward ? pages : pages.reversed) {
          final at = page.lineEdge(isEnd: forward);
          if (at == null) continue;
          _moveEdge(page, at, isEnd: forward);
          break;
        }
      }
      carry.spread = whole;
    }
    if (_spreadSelection() == null) {
      // An edge that missed its text: the spread whole, as it was.
      region.selectAll(SelectionChangedCause.toolbar);
    }
    _carryPending = false;
    _syncSelection();
    // Landed, even when what is reported did not change.
    _setAdjusting(false);
  }

  /// The pages of the spread shown, in document order.
  Iterable<RenderTextColumnPage> get _pages sync* {
    for (final key in _columnKeys) {
      final page = key.currentContext?.findRenderObject();
      if (page is RenderTextColumnPage && page.attached) yield page;
    }
  }

  /// Moves one edge of the selection to [local], a point on [page], as a
  /// handle dragged there would.
  void _moveEdge(
    RenderTextColumnPage page,
    Offset local, {
    required bool isEnd,
  }) {
    final global = page.localToGlobal(local);
    _region?.dispatchSelectionEvent(
      isEnd
          ? SelectionEdgeUpdateEvent.forEnd(globalPosition: global)
          : SelectionEdgeUpdateEvent.forStart(globalPosition: global),
    );
  }

  /// What is selected on the spread shown, alone.
  TextPagesSelection? _spreadSelection() {
    final spread = _shown;
    if (spread == null) return null;
    TextPoint? start;
    TextPoint? end;
    Rect? bounds;
    final texts = <String>[];
    final view = context.findRenderObject();
    for (final page in _pages) {
      final selected = page.selection;
      if (selected == null) continue;
      start ??= selected.start;
      end = selected.end;
      texts.add(selected.text);
      final box = page.selectionBounds;
      if (box != null && view is RenderBox) {
        final inView = MatrixUtils.transformRect(
          page.getTransformTo(view),
          box,
        );
        bounds = bounds == null ? inView : bounds.expandToInclude(inView);
      }
    }
    if (start == null || end == null) return null;
    return TextPagesSelection(
      section: spread.layout,
      range: TextPointRange(start, end),
      text: texts.join('\n'),
      bounds: bounds,
    );
  }

  /// Reports the selection when its part on the spread shown changed.
  void _syncSelection() {
    final onSpread = _spreadSelection();
    if (onSpread == null && _hasSelection && _pointers > 0) {
      _droppedUnderFinger = true;
      return;
    }
    // Selected again under the finger, as a long press does.
    if (onSpread != null) _droppedUnderFinger = false;
    _nativeSelection.refresh(deferred: _pointers > 0 || _carryPending);
    if (onSpread?.range == _onSpread) return;
    _onSpread = onSpread?.range;
    final selection = onSpread == null ? null : _withCarry(onSpread);
    if (selection == null) _carry = null;
    _selection = selection;
    widget.onSelectionChanged?.call(selection);
    if (!_nativeAdjusting) _setAdjusting(false);
  }

  /// [onSpread] with the part the reader turned away from, while the
  /// spread's edge on that side is still selected.
  TextPagesSelection _withCarry(TextPagesSelection onSpread) {
    final carry = _carry;
    final spread = carry?.spread;
    if (carry == null ||
        spread == null ||
        !identical(carry.layout, onSpread.section)) {
      _carry = null;
      return onSpread;
    }
    final doc = onSpread.section.prepared.document;
    final TextPointRange range;
    if (doc.comparePoints(carry.anchor, spread.start) <= 0 &&
        onSpread.range.start == spread.start) {
      range = TextPointRange(carry.anchor, onSpread.range.end);
    } else if (doc.comparePoints(carry.anchor, spread.end) >= 0 &&
        onSpread.range.end == spread.end) {
      range = TextPointRange(onSpread.range.start, carry.anchor);
    } else {
      // That edge moved into the spread: the selection starts over here.
      _carry = null;
      return onSpread;
    }
    return TextPagesSelection(
      section: onSpread.section,
      range: range,
      text: textWithBlockBreaks(onSpread.section.prepared, range),
      bounds: onSpread.bounds,
    );
  }

  double get _extent =>
      widget.axis == Axis.horizontal ? _viewport.width : _viewport.height;

  /// The part of the spread shown that scrolls sideways at [global].
  ColumnScroller? _scrollerAt(Offset global) {
    for (final page in _pages) {
      final local = page.globalToLocal(global);
      if (!(Offset.zero & page.size).contains(local)) continue;
      return page.scrollerAt(local);
    }
    return null;
  }

  void _onTableDragStart(DragStartDetails details) {
    final scroller = _scrollerAt(details.globalPosition);
    if (scroller != null) _tableDrag.start(scroller);
  }

  void _onTableDragUpdate(DragUpdateDetails details) =>
      _tableDrag.update(details.delta.dx);

  void _onTableDragEnd(DragEndDetails details) {
    _tableDrag.end(details.velocity.pixelsPerSecond.dx);
    _keepDroppedSelection();
  }

  void _onPointerDown(PointerDownEvent event) => _pointers++;

  void _onPointerUp(PointerEvent event) {
    if (_pointers > 0) _pointers--;
    // After the gestures this pointer ends have had their say.
    if (_pointers == 0) {
      scheduleMicrotask(_settleDroppedSelection);
      _nativeSelection.refresh();
    }
  }

  /// No gesture of this view kept the selection the area dropped: it is
  /// gone.
  void _settleDroppedSelection() {
    if (!mounted || !_droppedUnderFinger || _pointers > 0) return;
    _droppedUnderFinger = false;
    if (_hasSelection && !_carryPending) _clearSelection();
  }

  /// A gesture that leaves the selection where it is ended: the area
  /// selects it again if it dropped it.
  void _keepDroppedSelection() {
    final range = _onSpread;
    if (!_droppedUnderFinger) return;
    _droppedUnderFinger = false;
    if (range != null && !_carryPending) _reselect(range);
  }

  /// Selects [range] on the spread shown, with Flutter's selection handles.
  void _reselect(TextPointRange range) {
    final region = _selectableRegion;
    if (region == null) return;
    _selectionControlsHidden = false;
    _selecting = true;
    try {
      region.selectAll(SelectionChangedCause.toolbar);
      final pages = _pages.toList();
      for (final (point, isEnd) in [(range.start, false), (range.end, true)]) {
        for (final page in pages) {
          final at = page.selectionEdgeAt(point, isEnd: isEnd);
          if (at == null) continue;
          _moveEdge(page, at, isEnd: isEnd);
          break;
        }
      }
    } finally {
      _selecting = false;
    }
    _syncSelection();
  }

  void _onSwipeStart(DragStartDetails details) {
    _tableDrag.stop();
    final scroller = _scrollerAt(details.globalPosition);
    if (scroller != null) {
      _tableDrag.start(scroller);
      _tableDragDecided = false;
      return;
    }
    _onDragStart(details);
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    final scroller = _tableDrag.scroller;
    if (scroller != null && !_tableDragDecided) {
      _tableDragDecided = true;
      if (!scroller.canScroll(-details.delta.dx)) {
        // The table is at its edge that way: the page turns.
        _tableDrag.stop();
        _onDragStart(
          DragStartDetails(
            globalPosition: details.globalPosition,
            localPosition: details.localPosition,
          ),
        );
      }
    }
    if (_tableDrag.scroller != null) {
      _tableDrag.update(details.delta.dx);
      return;
    }
    _onDragUpdate(details);
  }

  void _onSwipeEnd(DragEndDetails details) {
    if (_tableDrag.scroller != null && !_dragging) {
      _onTableDragEnd(details);
      return;
    }
    unawaited(_onDragEnd(details));
  }

  void _onDragStart(DragStartDetails details) {
    // Let a controller turn settle before interpreting another page drag.
    if (_committing || _leaving != null) return;
    if (_hasSelection) {
      // Handles live in the root overlay, outside the page's clipping region.
      _selectableRegion?.hideToolbar();
      _selectionControlsHidden = true;
      _setAdjusting(true);
    }
    _turn.stop();
    _leaving = null;
    _activeAnimation ??= widget.pageTurnAnimation;
    _dragging = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging || _extent <= 0) return;
    final delta =
        (widget.axis == Axis.horizontal ? details.delta.dx : details.delta.dy) /
        _extent;
    var offset = _offset + delta;
    // Toward a neighbour that is not ready: resist.
    final toward = offset * _forwardSign > 0 ? 1 : -1;
    if (offset != 0 && _controller.spreadAt(toward) == null) {
      offset = _offset + delta * 0.15;
    }
    setState(() => _offset = offset.clamp(-1.0, 1.0));
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (!_dragging) return;
    _dragging = false;
    // Kept, whichever way the swipe goes: it lands on the spread turned
    // to, or comes back with this one.
    final dropped = _droppedUnderFinger;
    _droppedUnderFinger = false;
    final velocity =
        (widget.axis == Axis.horizontal
            ? details.velocity.pixelsPerSecond.dx
            : details.velocity.pixelsPerSecond.dy) *
        _forwardSign;
    final travelled = _offset * _forwardSign;
    final direction =
        travelled > TextPagesView.turnThreshold ||
            velocity > TextPagesView.flingVelocity
        ? 1
        : travelled < -TextPagesView.turnThreshold ||
              velocity < -TextPagesView.flingVelocity
        ? -1
        : 0;
    if (direction != 0 && _controller.spreadAt(direction) != null) {
      _committing = true;
      _turn.value = _offset;
      await _turn.animateTo(
        _forwardSign * direction,
        duration: _reducedMotion
            ? Duration.zero
            : widget.turnDuration * (1 - travelled.abs()).clamp(0.2, 1.0),
        curve: Curves.easeOut,
      );
      final bool turned;
      try {
        turned = direction > 0
            ? await _controller.next()
            : await _controller.previous();
      } finally {
        _committing = false;
      }
      if (!mounted) return;
      _turn.value = 0;
      setState(() {
        _offset = 0;
        _leaving = null;
        if (turned) _shown = _controller.spreadAt(0);
      });
      if (dropped && !_carryPending) {
        // Not turned after all.
        _droppedUnderFinger = true;
        _keepDroppedSelection();
      }
      _settleSelection();
      return;
    }
    _turn.value = _offset;
    await _turn.animateTo(
      0,
      duration: _reducedMotion ? Duration.zero : widget.turnDuration,
      curve: Curves.easeOut,
    );
    if (!mounted) return;
    if (dropped && !_carryPending) {
      _droppedUnderFinger = true;
      _keepDroppedSelection();
    }
    _settleSelection();
  }

  /// After a swipe: the selection lands on the spread turned to, or stays
  /// on the one that came back.
  void _settleSelection() {
    _activeAnimation = null;
    if (_carryPending) {
      _selectionControlsHidden = false;
      _scheduleLanding();
    } else if (_hasSelection) {
      final range = _onSpread;
      if (_selectionControlsHidden && range != null) {
        _reselect(range);
      }
      _setAdjusting(false);
    }
  }

  void _onTapUp(TapUpDetails details) {
    // The tap decides what becomes of a selection.
    _droppedUnderFinger = false;
    if (_hasSelection) {
      final turned =
          !_viewport.isEmpty &&
          (widget.onSelectionTap?.call(_fractionOf(details.localPosition)) ??
              false);
      if (!turned) _clearSelection();
      return;
    }
    final spread = _shown;
    if (spread != null) {
      for (final key in _columnKeys) {
        final page = key.currentContext?.findRenderObject();
        if (page is! RenderTextColumnPage || !page.attached) continue;
        final local = page.globalToLocal(details.globalPosition);
        if (!(Offset.zero & page.size).contains(local)) continue;
        final link = page.linkAt(local);
        if (link != null && widget.onLinkTap != null) {
          widget.onLinkTap!(spread.layout, link);
          return;
        }
        final highlight = page.highlightAt(local);
        if (highlight != null && widget.onHighlightTap != null) {
          final view = context.findRenderObject()! as RenderBox;
          final rects = page.highlightRects(highlight.id);
          final rect = rects.isEmpty
              ? Rect.fromCenter(center: local, width: 1, height: 1)
              : rects.reduce((a, b) => a.expandToInclude(b));
          widget.onHighlightTap!(
            highlight,
            MatrixUtils.transformRect(page.getTransformTo(view), rect),
          );
          return;
        }
      }
    }
    if (_viewport.isEmpty) return;
    widget.onTap?.call(_fractionOf(details.localPosition));
  }

  Offset _fractionOf(Offset local) =>
      Offset(local.dx / _viewport.width, local.dy / _viewport.height);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _scheduleTracking();
      if (_hasSelection) {
        _nativeSelection.refresh(deferred: _pointers > 0 || _carryPending);
      }
      final size = constraints.biggest;
      if (size != _viewport && size.isFinite && !size.isEmpty) {
        _viewport = size;
        final landscape = MediaQuery.maybeSizeOf(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _controller.setViewport(
            size,
            landscape: landscape == null
                ? null
                : landscape.width > landscape.height,
          );
        });
      }
      _shown ??= _controller.spreadAt(0);
      final geometry = _controller.geometry;
      final shown = _shown;
      final children = <Widget>[];
      if (geometry != null && shown != null && geometry.viewport == size) {
        final leaving = _leaving;
        final frame = _turnFrame;
        if (leaving != null && !leaving.layout.isDisposed) {
          children.add(
            _PlacedSpread(
              key: const ValueKey('beside'),
              spread: leaving,
              frame: frame,
              role: PageTurnRole.outgoing,
              view: this,
            ),
          );
        } else if (_offset != 0) {
          final toward = _offset * _forwardSign > 0 ? 1 : -1;
          final neighbour = _controller.spreadAt(toward);
          if (neighbour != null) {
            children.add(
              _PlacedSpread(
                key: const ValueKey('beside'),
                spread: neighbour,
                frame: frame,
                role: PageTurnRole.incoming,
                view: this,
              ),
            );
          }
        }
        // Keyed, so a spread coming in beside it never moves its pages:
        // pages moved in the tree register their text with the selection
        // area again, which reselects where the old edges were on screen.
        children.add(
          _PlacedSpread(
            key: const ValueKey('shown'),
            spread: shown,
            frame: frame,
            role: leaving == null
                ? PageTurnRole.outgoing
                : PageTurnRole.incoming,
            view: this,
            columnKeys: _keysFor(shown.pages.length),
          ),
        );
        if (frame.isActive) {
          children.add(
            Positioned.fill(
              child: PageTurnDecoration(frame: frame),
            ),
          );
        }
      }
      final horizontal = widget.axis == Axis.horizontal;
      // Inside the selection area, so taps and swipes reach this detector
      // before the area's own recognizers; long presses still select.
      Widget pages = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        onHorizontalDragStart: horizontal ? _onSwipeStart : null,
        onHorizontalDragUpdate: horizontal ? _onSwipeUpdate : null,
        onHorizontalDragEnd: horizontal ? _onSwipeEnd : null,
        onVerticalDragStart: horizontal ? null : _onDragStart,
        onVerticalDragUpdate: horizontal ? null : _onDragUpdate,
        onVerticalDragEnd: horizontal ? null : _onDragEnd,
        child: Stack(children: children),
      );
      pages = Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        child: pages,
      );
      if (!horizontal) {
        // Pages turn up and down: sideways drags are the tables' alone.
        pages = RawGestureDetector(
          gestures: {
            ScrollerDragRecognizer:
                GestureRecognizerFactoryWithHandlers<ScrollerDragRecognizer>(
                  () => ScrollerDragRecognizer(
                    scrollerAt: _scrollerAt,
                    debugOwner: this,
                  ),
                  (recognizer) => recognizer
                    ..onStart = _onTableDragStart
                    ..onUpdate = _onTableDragUpdate
                    ..onEnd = _onTableDragEnd,
                ),
          },
          child: pages,
        );
      }
      if (widget.selectable) {
        final nativeActive = _nativeSelection.active;
        pages = SelectionArea(
          key: _selectionKey,
          selectionControls: nativeActive
              ? emptyTextSelectionControls
              : widget.selectionControls,
          magnifierConfiguration: nativeActive
              ? TextMagnifierConfiguration.disabled
              : null,
          contextMenuBuilder: nativeActive
              ? (context, state) => const SizedBox.shrink()
              : widget.contextMenuBuilder ??
                    (context, state) =>
                        AdaptiveTextSelectionToolbar.selectableRegion(
                          selectableRegionState: state,
                        ),
          child: _RegionProbe(onRegion: _setRegion, child: pages),
        );
        pages = DefaultSelectionStyle(
          selectionColor: nativeActive
              ? Colors.transparent
              : DefaultSelectionStyle.of(context).selectionColor,
          child: pages,
        );
        pages = NativeSelectionSurface(
          snapshot: _nativeSelection.snapshot,
          onSelectionChanged: _nativeSelection.setSelection,
          onAdjusting: _onNativeAdjusting,
          onActiveChanged: _nativeSelection.setActive,
          enabled: !_dragging && !_committing && !_carryPending && _offset == 0,
          child: pages,
        );
      }
      return ColoredBox(
        color: widget.backgroundColor,
        child: ClipRect(child: pages),
      );
    },
  );

  List<GlobalKey> _keysFor(int count) {
    while (_columnKeys.length < count) {
      _columnKeys.add(GlobalKey());
    }
    return _columnKeys.sublist(0, count);
  }
}

/// One spread: its column pages where the geometry puts them.
class _Spread extends StatelessWidget {
  const _Spread({
    required this.spread,
    required this.geometry,
    required this.images,
    required this.highlights,
    required this.rtl,
    this.columnKeys,
  });

  final TextSpread spread;
  final TextPageGeometry geometry;
  final BookImageCache images;
  final List<TextHighlight> highlights;
  final bool rtl;
  final List<GlobalKey>? columnKeys;

  @override
  Widget build(BuildContext context) {
    final layout = spread.layout;
    final prepared = layout.prepared;
    return Stack(
      children: [
        for (final (i, page) in spread.pages.indexed)
          Positioned(
            left: geometry.columnLeft(
              rtl ? geometry.columns - 1 - i : i,
            ),
            top: geometry.topMargin,
            child: TextColumnPage(
              key: columnKeys?[i],
              column: layout.column,
              page: page,
              images: images,
              imageKey: (src) => prepared.imageKeys[src],
              document: prepared.document,
              highlights: highlights,
            ),
          ),
      ],
    );
  }
}

/// A spread presented by the shared page-turn renderer. Only the spread shown,
/// the one with [columnKeys], takes part in a selection.
class _PlacedSpread extends StatelessWidget {
  const _PlacedSpread({
    super.key,
    required this.spread,
    required this.frame,
    required this.role,
    required this.view,
    this.columnKeys,
  });

  final TextSpread spread;
  final PageTurnFrame frame;
  final PageTurnRole role;
  final _TextPagesViewState view;
  final List<GlobalKey>? columnKeys;

  @override
  Widget build(BuildContext context) {
    final widget = view.widget;
    final controller = widget.controller;
    final size = view._viewport;
    final pages = _Spread(
      spread: spread,
      geometry: controller.geometry!,
      images: controller.images,
      highlights: widget.highlightsOf?.call(spread.section) ?? const [],
      rtl: controller.rtl,
      columnKeys: columnKeys,
    );
    return Positioned.fill(
      child: PageTurnLayer(
        frame: frame,
        role: role,
        viewportSize: size,
        backgroundColor: widget.backgroundColor,
        child: columnKeys == null
            ? SelectionContainer.disabled(child: pages)
            : pages,
      ),
    );
  }
}

/// A selection's boundary on a spread the reader turned away from: in
/// [layout]'s section, at [anchor]. [forward] is the last turn's
/// direction, [spread] the range of the spread it landed on.
class _CarriedSelection {
  _CarriedSelection(this.layout, this.anchor, {required this.forward});

  final TextSectionLayout layout;
  final TextPoint anchor;
  bool forward;
  TextPointRange? spread;
}

/// Hands [onRegion] the container of the selection area above it.
class _RegionProbe extends StatefulWidget {
  const _RegionProbe({required this.onRegion, required this.child});

  final ValueChanged<SelectionHandler?> onRegion;
  final Widget child;

  @override
  State<_RegionProbe> createState() => _RegionProbeState();
}

class _RegionProbeState extends State<_RegionProbe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The area's container is a SelectionContainerDelegate: both.
    final registrar = SelectionContainer.maybeOf(context);
    widget.onRegion(
      registrar is SelectionHandler ? registrar as SelectionHandler : null,
    );
  }

  @override
  void dispose() {
    widget.onRegion(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
