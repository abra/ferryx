import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../page_turn/page_turn_animation.dart';
import '../page_turn/page_turn_decoration.dart';
import '../page_turn/page_turn_frame.dart';
import '../page_turn/page_turn_layer.dart';
import 'fixed_page_source.dart';
import 'fixed_pages_controller.dart';
import 'page_colors.dart';
import 'spread_layout.dart';
import 'zoom_tiles.dart';

/// Builds what sits over a page image: saved areas, a selection draft.
/// [imageRect] is where the whole page is drawn inside the page frame, so
/// overlays can map page-normalized coordinates; with a margin crop it
/// extends past the frame, which clips it.
typedef PageOverlayBuilder =
    Widget Function(BuildContext context, int page, Rect imageRect);

/// The part of a page to show, as fractions of the page, or null for the
/// whole page: a margin crop.
typedef VisibleRectOf = Rect? Function(int page);

/// Fixed-page documents (comics, PDF, DjVu): single pages or spreads,
/// presented with [pageTurnAnimation],
/// pinch and double-tap zoom, and the tap arbitration of the WebView
/// reader. The pages come from a [FixedPageSource]; the view knows nothing
/// of formats.
///
/// Reading direction comes from [FixedPagesController.rtl] through
/// `Directionality`, so a right-to-left comic swipes the other way. Taps
/// reach [onTap] as fractions of the view: edge taps at once, centre taps
/// after the double-tap window, all taps as the centre while zoomed.
/// Swipes turn pages at fit scale and pan while zoomed; every turn,
/// jump or rotation returns to fit.
class FixedPagesView extends StatefulWidget {
  const FixedPagesView({
    super.key,
    required this.pages,
    required this.controller,
    this.onTap,
    this.onPageShown,
    this.pageOverlayBuilder,
    this.visibleRectOf,
    this.pageColors,
    this.axis = Axis.horizontal,
    this.pageTurnAnimation = PageTurnAnimation.cover,
    this.edgeTapZoneFraction = 0.3,
    this.backgroundColor = const Color(0xFF000000),
    this.turnDuration = const Duration(milliseconds: 250),
    this.pageSemanticsLabel = _defaultPageLabel,
    this.failedPageSemanticsLabel = _defaultFailedPageLabel,
  }) : assert(edgeTapZoneFraction >= 0 && edgeTapZoneFraction < 0.5);

  final FixedPageSource pages;
  final FixedPagesController controller;

  /// A tap that is not a zoom gesture, as fractions of the view's size.
  final ValueChanged<Offset>? onTap;

  /// A visible page's image is on screen for the first time; the first
  /// call is the moment the comic is readable. Neighbours decoded in
  /// advance are not reported.
  final ValueChanged<int>? onPageShown;

  final PageOverlayBuilder? pageOverlayBuilder;

  /// Margin crops per page; the visible part is what is fitted to the
  /// frame and what spreads are laid out with.
  final VisibleRectOf? visibleRectOf;

  /// Theme colours for the pages, or null to draw them as published.
  final PageColors? pageColors;

  /// The direction pages turn in: side to side, or up and down as the
  /// reader's vertical page turn. Reading direction only applies side to
  /// side; tap zones stay at the left and right edges either way.
  final Axis axis;
  final PageTurnAnimation pageTurnAnimation;

  /// Width share at each edge where a tap turns the page at once.
  final double edgeTapZoneFraction;

  final Color backgroundColor;

  /// Page-turn animation; reduced motion jumps instead.
  final Duration turnDuration;

  final String Function(int page, int pageCount) pageSemanticsLabel;
  final String Function(int page) failedPageSemanticsLabel;

  /// A second tap within this window and distance of the first is a
  /// double tap.
  static const doubleTapWindow = Duration(milliseconds: 280);
  static const doubleTapDistance = 32.0;

  /// Double tap zooms to this scale at the tapped point, or back to fit.
  static const doubleTapScale = 2.5;
  static const minScale = 1.0;
  static const maxScale = 4.0;

  /// Pixel budget of one sharp tile, the WebView reader's for a canvas.
  static const maxTilePixels = 6000000;

  /// Sharp tiles rendered so far; tests read it to see a zoom take effect.
  @visibleForTesting
  static int debugTileRenders = 0;

  static String _defaultPageLabel(int page, int pageCount) =>
      'Page ${page + 1} of $pageCount';

  static String _defaultFailedPageLabel(int page) =>
      'Page ${page + 1} could not be shown';

