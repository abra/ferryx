import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../css/css_values.dart';
import 'book_style.dart';
import 'box_tree.dart';
import 'column_decoration.dart';
import 'inline_styler.dart';
import 'line_exclusions.dart';
import 'column_scroller.dart';
import 'paragraph_layout.dart';

export 'column_decoration.dart' show ColumnDecoration;
export 'column_scroller.dart' show ColumnScroller;

part 'column_table.dart';

/// One section laid out as a single column of fixed width: CSS block
/// layout (CSS 2.1 §10, §8.3.1 margin collapsing) over the boxes, with
/// paragraphs laid out by [ParagraphLayout].
///
/// The column is what both reading modes show: pages are slices of it
/// cut at [breaks] (see `paginateColumn`), scrolling shows it whole.
/// A [ColumnLayoutTask] grows a column a little at a time; until it
/// [isComplete], [height] is how far it has got. Owns the paragraphs'
/// native resources: [dispose] when done.
class ColumnLayout {
  ColumnLayout._(this.width, this._builder);

  /// Lays [boxes] out [width] wide for pages [pageHeight] tall, all at
  /// once: images fit a page, and break opportunities follow the CSS
  /// fragmentation rules v1 supports (`page-break-*`, headings kept with
  /// what follows, orphans and widows, `page-break-inside: avoid`, rows
  /// and images never split).
  factory ColumnLayout.layout(
    SectionBoxes boxes, {
    required double width,
    required double pageHeight,
    required TextLayoutEnvironment text,
    required BookStyle bookStyle,
  }) {
    final task = ColumnLayoutTask(
      boxes,
      width: width,
      pageHeight: pageHeight,
      text: text,
      bookStyle: bookStyle,
    )..advance();
    return task.column;
  }

  final double width;
  final _ColumnBuilder _builder;

  /// Whether the whole section is laid out.
  bool get isComplete => _builder.isComplete;

  /// The height laid out so far; the column's height once complete.
  double get height => _builder.y;

  /// Where the content ends: [height] without the margins after it.
  double get contentHeight => _builder.contentEnd ?? _builder.y;

  /// Text, images and markers in document order.
  List<ColumnItem> get items => _builder.items;

  /// Backgrounds and borders, outer boxes first: painted under [items].
  /// A box still being laid out reaches down to [height].
  List<ColumnDecoration> get decorations => _builder.currentDecorations();

  /// Where a page may end, by `y`.
  List<ColumnBreak> get breaks => _builder.breaks;

  /// The parts that scroll sideways, in document order.
  List<ColumnScroller> get scrollers => _builder.scrollers;

  /// The laid-out paragraphs, in document order.
  Iterable<ColumnText> get paragraphs => items.whereType<ColumnText>();

  /// Whether [dispose] ran: the paragraphs can no longer be painted.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final item in items) {
      switch (item) {
        case ColumnText(:final paragraph):
          paragraph.dispose();
        case ColumnMarker(:final painter):
          painter.dispose();
        case ColumnImage():
          break;
      }
    }
    for (final scroller in scrollers) {
      scroller.dispose();
    }
    _builder.stop();
  }
}

/// Lays a section out a little at a time, so a long chapter never holds
/// a frame: [advance] works until a time budget is spent or a height is
/// laid out, while [column] grows. Breaks and pages above the laid-out
/// height never change afterwards.
class ColumnLayoutTask {
  ColumnLayoutTask(
    SectionBoxes boxes, {
    required double width,
    required double pageHeight,
    required TextLayoutEnvironment text,
    required BookStyle bookStyle,
  }) : _builder = _ColumnBuilder(
         pageHeight: pageHeight,
         text: text,
         bookStyle: bookStyle,
       ) {
    _builder.start(boxes.root, width);
    column = ColumnLayout._(width, _builder);
  }

  final _ColumnBuilder _builder;
  late final ColumnLayout column;

  bool get isComplete => _builder.isComplete;

  /// Lays out until the section is done, [budget] has passed (checked
  /// after each paragraph, image or table) or the column is [untilHeight]
  /// tall. Returns whether the section is done.
  bool advance({Duration? budget, double? untilHeight}) {
    final watch = budget == null ? null : (Stopwatch()..start());
    while (!_builder.isComplete) {
      _builder.step();
      if (untilHeight != null && _builder.y >= untilHeight) break;
      if (watch != null && watch.elapsed >= budget!) break;
    }
    return _builder.isComplete;
  }

