import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../css/computed_style.dart';
import '../document/content_document.dart';
import '../document/text_point.dart';
import 'book_image_cache.dart';
import 'box_tree.dart';
import 'column_decoration.dart';
import 'column_decoration_painter.dart';
import 'column_layout.dart';
import 'column_pages.dart';
import 'paragraph_layout.dart';
import 'text_page_highlights.dart';
import 'text_page_selection.dart';

/// The cache key of image [src] as its section writes it.
typedef ImageKeyOf = String? Function(String src);

/// One page of a laid-out section: the slice [page] of [column], drawn
/// inside [padding] in its own layer, so a page turn moves it without
/// repainting. Images come from [images] and repaint the page when they
/// are decoded. Inside a `SelectionArea` or `SelectableRegion` its text is
/// selectable: each paragraph registers as a [PageParagraphSelectable], which
/// preserves source offsets for Flutter and the native selection adapter.
/// [highlights] are tinted under the text; they are ranges of
/// [document], the section's document, and need it.
class TextColumnPage extends StatefulWidget {
  const TextColumnPage({
    super.key,
    required this.column,
    required this.page,
    required this.images,
    required this.imageKey,
    this.padding = EdgeInsets.zero,
    this.document,
    this.highlights = const [],
  }) : assert(highlights.length == 0 || document != null);

  final ColumnLayout column;
  final ColumnPage page;
  final BookImageCache images;
  final ImageKeyOf imageKey;
  final EdgeInsets padding;
  final ContentDocument? document;

  /// In paint order: the last one is on top.
  final List<TextHighlight> highlights;

  @override
  State<TextColumnPage> createState() => _TextColumnPageState();
}

class _TextColumnPageState extends State<TextColumnPage> {
  /// The page's own selection container, made once a selection region is
  /// above it: it keeps the page's paragraphs in document order, and makes
  /// the page one selectable in the region, so pages side by side are
  /// ordered by where they are.
  PageSelectionDelegate? _delegate;

  @override
  void dispose() {
    _delegate?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = _TextColumnPageLeaf(widget);
    if (SelectionContainer.maybeOf(context) == null) return page;
    return SelectionContainer(
      delegate: _delegate ??= PageSelectionDelegate(),
      child: page,
    );
  }
}

class _TextColumnPageLeaf extends LeafRenderObjectWidget {
  const _TextColumnPageLeaf(this.config);

  final TextColumnPage config;

  @override
  RenderTextColumnPage createRenderObject(BuildContext context) =>
      RenderTextColumnPage(
        column: config.column,
        page: config.page,
        images: config.images,
        imageKey: config.imageKey,
        padding: config.padding,
        devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
        registrar: SelectionContainer.maybeOf(context),
        selectionColor: _selectionColor(context),
        document: config.document,
        highlights: config.highlights,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTextColumnPage renderObject,
  ) {
    renderObject
      ..column = config.column
      ..page = config.page
      ..images = config.images
      ..imageKey = config.imageKey
      ..padding = config.padding
      ..devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1
      ..registrar = SelectionContainer.maybeOf(context)
      ..selectionColor = _selectionColor(context)
      ..setHighlights(config.document, config.highlights);
  }

  static Color _selectionColor(BuildContext context) =>
      DefaultSelectionStyle.of(context).selectionColor ??
      DefaultSelectionStyle.defaultColor;
}

class RenderTextColumnPage extends RenderBox {
  RenderTextColumnPage({
    required ColumnLayout column,
    required ColumnPage page,
    required BookImageCache images,
    required ImageKeyOf imageKey,
    required EdgeInsets padding,
    required double devicePixelRatio,
    SelectionRegistrar? registrar,
    Color? selectionColor,
    ContentDocument? document,
    List<TextHighlight> highlights = const [],
  }) : _column = column,
       _page = page,
       _images = images,
       _imageKey = imageKey,
       _padding = padding,
       _devicePixelRatio = devicePixelRatio,
       _registrar = registrar,
       _selectionColor = selectionColor,
       _document = document,
       _highlights = highlights;

  ColumnLayout _column;
  set column(ColumnLayout value) {
    if (identical(value, _column)) return;
    _column = value;
    _placed = null;
    _semanticsText = null;
    markNeedsSemanticsUpdate();
    _rebuildSelectables();
    _listenToScrollers();
    markNeedsLayout();
  }

