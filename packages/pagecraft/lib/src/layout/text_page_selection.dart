import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../css/computed_style.dart';
import '../document/text_point.dart';
import 'column_layout.dart';
import 'box_tree.dart';
import 'column_pages.dart';
import 'paragraph_layout.dart';

/// One paragraph's lines on one page, as a [Selectable]: a text page
/// registers one per paragraph it shows with the enclosing
/// `SelectionArea` or `SelectableRegion`, which provides Flutter's adaptive
/// selection gestures, handles, magnifier and keyboard behaviour, as
/// `RenderParagraph` does for `Text`.
///
/// Coordinates are the page's: [origin] is where the paragraph's top
/// left sits on the page, moved by its scroller's scroll for a paragraph
/// in a table that scrolls sideways (the page calls [didScroll]); then
/// only what is in the scroller's viewport can be selected, and a handle
/// whose edge is out of it is hidden. Offsets are the paragraph's text
/// offsets; the fragment covers `[start, end)`, the lines whole on this
/// page, so a paragraph split across pages is two fragments.
class PageParagraphSelectable
    with Selectable, ChangeNotifier, SelectionRegistrant {
  PageParagraphSelectable({
    required RenderBox page,
    required this.item,
    required this.order,
    required Offset origin,
    required this.start,
    required this.end,
  }) : _page = page,
       _origin = origin;

  /// The fragments of [column]'s page [page], placed at [inset] in the
  /// page's render box.
  static List<PageParagraphSelectable> forPage(
    RenderBox renderPage,
    ColumnLayout column,
    ColumnPage page,
    Offset inset,
  ) => [
    for (final part in pageTextParts(column, page))
      PageParagraphSelectable(
        page: renderPage,
        item: part.item,
        order: part.order,
        origin:
            inset + Offset(part.item.rect.left, part.item.rect.top - page.top),
        start: part.start,
        end: part.end,
      ),
  ];

  final RenderBox _page;
  final ColumnText item;

  /// The item's index in its column: document order, which the page's
  /// selection container sorts by.
  final int order;

  final Offset _origin;
  final int start;
  final int end;

  Offset get origin {
    final scroller = item.scroller;
    return scroller == null
        ? _origin
        : _origin - Offset(scroller.offset.value, 0);
  }

  /// Where the paragraph's scroller shows it, on the page; null when the
  /// paragraph does not scroll.
  Rect? get _viewport =>
      item.scroller?.viewport.shift(_origin - item.rect.topLeft);

  /// The paragraph's scroller moved: its text is elsewhere on the page.
  void didScroll() {
    _boxes = null;
    if (_selectionStart == null || _selectionEnd == null) return;
    _geometry = _computeGeometry();
    notifyListeners();
  }

  ParagraphLayout get _paragraph => item.paragraph;

  int? _selectionStart;
  int? _selectionEnd;

  /// The word a long press selected here, kept while its drag extends the
  /// selection by words.
  TextRange? _originWord;

  /// The selected text range, normalized, or null.
  TextRange? get selection {
    final a = _selectionStart;
    final b = _selectionEnd;
    if (a == null || b == null) return null;
    return TextRange(start: math.min(a, b), end: math.max(a, b));
  }

  /// The selected range as document points, or null when nothing here is
  /// selected (or the selection is empty).
  ({TextPoint start, TextPoint end})? get selectedPoints {
    final range = selection;
    if (range == null || range.isCollapsed) return null;
    final map = _paragraph.box.sourceMap;
    final start = map.toSource(range.start);
    final end = map.toSourceEnd(range.end);
    if (start == null || end == null) return null;
    return (
      start: TextPoint(start.node, start.offset),
      end: TextPoint(end.node, end.offset),
    );
  }

  /// The selected text, as [ParagraphBox.plainText] gives it.
  String? get selectedText {
    final range = selection;
    if (range == null || range.isCollapsed) return null;
    return _paragraph.box.plainText(range.start, range.end);
  }

  LayerLink? _startHandle;
  LayerLink? _endHandle;

  SelectionGeometry _geometry = const SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: true,
  );

  @override
  SelectionGeometry get value => _geometry;

  List<Rect>? _boxes;

  @override
  List<Rect> get boundingBoxes => _boxes ??= _clipped([
    for (final box in _paragraph.boxesFor(
      start,
      end,
      heightStyle: ui.BoxHeightStyle.max,
    ))
      box.toRect().shift(origin),
  ]);

  /// [rects] within the paragraph's scroller, if it has one.
  List<Rect> _clipped(List<Rect> rects) {
    final viewport = _viewport;
    if (viewport == null) return rects;
    return [
      for (final rect in rects)
        if (rect.overlaps(viewport)) rect.intersect(viewport),
    ];
  }

  /// [point], or null when it is out of the paragraph's scroller.
  SelectionPoint? _seen(SelectionPoint point) {
    final viewport = _viewport;
    final x = point.localPosition.dx;
    return viewport == null ||
            (x >= viewport.left - 0.5 && x <= viewport.right + 0.5)
        ? point
        : null;
  }

  Rect get _rect {
    final boxes = boundingBoxes;
    if (boxes.isEmpty) return Rect.fromLTWH(origin.dx, origin.dy, 0, 0);
    return boxes.skip(1).fold(boxes.first, (r, b) => r.expandToInclude(b));
  }

  @override
  Size get size => _page.size;

  @override
  int get contentLength => end - start;

  @override
  Matrix4 getTransformTo(RenderObject? ancestor) =>
      _page.getTransformTo(ancestor);

  TextDirection get _direction =>
      _paragraph.box.style.direction == CssDirection.rtl
      ? TextDirection.rtl
      : TextDirection.ltr;

  Offset _toLocal(Offset global) {
    final transform = _page.getTransformTo(null)..invert();
    return MatrixUtils.transformPoint(transform, global);
  }

  int _offsetAt(Offset local) =>
      _paragraph.positionAt(local - origin).offset.clamp(start, end);

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final oldStart = _selectionStart;
    final oldEnd = _selectionEnd;
    final SelectionResult result;
    switch (event) {
      case SelectionEdgeUpdateEvent():
        result = _updateEdge(
          event.globalPosition,
          isEnd: event.type == SelectionEventType.endEdgeUpdate,
          byWord: event.granularity == TextGranularity.word,
        );
      case ClearSelectionEvent():
        _selectionStart = _selectionEnd = null;
        _originWord = null;
        result = SelectionResult.none;
      case SelectAllSelectionEvent():
        _selectionStart = start;
        _selectionEnd = end;
        result = SelectionResult.none;
      case SelectWordSelectionEvent():
        result = _selectWord(event.globalPosition);
      case SelectParagraphSelectionEvent():
        _selectionStart = start;
        _selectionEnd = end;
        result = event.absorb ? SelectionResult.next : SelectionResult.end;
      case GranularlyExtendSelectionEvent():
        result = _extendGranularly(event);
      case DirectionallyExtendSelectionEvent():
        result = _extendDirectionally(event);
      default:
        result = SelectionResult.none;
    }
    if (oldStart != _selectionStart || oldEnd != _selectionEnd) {
      _geometry = _computeGeometry();
      _page.markNeedsPaint();
      notifyListeners();
    }
    return result;
  }

  SelectionResult _updateEdge(
    Offset global, {
    required bool isEnd,
    required bool byWord,
  }) {
    final local = _toLocal(global);
    final rect = _rect;
    if (rect.isEmpty) return SelectionUtils.getResultBasedOnRect(rect, local);
    final adjusted = SelectionUtils.adjustDragOffset(
      rect,
      local,
      direction: _direction,
    );
    var offset = _offsetAt(adjusted);
    if (byWord) {
      final word = _paragraph.wordAt(offset);
      final origin = _originWord;
      if (origin != null && isEnd) {
        // A long-press drag: the pressed word stays selected whichever
        // way the finger goes, as in `RenderParagraph`.
        final backward = offset < origin.start;
        _selectionStart = backward ? origin.end : origin.start;
        offset = backward ? word.start : math.max(word.end, origin.end);
      } else {
        // The edge takes the whole word on its side of the other edge.
        final other = isEnd ? _selectionStart : _selectionEnd;
        final isMax = other == null ? isEnd : offset >= other;
        offset = isMax ? word.end : word.start;
      }
      offset = offset.clamp(start, end);
    }
    // Only the moving edge changes; the container brings the other one to
    // each fragment it spans.
    if (isEnd) {
      _selectionEnd = offset;
    } else {
      _selectionStart = offset;
    }
    if (offset == end) return SelectionResult.next;
    if (offset == start) return SelectionResult.previous;
    return SelectionUtils.getResultBasedOnRect(rect, local);
  }

  SelectionResult _selectWord(Offset global) {
    final offset = _paragraph.positionAt(_toLocal(global) - origin).offset;
    final current = selection;
    if (current != null &&
        !current.isCollapsed &&
        offset >= current.start &&
        offset <= current.end) {
      return SelectionResult.end;
    }
    final word = _paragraph.wordAt(offset);
    if (word.end <= start && word.start < start) {
      return SelectionResult.previous;
    }
    if (word.start >= end && word.end > end) return SelectionResult.next;
    _selectionStart = math.max(word.start, start);
    _selectionEnd = math.min(word.end, end);
    _originWord = TextRange(start: _selectionStart!, end: _selectionEnd!);
    return SelectionResult.end;
  }

  SelectionResult _extendGranularly(GranularlyExtendSelectionEvent event) {
    if (_selectionStart == null || _selectionEnd == null) {
      // Nothing selected here: the selection enters from a neighbour.
      final edge = event.forward ? start : end;
      _selectionStart = _selectionEnd = edge;
    }
    var offset = event.isEnd ? _selectionEnd! : _selectionStart!;
    final text = _paragraph.box.text;
    switch (event.granularity) {
      case TextGranularity.character:
        offset += event.forward ? 1 : -1;
      case TextGranularity.word:
        if (event.forward) {
          while (offset < end && text.codeUnitAt(offset) == 0x20) {
            offset++;
          }
          offset = _paragraph.wordAt(offset).end;
        } else {
          while (offset > start && text.codeUnitAt(offset - 1) == 0x20) {
            offset--;
          }
          offset = offset <= start
              ? start
              : _paragraph.wordAt(offset - 1).start;
        }
      case TextGranularity.line:
        final line = _paragraph.lineAt(
          event.forward ? offset : math.max(start, offset - 1),
        );
        offset = event.forward
            ? (line + 1 < _paragraph.lines.length
                  ? _paragraph.lineStart(line + 1)
                  : text.length)
            : _paragraph.lineStart(line);
      case TextGranularity.paragraph || TextGranularity.document:
        offset = event.forward ? end : start;
    }
    offset = offset.clamp(start, end);
    if (event.isEnd) {
      _selectionEnd = offset;
    } else {
      _selectionStart = offset;
    }
    if (event.forward && offset == end) return SelectionResult.next;
    if (!event.forward && offset == start) return SelectionResult.previous;
    return SelectionResult.end;
  }

  SelectionResult _extendDirectionally(
    DirectionallyExtendSelectionEvent event,
  ) {
    if (_selectionStart == null || _selectionEnd == null) {
      final edge = switch (event.direction) {
        SelectionExtendDirection.previousLine ||
        SelectionExtendDirection.backward => end,
        SelectionExtendDirection.nextLine ||
        SelectionExtendDirection.forward => start,
      };
      _selectionStart = _selectionEnd = edge;
    }
    final current = event.isEnd ? _selectionEnd! : _selectionStart!;
    final line = _paragraph.lineAt(current);
    final local = _toLocal(Offset(event.dx, 0)).dx - origin.dx;
    int offset;
    switch (event.direction) {
      case SelectionExtendDirection.previousLine:
        if (line == 0 || _paragraph.lineStart(line) <= start) {
          offset = start;
        } else {
          final y =
              (_paragraph.lineTop(line - 1) + _paragraph.lineTop(line)) / 2;
          offset = _paragraph.positionAt(Offset(local, y)).offset;
        }
      case SelectionExtendDirection.nextLine:
        if (line + 1 >= _paragraph.lines.length) {
          offset = end;
        } else {
          final y =
              (_paragraph.lineTop(line + 1) + _paragraph.lineTop(line + 2)) / 2;
          offset = _paragraph.positionAt(Offset(local, y)).offset;
        }
      case SelectionExtendDirection.forward:
        offset = end;
      case SelectionExtendDirection.backward:
        offset = start;
    }
    offset = offset.clamp(start, end);
    if (event.isEnd) {
      _selectionEnd = offset;
    } else {
      _selectionStart = offset;
    }
    if (offset == end && event.direction != SelectionExtendDirection.backward) {
      return SelectionResult.next;
    }
    if (offset == start &&
        event.direction != SelectionExtendDirection.forward) {
      return SelectionResult.previous;
    }
    return SelectionResult.end;
  }

  SelectionGeometry _computeGeometry() {
    final a = _selectionStart;
    final b = _selectionEnd;
    if (a == null || b == null) {
      return const SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: true,
      );
    }
    final collapsed = a == b;
    final reversed = a > b;
    final flip = reversed != (_direction == TextDirection.rtl);
    final (startType, endType) = switch ((collapsed, flip)) {
      (true, _) => (
        TextSelectionHandleType.collapsed,
        TextSelectionHandleType.collapsed,
      ),
      (false, true) => (
        TextSelectionHandleType.right,
        TextSelectionHandleType.left,
      ),
      (false, false) => (
        TextSelectionHandleType.left,
        TextSelectionHandleType.right,
      ),
    };
    final origin = this.origin;
    return SelectionGeometry(
      startSelectionPoint: _seen(
        SelectionPoint(
          localPosition: origin + _paragraph.caretBottom(a),
          lineHeight: _paragraph.caretHeight(a),
          handleType: startType,
        ),
      ),
      endSelectionPoint: _seen(
        SelectionPoint(
          localPosition: origin + _paragraph.caretBottom(b),
          lineHeight: _paragraph.caretHeight(b),
          handleType: endType,
        ),
      ),
      selectionRects: _clipped([
        for (final box in _paragraph.boxesFor(math.min(a, b), math.max(a, b)))
          box.toRect().shift(origin),
      ]),
      status: collapsed
          ? SelectionStatus.collapsed
          : SelectionStatus.uncollapsed,
      hasContent: true,
    );
  }

  @override
  SelectedContent? getSelectedContent() {
    final text = selectedText;
    return text == null ? null : SelectedContent(plainText: text);
  }

  @override
  SelectedContentRange? getSelection() {
    final a = _selectionStart;
    final b = _selectionEnd;
    if (a == null || b == null) return null;
    return SelectedContentRange(startOffset: a - start, endOffset: b - start);
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (_startHandle == startHandle && _endHandle == endHandle) return;
    _startHandle = startHandle;
    _endHandle = endHandle;
    if (_page.attached) {
      _page.markNeedsPaint();
    }
  }

  /// Paints the selection tint and the handles' anchors, at the page's
  /// [offset].
  void paint(PaintingContext context, Offset offset, Color? selectionColor) {
    final geometry = _geometry;
    if (geometry.status == SelectionStatus.none) return;
    if (selectionColor != null && geometry.selectionRects.isNotEmpty) {
      final paint = Paint()..color = selectionColor;
      for (final rect in geometry.selectionRects) {
        context.canvas.drawRect(rect.shift(offset), paint);
      }
    }
    final startPoint = geometry.startSelectionPoint;
    final startHandle = _startHandle;
    if (startHandle != null && startPoint != null) {
      context.pushLayer(
        LeaderLayer(
          link: startHandle,
          offset: offset + startPoint.localPosition,
        ),
        (context, offset) {},
        Offset.zero,
      );
    }
    final endPoint = geometry.endSelectionPoint;
    final endHandle = _endHandle;
    if (endHandle != null && endPoint != null) {
      context.pushLayer(
        LeaderLayer(link: endHandle, offset: offset + endPoint.localPosition),
        (context, offset) {},
        Offset.zero,
      );
    }
  }
}

