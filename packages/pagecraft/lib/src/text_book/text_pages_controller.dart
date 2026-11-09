import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '../formats/book_navigation.dart';
import '../layout/book_fonts.dart';
import '../layout/book_image_cache.dart';
import '../layout/book_style.dart';
import '../layout/column_layout.dart';
import '../layout/column_pages.dart';
import '../progress/section_progress.dart';
import '../progress/toc_progress.dart';
import 'page_progression.dart';
import 'text_anchor.dart';
import 'text_book_layout.dart';
import 'text_book_source.dart';
import 'text_book_support.dart';
import 'text_locator.dart';
import 'text_page_geometry.dart';

/// Why the reader is where it is.
enum TextRelocationReason {
  /// A turn: a swipe, a tap, [TextPagesController.next] or `previous`.
  page,

  /// A jump: a saved position, the table of contents, a link, the slider.
  navigation,

  /// The same text laid out again: a rotation, a style or font change.
  layout,
}

/// The pages of one spread: [pages] (one per column) of [layout]'s
/// section, spread [spread] of it.
class TextSpread {
  const TextSpread(this.layout, this.spread, this.pages);

  final TextSectionLayout layout;
  final int spread;
  final List<ColumnPage> pages;

  int get section => layout.index;

  @override
  bool operator ==(Object other) =>
      other is TextSpread &&
      identical(other.layout, layout) &&
      other.spread == spread &&
      listEquals(other.pages, pages);

  @override
  int get hashCode => Object.hash(identityHashCode(layout), spread);
}

/// Where the reader is, as foliate-js's `relocate` reports it.
@immutable
class TextPagePosition {
  const TextPagePosition({
    required this.section,
    required this.spread,
    required this.spreadCount,
    required this.cfi,
    required this.progress,
    required this.reason,
    this.tocItem,
  });

  final int section;

  /// The spread shown, from 0, within the section.
  final int spread;

  /// The section's spreads, once it is laid out whole.
  final int? spreadCount;

  /// The CFI range of what is shown, as foliate-js reports a page; a
  /// saved position or a link's CFI as it was asked for after a jump.
  final String cfi;

  /// Book fraction, locations and time left.
  final ProgressDetails progress;
  final TextRelocationReason reason;

  /// The table of contents entry the reader is in.
  final BookNavItem? tocItem;

  double get fraction => progress.fraction;

  @override
  bool operator ==(Object other) =>
      other is TextPagePosition &&
      other.section == section &&
      other.spread == spread &&
      other.spreadCount == spreadCount &&
      other.cfi == cfi &&
      other.progress.fraction == progress.fraction &&
      other.reason == reason &&
      identical(other.tocItem, tocItem);

  @override
  int get hashCode => Object.hash(section, spread, spreadCount, cfi, reason);

  @override
  String toString() =>
      'TextPagePosition($section:$spread/${spreadCount ?? '?'} $cfi '
      '${(fraction * 100).toStringAsFixed(1)}%)';
}

/// The model behind `TextPagesView`, usable without it: lays a text book
/// out for the view's size (through a [TextBookLayout]), knows which
/// spread is shown, turns and jumps, and reports [position].
///
/// Positions are kept as the CFI of the first thing shown, so a new size,
/// style or font lays the book out again and stays on the same text.
/// Operations run one at a time in the order they were asked for.
class TextPagesController extends ChangeNotifier {
  TextPagesController({
    required this.source,
    required BookStyle style,
    required BookFonts fonts,
    required this.images,
    TextPageSettings settings = const TextPageSettings(),
    TextScaler textScaler = TextScaler.noScaling,
    bool? rtl,
    String? initialCfi,
    double? initialFraction,
  }) : _rtlOverride = rtl,
       _rtl = rtl ?? source.rtl,
       _settings = settings,
       _layout = TextBookLayout(
         source: source,
         style: style,
         fonts: fonts,
         images: images,
         textScaler: textScaler,
       ),
       _initialCfi = initialCfi,
       _initialFraction = initialFraction,
       _progress = SectionProgress(
         [for (var i = 0; i < source.sectionCount; i++) source.sectionSize(i)],
         linear: [
           for (var i = 0; i < source.sectionCount; i++) source.isLinear(i),
         ],
       ) {
    final toc = source.toc;
    if (toc != null && toc.isNotEmpty) {
      unawaited(
        TocProgress.build(
          toc,
          sectionCount: source.sectionCount,
          resolve: source.resolveHref,
        ).then((value) {
          _toc = value;
          if (_current != null) _report(_reason);
        }),
      );
    }
  }

  final TextBookSource source;
  final BookImageCache images;

  /// Effective page progression, resolved before the first spread is shown.
  /// An explicit constructor value overrides content inference.
  bool get rtl => _rtl;
  bool _rtl;
  final bool? _rtlOverride;

