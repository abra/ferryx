import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../document/content_document.dart';
import '../document/text_point.dart';
import '../layout/book_fonts.dart';
import '../layout/book_image_cache.dart';
import '../layout/book_style.dart';
import 'text_book_layout.dart';
import 'text_book_source.dart';
import 'text_page_geometry.dart';

/// What moved a scrolled text last: the reader's finger, a jump to a
/// place, or a new layout keeping the place.
enum TextScrollReason { scroll, navigation, layout }

/// Where a scrolled text is: the requested point after navigation, or
/// the first text at the middle of the view after scrolling ([point]:
/// what the reader keeps as the reading position), how far down it is,
/// whether the start or the end is in view, and what moved it there.
@immutable
class TextScrollPosition {
  const TextScrollPosition({
    required this.point,
    required this.fraction,
    required this.atStart,
    required this.atEnd,
    this.reason = TextScrollReason.navigation,
  });

  final TextPoint? point;

  /// The scroll offset as a share of the scroll range: 1 when everything
  /// fits.
  final double fraction;
  final bool atStart;
  final bool atEnd;
  final TextScrollReason reason;

  @override
  bool operator ==(Object other) =>
      other is TextScrollPosition &&
      other.point == point &&
      other.fraction == fraction &&
      other.atStart == atStart &&
      other.atEnd == atEnd &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(point, fraction, atStart, atEnd, reason);

  @override
  String toString() =>
      'TextScrollPosition($point, ${fraction.toStringAsFixed(3)})';
}

/// A text of one section that scrolls (an article): the section laid out
/// as one column the width of the view less its margins (no wider than
/// the measure), shown from its top margin to its bottom one, laid out
/// as far as the view needs and the rest between frames. It keeps the
/// reading position across a change of size, style or fonts, and moves
/// to a point, a range or a share of the text.
///
/// [initialPoint] says where to open, from the prepared document (an
/// article's saved anchor); else [initialFraction].
class TextScrollController extends ChangeNotifier {
  TextScrollController({
    required TextBookSource source,
    required BookStyle style,
    required BookFonts fonts,
    required this.images,
    TextPageSettings settings = const TextPageSettings(),
    TextScaler textScaler = TextScaler.noScaling,
    TextPoint? Function(ContentDocument document)? initialPoint,
    double? initialFraction,
  }) : _settings = settings,
       _initialPoint = initialPoint,
       _initialFraction = initialFraction,
       _layout = TextBookLayout(
         source: source,
         style: style,
         fonts: fonts,
         images: images,
         textScaler: textScaler,
       ) {
    scroll.addListener(_onScroll);
  }

  final BookImageCache images;
  final TextBookLayout _layout;
  TextPageSettings _settings;
  TextPoint? Function(ContentDocument document)? _initialPoint;
  double? _initialFraction;

  /// The scrollable's controller: the view scrolls with it.
  final scroll = ScrollController();

  Size _viewport = Size.zero;
  TextSectionLayout? _section;
  TextScrollPosition? _position;
  TextPoint? _anchor;
  Object? _error;
  int _loads = 0;
  bool _disposed = false;
  bool _positionScheduled = false;

  /// Where to scroll once the view has a scrollable.
  double? _pendingOffset;

  /// What moved the text last; scrolls during [_jump] are the
  /// controller's own.
  TextScrollReason _reason = TextScrollReason.navigation;
  bool _jumping = false;

  TextBookLayout get layout => _layout;
  TextSectionLayout? get section => _section;
  TextScrollPosition? get position => _position;
  Object? get error => _error;
  Size get viewport => _viewport;
  TextPageSettings get settings => _settings;

  /// The space above the text and below it.
  double get topInset => _settings.topMargin;
  double get bottomInset => _settings.bottomMargin;

  /// Where the column starts from the view's left edge.
  double get columnLeft => (_viewport.width - _layout.columnWidth) / 2;

  /// Everything there is to scroll through, as laid out so far.
  double get contentHeight {
    final section = _section;
    if (section == null) return 0;
    final column = section.column;
    final text = section.isComplete ? column.contentHeight : column.height;
    return topInset + text + bottomInset;
  }