  @override
  State<FixedPagesView> createState() => _FixedPagesViewState();
}

class _FixedPagesViewState extends State<FixedPagesView> {
  final _viewportKey = GlobalKey();
  late PageController _pageController;
  late bool _singlePage;
  late int _turnOriginUnit;
  PageTurnAnimation? _activeAnimation;
  final _zoomControllers = <int, TransformationController>{};
  Size _size = Size.zero;
  Timer? _pendingTap;
  Offset? _pendingTapPoint;
  bool _animating = false;

  FixedPagesController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _singlePage = _controller.singlePage;
    _turnOriginUnit = _controller.unit;
    _pageController = PageController(initialPage: _controller.unit);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(FixedPagesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _resetPageController();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _cancelPendingTap();
    _pageController.dispose();
    for (final zoom in _zoomControllers.values) {
      zoom.dispose();
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller.singlePage != _singlePage) {
      _cancelPendingTap();
      setState(_resetPageController);
      return;
    }
    final unit = _controller.unit;
    if (_pageController.hasClients && !_animating) {
      final shown = _pageController.page?.round();
      if (shown != null && shown != unit) {
        _cancelPendingTap();
        _showUnit(unit);
      }
    }
    // Physics follow the zoomed and locked state.
    setState(() {});
  }

  void _resetPageController() {
    _singlePage = _controller.singlePage;
    _turnOriginUnit = _controller.unit;
    _activeAnimation = null;
    final previous = _pageController;
    _pageController = PageController(initialPage: _controller.unit);
    // The old controller is still attached to the outgoing PageView until
    // the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  Future<void> _showUnit(int unit) async {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pageController.jumpToPage(unit);
      return;
    }
    _activeAnimation ??= widget.pageTurnAnimation;
    _animating = true;
    try {
      await _pageController.animateToPage(
        unit,
        duration: widget.turnDuration,
        curve: Curves.easeOutCubic,
      );
    } finally {
      _animating = false;
    }
    // A unit change during the animation wins, as the latest turn does.
    if (mounted && _pageController.hasClients) {
      final shown = _pageController.page?.round();
      if (shown != null && shown != _controller.unit) {
        _showUnit(_controller.unit);
      }
    }
  }

  void _onPageChanged(int unit) {
    if (_animating) return;
    _cancelPendingTap();
    _controller.showUnit(unit);
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 ||
        (notification is! ScrollStartNotification &&
            notification is! ScrollEndNotification)) {
      return false;
    }
    final page = _pageController.page;
    if (page != null && (page - page.round()).abs() < 0.000001) {
      // An interrupted turn keeps its origin until it reaches a whole page.
      _turnOriginUnit = page.round();
      _activeAnimation = notification is ScrollStartNotification
          ? widget.pageTurnAnimation
          : null;
    }
    return false;
  }

  _PageTurnPosition get _turnPosition => _PageTurnPosition(
    page: _pageController.hasClients
        ? (_pageController.page ?? _turnOriginUnit.toDouble())
        : _turnOriginUnit.toDouble(),
    origin: _turnOriginUnit,
    count: _controller.unitCount,
    axis: widget.axis,
    rtl: _controller.rtl,
  );

  PageTurnFrame _frameFor(_PageTurnPosition position) {
    final animation = _activeAnimation ?? widget.pageTurnAnimation;
    final incoming = position.incomingOffset;
    return incoming == null
        ? PageTurnFrame.idle(animation: animation, axis: widget.axis)
        : PageTurnFrame.active(
            animation: animation,
            axis: widget.axis,
            incomingOffset: incoming,
            entrySide: position.entrySide,
          );
  }

  TransformationController _zoomControllerFor(int unit) =>
      _zoomControllers.putIfAbsent(unit, TransformationController.new);

  void _releaseZoomController(int unit) {
    _zoomControllers.remove(unit)?.dispose();
  }

  // Taps.

  void _onTapUp(TapUpDetails details) {
    if (_controller.inputLocked || _size.isEmpty) return;
    final point = details.localPosition;
    final zoomed = _controller.isZoomed;
    final x = point.dx / _size.width;
    final edge = widget.edgeTapZoneFraction;
    // Edge navigation is never a zoom gesture; zoomed pages have no edges.
    if (!zoomed && (x <= edge || x >= 1 - edge)) {
      _cancelPendingTap();
      _fireTap(point);
      return;
    }
    final previous = _pendingTapPoint;
    if (previous != null &&
        (point - previous).distance <= FixedPagesView.doubleTapDistance) {
      _cancelPendingTap();
      _toggleZoom(point);
      return;
    }
    _cancelPendingTap(firePrevious: true);
    final tapPoint = zoomed ? _size.center(Offset.zero) : point;
    _pendingTapPoint = point;
    _pendingTap = Timer(FixedPagesView.doubleTapWindow, () {
      _pendingTap = null;
      _pendingTapPoint = null;
      _fireTap(tapPoint);
    });
  }

  void _cancelPendingTap({bool firePrevious = false}) {
    final timer = _pendingTap;
    final point = _pendingTapPoint;
    _pendingTap = null;
    _pendingTapPoint = null;
    timer?.cancel();
    if (firePrevious && point != null) {
      _fireTap(_controller.isZoomed ? _size.center(Offset.zero) : point);
    }
  }

  void _fireTap(Offset point) {
    if (!mounted || _controller.inputLocked) return;
    widget.onTap?.call(
      Offset(point.dx / _size.width, point.dy / _size.height),
    );
  }

  void _toggleZoom(Offset point) {
    final zoom = _zoomControllerFor(_controller.unit);
    if (_controller.isZoomed) {
      zoom.value = Matrix4.identity();
      _controller.reportZoomScale(1);
      return;
    }
    zoom.value = zoomMatrixAt(
      point,
      scale: FixedPagesView.doubleTapScale,
      viewport: _size,
    );
    _controller.reportZoomScale(FixedPagesView.doubleTapScale);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        _controller.attachViewport(_size);
        final singlePage = _controller.singlePage;
        if (singlePage != _singlePage) _resetPageController();
        final locked = _controller.isZoomed || _controller.inputLocked;
        return FixedPagesViewportScope(
          viewportKey: _viewportKey,
          child: ColoredBox(
            key: _viewportKey,
            color: widget.backgroundColor,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _onTapUp,
              child: Directionality(
                textDirection: _controller.rtl
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: PageView.builder(
                        key: ValueKey<bool>(singlePage),
                        controller: _pageController,
                        scrollDirection: widget.axis,
                        physics: locked
                            ? const NeverScrollableScrollPhysics()
                            : const PageScrollPhysics(),
                        allowImplicitScrolling: true,
                        onPageChanged: _onPageChanged,
                        itemCount: _controller.unitCount,
                        itemBuilder: (context, unit) => _PageTurnUnit(
                          unit: unit,
                          view: this,
                          child: _PageUnit(
                            key: ValueKey<int>(unit),
                            unit: unit,
                            view: widget,
                            size: _size,
                            zoomController: _zoomControllerFor(unit),
                            onDisposed: () => _releaseZoomController(unit),
                          ),
                        ),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, _) => PageTurnDecoration(
                        frame: _frameFor(_turnPosition),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Adapts native viewport offsets to the shared page-turn presentation.
class _PageTurnUnit extends StatelessWidget {
  const _PageTurnUnit({
    required this.unit,
    required this.view,
    required this.child,
  });

  final int unit;
  final _FixedPagesViewState view;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: view._pageController,
    child: child,
    builder: (context, child) {
      final position = view._turnPosition;
      final frame = view._frameFor(position);
      final role = !frame.isActive
          ? null
          : unit == position.outgoing
          ? PageTurnRole.outgoing
          : unit == position.incoming
          ? PageTurnRole.incoming
          : null;
      return PageTurnLayer(
        frame: frame,
        role: role,
        nativeOffset: position.offsetOf(unit),
        viewportSize: view._size,
        backgroundColor: view.widget.backgroundColor,
        child: child!,
      );
    },
  );
}

class _PageTurnPosition {
  const _PageTurnPosition({
    required this.page,
    required this.origin,
    required this.count,
    required this.axis,
    required this.rtl,
  });

  final double page;
  final int origin;
  final int count;
  final Axis axis;
  final bool rtl;

  int get _direction => (page - origin).sign.toInt();
  double get _sign => axis == Axis.horizontal && rtl ? -1 : 1;
  int get outgoing => _direction >= 0 ? page.floor() : page.ceil();
  int get incoming => outgoing + _direction;
  double get entrySide => _direction * _sign;
  double offsetOf(int unit) => (unit - page) * _sign;

  double? get incomingOffset {
    if (_direction == 0 || incoming < 0 || incoming >= count) return null;
    return (incoming - page) * _sign;
  }
}

/// Lets overlays inside a `FixedPagesView` express rectangles as fractions
/// of the whole view, the coordinate space the app's selection chrome uses.
class FixedPagesViewportScope extends InheritedWidget {
  const FixedPagesViewportScope({
    super.key,
    required this.viewportKey,
    required super.child,
  });

  final GlobalKey viewportKey;

  /// [rect] in [box]'s coordinates as fractions of the view enclosing
  /// [context], or null when there is no view or either is not laid out.
  static Rect? fractionsOf(BuildContext context, Rect rect, RenderBox box) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<FixedPagesViewportScope>();
    return scope?._fractionsOf(rect, box);
  }

  Rect? _fractionsOf(Rect rect, RenderBox box) {
    final viewport = viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize || !box.hasSize) {
      return null;
    }
    final size = viewport.size;
    if (size.isEmpty) return null;
    final topLeft = box.localToGlobal(rect.topLeft, ancestor: viewport);
    final bottomRight = box.localToGlobal(rect.bottomRight, ancestor: viewport);
    return Rect.fromLTRB(
      (topLeft.dx / size.width).clamp(0.0, 1.0),
      (topLeft.dy / size.height).clamp(0.0, 1.0),
      (bottomRight.dx / size.width).clamp(0.0, 1.0),
      (bottomRight.dy / size.height).clamp(0.0, 1.0),
    );
  }

  @override
  bool updateShouldNotify(FixedPagesViewportScope oldWidget) =>
      oldWidget.viewportKey != viewportKey;
}

/// The transform that scales a page view by [scale] around [point], panned
/// back so the page keeps covering the viewport: what a double tap sets.
Matrix4 zoomMatrixAt(
  Offset point, {
  required double scale,
  required Size viewport,
}) {
  final tx = (point.dx * (1 - scale)).clamp(viewport.width * (1 - scale), 0.0);
  final ty = (point.dy * (1 - scale)).clamp(viewport.height * (1 - scale), 0.0);
  return Matrix4.identity()
    ..translateByDouble(tx, ty, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);
}

/// One scroll unit: a page or a spread, with its own zoom.
class _PageUnit extends StatefulWidget {
  const _PageUnit({
    super.key,
    required this.unit,
    required this.view,
    required this.size,
    required this.zoomController,
    required this.onDisposed,
  });

  final int unit;
  final FixedPagesView view;
  final Size size;
  final TransformationController zoomController;
  final VoidCallback onDisposed;

  @override
  State<_PageUnit> createState() => _PageUnitState();
}

class _PageUnitState extends State<_PageUnit> {
  late int _zoomEpoch;
  final _pageSizes = <int, Size>{};
  final _unitKey = GlobalKey();

  /// Bumped when a zoom or pan gesture ends, so frames look for a sharper
  /// tile of what is now on screen.
  int _gestureEpoch = 0;

  FixedPagesController get _controller => widget.view.controller;

  @override
  void initState() {
    super.initState();
    _zoomEpoch = _controller.zoomEpoch;
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    widget.onDisposed();
    super.dispose();
  }

  void _onControllerChanged() {
    if (_controller.zoomEpoch != _zoomEpoch) {
      _zoomEpoch = _controller.zoomEpoch;
      widget.zoomController.value = Matrix4.identity();
    }
    if (mounted) setState(() {});
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    _controller.reportZoomScale(
      widget.zoomController.value.getMaxScaleOnAxis(),
    );
    setState(() => _gestureEpoch++);
  }

  void _onPageSize(int page, Size size) {
    if (_pageSizes[page] == size) return;
    setState(() => _pageSizes[page] = size);
  }

  /// The decoded size, or the source's ratio before the page is drawn,
  /// reduced to the visible part when the page is cropped.
  Size? _sizeOf(int page) {
    final whole =
        _pageSizes[page] ??
        switch (widget.view.pages.pageAspect(page)) {
          final aspect? => Size(aspect, 1),
          null => null,
        };
    if (whole == null) return null;
    final visible = widget.view.visibleRectOf?.call(page);
    if (visible == null) return whole;
    return Size(whole.width * visible.width, whole.height * visible.height);
  }

  @override
  Widget build(BuildContext context) {
    final layout = _controller.layout;
    final zoomed = _controller.isZoomed;
    final zoomScale = _controller.zoomScale;
    final Widget frames;
    if (_controller.singlePage) {
      final page = layout.pageAt(layout.locationOfPage(widget.unit));
      frames = _PageFrame(
        key: ValueKey<int>(page),
        page: page,
        view: widget.view,
        frameSize: widget.size,
        zoomScale: zoomScale,
        unitKey: _unitKey,
        zoomController: widget.zoomController,
        gestureEpoch: _gestureEpoch,
        onImageSize: _onPageSize,
      );
    } else {
      final spread = layout.spreads[widget.unit];
      final center = spread.center;
      if (center != null) {
        frames = _PageFrame(
          key: ValueKey<int>(center),
          page: center,
          view: widget.view,
          frameSize: widget.size,
          zoomScale: zoomScale,
          unitKey: _unitKey,
          zoomController: widget.zoomController,
          gestureEpoch: _gestureEpoch,
          onImageSize: _onPageSize,
        );
      } else {
        final halfSize = Size(widget.size.width / 2, widget.size.height);
        frames = CustomMultiChildLayout(
          delegate: _SpreadLayoutDelegate(
            left: spread.left != null ? _sizeOf(spread.left!) : null,
            right: spread.right != null ? _sizeOf(spread.right!) : null,
            hasLeft: spread.left != null,
            hasRight: spread.right != null,
          ),
          children: [
            if (spread.left != null)
              LayoutId(
                id: SpreadSide.left,
                child: _PageFrame(
                  key: ValueKey<int>(spread.left!),
                  page: spread.left!,
                  view: widget.view,
                  frameSize: halfSize,
                  zoomScale: zoomScale,
                  unitKey: _unitKey,
                  zoomController: widget.zoomController,
                  gestureEpoch: _gestureEpoch,
                  onImageSize: _onPageSize,
                ),
              ),
            if (spread.right != null)
              LayoutId(
                id: SpreadSide.right,
                child: _PageFrame(
                  key: ValueKey<int>(spread.right!),
                  page: spread.right!,
                  view: widget.view,
                  frameSize: halfSize,
                  zoomScale: zoomScale,
                  unitKey: _unitKey,
                  zoomController: widget.zoomController,
                  gestureEpoch: _gestureEpoch,
                  onImageSize: _onPageSize,
                ),
              ),
          ],
        );
      }
    }
    final locked = _controller.inputLocked;
    return InteractiveViewer(
      transformationController: widget.zoomController,
      minScale: FixedPagesView.minScale,
      maxScale: FixedPagesView.maxScale,
      panEnabled: zoomed && !locked,
      scaleEnabled: !locked,
      onInteractionEnd: _onInteractionEnd,
      child: SizedBox.fromSize(
        key: _unitKey,
        size: widget.size,
        child: _PageSwipeDetector(
          enabled: !zoomed && !locked,
          axis: widget.view.axis,
          child: frames,
        ),
      ),
    );
  }
}

/// Turns pages from inside the zoom viewer.
///
/// `InteractiveViewer` keeps a scale recognizer for pinches. It is deeper
/// than the `PageView`, so it sees every pointer event first, and it
/// claims a single pointer as soon as one event moves it past the pan
/// slop: a quick flick, whose events outrun that slop, then never reached
/// the page scroll. This detector sits deeper still and hands the drag to
/// the page position at the ordinary slop, the way `Scrollable` does.
class _PageSwipeDetector extends StatefulWidget {
  const _PageSwipeDetector({
    required this.enabled,
    required this.axis,
    required this.child,
  });

  final bool enabled;
  final Axis axis;
  final Widget child;

  @override
  State<_PageSwipeDetector> createState() => _PageSwipeDetectorState();
}

class _PageSwipeDetectorState extends State<_PageSwipeDetector> {
  ScrollHoldController? _hold;
  Drag? _drag;

  ScrollPosition get _position => Scrollable.of(context).position;

  void _onDown(DragDownDetails details) {
    _hold = _position.hold(() => _hold = null);
  }

  void _onStart(DragStartDetails details) {
    _drag = _position.drag(details, () => _drag = null);
    _hold = null;
  }

  void _onUpdate(DragUpdateDetails details) => _drag?.update(details);

  void _onEnd(DragEndDetails details) => _drag?.end(details);

  void _onCancel() {
    _hold?.cancel();
    _drag?.cancel();
  }

  void _configure(DragGestureRecognizer recognizer) => recognizer
    ..onDown = _onDown
    ..onStart = _onStart
    ..onUpdate = _onUpdate
    ..onEnd = _onEnd
    ..onCancel = _onCancel;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        if (widget.enabled && widget.axis == Axis.horizontal)
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                HorizontalDragGestureRecognizer
              >(HorizontalDragGestureRecognizer.new, _configure),
        if (widget.enabled && widget.axis == Axis.vertical)
          VerticalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                VerticalDragGestureRecognizer
              >(VerticalDragGestureRecognizer.new, _configure),
      },
      child: widget.child,
    );
  }
}

