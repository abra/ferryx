import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart'
    show ScrollCacheExtent, SelectedContent, SelectionHandler;
import 'package:flutter/scheduler.dart';
import 'package:native_text_selection/native_text_selection.dart';

import '../document/text_point.dart';
import '../layout/column_pages.dart';
import '../layout/column_scroller.dart';
import '../layout/text_page.dart';
import '../layout/text_page_highlights.dart';
import 'text_pages_view.dart'
    show TextHighlightTapCallback, TextLinkTapCallback, TextPagesSelection;
import 'scroller_gestures.dart';
import 'text_scroll_controller.dart';
import 'text_native_selection.dart';

/// A text that scrolls (an article): [controller]'s column shown in
/// slices the height of the view as they scroll into it, with its
/// highlights. Taps go to a link under them ([onLinkTap]), then a
/// highlight ([onHighlightTap]), then [onTap] as fractions of the view;
/// a tap while text is selected clears the selection. With [selectable]
/// the text is a selection area across the slices. iOS and Android use native
/// handles and magnification when the platform adapter accepts the geometry;
/// other hosts retain Flutter controls. A table wider than the
/// column scrolls sideways under a horizontal drag that starts on it.
///
/// [onHighlightRects] hears where highlight [trackedHighlight] is drawn
/// in the view after each frame that moves it.
class TextScrollView extends StatefulWidget {
  const TextScrollView({
    super.key,
    required this.controller,
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.highlights = const [],
    this.onTap,
    this.onLinkTap,
    this.onHighlightTap,
    this.selectable = true,
    this.selectionControls,
    this.contextMenuBuilder,
    this.onSelectionChanged,
    this.onSelectionAdjusting,
    this.trackedHighlight,
    this.onHighlightRects,
  });

  final TextScrollController controller;
  final Color backgroundColor;
  final List<TextHighlight> highlights;
  final ValueChanged<Offset>? onTap;
  final TextLinkTapCallback? onLinkTap;
  final TextHighlightTapCallback? onHighlightTap;
  final bool selectable;

  /// Controls for the Flutter fallback; platform-adaptive when null.
  final TextSelectionControls? selectionControls;

  /// Flutter's adaptive toolbar when null.
  /// Native-mode custom actions dismiss it with
  /// [ContextMenuController.removeAny] or clear the selection.
  final SelectableRegionContextMenuBuilder? contextMenuBuilder;
  final ValueChanged<TextPagesSelection?>? onSelectionChanged;
  final ValueChanged<bool>? onSelectionAdjusting;
  final String? trackedHighlight;
  final ValueChanged<List<Rect>>? onHighlightRects;

  @override
  State<TextScrollView> createState() => _TextScrollViewState();
}