  /// Finishes the layout in slices of [slice], with [pause] between them
  /// (by default a turn of the event loop, so frames get drawn).
  Future<void> complete({
    Duration slice = const Duration(milliseconds: 6),
    Future<void> Function()? pause,
  }) async {
    while (!advance(budget: slice)) {
      if (_builder.stopped) return;
      await (pause ?? () => Future<void>.delayed(Duration.zero))();
    }
  }
}

/// Something drawn in the column, at [rect].
sealed class ColumnItem {
  const ColumnItem(this.rect, {this.scroller});

  final Rect rect;

  /// The part of the column that scrolls it sideways, if any: [rect] is
  /// where it is with the scroll at 0.
  final ColumnScroller? scroller;

  /// The same item moved by [offset]: a table cell's content aligned in
  /// its row.
  ColumnItem shift(Offset offset) => _copy(rect.shift(offset), scroller);

  /// The same item, scrolled by [scroller].
  ColumnItem inScroller(ColumnScroller scroller) => _copy(rect, scroller);

  ColumnItem _copy(Rect rect, ColumnScroller? scroller) => switch (this) {
    ColumnText(:final paragraph) => ColumnText(
      paragraph,
      rect,
      scroller: scroller,
    ),
    ColumnImage(:final box) => ColumnImage(box, rect, scroller: scroller),
    ColumnMarker(:final painter) => ColumnMarker(
      painter,
      rect,
      scroller: scroller,
    ),
  };
}

class ColumnText extends ColumnItem {
  const ColumnText(this.paragraph, super.rect, {super.scroller});

  final ParagraphLayout paragraph;
}

/// A block-level image.
class ColumnImage extends ColumnItem {
  const ColumnImage(this.box, super.rect, {super.scroller});

  final ImageBox box;

  String get src => box.src;
}

/// A list item's marker, outside its content.
class ColumnMarker extends ColumnItem {
  const ColumnMarker(this.painter, super.rect, {super.scroller});

  final TextPainter painter;
}

enum ColumnBreakKind {
  /// A page may end here.
  allowed,

  /// Only if nothing better fits: after a heading, inside an avoid box.
  avoid,

  /// A page ends here: `page-break-before: always` and the like.
  forced,
}

/// A place a page may end: the top of a block, line or row. A page that
/// ends here holds what lies above [fit]; the next starts at [y]. They
/// differ by the margins between two blocks, which CSS truncates before
/// a break (CSS Fragmentation 3 §5.2): only the content above has to
/// fit.
class ColumnBreak {
  const ColumnBreak(this.y, this.kind, {double? fit}) : fit = fit ?? y;

  final double y;
  final double fit;
  final ColumnBreakKind kind;

  @override
  String toString() => '${kind.name}@$y${fit == y ? '' : ' (fits from $fit)'}';
}

/// Collapsing vertical margins: the largest positive plus the most
/// negative, CSS 2.1 §8.3.1.
class _Margin {
  const _Margin(this.positive, this.negative);

  static const zero = _Margin(0, 0);

  final double positive;
  final double negative;

  double get value => positive + negative;

  _Margin add(double margin) => margin >= 0
      ? _Margin(margin > positive ? margin : positive, negative)
      : _Margin(positive, margin < negative ? margin : negative);
}

/// A block whose border-box top waits for its first content, when its
/// top margin collapses with a child's.
/// A float as placed: its margin box in the column, on the left or the
/// right.
class _PlacedFloat {
  const _PlacedFloat(this.rect, {required this.left});

  final Rect rect;
  final bool left;
}

class _OpenBlock {
  double? top;
}

/// An open block: what closing it needs, and where its children go.
class _BlockFrame {
  _BlockFrame({
    required this.box,
    required this.marginBottom,
    required this.border,
    required this.padding,
    required this.boxLeft,
    required this.outer,
    required this.contentLeft,
    required this.contentWidth,
    required this.contentTop,
    required this.decorationIndex,
    required this.open,
    required this.hasTopEdge,
    required this.avoidsInside,
    required this.firstItem,
    required this.childrenInListItem,
    this.collapsed,
  });

  final BlockBox box;
  final double marginBottom;

  /// The border widths the box's geometry uses: its own, or half of a
  /// collapsed table cell's shared borders.
  final CssEdges<double> border;

  /// A collapsed table cell's resolved borders, which its decoration
  /// draws centred on the grid lines; null for every other box.
  final _CellBorders? collapsed;
  final CssEdges<double> padding;
  final double boxLeft;

  /// The border box's width.
  final double outer;
  final double contentLeft;
  final double contentWidth;
  final double contentTop;