  final TextBookLayout _layout;
  final SectionProgress _progress;
  TocProgress? _toc;
  TextPageSettings _settings;
  TextPageGeometry? _geometry;
  final String? _initialCfi;
  final double? _initialFraction;
  bool _opened = false;

  TextSectionLayout? _current;
  int _spread = 0;
  String? _anchor;
  TextRelocationReason _reason = TextRelocationReason.navigation;
  TextPagePosition? _position;
  Object? _error;
  bool _disposed = false;

  /// Operations wait for the one before.
  Future<void> _queue = Future.value();

  /// Increments with every relocation; background work started for an
  /// older one stops.
  int _epoch = 0;

  TextPageGeometry? get geometry => _geometry;
  TextPageSettings get settings => _settings;
  TextBookLayout get layout => _layout;

  /// Where the reader is; null until the first spread is shown.
  TextPagePosition? get position => _position;

  /// Why opening failed, if it did.
  Object? get error => _error;

  bool get isReady => _current != null && !_current!.isStale;

  int get columns => _geometry?.columns ?? 1;

  /// The view's size: the first one opens the book, later ones lay it out
  /// again at the same text. [landscape] is the window's orientation.
  void setViewport(Size size, {bool? landscape}) {
    final geometry = TextPageGeometry.of(size, _settings, landscape: landscape);
    if (geometry == _geometry) return;
    _geometry = geometry;
    _layout.setPageSize(geometry.columnWidth, geometry.pageHeight);
    _relayout();
  }

  set settings(TextPageSettings value) {
    if (value == _settings) return;
    _settings = value;
    final geometry = _geometry;
    if (geometry != null) setViewport(geometry.viewport);
  }

  set style(BookStyle value) {
    if (value == _layout.style) return;
    _layout.style = value;
    _relayout();
  }

  set fonts(BookFonts value) {
    _layout.fonts = value;
    _relayout();
  }

  set textScaler(TextScaler value) {
    _layout.textScaler = value;
    _relayout();
  }

  void _relayout() {
    if (_geometry == null) return;
    final generation = _layout.generation;
    if (_opened && _current != null && !_current!.isStale) return;
    _current = null;
    final anchor = _anchor;
    final first = !_opened;
    _opened = true;
    _serial(() async {
      if (generation != _layout.generation && _current != null) return;
      if (first && source.isFixedLayout) {
        throw const UnsupportedTextBookException(
          TextBookUnsupported.fixedLayout,
        );
      }
      if (first) {
        _rtl = _rtlOverride ?? await resolvePageProgressionRtl(source);
        if (_disposed) return;
        final cfi = _initialCfi;
        final fraction = _initialFraction;
        if (cfi != null &&
            await _goToCfi(cfi, TextRelocationReason.navigation)) {
          return;
        }
        if (fraction != null) {
          await _goToFraction(fraction, TextRelocationReason.navigation);
          return;
        }
        await _goToSection(_firstLinear(), TextRelocationReason.navigation);
        return;
      }
      if (anchor == null ||
          !await _goToCfi(anchor, TextRelocationReason.layout)) {
        await _goToSection(_firstLinear(), TextRelocationReason.layout);
      }
    });
  }

  /// The table of contents entry a section starts in, once the table is
  /// resolved.
  BookNavItem? tocItemOf(int section) => _toc?.itemAt(section);

  /// Increments when the selection on the spread shown should go: the
  /// view watches it.
  int get selectionClears => _selectionClears;
  int _selectionClears = 0;

  /// Clears the text selected in the view.
  void clearSelection() {
    _selectionClears++;
    notifyListeners();
  }

  /// The spread [delta] steps from the one shown, when it is laid out
  /// already: what the view draws beside the page while it turns. Null at
  /// the ends and while a neighbour is being prepared.
  TextSpread? spreadAt(int delta) {
    final current = _current;
    if (current == null || current.isStale) return null;
    final columns = this.columns;
    if (delta == 0) return _spreadOf(current, _spread);
    if (delta == 1) {
      final next = _spreadOf(current, _spread + 1);
      if (next != null) return next;
      if (!current.isComplete) return null;
      final index = _adjacentLinear(current.index, 1);
      final layout = index == null ? null : _layout.laidOut(index);
      return layout == null ? null : _spreadOf(layout, 0);
    }
    if (delta == -1) {
      if (_spread > 0) return _spreadOf(current, _spread - 1);
      final index = _adjacentLinear(current.index, -1);
      final layout = index == null ? null : _layout.laidOut(index);
      if (layout == null || !layout.isComplete) return null;
      return _spreadOf(layout, _lastSpread(layout, columns));
    }
    return null;
  }