class _TextScrollViewState extends State<TextScrollView>
    with SingleTickerProviderStateMixin {
  late final _tableDrag = ScrollerDrag(this);

  final _selectionKey = GlobalKey<SelectionAreaState>();

  /// The slices built, by index: where taps and selections are found.
  final _slices = <int, GlobalKey>{};
  bool _hasSelection = false;
  int _selectionClears = 0;
  int _pointers = 0;
  SelectionHandler? _region;
  late final _nativeSelection = TextNativeSelectionController(
    pages: () => _pages,
    viewport: () => context,
    region: () => _region,
    selectionState: () => _selectionKey.currentState?.selectableRegion,
    contextMenuBuilder: () => widget.contextMenuBuilder,
    onChanged: () => _onSelectionChanged(_region?.getSelectedContent()),
    onClear: () =>
        _selectionKey.currentState?.selectableRegion.clearSelection(),
  );

  /// What the slices were built for: a new layout, more of it, or a new
  /// view rebuilds them; a position report alone does not.
  (Object?, double, Size)? _built;

  /// Where [TextScrollView.trackedHighlight] was last reported.
  List<Rect> _trackedRects = const [];
  bool _trackScheduled = false;

  TextScrollController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _nativeSelection.addListener(_onNativeChanged);
    _selectionClears = _controller.selectionClears;
    _controller.addListener(_onController);
    _controller.scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(TextScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      oldWidget.controller.scroll.removeListener(_onScroll);
      widget.controller.addListener(_onController);
      widget.controller.scroll.addListener(_onScroll);
    }
    if (oldWidget.trackedHighlight != widget.trackedHighlight ||
        !identical(oldWidget.highlights, widget.highlights)) {
      _scheduleTracking();
    }
  }

  @override
  void dispose() {
    _nativeSelection.dispose();
    _controller.removeListener(_onController);
    _controller.scroll.removeListener(_onScroll);
    _tableDrag.dispose();
    super.dispose();
  }

  void _onNativeChanged() {
    if (mounted) setState(() {});
  }

  void _onNativeAdjusting(bool value) {
    _nativeSelection.setAdjusting(value);
    widget.onSelectionAdjusting?.call(value);
  }

  void _onScroll() {
    _scheduleTracking();
    _nativeSelection.refresh(deferred: _pointers > 0);
  }

  void _onPointerDown(PointerDownEvent event) => _pointers++;

  void _onPointerUp(PointerEvent event) {
    if (_pointers > 0) _pointers--;
    if (_pointers == 0) _nativeSelection.refresh();
  }

  /// Reports where the tracked highlight is after the next frame.
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
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Where highlight [id] is drawn on the slices in view, in the view.
  List<Rect> _rectsOf(String? id) {
    final view = context.findRenderObject();
    if (id == null || view is! RenderBox || !view.hasSize) return const [];
    final bounds = Offset.zero & view.size;
    return [
      for (final page in _pages)
        for (final rect in page.highlightRects(id))
          if (MatrixUtils.transformRect(page.getTransformTo(view), rect)
              case final inView when inView.overlaps(bounds))
            inView,
    ];
  }

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
      if (_hasSelection) {
        _selectionKey.currentState?.selectableRegion.clearSelection();
      }
    }
    final built = (
      _controller.section,
      _controller.contentHeight,
      _controller.viewport,
    );
    if (built != _built) setState(() {});
    _nativeSelection.refresh(deferred: _pointers > 0);
    _scheduleTracking();
  }

  Iterable<RenderTextColumnPage> get _pages sync* {
    for (final key in _slices.values) {
      final page = key.currentContext?.findRenderObject();
      if (page is RenderTextColumnPage && page.attached) yield page;
    }
  }

  /// The part of the text that scrolls sideways at [global].
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

  void _onTableDragEnd(DragEndDetails details) =>
      _tableDrag.end(details.velocity.pixelsPerSecond.dx);

  void _onTapUp(TapUpDetails details) {
    if (_hasSelection) {
      _selectionKey.currentState?.selectableRegion.clearSelection();
      return;
    }
    final section = _controller.section;
    if (section != null) {
      for (final page in _pages) {
        final local = page.globalToLocal(details.globalPosition);
        if (!(Offset.zero & page.size).contains(local)) continue;
        final link = page.linkAt(local);
        if (link != null && widget.onLinkTap != null) {
          widget.onLinkTap!(section, link);
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
    final viewport = _controller.viewport;
    if (viewport.isEmpty) return;
    widget.onTap?.call(
      Offset(
        details.localPosition.dx / viewport.width,
        details.localPosition.dy / viewport.height,
      ),
    );
  }

  void _onSelectionChanged(SelectedContent? content) {
    if (_nativeSelection.selecting) return;
    final section = _controller.section;
    TextPagesSelection? selection;
    if (content != null && section != null) {
      final view = context.findRenderObject() as RenderBox?;
      final parts = [
        for (final page in _pages)
          if (page.selection case final selected?) (page, selected),
      ]..sort((a, b) => _order(a.$2.start, b.$2.start));
      TextPoint? start;
      TextPoint? end;
      Rect? bounds;
      final texts = <String>[];
      for (final (page, selected) in parts) {
        start ??= selected.start;
        end = selected.end;
        // A paragraph split between slices is selected in both: once.
        if (texts.isEmpty || texts.last != selected.text) {
          texts.add(selected.text);
        }
        final box = page.selectionBounds;
        if (box != null && view != null) {
          final inView = MatrixUtils.transformRect(
            page.getTransformTo(view),
            box,
          );
          bounds = bounds == null ? inView : bounds.expandToInclude(inView);
        }
      }
      if (start != null && end != null) {
        selection = TextPagesSelection(
          section: section,
          range: TextPointRange(start, end),
          text: content.plainText,
          bounds: bounds,
        );
      }
    }
    _hasSelection = selection != null;
    _nativeSelection.refresh(deferred: _pointers > 0);
    widget.onSelectionChanged?.call(selection);
  }

  int _order(TextPoint a, TextPoint b) {
    final doc = _controller.section?.prepared.document;
    return doc == null ? 0 : doc.comparePoints(a, b);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_hasSelection) _nativeSelection.refresh(deferred: _pointers > 0);
      final size = constraints.biggest;
      if (size.isFinite && !size.isEmpty && size != _controller.viewport) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _controller.setViewport(size);
        });
      }
      final section = _controller.section;
      _built = (section, _controller.contentHeight, _controller.viewport);
      Widget child;
      if (section == null || _controller.viewport != size) {
        child = const SizedBox.expand();
      } else {
        final height = size.height;
        final contentHeight = _controller.contentHeight;
        final fullSlices = (contentHeight / height).floor();
        final hasLastSlice = contentHeight > fullSlices * height;
        final lastTop = fullSlices * height - _controller.topInset;
        final document = section.prepared.document;
        final imageKeys = section.prepared.imageKeys;
        child = NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            _controller.attached();
            return false;
          },
          child: CustomScrollView(
            controller: _controller.scroll,
            semanticChildCount: fullSlices + (hasLastSlice ? 1 : 0),
            // A view's height of slices above and below, built ahead.
            scrollCacheExtent: const ScrollCacheExtent.viewport(1),
            slivers: [
              SliverFixedExtentList.builder(
                itemExtent: height,
                itemCount: fullSlices,
                itemBuilder: (context, index) {
                  final top = index * height - _controller.topInset;
                  return TextColumnPage(
                    key: _slices.putIfAbsent(index, GlobalKey.new),
                    column: section.column,
                    page: ColumnPage(top, top + height),
                    images: _controller.images,
                    imageKey: (src) => imageKeys[src],
                    padding: EdgeInsets.only(left: _controller.columnLeft),
                    document: document,
                    highlights: widget.highlights,
                  );
                },
              ),
              // The last slice ends at the bottom margin, without rounding
              // the scroll range up to another full viewport.
              if (hasLastSlice)
                SliverToBoxAdapter(
                  child: IndexedSemantics(
                    index: fullSlices,
                    child: TextColumnPage(
                      key: _slices.putIfAbsent(fullSlices, GlobalKey.new),
                      column: section.column,
                      page: ColumnPage(
                        lastTop,
                        contentHeight - _controller.topInset,
                      ),
                      images: _controller.images,
                      imageKey: (src) => imageKeys[src],
                      padding: EdgeInsets.only(left: _controller.columnLeft),
                      document: document,
                      highlights: widget.highlights,
                    ),
                  ),
                ),
            ],
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _controller.attached();
        });
      }
      child = RawGestureDetector(
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _onTapUp,
          child: child,
        ),
      );
      if (widget.selectable) {
        final nativeActive = _nativeSelection.active;
        child = SelectionArea(
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
          onSelectionChanged: _onSelectionChanged,
          child: TextSelectionRegionProbe(
            onRegion: (region) => _region = region,
            child: child,
          ),
        );
        child = DefaultSelectionStyle(
          selectionColor: nativeActive
              ? Colors.transparent
              : DefaultSelectionStyle.of(context).selectionColor,
          child: child,
        );
        child = Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: child,
        );
        child = NativeSelectionSurface(
          snapshot: _nativeSelection.snapshot,
          onSelectionChanged: _nativeSelection.setSelection,
          onAdjusting: _onNativeAdjusting,
          onActiveChanged: _nativeSelection.setActive,
          child: child,
        );
      }
      return ColoredBox(color: widget.backgroundColor, child: child);
    },
  );
}