  /// Its slot in the decorations, or -1.
  final int decorationIndex;
  final _OpenBlock open;
  final bool hasTopEdge;
  final bool avoidsInside;

  /// The first item laid out inside it, for its list marker.
  final int firstItem;
  final bool childrenInListItem;

  /// The next child to lay out.
  int next = 0;
}

class _ColumnBuilder {
  _ColumnBuilder({
    required this.pageHeight,
    required this.text,
    required this.bookStyle,
  });

  final double pageHeight;
  final TextLayoutEnvironment text;
  final BookStyle bookStyle;

  final items = <ColumnItem>[];
  final decorations = <ColumnDecoration?>[];
  final breaks = <ColumnBreak>[];
  final scrollers = <ColumnScroller>[];

  /// Nesting of tables being laid out: a table in a table never scrolls.
  int _tables = 0;

  double y = 0;
  _Margin _pending = _Margin.zero;
  final _open = <_OpenBlock>[];

  /// Set by a box that asks for a break before the next content.
  ColumnBreakKind? _nextBreak;

  /// Nesting of `page-break-inside: avoid` boxes.
  int _avoidInside = 0;

  /// Avoid boxes whose top edge is still to come: the break at their
  /// top is outside them, so they count from the edge after it.
  int _avoidFromNextEdge = 0;

  /// Nesting of table rows, which never split.
  int _noBreaks = 0;

  /// Whether content has been placed: a break before the first content
  /// would make an empty first page.
  bool _started = false;

  /// Floats placed so far, in column coordinates: lines that start
  /// beside one are shortened. A float and a table cell lay their
  /// content out with floats of their own (block formatting contexts).
  var _floats = <_PlacedFloat>[];

  /// The top of the last float placed: no float is placed higher.
  double _floatTop = 0;

  /// Floats met since the last edge, with their containing block's
  /// left and width: placed at the next edge, where the margins above it
  /// have collapsed (a float is as high as the line that follows it).
  final _waitingFloats = <({FloatBox box, double left, double width})>[];

  /// Open blocks, innermost last.
  final _stack = <_BlockFrame>[];
  bool _finished = false;
  bool stopped = false;

  bool get isComplete => _finished;

  void start(BlockBox root, double width) {
    _enterBlock(root, 0, width, inListItem: false);
  }

  /// Stops a layout whose column was disposed.
  void stop() {
    stopped = true;
    _stack.clear();
    _finished = true;
  }

  /// Lays out the next paragraph, image or table, entering and leaving
  /// the blocks around it.
  void step() {
    while (_stack.isNotEmpty) {
      final frame = _stack.last;
      if (frame.next >= frame.box.children.length) {
        _stack.removeLast();
        _exitBlock(frame);
        continue;
      }
      final child = frame.box.children[frame.next++];
      final listItem = frame.childrenInListItem;
      switch (child) {
        case ParagraphBox():
          _paragraph(
            child,
            frame.contentLeft,
            frame.contentWidth,
            listItem: listItem,
          );
          return;
        case TableBox():
          _table(child, frame.contentLeft, frame.contentWidth);
          return;
        case ImageBox():
          _image(child, frame.contentLeft, frame.contentWidth);
          return;
        case FloatBox():
          _float(child, frame.contentLeft, frame.contentWidth);
          return;
        case BlockBox():
          _enterBlock(
            child,
            frame.contentLeft,
            frame.contentWidth,
            inListItem: listItem,
          );
      }
    }
    if (!_finished) _finish();
  }

  /// Lays [box] out completely before returning: table cells (with
  /// [collapsed] borders in a collapsed table), captions and floats
  /// (whose own percentages are of [percentOf], their containing block's
  /// width).
  void _placeNow(
    BlockBox box,
    double left,
    double width, {
    _CellBorders? collapsed,
    double? percentOf,
  }) {
    final depth = _stack.length;
    _enterBlock(
      box,
      left,
      width,
      inListItem: false,
      collapsed: collapsed,
      percentOf: percentOf,
    );
    while (_stack.length > depth) {
      final frame = _stack.last;
      if (frame.next >= frame.box.children.length) {
        _stack.removeLast();
        _exitBlock(frame);
        continue;
      }
      final child = frame.box.children[frame.next++];
      switch (child) {
        case ParagraphBox():
          _paragraph(
            child,
            frame.contentLeft,
            frame.contentWidth,
            listItem: frame.childrenInListItem,
          );
        case TableBox():
          _table(child, frame.contentLeft, frame.contentWidth);
        case ImageBox():
          _image(child, frame.contentLeft, frame.contentWidth);
        case FloatBox():
          _float(child, frame.contentLeft, frame.contentWidth);
        case BlockBox():
          _enterBlock(
            child,
            frame.contentLeft,
            frame.contentWidth,
            inListItem: frame.childrenInListItem,
          );
      }
    }
  }