  ColumnPage _page;
  set page(ColumnPage value) {
    if (value == _page) return;
    _page = value;
    _placed = null;
    _semanticsText = null;
    markNeedsSemanticsUpdate();
    _rebuildSelectables();
    _listenToScrollers();
    markNeedsLayout();
  }

  SelectionRegistrar? _registrar;
  set registrar(SelectionRegistrar? value) {
    if (identical(value, _registrar)) return;
    _registrar = value;
    _rebuildSelectables();
  }

  Color? _selectionColor;
  set selectionColor(Color? value) {
    if (value == _selectionColor) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  ContentDocument? _document;
  List<TextHighlight> _highlights;

  /// Where the highlights fall on this page, worked out at the next paint.
  List<PlacedHighlight>? _placed;

  void setHighlights(ContentDocument? document, List<TextHighlight> value) {
    if (identical(document, _document) && listEquals(value, _highlights)) {
      return;
    }
    _document = document;
    _highlights = value;
    _placed = null;
    markNeedsPaint();
  }

  List<PlacedHighlight> get _placedHighlights {
    final document = _document;
    return _placed ??= document == null
        ? const []
        : placeHighlights(document, _column, _page, _highlights);
  }

  /// Column coordinates of [local], a point in this page; null outside
  /// the page's slice.
  Offset? _toColumn(Offset local) {
    final point = local - _padding.topLeft + Offset(0, _page.top);
    return _page.contains(point.dy) &&
            point.dx >= 0 &&
            point.dx <= _column.width
        ? point
        : null;
  }

  /// [point], a point in the column as shown, where the items of
  /// [scroller] are laid out; null when it is outside the scroller.
  static Offset? _inContent(ColumnScroller? scroller, Offset point) {
    if (scroller == null) return point;
    return scroller.viewport.contains(point) ? scroller.toContent(point) : null;
  }

  /// The scrollers this page shows a part of.
  List<ColumnScroller> _scrollers = const [];

  void _listenToScrollers() {
    for (final scroller in _scrollers) {
      scroller.offset.removeListener(_onScroll);
    }
    _scrollers = !attached
        ? const []
        : [
            for (final scroller in _column.scrollers)
              if (scroller.viewport.bottom > _page.top &&
                  scroller.viewport.top < _page.bottom)
                scroller,
          ];
    for (final scroller in _scrollers) {
      scroller.offset.addListener(_onScroll);
    }
  }

  void _onScroll() {
    for (final selectable in _selectables) {
      selectable.didScroll();
    }
    markNeedsPaint();
  }

  /// The part of the column that scrolls sideways under [local], a point
  /// in this page, or null.
  ColumnScroller? scrollerAt(Offset local) {
    final point = _toColumn(local);
    if (point == null) return null;
    for (final scroller in _scrollers) {
      if (scroller.viewport.contains(point)) return scroller;
    }
    return null;
  }

  /// The topmost highlight drawn at [local], a point in this page, or
  /// null: what a tap there opens.
  TextHighlight? highlightAt(Offset local) {
    final point = _toColumn(local);
    if (point == null) return null;
    final placed = _placedHighlights;
    for (var i = placed.length - 1; i >= 0; i--) {
      final at = _inContent(placed[i].item.scroller, point);
      if (at == null) continue;
      for (final rect in placed[i].rects) {
        if (rect.contains(at)) return placed[i].highlight;
      }
    }
    return null;
  }

  /// The link at [local], a point in this page: its `<a>` element, or
  /// null. Glyphs take [slop] logical pixels around them, so a footnote
  /// number is not a pixel hunt.
  int? linkAt(Offset local, {double slop = 4}) {
    final shown = local - _padding.topLeft + Offset(0, _page.top);
    if (!_page.contains(shown.dy)) return null;
    for (final item in _column.items) {
      final point = _inContent(item.scroller, shown);
      if (point == null || !item.rect.inflate(slop).contains(point)) continue;
      switch (item) {
        case ColumnImage(:final box):
          if (box.link >= 0) return box.link;
        case ColumnText(:final paragraph, :final rect):
          final link = _linkIn(paragraph, point - rect.topLeft, slop);
          if (link != null) return link;
        case ColumnMarker():
          break;
      }
    }
    return null;
  }

  static int? _linkIn(ParagraphLayout paragraph, Offset at, double slop) {
    final box = paragraph.box;
    final caret = paragraph.positionAt(at).offset;
    // The characters on both sides of the nearest caret position.
    for (final offset in [caret, caret - 1]) {
      if (offset < 0 || offset >= box.text.length) continue;
      final hit = paragraph
          .boxesFor(offset, offset + 1)
          .any((b) => b.toRect().inflate(slop).contains(at));
      if (!hit) continue;
      for (final atomic in box.atomics) {
        if (atomic.offset != offset) continue;
        switch (atomic) {
          case InlineImage(:final link) when link >= 0:
            return link;
          case InlineText(:final link) when link >= 0:
            return link;
          case InlineText(:final paragraph):
            // A note number: `<sup><a href>1</a></sup>`.
            for (final run in paragraph.runs) {
              if (run.link >= 0) return run.link;
            }
          case InlineBox(:final link) || InlineMath(:final link) when link >= 0:
            return link;
          case InlineImage() || InlineSpacer() || InlineBox() || InlineMath():
            break;
        }
      }
      for (final run in box.runs) {
        if (run.start <= offset && offset < run.end && run.link >= 0) {
          return run.link;
        }
      }
    }
    return null;
  }

  /// The boxes of highlight [id] on this page, in the page's coordinates:
  /// where its menu goes.
  List<Rect> highlightRects(String id) {
    final shift = _padding.topLeft - Offset(0, _page.top);
    final slice = Rect.fromLTWH(0, _page.top, _column.width, _page.height);
    return [
      for (final placed in _placedHighlights)
        if (placed.highlight.id == id)
          for (final rect in placed.rects)
            if (_shown(placed.item.scroller, rect) case final shown?
                when shown.overlaps(slice))
              shown.intersect(slice).shift(shift),
    ];
  }

  /// Where [rect], laid out in [scroller] (if any), is seen in the column;
  /// null when it is scrolled out of sight.
  static Rect? _shown(ColumnScroller? scroller, Rect rect) {
    if (scroller == null) return rect;
    final moved = rect.shift(Offset(-scroller.offset.value, 0));
    return moved.overlaps(scroller.viewport)
        ? moved.intersect(scroller.viewport)
        : null;
  }

  /// Where a selection edge event puts that edge at document point
  /// [point]: a point inside the character after it, or before it for a
  /// range's end ([isEnd]), in the page's coordinates. Null when the page
  /// does not show that character.
  Offset? selectionEdgeAt(TextPoint point, {required bool isEnd}) {
    final document = _document;
    if (document == null) return null;
    for (final part in pageTextParts(_column, _page)) {
      final offset = paragraphOffsetOf(
        document,
        part.item,
        point,
        isEnd: isEnd,
      );
      if (offset == null) continue;
      final char = isEnd ? offset - 1 : offset;
      if (char < part.start || char >= part.end) continue;
      return _edgeIn(part.item, char, isEnd: isEnd);
    }
    return null;
  }

  /// Where a selection edge event takes a whole line: the end of the
  /// page's first line for a range's end ([isEnd]), the start of its last
  /// line otherwise, past the spaces there. Null on a page without text.
  Offset? lineEdge({required bool isEnd}) {
    final parts = pageTextParts(_column, _page);
    if (parts.isEmpty) return null;
    final part = isEnd ? parts.first : parts.last;
    final paragraph = part.item.paragraph;
    final text = paragraph.box.text;
    bool blank(int char) => text[char].trim().isEmpty;
    // Lines by where they start: `lineAt` of a line's first offset can
    // answer the line before, whose caret after a trailing space is there.
    final lines = paragraph.lines.length;
    var line = 0;
    if (isEnd) {
      while (line + 1 < lines && paragraph.lineStart(line + 1) <= part.start) {
        line++;
      }
      final next = line + 1 < lines
          ? paragraph.lineStart(line + 1)
          : text.length;
      var char = math.min(next, part.end) - 1;
      while (char > part.start && blank(char)) {
        char--;
      }
      return _edgeIn(part.item, char, isEnd: true);
    }
    while (line + 1 < lines && paragraph.lineStart(line + 1) < part.end) {
      line++;
    }
    var char = math.max(paragraph.lineStart(line), part.start);
    while (char < part.end - 1 && blank(char)) {
      char++;
    }
    return _edgeIn(part.item, char, isEnd: false);
  }

  /// A point inside character [char] of [item]'s paragraph, near its end
  /// in the text's direction for a range's end ([isEnd]), near its start
  /// otherwise, in the page's coordinates.
  Offset? _edgeIn(ColumnText item, int char, {required bool isEnd}) {
    final boxes = item.paragraph.boxesFor(char, char + 1);
    if (boxes.isEmpty) return null;
    final box = boxes.first;
    final rect = box.toRect().shift(
      Offset(-(item.scroller?.offset.value ?? 0), 0),
    );
    final x = isEnd != (box.direction == TextDirection.rtl)
        ? rect.right - rect.width / 4
        : rect.left + rect.width / 4;
    return _padding.topLeft +
        item.rect.topLeft -
        Offset(0, _page.top) +
        Offset(x, rect.center.dy);
  }

  /// The selectable paragraphs on this page, while it has a registrar.
  List<PageParagraphSelectable> _selectables = const [];

  @visibleForTesting
  List<PageParagraphSelectable> get debugSelectables => _selectables;

  /// Paragraph fragments used by the platform selection adapter. Their
  /// offsets stay in the laid-out paragraph, including source-map markers.
  Iterable<PageParagraphSelectable> get selectionFragments => _selectables;

  /// The box around the selection's highlighted lines on this page, in
  /// the page's coordinates, or null: where a selection menu goes.
  Rect? get selectionBounds {
    Rect? bounds;
    for (final selectable in _selectables) {
      for (final rect in selectable.value.selectionRects) {
        bounds = bounds == null ? rect : bounds.expandToInclude(rect);
      }
    }
    return bounds;
  }

  /// What is selected on this page, or null.
  PageTextSelection? get selection {
    TextPoint? start;
    TextPoint? end;
    final texts = <String>[];
    for (final selectable in _selectables) {
      final points = selectable.selectedPoints;
      if (points == null) continue;
      start ??= points.start;
      end = points.end;
      texts.add(selectable.selectedText!);
    }
    if (start == null || end == null) return null;
    return PageTextSelection(start: start, end: end, text: texts.join('\n'));
  }

  void _disposeSelectables() {
    for (final selectable in _selectables) {
      selectable.dispose();
    }
    _selectables = const [];
  }

  void _rebuildSelectables() {
    _disposeSelectables();
    final registrar = _registrar;
    if (!attached || registrar == null) return;
    _selectables = PageParagraphSelectable.forPage(
      this,
      _column,
      _page,
      _padding.topLeft,
    );
    for (final selectable in _selectables) {
      selectable.registrar = registrar;
    }
  }

  BookImageCache _images;
  set images(BookImageCache value) {
    if (identical(value, _images)) return;
    if (attached) _images.removeListener(markNeedsPaint);
    _images = value;
    if (attached) _images.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  ImageKeyOf _imageKey;
  set imageKey(ImageKeyOf value) {
    if (identical(value, _imageKey)) return;
    _imageKey = value;
    markNeedsPaint();
  }

  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    _rebuildSelectables();
    markNeedsLayout();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _images.addListener(markNeedsPaint);
    _rebuildSelectables();
    _listenToScrollers();
  }

  @override
  void detach() {
    _disposeSelectables();
    _images.removeListener(markNeedsPaint);
    super.detach();
    _listenToScrollers();
  }

  @override
  void dispose() {
    _disposeSelectables();
    super.dispose();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(
      _column.width + _padding.horizontal,
      _page.height + _padding.vertical,
    ),
  );

  /// Not sized by the parent: the size follows the column, page and
  /// padding, and a page view reuses one page for the next.
  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  /// What a screen reader reads: the page's text, its paragraphs on lines
  /// of their own, in the book's direction.
  String? _semanticsText;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    final text = _semanticsText ??= [
      for (final part in pageTextParts(_column, _page))
        part.item.paragraph.box.plainText(part.start, part.end),
    ].join('\n');
    if (text.isEmpty) return;
    config
      ..isSemanticBoundary = true
      ..label = text
      ..textDirection = _directionOf(_column);
  }