  TextSpread? _spreadOf(TextSectionLayout layout, int spread) {
    final columns = this.columns;
    final first = spread * columns;
    if (spread < 0 || first >= layout.pages.length) return null;
    return TextSpread(
      layout,
      spread,
      layout.pages.sublist(
        first,
        math.min(first + columns, layout.pages.length),
      ),
    );
  }

  static int _lastSpread(TextSectionLayout layout, int columns) =>
      math.max(0, (layout.pages.length - 1) ~/ columns);

  /// Turns forward; false at the end of the book.
  Future<bool> next() => _serial(() => _turn(1));

  /// Turns backward; false at the start.
  Future<bool> previous() => _serial(() => _turn(-1));

  /// Opens the place [cfi] points to; false when it is not in the book.
  Future<bool> goToCfi(String cfi) =>
      _serial(() => _goToCfi(cfi, TextRelocationReason.navigation));

  /// Opens the page at [fraction] of the book (the slider).
  Future<void> goToFraction(double fraction) =>
      _serial(() => _goToFraction(fraction, TextRelocationReason.navigation));

  /// Opens a link's or a table of contents entry's target.
  Future<void> goToTarget(TextTarget target) =>
      _serial(() => _goToTarget(target, TextRelocationReason.navigation));

  /// Opens [href] as the book resolves it; false when it points nowhere.
  Future<bool> goToHref(String href) => _serial(() async {
    final target = await source.resolveHref(href);
    if (target == null) return false;
    await _goToTarget(target, TextRelocationReason.navigation);
    return true;
  });