  /// [y] before the margins [_finish] added.
  double? contentEnd;

  void _finish() {
    _placeWaitingFloats(y + _pending.value);
    // The section holds its floats (the root is a block formatting
    // context).
    final floats = _floatsBottom();
    if (floats > y) y = floats;
    contentEnd = y;
    y += _pending.value > 0 ? _pending.value : 0;
    _pending = _Margin.zero;
    _finished = true;
  }

  /// Breaks in order of `y`; table cells side by side may place them out
  /// of order, though rows suppress their breaks.
  void _addBreak(ColumnBreak b) {
    // A float never breaks: nor do the lines beside it, so a page
    // keeps them together where it can.
    if (b.kind == ColumnBreakKind.allowed && _besideFloat(b.y)) {
      b = ColumnBreak(b.y, ColumnBreakKind.avoid, fit: b.fit);
    }
    if (breaks.isEmpty || b.y >= breaks.last.y) {
      breaks.add(b);
      return;
    }
    var lo = 0;
    var hi = breaks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (breaks[mid].y <= b.y) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    breaks.insert(lo, b);
  }

  /// Closed decorations, and the open ones down to the current height.
  List<ColumnDecoration> currentDecorations() {
    final open = <int, _BlockFrame>{
      for (final f in _stack)
        if (f.decorationIndex >= 0) f.decorationIndex: f,
    };
    return [
      for (var i = 0; i < decorations.length; i++)
        if (decorations[i] case final d?)
          d
        else if (open[i] case final frame?)
          _decorationOf(frame, frame.open.top ?? frame.contentTop, y),
    ];
  }

  /// Places a top edge (border, padding, the first line, an image):
  /// the collapsed margin above it is spent, a page may break here, and
  /// open blocks waiting for their top get it.
  void _placeEdge() {
    final above = y;
    y += _pending.value;
    _pending = _Margin.zero;
    _placeWaitingFloats(y);
    final kind =
        _nextBreak ??
        (_avoidInside > 0 ? ColumnBreakKind.avoid : ColumnBreakKind.allowed);
    if (_started && _noBreaks == 0) {
      _addBreak(ColumnBreak(y, kind, fit: above < y ? above : y));
    }
    _nextBreak = null;
    _avoidInside += _avoidFromNextEdge;
    _avoidFromNextEdge = 0;
    for (final open in _open) {
      open.top ??= y;
    }
  }

  void _requestBreak(ColumnBreakKind kind) {
    final current = _nextBreak;
    if (current == null || kind.index > current.index) _nextBreak = kind;
  }

  void _paragraph(
    ParagraphBox box,
    double left,
    double width, {
    required bool listItem,
  }) {
    _placeEdge();
    final top = y;
    // Floats wholly above shorten no line again.
    _floats.removeWhere((placed) => placed.rect.bottom <= top);
    final layout = ParagraphLayout.layout(
      box,
      width: width,
      environment: text,
      listItem: listItem,
      exclusions: _exclusionsAt(left, width, top),
    );
    items.add(
      ColumnText(layout, Rect.fromLTWH(left, top, width, layout.height)),
    );
    if (_noBreaks == 0) {
      final lines = layout.lines.length;
      final orphans = box.style.orphans;
      final widows = box.style.widows;
      final kind = _avoidInside > 0
          ? ColumnBreakKind.avoid
          : ColumnBreakKind.allowed;
      for (var i = 1; i < lines; i++) {
        if (i >= orphans && lines - i >= widows) {
          _addBreak(ColumnBreak(top + layout.lineTop(i), kind));
        }
      }
    }
    y = top + layout.height;
    _started = true;
  }

  /// The used margins of [box] in a containing block [width] wide; null
  /// for `auto`. Prose takes the reader's paragraph spacing, as
  /// foliate-js's `margin-block` on body text.
  ({double top, double bottom, double? left, double? right}) _margins(
    LayoutBox box,
    double width,
  ) {
    final s = box.style;
    double resolve(CssLength length) => InlineStyler.px(length, width);
    final top = s.margin.top;
    final bottom = s.margin.bottom;
    final left = s.margin.left;
    final right = s.margin.right;
    var marginTop = top == null ? 0.0 : resolve(top);
    var marginBottom = bottom == null ? 0.0 : resolve(bottom);
    if (box is BlockBox && box.isProse && bookStyle.useBookLayout) {
      marginTop = marginBottom = bookStyle.paragraphSpacing / 2 * s.fontSize;
    }
    return (
      top: marginTop,
      bottom: marginBottom,
      left: left == null ? null : resolve(left),
      right: right == null ? null : resolve(right),
    );
  }