  double get _maxScroll => math.max(0, contentHeight - _viewport.height);

  /// How far the text scrolls, as laid out so far.
  double get maxScroll => _maxScroll;

  /// Where [point] (its line's top, or an element's first content) is
  /// down the scrolled content, top margin included; null until it is
  /// laid out.
  double? contentOffsetOf(TextPoint point) {
    final y = _section?.locator.yOf(point.node, point.offset);
    return y == null ? null : topInset + y;
  }

  /// Sets the view's size: the first opens the text, later ones lay it
  /// out again where the reader is.
  void setViewport(Size size) {
    if (size == _viewport || size.isEmpty) return;
    _viewport = size;
    _relayout();
  }

  /// New margins move the text even when its column keeps its width.
  set settings(TextPageSettings value) {
    if (value == _settings) return;
    _settings = value;
    _relayout();
    notifyListeners();
  }

  set style(BookStyle value) {
    _layout.style = value;
    _relayoutIfStale();
  }

  set fonts(BookFonts value) {
    _layout.fonts = value;
    _relayoutIfStale();
  }

  set textScaler(TextScaler value) {
    _layout.textScaler = value;
    _relayoutIfStale();
  }

  /// Lays the text out again where the reader is, when a change dropped
  /// its layout; an unchanged style, font or size keeps it as it is.
  void _relayoutIfStale() {
    final section = _section;
    if (section != null && !section.isStale) return;
    _reload(keep: _anchor ?? _position?.point);
  }

  void _relayout() {
    if (_viewport.isEmpty) return;
    final side = math.max(
      _viewport.width * _settings.sideMarginPercent / 100,
      _settings.safeInlineInset,
    );
    var width = _viewport.width - 2 * side;
    final measure = _settings.measure;
    if (measure != null && width > measure) width = measure;
    _layout.setPageSize(math.max(width, 1), _viewport.height);
    _relayoutIfStale();
  }

  /// Lays the section out (again), then scrolls to [keep] (a layout
  /// keeping the place), or the opening place the first time.
  Future<void> _reload({TextPoint? keep}) async {
    if (_viewport.isEmpty || _disposed) return;
    final load = ++_loads;
    final TextSectionLayout section;
    try {
      section = await _layout.section(0);
    } on Object catch (error) {
      if (load != _loads || _disposed) return;
      _error = error;
      notifyListeners();
      return;
    }
    if (load != _loads || _disposed) return;
    _section = section;
    _error = null;
    final opening = _initialPoint;
    final fraction = _initialFraction;
    _initialPoint = null;
    _initialFraction = null;
    final point = keep ?? opening?.call(section.prepared.document);
    final reason = keep != null
        ? TextScrollReason.layout
        : TextScrollReason.navigation;
    if (point != null) {
      _scrollToPoint(point, center: true, reason: reason);
    } else if (fraction != null) {
      section.complete();
      _scrollTo(fraction * _maxScroll, reason: reason);
    } else {
      _scrollTo(
        scroll.hasClients ? scroll.offset : 0,
        reason: TextScrollReason.layout,
      );
    }
    notifyListeners();
    // More text moves the scroll range: the share read and the end with it.
    void grown() {
      if (_disposed || load != _loads) return;
      notifyListeners();
      _schedulePosition();
    }

    unawaited(section.completeInSlices(onPages: grown).then((_) => grown()));
  }

  /// Increments when the text selected should go: the view watches it.
  int get selectionClears => _selectionClears;
  int _selectionClears = 0;

  /// Clears the text selected in the view.
  void clearSelection() {
    _selectionClears++;
    notifyListeners();
  }

  /// Scrolls so that [point] is at the middle of the view ([center]) or
  /// at the top margin.
  Future<void> goToPoint(TextPoint point, {bool center = true}) async {
    final section = _section;
    if (section == null) return;
    _scrollToPoint(point, center: center);
  }