  /// Opens section [index] at its start.
  Future<void> goToSection(int index) =>
      _serial(() => _goToSection(index, TextRelocationReason.navigation));

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) {
      if (_disposed) throw StateError('TextPagesController disposed');
      return operation();
    });
    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (_disposed) return;
        _error = error;
        notifyListeners();
      },
    );
    return result;
  }

  Future<bool> _turn(int direction) async {
    final current = await _ensureCurrent();
    if (current == null) return false;
    final columns = this.columns;
    if (direction > 0) {
      current.ensurePage((_spread + 1) * columns);
      if (current.pages.length > (_spread + 1) * columns) {
        _show(current, _spread + 1, TextRelocationReason.page);
        return true;
      }
      current.complete();
      if (current.pages.length > (_spread + 1) * columns) {
        _show(current, _spread + 1, TextRelocationReason.page);
        return true;
      }
      final index = _adjacentLinear(current.index, 1);
      if (index == null) return false;
      _show(await _layout.section(index), 0, TextRelocationReason.page);
      return true;
    }
    if (_spread > 0) {
      _show(current, _spread - 1, TextRelocationReason.page);
      return true;
    }
    final index = _adjacentLinear(current.index, -1);
    if (index == null) return false;
    final layout = await _layout.section(index)
      ..complete();
    _show(layout, _lastSpread(layout, columns), TextRelocationReason.page);
    return true;
  }

  /// The layout shown, laid out again if a font or size change dropped
  /// it.
  Future<TextSectionLayout?> _ensureCurrent() async {
    final current = _current;
    if (current != null && !current.isStale) return current;
    final anchor = _anchor;
    if (anchor != null && await _goToCfi(anchor, TextRelocationReason.layout)) {
      return _current;
    }
    return null;
  }

  Future<bool> _goToCfi(String cfi, TextRelocationReason reason) async {
    final index = source.sectionOfCfi(cfi);
    if (index == null || index < 0 || index >= source.sectionCount) {
      return false;
    }
    final layout = await _layout.section(index);
    var y = layout.locator.yOfCfi(cfi);
    while (y == null && !layout.isComplete) {
      layout.ensureHeight(layout.column.height + layout.pageHeight * 4);
      y = layout.locator.yOfCfi(cfi);
    }
    final page = y == null ? 0 : _pageAt(layout, y);
    _show(layout, page ~/ columns, reason, anchor: cfi);
    return true;
  }

  Future<void> _goToFraction(
    double fraction,
    TextRelocationReason reason,
  ) async {
    final (index, inSection) = _progress.section(fraction);
    final layout = await _layout.section(index)
      ..complete();
    final spreads = _lastSpread(layout, columns) + 1;
    final spread = math.min(spreads - 1, (inSection * spreads).floor());
    _show(layout, math.max(0, spread), reason);
  }

  Future<void> _goToTarget(
    TextTarget target,
    TextRelocationReason reason,
  ) async {
    final layout = await _layout.section(target.index);
    final anchor = target.anchor;
    if (anchor == null) {
      _show(layout, 0, reason);
      return;
    }
    var y = layout.locator.yOfAnchor(anchor);
    while (y == null && !layout.isComplete) {
      layout.ensureHeight(layout.column.height + layout.pageHeight * 4);
      y = layout.locator.yOfAnchor(anchor);
    }
    _show(layout, y == null ? 0 : _pageAt(layout, y) ~/ columns, reason);
  }

  Future<void> _goToSection(int index, TextRelocationReason reason) async {
    _show(await _layout.section(index), 0, reason);
  }

  int _pageAt(TextSectionLayout layout, double y) {
    layout.ensureHeight(y);
    return pageAtY(layout.pages, y);
  }

  int _firstLinear() {
    for (var i = 0; i < source.sectionCount; i++) {
      if (source.isLinear(i)) return i;
    }
    return 0;
  }

  /// The next (or previous) section in the reading order, skipping
  /// `linear="no"` ones as view.js does.
  int? _adjacentLinear(int index, int direction) {
    for (
      var i = index + direction;
      i >= 0 && i < source.sectionCount;
      i += direction
    ) {
      if (source.isLinear(i)) return i;
    }
    return null;
  }

  void _show(
    TextSectionLayout layout,
    int spread,
    TextRelocationReason reason, {
    String? anchor,
  }) {
    if (_disposed) return;
    layout.ensurePage(spread * columns);
    _current = layout;
    _spread = math.max(0, math.min(spread, _lastSpread(layout, columns)));
    _reason = reason;
    _error = null;
    _epoch++;
    final pages = _spreadOf(layout, _spread)?.pages;
    _anchor =
        anchor ??
        (pages == null
            ? layout.sectionCfi
            : layout.locator.rangeCfiAt(pages.first.top, pages.last.bottom));
    _layout.retain([
      layout.index,
      ?_adjacentLinear(layout.index, 1),
      ?_adjacentLinear(layout.index, -1),
    ]);
    _report(reason);
    _releaseRetired();
    unawaited(_prepareNeighbours(_epoch));
  }

  /// Layouts a change dropped stay drawable until the view has drawn the
  /// new spread in their place: the old page shows while the new one is
  /// laid out, never a blank one.
  void _releaseRetired() {
    if (!_layout.hasRetired) return;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (!_disposed) _layout.releaseRetired();
      })
      ..ensureVisualUpdate();
  }

  void _report(TextRelocationReason reason) {
    final current = _current;
    if (current == null || current.isStale) return;
    final columns = this.columns;
    final spreads = current.isComplete
        ? _lastSpread(current, columns) + 1
        : null;
    final spread = _spreadOf(current, _spread);
    final top = spread?.pages.first.top ?? 0;
    final double inSection;
    final double size;
    if (spreads != null) {
      inSection = _spread / spreads;
      size = 1 / spreads;
    } else {
      (inSection, size) = _estimate(
        current,
        top,
        spread?.pages.last.bottom ?? top,
      );
    }
    final bottom = spread?.pages.last.bottom ?? top;
    _position = TextPagePosition(
      section: current.index,
      spread: _spread,
      spreadCount: spreads,
      cfi: _anchor ?? current.sectionCfi,
      progress: _progress.progress(
        current.index,
        inSection,
        pageFraction: size,
      ),
      reason: reason,
      tocItem: _toc?.itemAt(
        current.index,
        document: current.prepared.document,
        end: current.locator.endPointAt(bottom),
      ),
    );
    notifyListeners();
  }

  /// The section fraction at [top] and a spread's share before the
  /// section is laid out whole: by characters of text before it.
  (double, double) _estimate(
    TextSectionLayout layout,
    double top,
    double bottom,
  ) {
    var total = 0;
    for (final paragraph in layout.prepared.boxes.paragraphs) {
      total += paragraph.text.length;
    }
    if (total == 0) return (0, 1);
    var before = 0;
    var shown = 0;
    for (final item in layout.column.items) {
      if (item is! ColumnText) continue;
      final length = item.paragraph.box.text.length;
      if (item.rect.bottom <= top) {
        before += length;
      } else if (item.rect.top < bottom) {
        shown += length;
      }
    }
    return (before / total, math.max(shown, 1) / total);
  }

  /// Lays out what a turn reaches next: the rest of this section, the
  /// first pages of the next one, the whole previous one.
  Future<void> _prepareNeighbours(int epoch) async {
    final current = _current;
    if (current == null) return;
    bool stale() => _disposed || epoch != _epoch || current.isStale;
    try {
      await current.completeInSlices(
        onPages: () {
          if (!stale()) notifyListeners();
        },
      );
      if (stale()) return;
      _report(_reason);
      final next = _adjacentLinear(current.index, 1);
      if (next != null) await _layout.section(next);
      if (stale()) return;
      final previous = _adjacentLinear(current.index, -1);
      if (previous != null) {
        final layout = await _layout.section(previous);
        if (stale()) return;
        await layout.completeInSlices();
      }
      if (!stale()) notifyListeners();
    } on Object {
      // A neighbour that fails to open fails again, visibly, when the
      // reader turns to it.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _layout.dispose();
    super.dispose();
  }
}