  /// Opens [box]: its margins, top edge and geometry; its children are
  /// laid out by [step]. [inListItem]: [box] is a list item's child,
  /// whose paragraphs take no prose indent (`li > p` in foliate-js's CSS).
  void _enterBlock(
    BlockBox box,
    double left,
    double width, {
    required bool inListItem,
    _CellBorders? collapsed,
    double? percentOf,
  }) {
    final s = box.style;
    final base = percentOf ?? width;
    final margins = _margins(box, base);
    final border = collapsed?.half ?? s.borderWidth;
    final padding = CssEdges(
      InlineStyler.px(s.padding.top, base),
      InlineStyler.px(s.padding.right, base),
      InlineStyler.px(s.padding.bottom, base),
      InlineStyler.px(s.padding.left, base),
    );

    switch (s.pageBreakBefore) {
      case CssPageBreak.always || CssPageBreak.left || CssPageBreak.right:
        _requestBreak(ColumnBreakKind.forced);
      case CssPageBreak.avoid:
        _requestBreak(ColumnBreakKind.avoid);
      case CssPageBreak.auto:
        break;
    }
    _clear(s.clear);

    // Horizontal geometry: a set width narrows the box, auto margins
    // centre it.
    var marginLeft = margins.left ?? 0;
    var marginRight = margins.right ?? 0;
    var outer = width - marginLeft - marginRight;
    final frameWidth =
        border.left + border.right + padding.left + padding.right;
    // `box-sizing: border-box` sizes count the padding and border.
    final sizing = s.boxSizing == CssBoxSizing.borderBox ? frameWidth : 0.0;
    final specified = s.width == null
        ? null
        : InlineStyler.px(s.width!, base) - sizing;
    final maxWidth = s.maxWidth == null
        ? null
        : InlineStyler.px(s.maxWidth!, base) - sizing;
    var contentWidth = outer - frameWidth;
    if (specified != null && specified < contentWidth) contentWidth = specified;
    if (maxWidth != null && maxWidth < contentWidth) contentWidth = maxWidth;
    if (contentWidth < outer - frameWidth) {
      final spare = outer - frameWidth - contentWidth;
      if (margins.left == null && margins.right == null) {
        marginLeft += spare / 2;
        marginRight += spare / 2;
      } else if (margins.left == null) {
        marginLeft += spare;
      } else {
        marginRight += spare;
      }
      outer = width - marginLeft - marginRight;
    }
    if (contentWidth < 1) contentWidth = 1;
    final boxLeft = left + marginLeft;

    final decorated = collapsed == null
        ? _isDecorated(s)
        : collapsed.hasBorder || (s.backgroundColor >> 24) != 0;
    final decorationIndex = decorated ? decorations.length : -1;
    if (decorated) decorations.add(null);

    _pending = _pending.add(margins.top);
    final open = _OpenBlock();
    final hasTopEdge = border.top > 0 || padding.top > 0;
    if (hasTopEdge) {
      _placeEdge();
      open.top = y;
      y += border.top + padding.top;
    } else {
      _open.add(open);
    }
    final avoidsInside = s.avoidPageBreakInside;
    if (avoidsInside) {
      if (hasTopEdge) {
        _avoidInside++;
      } else {
        _avoidFromNextEdge++;
      }
    }
    _stack.add(
      _BlockFrame(
        box: box,
        marginBottom: margins.bottom,
        border: border,
        padding: padding,
        boxLeft: boxLeft,
        outer: outer,
        contentLeft: boxLeft + border.left + padding.left,
        contentWidth: contentWidth,
        contentTop: y,
        decorationIndex: decorationIndex,
        open: open,
        hasTopEdge: hasTopEdge,
        avoidsInside: avoidsInside,
        firstItem: items.length,
        childrenInListItem: box.marker != null || inListItem,
        collapsed: collapsed,
      ),
    );
  }