  static TextDirection _directionOf(ColumnLayout column) {
    for (final item in column.items) {
      if (item is ColumnText) {
        return item.paragraph.box.style.direction == CssDirection.rtl
            ? TextDirection.rtl
            : TextDirection.ltr;
      }
    }
    return TextDirection.ltr;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // A page view drops a page's column only after it draws another.
    if (_column.isDisposed) return;
    paintColumnPage(
      context.canvas,
      _column,
      _page,
      offset + _padding.topLeft,
      images: _images,
      imageKey: _imageKey,
      devicePixelRatio: _devicePixelRatio,
      highlights: _placedHighlights,
    );
    for (final selectable in _selectables) {
      selectable.paint(context, offset, _selectionColor);
    }
  }
}

/// Paints the slice [page] of [column] with its top left at [origin],
/// clipped to the slice so the lines of the next page never show.
void paintColumnPage(
  Canvas canvas,
  ColumnLayout column,
  ColumnPage page,
  Offset origin, {
  required BookImageCache images,
  required ImageKeyOf imageKey,
  required double devicePixelRatio,
  List<PlacedHighlight> highlights = const [],
}) {
  canvas
    ..save()
    ..clipRect(Rect.fromLTWH(origin.dx, origin.dy, column.width, page.height))
    ..translate(origin.dx, origin.dy - page.top);
  bool visible(Rect rect) => rect.bottom > page.top && rect.top < page.bottom;
  final imagePaint = Paint()..filterQuality = FilterQuality.medium;
  void paintImage(String src, Rect rect) {
    final key = imageKey(src);
    if (key == null || rect.isEmpty) return;
    final image = images.image(key, (rect.width * devicePixelRatio).ceil());
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      imagePaint,
    );
  }

  // What scrolls sideways is drawn moved by its scroll, clipped to where
  // it is seen.
  void scrolled(ColumnScroller? scroller, void Function() paint) {
    if (scroller == null) return paint();
    canvas
      ..save()
      ..clipRect(scroller.viewport)
      ..translate(-scroller.offset.value, 0);
    paint();
    canvas.restore();
  }

  final shown = Rect.fromLTRB(0, page.top, column.width, page.bottom);
  void paintDecoration(ColumnDecoration decoration) {
    paintColumnDecoration(canvas, decoration);
    final background = decoration.backgroundImage;
    final key = background == null ? null : imageKey(background.source);
    final intrinsic = key == null ? null : images.sizeOf(key);
    if (background == null || intrinsic == null) return;
    final area = decoration.paddingBox;
    final scroll = decoration.scroller?.offset.value ?? 0;
    canvas
      ..save()
      ..clipRect(area);
    for (final tile in backgroundTiles(
      background,
      intrinsic,
      area,
      visible: shown.shift(Offset(scroll, 0)),
    )) {
      paintImage(background.source, tile);
    }
    canvas.restore();
  }

  for (final decoration in column.decorations) {
    if (!visible(decoration.rect)) continue;
    scrolled(decoration.scroller, () => paintDecoration(decoration));
  }
  for (final item in column.items) {
    if (item is ColumnText && visible(item.rect)) {
      scrolled(
        item.scroller,
        () => item.paragraph.paintDecorations(canvas, item.rect.topLeft),
      );
    }
  }
  // Under the text, so it stays as crisp and dark as around them.
  final tint = Paint();
  for (final placed in highlights) {
    tint.color = placed.highlight.color;
    scrolled(placed.item.scroller, () {
      for (final rect in placed.rects) {
        if (visible(rect)) canvas.drawRect(rect, tint);
      }
    });
  }
  void paintItem(ColumnItem item) {
    switch (item) {
      case ColumnText(:final paragraph, :final rect):
        paragraph.paint(canvas, rect.topLeft);
        for (final image in paragraph.images) {
          paintImage(image.src, image.rect.shift(rect.topLeft));
        }
      case ColumnImage(:final src, :final rect):
        paintImage(src, rect);
      case ColumnMarker(:final painter, :final rect):
        painter.paint(canvas, rect.topLeft);
    }
  }

  for (final item in column.items) {
    if (visible(item.rect)) scrolled(item.scroller, () => paintItem(item));
  }
  canvas.restore();
}