/// Facing pages share one scale and meet at the gutter, as in
/// `fixed-layout.js`; unknown sizes assume a 2:3 page.
class _SpreadLayoutDelegate extends MultiChildLayoutDelegate {
  _SpreadLayoutDelegate({
    required this.left,
    required this.right,
    required this.hasLeft,
    required this.hasRight,
  });

  final Size? left;
  final Size? right;
  final bool hasLeft;
  final bool hasRight;

  static const _defaultPage = Size(2, 3);

  @override
  void performLayout(Size size) {
    final leftSize = hasLeft ? (left ?? _defaultPage) : Size.zero;
    final rightSize = hasRight ? (right ?? _defaultPage) : Size.zero;
    final width = leftSize.width + rightSize.width;
    final height = math.max(leftSize.height, rightSize.height);
    if (width <= 0 || height <= 0) return;
    final scale = math.min(size.width / width, size.height / height);
    final x0 = (size.width - width * scale) / 2;
    if (hasLeft) {
      final placed = Size(leftSize.width * scale, leftSize.height * scale);
      layoutChild(SpreadSide.left, BoxConstraints.tight(placed));
      positionChild(
        SpreadSide.left,
        Offset(x0, (size.height - placed.height) / 2),
      );
    }
    if (hasRight) {
      final placed = Size(rightSize.width * scale, rightSize.height * scale);
      layoutChild(SpreadSide.right, BoxConstraints.tight(placed));
      positionChild(
        SpreadSide.right,
        Offset(x0 + leftSize.width * scale, (size.height - placed.height) / 2),
      );
    }
  }