  /// Scrolls so that [range] is in the middle of the view, or starts near
  /// its top when it is taller than the view.
  Future<void> goToRange(TextPointRange range) async {
    final section = _section;
    if (section == null) return;
    final top = _yOf(section, range.start);
    final bottom = _yOf(section, range.end);
    if (top == null) return;
    final height = (bottom ?? top) - top;
    final offset = height <= _viewport.height - 2 * topInset
        ? topInset + top + height / 2 - _viewport.height / 2
        : top;
    _scrollTo(offset, reason: TextScrollReason.navigation);
  }

  /// Scrolls to [fraction] of the scroll range: the whole text is laid
  /// out first, so the range is known.
  Future<void> goToFraction(double fraction) async {
    final section = _section;
    if (section == null) return;
    section.complete();
    _scrollTo(
      fraction.clamp(0.0, 1.0) * _maxScroll,
      reason: TextScrollReason.navigation,
    );
    notifyListeners();
  }

  void _scrollToPoint(
    TextPoint point, {
    required bool center,
    TextScrollReason reason = TextScrollReason.navigation,
  }) {
    final section = _section!;
    final y = _yOf(section, point);
    if (y == null) return;
    // Centred, or at the top margin.
    _scrollTo(
      center ? topInset + y - _viewport.height / 2 : y,
      reason: reason,
      point: point,
    );
  }

  /// [point]'s height in the column, laid out as far as it is.
  double? _yOf(TextSectionLayout section, TextPoint point) {
    var y = section.locator.yOf(point.node, point.offset);
    if (y == null && !section.isComplete) {
      section.complete();
      y = section.locator.yOf(point.node, point.offset);
    }
    return y;
  }

  void _scrollTo(
    double offset, {
    required TextScrollReason reason,
    TextPoint? point,
  }) {
    final section = _section;
    _reason = reason;
    // Several sentences can share a line: its start loses the exact target.
    _anchor = point;
    final target = offset.clamp(0.0, _maxScroll);
    section?.ensureHeight(target + _viewport.height * 2);
    if (scroll.hasClients) {
      _jump(target.clamp(0.0, _maxScroll));
      _pendingOffset = null;
    } else {
      _pendingOffset = target;
    }
    _schedulePosition();
  }

  void _jump(double offset) {
    _jumping = true;
    try {
      scroll.jumpTo(offset);
    } finally {
      _jumping = false;
    }
  }

  /// Called by the view once its scrollable is attached.
  void attached() {
    final pending = _pendingOffset;
    if (pending != null && scroll.hasClients) {
      _pendingOffset = null;
      _jump(pending.clamp(0.0, _maxScroll));
    }
    _schedulePosition();
  }

  void _onScroll() {
    if (!_jumping) {
      _reason = TextScrollReason.scroll;
      _anchor = null;
    }
    final section = _section;
    if (section != null && !section.isComplete && scroll.hasClients) {
      final before = section.column.height;
      section.ensureHeight(scroll.offset + _viewport.height * 2);
      if (section.column.height != before) notifyListeners();
    }
    _schedulePosition();
  }

  /// One position update a frame, however often the scroll moves.
  void _schedulePosition() {
    if (_positionScheduled || _disposed) return;
    _positionScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _positionScheduled = false;
      if (_disposed) return;
      _updatePosition();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _updatePosition() {
    final section = _section;
    if (section == null || _viewport.isEmpty) return;
    final offset = scroll.hasClients ? scroll.offset : (_pendingOffset ?? 0);
    final max = _maxScroll;
    final middle = offset + _viewport.height / 2 - topInset;
    final next = TextScrollPosition(
      point:
          _anchor ??
          section.locator.pointAt(math.max(0, middle)) ??
          section.locator.pointAt(0),
      fraction: max <= 0 ? 1 : (offset / max).clamp(0.0, 1.0),
      atStart: offset <= 1,
      atEnd: section.isComplete && offset >= max - 1,
      reason: _reason,
    );
    if (next == _position) return;
    _position = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    scroll
      ..removeListener(_onScroll)
      ..dispose();
    _layout.dispose();
    super.dispose();
  }
}