  /// Closes [frame]'s block after its children: bottom edge, marker,
  /// decoration, bottom margin and the break after it.
  void _exitBlock(_BlockFrame frame) {
    final box = frame.box;
    final s = box.style;
    final open = frame.open;
    if (frame.avoidsInside) {
      // An empty box never reached its top edge.
      if (!frame.hasTopEdge && open.top == null) {
        _avoidFromNextEdge--;
      } else {
        _avoidInside--;
      }
    }
    if (!frame.hasTopEdge) _open.remove(open);

    final specifiedHeight = s.height == null || s.height!.hasPercent
        ? null
        : InlineStyler.px(s.height!, 0) -
              (s.boxSizing == CssBoxSizing.borderBox
                  ? frame.border.top +
                        frame.border.bottom +
                        frame.padding.top +
                        frame.padding.bottom
                  : 0);
    final hasBottomEdge =
        frame.border.bottom > 0 ||
        frame.padding.bottom > 0 ||
        specifiedHeight != null;
    if (hasBottomEdge) {
      y += _pending.value;
      _pending = _Margin.zero;
      _placeWaitingFloats(y);
      open.top ??= frame.contentTop;
      if (specifiedHeight != null && y - frame.contentTop < specifiedHeight) {
        y = frame.contentTop + specifiedHeight;
      }
      y += frame.padding.bottom + frame.border.bottom;
    }
    final top = open.top ?? y + _pending.value;
    final bottom = hasBottomEdge ? y : (y > top ? y : top);

    if (box.marker != null) {
      _placeMarker(box, frame.firstItem, frame.contentLeft, top);
    }
    if (frame.decorationIndex >= 0) {
      decorations[frame.decorationIndex] = _decorationOf(frame, top, bottom);
    }

    _pending = _pending.add(frame.marginBottom);
    switch (s.pageBreakAfter) {
      case CssPageBreak.always || CssPageBreak.left || CssPageBreak.right:
        _requestBreak(ColumnBreakKind.forced);
      case CssPageBreak.avoid:
        _requestBreak(ColumnBreakKind.avoid);
      case CssPageBreak.auto:
        if (box.isHeading) _requestBreak(ColumnBreakKind.avoid);
    }
  }

  ColumnDecoration _decorationOf(_BlockFrame frame, double top, double bottom) {
    final s = frame.box.style;
    final rect = Rect.fromLTRB(
      frame.boxLeft,
      top,
      frame.boxLeft + frame.outer,
      bottom,
    );
    final collapsed = frame.collapsed;
    if (collapsed != null) {
      // Borders centred on the grid lines: half of each outside the box.
      final half = collapsed.half;
      return ColumnDecoration(
        rect: Rect.fromLTRB(
          rect.left - half.left,
          rect.top - half.top,
          rect.right + half.right,
          rect.bottom + half.bottom,
        ),
        background: s.backgroundColor,
        borderWidth: collapsed.width,
        borderStyle: collapsed.style,
        borderColor: collapsed.color,
        backgroundImage: s.backgroundImage,
      );
    }
    return ColumnDecoration(
      rect: rect,
      background: s.backgroundColor,
      borderWidth: frame.border,
      borderStyle: s.borderStyle,
      borderColor: s.borderColor,
      radius: s.borderRadius,
      backgroundImage: s.backgroundImage,
    );
  }

  bool _isDecorated(ComputedStyle s) {
    final hasBorder =
        s.borderWidth.top > 0 ||
        s.borderWidth.right > 0 ||
        s.borderWidth.bottom > 0 ||
        s.borderWidth.left > 0;
    final hasBackground =
        (s.backgroundColor >> 24) != 0 || s.backgroundImage != null;
    return hasBorder || hasBackground;
  }

  /// The marker of list item [box], right-aligned before its content on
  /// the first line's baseline (`list-style-position: outside`).
  void _placeMarker(
    BlockBox box,
    int firstItem,
    double contentLeft,
    double top,
  ) {
    final s = box.style;
    final style = text.styler.textStyle(s, s, prose: false);
    final painter = TextPainter(
      text: TextSpan(text: box.marker, style: style),
      textDirection: InlineStyler.direction(s),
      textScaler: text.textScaler,
    )..layout();
    var baseline =
        top + painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    for (var i = firstItem; i < items.length; i++) {
      final item = items[i];
      if (item is ColumnText) {
        baseline = item.rect.top + item.paragraph.firstBaseline;
        break;
      }
    }
    final gap = s.fontSize * 0.5;
    final markerTop =
        baseline -
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final markerLeft = s.direction == CssDirection.rtl
        ? contentLeft + gap
        : contentLeft - gap - painter.width;
    items.add(
      ColumnMarker(
        painter,
        Rect.fromLTWH(markerLeft, markerTop, painter.width, painter.height),
      ),
    );
  }

  /// Float [box] of the content box `[left, left + width]`: placed at the
  /// next edge.
  void _float(FloatBox box, double left, double width) =>
      _waitingFloats.add((box: box, left: left, width: width));