  @override
  bool shouldRelayout(_SpreadLayoutDelegate oldDelegate) =>
      oldDelegate.left != left ||
      oldDelegate.right != right ||
      oldDelegate.hasLeft != hasLeft ||
      oldDelegate.hasRight != hasRight;
}

/// One page image fitted into its frame, with its overlay and, while
/// zoomed, a sharp tile of what is on screen.
class _PageFrame extends StatefulWidget {
  const _PageFrame({
    super.key,
    required this.page,
    required this.view,
    required this.frameSize,
    required this.zoomScale,
    required this.unitKey,
    required this.zoomController,
    required this.gestureEpoch,
    required this.onImageSize,
  });

  final int page;
  final FixedPagesView view;

  /// The box the page is fitted into, in logical pixels.
  final Size frameSize;

  /// The current zoom; the page is decoded denser to stay sharp under it.
  final double zoomScale;

  /// The scroll unit this frame sits in, the space the zoom transform
  /// applies to.
  final GlobalKey unitKey;
  final TransformationController zoomController;

  /// Changes when a gesture ends; the frame then plans a tile.
  final int gestureEpoch;
  final void Function(int page, Size size) onImageSize;

  @override
  State<_PageFrame> createState() => _PageFrameState();
}

class _PageFrameState extends State<_PageFrame> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  Object? _error;

  ImageStream? _tileStream;
  ImageStreamListener? _tileListener;
  ImageInfo? _tileInfo;
  TileRegion? _tileRegion;
  TileRegion? _pendingTileRegion;

  /// The visible part of the page as fractions, or the whole page.
  Rect get _visible =>
      widget.view.visibleRectOf?.call(widget.page) ??
      const Rect.fromLTWH(0, 0, 1, 1);

  /// The visible part the image was asked for: a crop measured later
  /// through the same [FixedPagesView.visibleRectOf] asks again.
  Rect? _requestedVisible;

  /// Zoom re-decodes denser, up to the gesture's scale, so a zoomed page
  /// is sharp without holding full-resolution scans at fit; a crop asks
  /// for the whole page at the density its visible part is shown at.
  int get _targetWidth {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final width = widget.frameSize.width * dpr * widget.zoomScale;
    return (width / _visible.width).ceil();
  }

  ImageProvider get _provider =>
      widget.view.pages.pageImage(widget.page, targetWidth: _targetWidth);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_PageFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frameSize != widget.frameSize ||
        oldWidget.zoomScale != widget.zoomScale ||
        oldWidget.page != widget.page ||
        oldWidget.view.pages != widget.view.pages ||
        oldWidget.view.visibleRectOf != widget.view.visibleRectOf ||
        _visible != _requestedVisible) {
      _resolve();
    }
    if (oldWidget.gestureEpoch != widget.gestureEpoch ||
        oldWidget.zoomScale != widget.zoomScale) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _planTile());
    }
  }

  void _resolve() {
    _requestedVisible = _visible;
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _detach();
    _stream = stream;
    _listener = ImageStreamListener(_onImage, onError: _onError);
    stream.addListener(_listener!);
  }

  void _detach() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    _stream = null;
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final previous = _info;
    final size = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    if (!mounted) {
      info.dispose();
      return;
    }
    final resized =
        previous != null &&
        (previous.image.width != info.image.width ||
            previous.image.height != info.image.height);
    setState(() {
      _info = info;
      _error = null;
    });
    previous?.dispose();
    if (resized) {
      // A tile is placed in the base image's pixels: plan it again over
      // the new one.
      _dropTile();
      WidgetsBinding.instance.addPostFrameCallback((_) => _planTile());
    }
    widget.onImageSize(widget.page, size);
    if (previous == null &&
        widget.view.controller.visiblePages.contains(widget.page)) {
      widget.view.onPageShown?.call(widget.page);
    }
  }

  void _onError(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    // A page that cannot be decoded is a placeholder; the comic goes on.
    setState(() => _error = error);
  }

  // Sharp tiles.

  /// Renders the part of the page now on screen denser than the base
  /// image when the zoom shows it blurred; drops the tile at fit.
  void _planTile() {
    if (!mounted) return;
    final info = _info;
    final region = info == null ? null : _regionToSharpen(info.image);
    if (region == null) {
      _dropTile();
      return;
    }
    if (tileCovers(_tileRegion, region) ||
        tileCovers(_pendingTileRegion, region)) {
      return;
    }
    final tile = tileFor(
      region,
      pageWidth: info!.image.width.toDouble(),
      pageHeight: info.image.height.toDouble(),
      maxPixels: FixedPagesView.maxTilePixels,
    );
    final provider = widget.view.pages.pageTile(
      widget.page,
      fullWidth: (info.image.width * tile.density).round(),
      region: (
        x: (tile.left * tile.density).round(),
        y: (tile.top * tile.density).round(),
        width: math.max(1, (tile.width * tile.density).round()),
        height: math.max(1, (tile.height * tile.density).round()),
      ),
    );
    if (provider == null) return;
    _detachTile();
    _pendingTileRegion = tile;
    FixedPagesView.debugTileRenders++;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _tileStream = stream;
    _tileListener = ImageStreamListener(
      (tileInfo, _) {
        if (!mounted || _pendingTileRegion != tile) {
          tileInfo.dispose();
          return;
        }
        final previous = _tileInfo;
        setState(() {
          _tileInfo = tileInfo;
          _tileRegion = tile;
          _pendingTileRegion = null;
        });
        previous?.dispose();
      },
      onError: (_, _) {
        // The base image stays; the next gesture tries again.
        if (_pendingTileRegion == tile) _pendingTileRegion = null;
      },
    );
    stream.addListener(_tileListener!);
  }

  /// The base-image region the screen shows denser than the image, with
  /// the frame and viewport taken through the unit's zoom transform.
  TileRegion? _regionToSharpen(ui.Image image) {
    if (!widget.view.controller.isZoomed) return null;
    final frameBox = context.findRenderObject();
    final unitBox = widget.unitKey.currentContext?.findRenderObject();
    if (frameBox is! RenderBox ||
        unitBox is! RenderBox ||
        !frameBox.hasSize ||
        !unitBox.hasSize) {
      return null;
    }
    final origin = frameBox.localToGlobal(Offset.zero, ancestor: unitBox);
    final drawn = _drawnRect(frameBox.size).shift(origin);
    final matrix = widget.zoomController.value;
    final onScreen = MatrixUtils.transformRect(matrix, drawn);
    final visible = _visible;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return sharpenRegion(
      frameRect: onScreen,
      viewport: Offset.zero & unitBox.size,
      visible: Rect.fromLTWH(
        visible.left * image.width,
        visible.top * image.height,
        visible.width * image.width,
        visible.height * image.height,
      ),
      baseDensity: 1,
      devicePixelRatio: dpr,
    );
  }

  void _dropTile() {
    _detachTile();
    if (_tileInfo == null && _tileRegion == null) return;
    final previous = _tileInfo;
    setState(() {
      _tileInfo = null;
      _tileRegion = null;
    });
    previous?.dispose();
  }

  void _detachTile() {
    final listener = _tileListener;
    if (listener != null) _tileStream?.removeListener(listener);
    _tileListener = null;
    _tileStream = null;
    _pendingTileRegion = null;
  }

  @override
  void dispose() {
    _detach();
    _detachTile();
    _info?.dispose();
    _tileInfo?.dispose();
    super.dispose();
  }

  /// Where the visible part of the page lands inside a box of [size]:
  /// fitted and centred.
  Rect _drawnRect(Size size) {
    final info = _info;
    if (info == null) return Offset.zero & size;
    final visible = _visible;
    final visibleSize = Size(
      info.image.width * visible.width,
      info.image.height * visible.height,
    );
    final fitted = applyBoxFit(BoxFit.contain, visibleSize, size);
    return Alignment.center.inscribe(fitted.destination, Offset.zero & size);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.view.controller.pageCount;
    final info = _info;
    if (info == null) {
      return Semantics(
        image: true,
        label: _error != null
            ? widget.view.failedPageSemanticsLabel(widget.page)
            : widget.view.pageSemanticsLabel(widget.page, count),
        child: _error != null ? const _FailedPage() : const SizedBox.expand(),
      );
    }
    return Semantics(
      image: true,
      label: widget.view.pageSemanticsLabel(widget.page, count),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          final drawn = _drawnRect(box);
          final visible = _visible;
          // The whole page's rect, which overlays map their page-normalized
          // coordinates to; the crop only shows part of it.
          final imageRect = Rect.fromLTWH(
            drawn.left - visible.left / visible.width * drawn.width,
            drawn.top - visible.top / visible.height * drawn.height,
            drawn.width / visible.width,
            drawn.height / visible.height,
          );
          final overlay = widget.view.pageOverlayBuilder?.call(
            context,
            widget.page,
            imageRect,
          );
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: FixedPagePainter(
                    image: info.image,
                    imageRect: imageRect,
                    visible: visible,
                    colors: widget.view.pageColors,
                    tile: _tileInfo?.image,
                    tileRegion: _tileRegion,
                  ),
                ),
                ?overlay,
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Paints the base image's visible part and the sharp tile over it, both
/// through [paintPageWithColors]. Public for tests, which read the images
/// a frame holds.
@visibleForTesting
class FixedPagePainter extends CustomPainter {
  const FixedPagePainter({
    required this.image,
    required this.imageRect,
    required this.visible,
    required this.colors,
    required this.tile,
    required this.tileRegion,
  });

  final ui.Image image;

  /// Where the whole page lands, in the frame's coordinates.
  final Rect imageRect;
  final Rect visible;
  final PageColors? colors;
  final ui.Image? tile;
  final TileRegion? tileRegion;

  @override
  void paint(Canvas canvas, Size size) {
    final width = image.width.toDouble();
    final height = image.height.toDouble();
    paintPageWithColors(
      canvas,
      image,
      source: Rect.fromLTWH(
        visible.left * width,
        visible.top * height,
        visible.width * width,
        visible.height * height,
      ),
      destination: Rect.fromLTWH(
        imageRect.left + visible.left * imageRect.width,
        imageRect.top + visible.top * imageRect.height,
        visible.width * imageRect.width,
        visible.height * imageRect.height,
      ),
      colors: colors,
    );
    final tile = this.tile;
    final region = tileRegion;
    if (tile == null || region == null) return;
    paintPageWithColors(
      canvas,
      tile,
      source: Rect.fromLTWH(
        0,
        0,
        tile.width.toDouble(),
        tile.height.toDouble(),
      ),
      destination: Rect.fromLTWH(
        imageRect.left + region.left / width * imageRect.width,
        imageRect.top + region.top / height * imageRect.height,
        region.width / width * imageRect.width,
        region.height / height * imageRect.height,
      ),
      colors: colors,
    );
  }

  @override
  bool shouldRepaint(FixedPagePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.imageRect != imageRect ||
      oldDelegate.visible != visible ||
      oldDelegate.colors != colors ||
      oldDelegate.tile != tile ||
      oldDelegate.tileRegion != tileRegion;
}

class _FailedPage extends StatelessWidget {
  const _FailedPage();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0x33808080), child: SizedBox.expand());
}