/// What is selected on one page: from [start] to [end] in the section's
/// document and the text, paragraphs joined by line breaks.
@immutable
class PageTextSelection {
  const PageTextSelection({
    required this.start,
    required this.end,
    required this.text,
  });

  final TextPoint start;
  final TextPoint end;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is PageTextSelection &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'PageTextSelection($start, $end, "$text")';
}

/// The selection container of one page: its paragraphs in document
/// order, not the screen order a region uses (a table's cells sit side by
/// side, a float beside the text it wraps), and their text joined by line
/// breaks.
class PageSelectionDelegate extends StaticSelectionContainerDelegate {
  @override
  Comparator<Selectable> get compareOrder => _documentOrder;

  static int _documentOrder(Selectable a, Selectable b) =>
      (a as PageParagraphSelectable).order -
      (b as PageParagraphSelectable).order;

  @override
  SelectedContent? getSelectedContent() {
    final texts = [
      for (final selectable in selectables)
        if (selectable.getSelectedContent() case final content?)
          content.plainText,
    ];
    return texts.isEmpty ? null : SelectedContent(plainText: texts.join('\n'));
  }
}

/// The text [page] of [column] shows: for each paragraph on it, its index
/// in the column (document order) and the text offsets `[start, end)` of
/// its lines that are whole on the page. A paragraph split across pages
/// is in both, each with its own lines.
List<({ColumnText item, int order, int start, int end})> pageTextParts(
  ColumnLayout column,
  ColumnPage page,
) {
  final out = <({ColumnText item, int order, int start, int end})>[];
  final items = column.items;
  for (var order = 0; order < items.length; order++) {
    final item = items[order];
    if (item is! ColumnText) continue;
    if (item.rect.bottom <= page.top + 0.5 ||
        item.rect.top >= page.bottom - 0.5) {
      continue;
    }
    final paragraph = item.paragraph;
    final lines = paragraph.lines.length;
    if (lines == 0 || paragraph.box.text.isEmpty) continue;
    var first = 0;
    while (first < lines &&
        item.rect.top + paragraph.lineTop(first) < page.top - 0.5) {
      first++;
    }
    var last = first;
    while (last < lines &&
        item.rect.top + paragraph.lineTop(last + 1) <= page.bottom + 0.5) {
      last++;
    }
    if (last <= first) continue;
    final start = paragraph.lineStart(first);
    final end = last < lines
        ? paragraph.lineStart(last)
        : paragraph.box.text.length;
    if (end > start) {
      out.add((item: item, order: order, start: start, end: end));
    }
  }
  return out;
}