  /// Places the floats met since the last edge at [top].
  void _placeWaitingFloats(double top) {
    if (_waitingFloats.isEmpty) return;
    final floats = List.of(_waitingFloats);
    _waitingFloats.clear();
    for (final float in floats) {
      _placeFloat(float.box, float.left, float.width, top);
    }
  }

  /// Places float [box] at its edge of the content box `[left, left +
  /// width]`: at [top] (the next line's), never higher than an earlier
  /// float, beside the floats already there or below them where it does
  /// not fit (CSS 2.1 §9.5.1). Its width is its own (CSS's, kept even
  /// when its content is wider) or shrinks to fit its content. The flow
  /// stays where it is; lines placed after it are shortened.
  void _placeFloat(FloatBox box, double left, double width, double top) {
    final content = box.content;
    final margins = _margins(box, width);
    final marginsX = (margins.left ?? 0) + (margins.right ?? 0);
    Size? imageSize;
    double outer;
    if (content is ImageBox) {
      imageSize = ParagraphLayout.imageSize(
        content.style,
        text.imageSize(content.src),
        maxWidth: width - marginsX > 1 ? width - marginsX : 1,
        maxHeight: pageHeight,
      );
      outer = imageSize.width + marginsX;
    } else if (box.style.width case final cssWidth?) {
      final s = box.style;
      final edges =
          InlineStyler.px(s.padding.left, width) +
          InlineStyler.px(s.padding.right, width) +
          s.borderWidth.left +
          s.borderWidth.right;
      final specified = InlineStyler.px(cssWidth, width);
      outer =
          (s.boxSizing == CssBoxSizing.borderBox
              ? specified
              : specified + edges) +
          marginsX;
    } else {
      // Shrink-to-fit: the content's widest line where it fits, its
      // narrowest where nothing narrower would.
      final (:min, :max) = _intrinsic(content, width);
      outer = max < width ? max : (min > width ? min : width);
    }
    if (outer > width) outer = width;

    if (top < _floatTop) top = _floatTop;
    double x;
    while (true) {
      var start = left;
      var end = left + width;
      double? below;
      for (final placed in _floats) {
        final r = placed.rect;
        if (r.top > top || r.bottom <= top) continue;
        if (r.right <= left || r.left >= left + width) continue;
        if (placed.left) {
          if (r.right > start) start = r.right;
        } else if (r.left < end) {
          end = r.left;
        }
        if (below == null || r.bottom < below) below = r.bottom;
      }
      if (below == null || end - start >= outer - 0.5) {
        x = box.left ? start : end - outer;
        break;
      }
      top = below;
    }

    final double bottom;
    if (content is ImageBox) {
      final rect = Rect.fromLTWH(
        x + (margins.left ?? 0),
        top + margins.top,
        imageSize!.width,
        imageSize.height,
      );
      items.add(ColumnImage(content, rect));
      bottom = rect.bottom + margins.bottom;
    } else {
      bottom = _apart(top, () {
        switch (content) {
          case TableBox():
            _table(content, x, outer);
          case BlockBox():
            _placeNow(content, x, outer, percentOf: width);
          case ParagraphBox() || ImageBox() || FloatBox():
            break;
        }
      });
    }
    // Negative margins can leave the margin box no height: it then
    // shortens no line.
    _floats.add(
      _PlacedFloat(
        Rect.fromLTRB(x, top, x + outer, bottom > top ? bottom : top),
        left: box.left,
      ),
    );
    _floatTop = top;
  }

  /// Lays out what [place] places with the flow at [top] and nothing
  /// around it: no margin pending above, no breaks, no open block
  /// waiting for its top, floats of its own. The flow is put back after.
  /// Returns the bottom of what was placed, its margin below included.
  double _apart(double top, void Function() place) {
    final flowY = y;
    final pending = _pending;
    final started = _started;
    final nextBreak = _nextBreak;
    final avoidFromNextEdge = _avoidFromNextEdge;
    final open = List.of(_open);
    _open.clear();
    y = top;
    _pending = _Margin.zero;
    _nextBreak = null;
    _avoidFromNextEdge = 0;
    _noBreaks++;
    try {
      var bottom = double.negativeInfinity;
      final floats = _withOwnFloats(() {
        place();
        bottom = y + (_pending.value > 0 ? _pending.value : 0);
      });
      return floats > bottom ? floats : bottom;
    } finally {
      _noBreaks--;
      y = flowY;
      _pending = pending;
      _started = started;
      _nextBreak = nextBreak;
      _avoidFromNextEdge = avoidFromNextEdge;
      _open
        ..clear()
        ..addAll(open);
    }
  }

  /// Runs [place] with floats of its own, then puts the floats around
  /// back. Returns the bottom of the floats it placed, or -infinity.
  double _withOwnFloats(void Function() place) {
    final floats = _floats;
    final floatTop = _floatTop;
    final waiting = List.of(_waitingFloats);
    _waitingFloats.clear();
    _floats = [];
    _floatTop = double.negativeInfinity;
    try {
      place();
      _placeWaitingFloats(y + _pending.value);
      return _floatsBottom();
    } finally {
      _floats = floats;
      _floatTop = floatTop;
      _waitingFloats
        ..clear()
        ..addAll(waiting);
    }
  }

  /// The lowest float's bottom, or -infinity.
  double _floatsBottom() {
    var bottom = double.negativeInfinity;
    for (final placed in _floats) {
      if (placed.rect.bottom > bottom) bottom = placed.rect.bottom;
    }
    return bottom;
  }

  /// Whether [y] is inside a float, below its top.
  bool _besideFloat(double y) {
    for (final placed in _floats) {
      if (placed.rect.top < y - 0.5 && y < placed.rect.bottom - 0.5) {
        return true;
      }
    }
    return false;
  }

  /// The floats beside a paragraph placed at `[left, left + width]` from
  /// [top], in its coordinates; null when none is.
  LineExclusions? _exclusionsAt(double left, double width, double top) {
    List<FloatArea>? areas;
    for (final placed in _floats) {
      final r = placed.rect;
      if (r.bottom <= top || r.right <= left || r.left >= left + width) {
        continue;
      }
      (areas ??= []).add(
        FloatArea(r.translate(-left, -top), left: placed.left),
      );
    }
    return areas == null ? null : LineExclusions(areas);
  }

  /// Moves the flow below the floats [clear] names (CSS 2.1 §9.5.2),
  /// spending the margin above there.
  void _clear(CssClear clear) {
    if (clear == CssClear.none) return;
    _placeWaitingFloats(y + _pending.value);
    var floor = double.negativeInfinity;
    for (final placed in _floats) {
      final named = switch (clear) {
        CssClear.left => placed.left,
        CssClear.right => !placed.left,
        CssClear.both || CssClear.none => true,
      };
      if (named && placed.rect.bottom > floor) floor = placed.rect.bottom;
    }
    if (y + _pending.value < floor) {
      y = floor;
      _pending = _Margin.zero;
    }
  }

  /// Moves the flow below the floats over `[left, left + width]`: an
  /// image or a table does not go beside one in v1.
  void _clearBeside(double left, double width) {
    _placeWaitingFloats(y + _pending.value);
    var floor = double.negativeInfinity;
    for (final placed in _floats) {
      final r = placed.rect;
      if (r.right <= left || r.left >= left + width) continue;
      if (r.bottom > floor) floor = r.bottom;
    }
    if (y + _pending.value < floor) {
      y = floor;
      _pending = _Margin.zero;
    }
  }

  void _image(ImageBox box, double left, double width) {
    final s = box.style;
    _clear(s.clear);
    _clearBeside(left, width);
    final margins = _margins(box, width);
    _pending = _pending.add(margins.top);
    _placeEdge();
    final Size size;
    final viewBox = box.viewBox;
    if (viewBox != null) {
      // An SVG wrapper scales its image to fit, as covers expect.
      final scale = [
        width / viewBox.width,
        pageHeight / viewBox.height,
      ].reduce((a, b) => a < b ? a : b);
      size = Size(viewBox.width * scale, viewBox.height * scale);
    } else {
      size = ParagraphLayout.imageSize(
        s,
        text.imageSize(box.src),
        maxWidth: width,
        maxHeight: pageHeight,
      );
    }
    final double x;
    if (s.float == CssFloat.right) {
      x = left + width - (margins.right ?? 0) - size.width;
    } else if (s.float == CssFloat.left) {
      x = left + (margins.left ?? 0);
    } else if (viewBox != null ||
        (margins.left == null && margins.right == null)) {
      x = left + (width - size.width) / 2;
    } else if (margins.left == null) {
      x = left + width - (margins.right ?? 0) - size.width;
    } else {
      x = left + margins.left!;
    }
    items.add(ColumnImage(box, Rect.fromLTWH(x, y, size.width, size.height)));
    y += size.height;
    _started = true;
    _pending = _pending.add(margins.bottom);
  }
}
