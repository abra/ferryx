/// Box generation: a [ContentDocument] and its [ComputedStyles] become
/// the [SectionBoxes] the layout reads.
///
/// The rules are CSS 2.1 §9.2 (block and inline boxes, anonymous block
/// boxes around inline content beside blocks, a block inside an inline
/// splitting it), CSS Text 3 §4 (white space processing: collapsing,
/// segment breaks, preserved spaces and tabs) and the parts of HTML's
/// rendering section that generate content (`<br>`, `<wbr>`, `<q>`, list
/// markers, replaced images). What v1 leaves out, and does instead:
///
/// * floats: a float met before a line's first content leaves the flow
///   as a [FloatBox] (an image floated inside a line ends the paragraph
///   there); any other float inside a line stays in it;
/// * `inline-block` around block-level content: laid out as inline
///   content (around inline content it is an [InlineText] block);
/// * inline borders, padding and margins: not drawn (backgrounds are);
/// * SVG: a wrapper around one `<image>` is that image (covers); any
///   other `<svg>` is drawn as an image of itself ([_svgDocument]);
/// * video, audio, iframe and canvas: no box.
library;

import 'dart:convert';

import '../css/computed_style.dart';
import '../css/css_properties.dart';
import '../css/css_values.dart';
import '../css/style_resolver.dart';
import '../css/stylesheet_loader.dart' show cssImageSource;
import '../document/content_document.dart';
import '../text/hyphenator.dart';
import 'book_style.dart' show TextHyphenation;
import 'box_tree.dart';
import 'list_markers.dart';
import 'text_source_map.dart';

/// Builds the boxes of [document] with its [styles]; text with
/// `hyphens: auto` gets soft hyphens where [hyphenation] lets its words
/// break.
SectionBoxes buildSectionBoxes(
  ContentDocument document,
  ComputedStyles styles, {
  TextHyphenation hyphenation = const TextHyphenation(),
}) {
  final builder = _BoxBuilder(document, styles, hyphenation);
  final root = builder.rootBox();
  final body = document
      .childrenOf(ContentDocument.rootIndex)
      .where(
        (n) =>
            document.isElement(n) &&
            document.localNameOf(n).toLowerCase() == 'body',
      )
      .firstOrNull;
  return SectionBoxes(
    root,
    imageSources: builder.images.toList(),
    raisedElements: builder.raised,
    writingMode: styles[body ?? ContentDocument.rootIndex].writingMode,
  );
}

/// The boxes of one footnote of [document]: what foliate-js moves into
/// an empty body to show it. For an `li` or `aside` ([contentsOnly]) its
/// children, leaving its own box, marker and any `display: none` the
/// book's sheet gives it behind; otherwise the element itself. The root
/// takes the body's style.
SectionBoxes buildFragmentBoxes(
  ContentDocument document,
  ComputedStyles styles,
  int element, {
  required bool contentsOnly,
  TextHyphenation hyphenation = const TextHyphenation(),
}) {
  final builder = _BoxBuilder(document, styles, hyphenation);
  final root = builder.fragmentBox(element, contentsOnly: contentsOnly);
  return SectionBoxes(
    root,
    imageSources: builder.images.toList(),
    raisedElements: builder.raised,
  );
}

/// Whether `position: relative` moves the element: an offset other than
/// `auto` or zero.
bool _isRelativelyOffset(ComputedStyle style) {
  if (style.position != CssPosition.relative) return false;
  final o = style.offsets;
  bool moves(CssLength? length) => length != null && !length.isZero;
  return moves(o.top) || moves(o.bottom) || moves(o.left) || moves(o.right);
}

/// Elements that make no box, whatever their display.
const _skippedElements = {
  'video',
  'audio',
  'iframe',
  'embed',
  'canvas',
  'input',
  'select',
  'textarea',
  'source',
  'track',
};

/// Nesting deeper than this is laid out as plain inline text: no real
/// book comes near it, and it keeps the walk off the stack limit.
const _maxDepth = 256;

class _BoxBuilder {
  _BoxBuilder(this.doc, this.styles, TextHyphenation hyphenation)
    : _breaks = _WordBreaks(doc, hyphenation);

  final _WordBreaks _breaks;

  final ContentDocument doc;
  final ComputedStyles styles;
  final images = <String>{};
  final raised = <int>{};
  final _ordinals = <int, Map<int, int>>{};

  /// An `inside` list marker waiting for its item's first line.
  ({String text, ComputedStyle style})? _insideMarker;

  final _counters = _Counters();

  /// How deep `open-quote` has gone, document-wide.
  int _quoteDepth = 0;

  BlockBox rootBox() {
    const root = ContentDocument.rootIndex;
    final style = styles[root];
    return BlockBox(style, root, _blockChildren(root, style, -1, 0));
  }

  BlockBox fragmentBox(int element, {required bool contentsOnly}) {
    var body = element;
    while (body >= 0 && _name(body) != 'body') {
      body = doc.parentOf(body);
    }
    final rootStyle = styles[body >= 0 ? body : ContentDocument.rootIndex];
    final children = contentsOnly
        ? _blockChildren(element, styles[element], -1, 0)
        : _blockChildren(
            doc.parentOf(element),
            rootStyle,
            -1,
            0,
            only: element,
          );
    return BlockBox(rootStyle, element, children);
  }

  String _name(int element) => doc.localNameOf(element).toLowerCase();

  /// The boxes inside block container [parent]: blocks as they come,
  /// inline content gathered into anonymous paragraphs between them.
  /// With [only], that one child of [parent] alone.
  List<LayoutBox> _blockChildren(
    int parent,
    ComputedStyle parentStyle,
    int link,
    int depth, {
    int? only,
  }) {
    final out = <LayoutBox>[];
    _ParagraphCollector? paragraph;

    _ParagraphCollector collector() {
      final existing = paragraph;
      if (existing != null) return existing;
      final created = paragraph = _ParagraphCollector(
        doc,
        parentStyle,
        parent,
        isProse: _isProse(parent),
        breaks: _breaks,
      );
      // `list-style-position: inside`: the marker starts the first line.
      final marker = _insideMarker;
      if (marker != null) {
        _insideMarker = null;
        created.addGenerated(marker.text, marker.style, -1);
      }
      return created;
    }

    void flush() {
      final collected = paragraph;
      if (collected == null) return;
      paragraph = null;
      // Floats beside the first line do not take its indent away.
      final box = collected.build(
        indentFirstLine: out.every((box) => box is FloatBox),
      );
      if (box != null) out.add(box);
    }

    /// [parent]'s `::before` or `::after`: content at the start or end of
    /// its lines, or a block of its own.
    void pseudo(ComputedStyle? style) {
      if (style == null || !_generatesBox(style)) return;
      if (style.display.isBlockLevel) {
        flush();
        final block = _generatedBlock(parent, style, link);
        if (block != null) out.add(block);
      } else {
        _addGenerated(collector(), parent, style, link);
      }
    }

    /// Visits [node] in the flow of [parent], or, with [into], inside
    /// shifted text, where everything stays inline.
    void visit(int node, int link, int depth, [_ParagraphCollector? into]) {
      if (doc.isText(node)) {
        (into ?? collector()).addText(node, styles[node], link);
        return;
      }
      final style = styles[node];
      final name = _name(node);
      if (style.display == CssDisplay.none || _skippedElements.contains(name)) {
        return;
      }
      _counters.apply(style);
      if (_isRaised(style)) raised.add(node);
      if (depth > _maxDepth) {
        _addFlattened(into ?? collector(), node, link);
        return;
      }
      final linkHere = name == 'a' && doc.attributeOf(node, 'href') != null
          ? node
          : link;

      /// The element's children, between its `::before` and `::after`,
      /// in a counter scope of their own.
      void visitChildren(_ParagraphCollector? target) {
        _counters.push();
        final before = styles.before(node);
        if (before != null && _generatesBox(before)) {
          _addGenerated(target ?? collector(), node, before, linkHere);
        }
        for (
          var c = doc.firstChildOf(node);
          c != ContentDocument.none;
          c = doc.nextSiblingOf(c)
        ) {
          visit(c, linkHere, depth + 1, target);
        }
        final after = styles.after(node);
        if (after != null && _generatesBox(after)) {
          _addGenerated(target ?? collector(), node, after, linkHere);
        }
        _counters.pop();
      }

      if (style.display == CssDisplay.contents) {
        visitChildren(into);
        return;
      }
      if (into == null && _isFloat(style)) {
        final current = paragraph;
        final lineStart = current == null || current.isEmpty;
        if (lineStart || name == 'img') {
          if (!lineStart) flush();
          final box = _blockBox(node, name, style, linkHere, depth + 1);
          if (box != null) {
            out.add(
              FloatBox(style, node, box, left: style.float == CssFloat.left),
            );
          }
          return;
        }
      }
      if (into == null && _isBlockLevel(node, name, style)) {
        flush();
        final box = _blockBox(node, name, style, linkHere, depth + 1);
        if (box != null) out.add(box);
        return;
      }
      final target = into ?? collector();
      switch (name) {
        case 'br':
          target.addBreak(node);
          return;
        case 'wbr':
          target.addElementCharacter('\u200B', node, style, linkHere);
          return;
        case 'img':
          final src = _imageSource(node);
          if (src != null) {
            images.add(src);
            target.addImage(
              node,
              style,
              src,
              doc.attributeOf(node, 'alt'),
              linkHere,
            );
          }
          return;
        case 'svg':
          final src = _svgDocument(node);
          images.add(src);
          target.addImage(node, style, src, null, linkHere);
          return;
        case 'math':
          final formula = _mathOf(node);
          target.addMath(
            node,
            style,
            formula,
            doc.attributeOf(node, 'alttext') ?? formula.plainText,
            linkHere,
          );
          return;
      }
      if (_isSizedEmptyBox(node, style)) {
        target.addInlineBox(node, style, linkHere);
        return;
      }
      if (into == null &&
          style.display == CssDisplay.inlineBlock &&
          !_hasBlockContent(node)) {
        final inner = _ParagraphCollector(doc, style, node, breaks: _breaks);
        visitChildren(inner);
        final paragraph = inner.build(indentFirstLine: false);
        if (paragraph != null) {
          final parentNode = doc.parentOf(node);
          target.addInlineText(
            node,
            style,
            paragraph,
            linkHere,
            parentFontSize: parentNode == ContentDocument.none
                ? style.fontSize
                : styles[parentNode].fontSize,
            isInlineBlock: true,
          );
        }
        return;
      }
      final edges = _hasInlineEdges(style);
      final decorated = _isInlineDecorated(style);
      if (into == null && _isShifted(style)) {
        final shifted = _ParagraphCollector(
          doc,
          style,
          node,
          breaks: _breaks,
        );
        if (decorated) shifted.openDecoration(node, style);
        if (edges) shifted.addSpacer(node, style, linkHere, isStart: true);
        visitChildren(shifted);
        if (edges) shifted.addSpacer(node, style, linkHere, isStart: false);
        if (decorated) shifted.closeDecoration(node, style);
        final paragraph = shifted.build(indentFirstLine: false);
        if (paragraph != null) {
          final parentNode = doc.parentOf(node);
          target.addInlineText(
            node,
            style,
            paragraph,
            linkHere,
            parentFontSize: parentNode == ContentDocument.none
                ? style.fontSize
                : styles[parentNode].fontSize,
          );
        }
        return;
      }
      if (decorated) target.openDecoration(node, style);
      if (edges) target.addSpacer(node, style, linkHere, isStart: true);
      visitChildren(into);
      // A block inside may have ended the paragraph this one began in.
      final end = into ?? collector();
      if (edges) end.addSpacer(node, style, linkHere, isStart: false);
      if (decorated) end.closeDecoration(node, style);
    }

    if (only != null) {
      visit(only, link, depth + 1);
    } else {
      _counters.push();
      pseudo(styles.before(parent));
      for (
        var c = doc.firstChildOf(parent);
        c != ContentDocument.none;
        c = doc.nextSiblingOf(c)
      ) {
        visit(c, link, depth + 1);
      }
      pseudo(styles.after(parent));
      _counters.pop();
    }
    flush();
    return out;
  }

  /// Whether a `::before` or `::after` with [style] makes a box: it has
  /// content and stays in the flow (an absolutely placed one decorates
  /// a position pagecraft does not lay out).
  static bool _generatesBox(ComputedStyle style) =>
      style.content != null &&
      style.display != CssDisplay.none &&
      style.position != CssPosition.absolute &&
      style.position != CssPosition.fixed;

  /// Whether a shown descendant of [node] is block-level: an inline
  /// block around one stays inline content.
  bool _hasBlockContent(int node) {
    for (
      var child = doc.firstChildOf(node);
      child != ContentDocument.none;
      child = doc.nextSiblingOf(child)
    ) {
      if (!doc.isElement(child)) continue;
      final display = styles[child].display;
      if (display == CssDisplay.none) continue;
      if (display.isBlockLevel || _hasBlockContent(child)) return true;
    }
    return false;
  }

  /// An empty `inline-block` with a width or height: a box of its own
  /// size in the line.
  bool _isSizedEmptyBox(int node, ComputedStyle style) {
    if (style.display != CssDisplay.inlineBlock) return false;
    if (style.width == null && style.height == null) return false;
    for (final child in doc.childrenOf(node)) {
      if (doc.isElement(child)) return false;
      if (doc.textOf(child).trim().isNotEmpty) return false;
    }
    return true;
  }

  /// Puts the content of [node]'s pseudo-element with [style] into
  /// [target]: its text and images, with its own background, borders and
  /// edges; an empty `inline-block` with a size is a box of that size.
  void _addGenerated(
    _ParagraphCollector target,
    int node,
    ComputedStyle style,
    int link,
  ) {
    _counters.apply(style);
    final pieces = _generatedPieces(node, style);
    if (pieces.isEmpty) {
      if (style.display == CssDisplay.inlineBlock &&
          (style.width != null || style.height != null)) {
        target.addInlineBox(node, style, link);
      }
      return;
    }
    final decorated = _isInlineDecorated(style);
    final edges = _hasInlineEdges(style);
    if (decorated) target.openDecoration(node, style);
    if (edges) target.addSpacer(node, style, link, isStart: true);
    _addPieces(target, node, style, link, pieces);
    if (edges) target.addSpacer(node, style, link, isStart: false);
    if (decorated) target.closeDecoration(node, style);
  }

  /// A block-level `::before` or `::after` of [node]: a block holding its
  /// content as one paragraph; null when it shows nothing.
  BlockBox? _generatedBlock(int node, ComputedStyle style, int link) {
    _counters.apply(style);
    final pieces = _generatedPieces(node, style);
    final collector = _ParagraphCollector(
      doc,
      style,
      node,
      breaks: _breaks,
    );
    _addPieces(collector, node, style, link, pieces);
    final paragraph = collector.build(indentFirstLine: true);
    final w = style.borderWidth;
    final visible =
        paragraph != null || style.height != null || w.top > 0 || w.bottom > 0;
    if (!visible) return null;
    return BlockBox(style, node, [?paragraph]);
  }

  void _addPieces(
    _ParagraphCollector target,
    int node,
    ComputedStyle style,
    int link,
    List<Object> pieces,
  ) {
    for (final piece in pieces) {
      if (piece is String) {
        target.addGenerated(piece, style, link, transform: true);
      } else if (piece is _GeneratedImage) {
        images.add(piece.src);
        target.addGeneratedImage(node, style, piece.src, link);
      }
    }
  }

  /// What `content` shows for [node]: strings (with attributes, counters
  /// and quotes resolved, adjacent ones joined) and images.
  List<Object> _generatedPieces(int node, ComputedStyle style) {
    final pieces = <Object>[];
    final buffer = StringBuffer();
    void endText() {
      if (buffer.isEmpty) return;
      pieces.add(buffer.toString());
      buffer.clear();
    }

    for (final item in style.content ?? const <CssContentItem>[]) {
      switch (item) {
        case CssContentString(:final text):
          buffer.write(text);
        case CssContentAttr(:final name):
          buffer.write(doc.attributeOf(node, name) ?? '');
        case CssContentCounter(
          :final name,
          style: final counterStyle,
          :final separator,
        ):
          if (separator == null) {
            buffer.write(counterText(counterStyle, _counters.value(name)));
          } else {
            buffer.write(
              [
                for (final v in _counters.values(name))
                  counterText(counterStyle, v),
              ].join(separator),
            );
          }
        case CssContentQuote(:final open, :final mark):
          final quote = _quote(node, style, open: open);
          if (mark) buffer.write(quote);
        case CssContentUrl(:final url, :final base):
          endText();
          pieces.add(_GeneratedImage(cssImageSource(url, base)));
      }
    }
    endText();
    return pieces;
  }

  /// The mark `open-quote` or `close-quote` shows at the current depth,
  /// moving the depth: [style]'s `quotes` pairs, or [node]'s language's.
  String _quote(int node, ComputedStyle style, {required bool open}) {
    if (!open) _quoteDepth = _quoteDepth > 0 ? _quoteDepth - 1 : 0;
    final depth = _quoteDepth;
    if (open) _quoteDepth++;
    final custom = style.quotes;
    if (custom != null && custom.isEmpty) return '';
    final pairs = custom == null
        ? _languageQuotes(node)
        : [
            for (var i = 0; i + 1 < custom.length; i += 2)
              (custom[i], custom[i + 1]),
          ];
    // Deeper than the pairs go, the last pair repeats.
    final pair = depth < pairs.length ? pairs[depth] : pairs.last;
    return open ? pair.$1 : pair.$2;
  }

  /// Text of a subtree too deep to walk recursively, in document order.
  void _addFlattened(_ParagraphCollector collector, int node, int link) {
    final end = doc.subtreeEndOf(node);
    for (var n = node; n < end; n++) {
      if (doc.isText(n)) collector.addText(n, styles[n], link);
    }
  }

  final _prose = <int, bool>{};

  /// Whether [element] is prose: see [BlockBox.isProse]. The `div` test
  /// is foliate-js's `div:not(:has(*:not(b, a, em, i, strong, u, span)))`.
  bool _isProse(int element) => _prose.putIfAbsent(element, () {
    switch (_name(element)) {
      case 'p' || 'li' || 'blockquote' || 'dd' || 'font':
        return true;
      case 'div':
        final end = doc.subtreeEndOf(element);
        for (var n = element + 1; n < end; n++) {
          if (doc.isElement(n) && !_phrasing.contains(_name(n))) return false;
        }
        return true;
      default:
        return false;
    }
  });

  static const _phrasing = {'b', 'a', 'em', 'i', 'strong', 'u', 'span'};

  /// Inline text off the baseline: `super`, `sub` or a non-zero length.
  /// `isSuper` in footnotes.js: super, top, text-top, or a computed
  /// length that does not start with a minus sign.
  static bool _isRaised(ComputedStyle style) => switch (style.verticalAlign) {
    CssVerticalAlign.sup ||
    CssVerticalAlign.top ||
    CssVerticalAlign.textTop => true,
    CssVerticalAlign.length =>
      !(style.verticalAlignLength?.value.isNegative ?? true),
    _ => false,
  };

  /// Inline text laid out as its own small paragraph: raised or lowered
  /// by `vertical-align`, or moved by `position: relative` (how
  /// publishers raise note numbers without opening up the line).
  static bool _isShifted(ComputedStyle style) =>
      switch (style.verticalAlign) {
        CssVerticalAlign.sup || CssVerticalAlign.sub => true,
        CssVerticalAlign.length => !(style.verticalAlignLength?.isZero ?? true),
        _ => false,
      } ||
      _isRelativelyOffset(style);

  /// An inline element that paints: a background or a border.
  static bool _isInlineDecorated(ComputedStyle style) {
    final w = style.borderWidth;
    return (style.backgroundColor >> 24) != 0 ||
        w.top > 0 ||
        w.right > 0 ||
        w.bottom > 0 ||
        w.left > 0;
  }

  /// An inline element whose start or end takes room in the line:
  /// horizontal margin, border or padding.
  static bool _hasInlineEdges(ComputedStyle style) {
    bool some(CssLength? length) => length != null && !length.isZero;
    return some(style.margin.left) ||
        some(style.margin.right) ||
        style.borderWidth.left > 0 ||
        style.borderWidth.right > 0 ||
        some(style.padding.left) ||
        some(style.padding.right);
  }

  /// Whether [style]'s element floats: absolute and fixed positions
  /// take it out of the flow instead (CSS 2.1 §9.7).
  static bool _isFloat(ComputedStyle style) =>
      style.float != CssFloat.none &&
      style.position != CssPosition.absolute &&
      style.position != CssPosition.fixed;

  bool _isBlockLevel(int node, String name, ComputedStyle style) {
    switch (style.display) {
      case CssDisplay.block ||
          CssDisplay.listItem ||
          CssDisplay.table ||
          CssDisplay.inlineTable ||
          CssDisplay.tableCaption ||
          CssDisplay.tableRowGroup ||
          CssDisplay.tableHeaderGroup ||
          CssDisplay.tableFooterGroup ||
          CssDisplay.tableRow ||
          CssDisplay.tableCell:
        return true;
      case CssDisplay.tableColumn || CssDisplay.tableColumnGroup:
        return true;
      default:
        break;
    }
    // An SVG wrapper around an image is a full-width picture: covers.
    if (name == 'svg') {
      return _svgImage(node) != null || style.display.isBlockLevel;
    }
    return false;
  }

  LayoutBox? _blockBox(
    int node,
    String name,
    ComputedStyle style,
    int link,
    int depth,
  ) {
    if (style.backgroundImage case final background?) {
      images.add(background.source);
    }
    if (name == 'img') {
      final src = _imageSource(node);
      if (src == null) return null;
      images.add(src);
      return ImageBox(
        style,
        node,
        src: src,
        alt: doc.attributeOf(node, 'alt'),
        link: link,
      );
    }
    if (name == 'math') {
      // A formula of its own: one line holding it, centred by its style.
      final line = _ParagraphCollector(doc, style, node, breaks: _breaks);
      final formula = _mathOf(node);
      line.addMath(
        node,
        style,
        formula,
        doc.attributeOf(node, 'alttext') ?? formula.plainText,
        link,
      );
      return BlockBox(style, node, [?line.build(indentFirstLine: false)]);
    }
    if (name == 'svg') {
      final image = _svgImage(node);
      if (image == null) {
        final src = _svgDocument(node);
        images.add(src);
        return ImageBox(style, node, src: src, link: link);
      }
      images.add(image.src);
      return ImageBox(
        style,
        node,
        src: image.src,
        viewBox: image.viewBox,
        link: link,
      );
    }
    switch (style.display) {
      case CssDisplay.table || CssDisplay.inlineTable:
        return _table(node, style, link, depth);
      case CssDisplay.tableColumn || CssDisplay.tableColumnGroup:
        return null;
      case CssDisplay.listItem:
        final marker = listMarkerText(style.listStyleType, _ordinalOf(node));
        if (style.listStyleInside && marker != null) {
          // Symbols take a space after them; counters carry their suffix.
          final suffixed = marker.endsWith(' ') || marker.endsWith('、');
          _insideMarker = (
            text: suffixed ? marker : '$marker ',
            style: style,
          );
          final children = _blockChildren(node, style, link, depth);
          // An item without a line keeps no marker.
          _insideMarker = null;
          return BlockBox(style, node, children, isProse: _isProse(node));
        }
        return BlockBox(
          style,
          node,
          _blockChildren(node, style, link, depth),
          marker: marker,
          isProse: _isProse(node),
        );
      default:
        return BlockBox(
          style,
          node,
          _blockChildren(node, style, link, depth),
          isProse: _isProse(node),
          isHeading: const {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(name),
        );
    }
  }

  /// The image's source: its `src`, or for MOBI 6 its `recindex` as
  /// `recindex:N`, which the MOBI source resolves.
  String? _imageSource(int img) {
    final src = doc.attributeOf(img, 'src')?.trim();
    if (src != null && src.isNotEmpty) return src;
    final recindex = doc.attributeOf(img, 'recindex')?.trim();
    if (recindex != null && recindex.isNotEmpty) return 'recindex:$recindex';
    return null;
  }

  /// The one `<image>` an SVG wrapper shows, and its view box.
  /// The MathML tree under [math]: its elements with their attributes,
  /// the text of token elements with white space collapsed and trimmed;
  /// annotations left out.
  MathNode _mathOf(int math) {
    final name = doc.localNameOf(math).toLowerCase();
    final attributes = {
      for (final (attribute, value) in doc.attributesOf(math))
        attribute.toLowerCase(): value,
    };
    if (_mathTokens.contains(name)) {
      final text = StringBuffer();
      for (final d in doc.descendantsOf(math)) {
        if (doc.isText(d)) text.write(doc.textOf(d));
      }
      return MathNode(
        name,
        attributes: attributes,
        text: text.toString().replaceAll(RegExp(r'\s+'), ' ').trim(),
      );
    }
    return MathNode(
      name,
      attributes: attributes,
      children: [
        for (
          var child = doc.firstChildOf(math);
          child != ContentDocument.none;
          child = doc.nextSiblingOf(child)
        )
          if (doc.isElement(child) &&
              !_mathAnnotations.contains(doc.localNameOf(child).toLowerCase()))
            _mathOf(child),
      ],
    );
  }

  static const _mathTokens = {'mi', 'mn', 'mo', 'mtext', 'ms', 'mspace'};
  static const _mathAnnotations = {'annotation', 'annotation-xml'};

  /// [svg] written out as an SVG document of its own, a `data:` image:
  /// an SVG in the markup (a diagram, an icon) is drawn as an image of
  /// itself, sized by its `width`, `height` and `viewBox` as an image
  /// file would be. Its namespaces are declared on its root.
  String _svgDocument(int svg) {
    final out = StringBuffer();
    void write(int node, {bool root = false}) {
      if (doc.isText(node)) {
        out.write(_escapeXml(doc.textOf(node)));
        return;
      }
      if (!doc.isElement(node)) return;
      final name = doc.qualifiedNameOf(node);
      out
        ..write('<')
        ..write(name);
      final attributes = doc.attributesOf(node).toList();
      if (root) {
        for (final (prefix, uri) in const [
          ('xmlns', 'http://www.w3.org/2000/svg'),
          ('xmlns:xlink', 'http://www.w3.org/1999/xlink'),
        ]) {
          if (!attributes.any((a) => a.$1 == prefix)) {
            out.write(' $prefix="$uri"');
          }
        }
      }
      for (final (attribute, value) in attributes) {
        out.write(' $attribute="${_escapeXml(value, attribute: true)}"');
      }
      final first = doc.firstChildOf(node);
      if (first == ContentDocument.none) {
        out.write('/>');
        return;
      }
      out.write('>');
      for (
        var child = first;
        child != ContentDocument.none;
        child = doc.nextSiblingOf(child)
      ) {
        write(child);
      }
      out.write('</$name>');
    }

    write(svg, root: true);
    return 'data:image/svg+xml;base64,'
        '${base64.encode(utf8.encode(out.toString()))}';
  }

  static String _escapeXml(String text, {bool attribute = false}) {
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return attribute ? escaped.replaceAll('"', '&quot;') : escaped;
  }

  ({String src, ({double width, double height})? viewBox})? _svgImage(int svg) {
    var image = ContentDocument.none;
    final end = doc.subtreeEndOf(svg);
    for (var n = svg + 1; n < end; n++) {
      if (doc.isElement(n) && _name(n) == 'image') {
        if (image != ContentDocument.none) return null;
        image = n;
      }
    }
    if (image == ContentDocument.none) return null;
    String? href;
    for (final (name, value) in doc.attributesOf(image)) {
      if (name == 'href' || name.endsWith(':href')) href = value.trim();
    }
    if (href == null || href.isEmpty) return null;
    final viewBox =
        _parseViewBox(doc.attributeOf(svg, 'viewBox')) ??
        _sizeFromAttributes(image);
    return (src: href, viewBox: viewBox);
  }

  static ({double width, double height})? _parseViewBox(String? value) {
    if (value == null) return null;
    final parts = value.trim().split(RegExp(r'[\s,]+'));
    if (parts.length != 4) return null;
    final width = double.tryParse(parts[2]);
    final height = double.tryParse(parts[3]);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return (width: width, height: height);
  }

  ({double width, double height})? _sizeFromAttributes(int element) {
    final width = double.tryParse(doc.attributeOf(element, 'width') ?? '');
    final height = double.tryParse(doc.attributeOf(element, 'height') ?? '');
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return (width: width, height: height);
  }

  /// The ordinal of list item [item], numbering its siblings once: an
  /// `<ol>`'s `start` and `reversed`, an item's `value`.
  int _ordinalOf(int item) {
    final parent = doc.parentOf(item);
    if (parent == ContentDocument.none) return 1;
    final cached = _ordinals[parent];
    if (cached != null) return cached[item] ?? 1;
    final items = <int>[
      for (
        var c = doc.firstChildOf(parent);
        c != ContentDocument.none;
        c = doc.nextSiblingOf(c)
      )
        if (doc.isElement(c) && styles[c].display == CssDisplay.listItem) c,
    ];
    final isOl = _name(parent) == 'ol';
    final reversed = isOl && doc.attributeOf(parent, 'reversed') != null;
    final start =
        int.tryParse(doc.attributeOf(parent, 'start')?.trim() ?? '') ??
        (reversed ? items.length : 1);
    final step = reversed ? -1 : 1;
    final ordinals = <int, int>{};
    var next = start;
    for (final c in items) {
      final value = int.tryParse(doc.attributeOf(c, 'value')?.trim() ?? '');
      if (value != null) next = value;
      ordinals[c] = next;
      next += step;
    }
    _ordinals[parent] = ordinals;
    return ordinals[item] ?? 1;
  }

  /// The quote pairs of [node]'s language, outer then inner.
  List<(String, String)> _languageQuotes(int node) {
    String? lang;
    for (var e = node; e != ContentDocument.none; e = doc.parentOf(e)) {
      lang = doc.attributeOf(e, 'xml:lang') ?? doc.attributeOf(e, 'lang');
      if (lang != null) break;
    }
    final primary = (lang ?? '').toLowerCase().split('-').first;
    return _quotes[primary] ?? _quotes['']!;
  }

  TableBox _table(int table, ComputedStyle style, int link, int depth) {
    _counters.push();
    try {
      return _tableOf(table, style, link, depth);
    } finally {
      _counters.pop();
    }
  }

  TableBox _tableOf(int table, ComputedStyle style, int link, int depth) {
    BlockBox? caption;
    final header = <TableRowBox>[];
    final body = <TableRowBox>[];
    final footer = <TableRowBox>[];
    var looseCells = <TableCellBox>[];

    void closeLooseRow(
      List<TableRowBox> into,
      int rowNode,
      ComputedStyle rowStyle,
    ) {
      if (looseCells.isEmpty) return;
      into.add(TableRowBox(rowStyle, rowNode, looseCells));
      looseCells = <TableCellBox>[];
    }

    for (
      var c = doc.firstChildOf(table);
      c != ContentDocument.none;
      c = doc.nextSiblingOf(c)
    ) {
      if (!doc.isElement(c)) continue;
      final childStyle = styles[c];
      switch (childStyle.display) {
        case CssDisplay.none ||
            CssDisplay.tableColumn ||
            CssDisplay.tableColumnGroup:
          continue;
        case CssDisplay.tableCaption:
          closeLooseRow(body, table, style);
          caption ??= BlockBox(
            childStyle,
            c,
            _blockChildren(c, childStyle, link, depth + 1),
          );
        case CssDisplay.tableHeaderGroup:
          closeLooseRow(body, table, style);
          header.addAll(
            _rowsOf(c, childStyle, link, depth + 1, isHeader: true),
          );
        case CssDisplay.tableFooterGroup:
          closeLooseRow(body, table, style);
          footer.addAll(_rowsOf(c, childStyle, link, depth + 1));
        case CssDisplay.tableRowGroup:
          closeLooseRow(body, table, style);
          body.addAll(_rowsOf(c, childStyle, link, depth + 1));
        case CssDisplay.tableRow:
          closeLooseRow(body, table, style);
          body.add(_row(c, childStyle, link, depth + 1));
        default:
          looseCells.add(_cell(c, childStyle, link, depth + 1));
      }
    }
    closeLooseRow(body, table, style);
    return TableBox(style, table, [
      ...header,
      ...body,
      ...footer,
    ], caption: caption);
  }

  List<TableRowBox> _rowsOf(
    int group,
    ComputedStyle groupStyle,
    int link,
    int depth, {
    bool isHeader = false,
  }) {
    final rows = <TableRowBox>[];
    var loose = <TableCellBox>[];
    for (
      var c = doc.firstChildOf(group);
      c != ContentDocument.none;
      c = doc.nextSiblingOf(c)
    ) {
      if (!doc.isElement(c)) continue;
      final style = styles[c];
      if (style.display == CssDisplay.none) continue;
      if (style.display == CssDisplay.tableRow) {
        if (loose.isNotEmpty) {
          rows.add(TableRowBox(groupStyle, group, loose, isHeader: isHeader));
          loose = <TableCellBox>[];
        }
        rows.add(_row(c, style, link, depth + 1, isHeader: isHeader));
      } else {
        loose.add(_cell(c, style, link, depth + 1));
      }
    }
    if (loose.isNotEmpty) {
      rows.add(TableRowBox(groupStyle, group, loose, isHeader: isHeader));
    }
    return rows;
  }

  TableRowBox _row(
    int row,
    ComputedStyle style,
    int link,
    int depth, {
    bool isHeader = false,
  }) => TableRowBox(
    style,
    row,
    [
      for (
        var c = doc.firstChildOf(row);
        c != ContentDocument.none;
        c = doc.nextSiblingOf(c)
      )
        if (doc.isElement(c) && styles[c].display != CssDisplay.none)
          _cell(c, styles[c], link, depth + 1),
    ],
    isHeader: isHeader,
  );

  /// A cell, or any other element in a row's place wrapped as one.
  TableCellBox _cell(int cell, ComputedStyle style, int link, int depth) {
    _counters.apply(style);
    final isCell = style.display == CssDisplay.tableCell;
    int span(String name) =>
        (int.tryParse(doc.attributeOf(cell, name)?.trim() ?? '') ?? 1).clamp(
          1,
          1000,
        );
    final children = isCell
        ? _blockChildren(cell, style, link, depth)
        : <LayoutBox>[
            ?_blockBox(cell, _name(cell), style, link, depth),
          ];
    return TableCellBox(
      style,
      cell,
      children,
      columnSpan: isCell ? span('colspan') : 1,
      rowSpan: isCell ? span('rowspan') : 1,
    );
  }
}

/// Quote pairs by primary language, outer then inner.
const _quotes = <String, List<(String, String)>>{
  '': [('“', '”'), ('‘', '’')],
  'en': [('“', '”'), ('‘', '’')],
  'ru': [('«', '»'), ('„', '“')],
  'uk': [('«', '»'), ('„', '“')],
  'be': [('«', '»'), ('„', '“')],
  'de': [('„', '“'), ('‚', '‘')],
  'fr': [('«\u202F', '\u202F»'), ('“', '”')],
  'es': [('«', '»'), ('“', '”')],
  'it': [('«', '»'), ('“', '”')],
  'pl': [('„', '”'), ('«', '»')],
  'cs': [('„', '“'), ('‚', '‘')],
  'ja': [('「', '」'), ('『', '』')],
  'zh': [('“', '”'), ('‘', '’')],
};

/// One paragraph's inline content as it is collected: text with
/// whitespace processed, style runs, atomics and the source map.
class _ParagraphCollector {
  _ParagraphCollector(
    this.doc,
    this.blockStyle,
    this.blockNode, {
    this.isProse = false,
    this.breaks,
  });

  final ContentDocument doc;
  final ComputedStyle blockStyle;
  final int blockNode;
  final bool isProse;

  /// Where `hyphens: auto` text breaks its words.
  final _WordBreaks? breaks;

  final _text = StringBuffer();
  int _length = 0;
  final _runs = <InlineRun>[];
  ComputedStyle? _runStyle;
  int _runLink = -1;
  int _runStart = 0;
  final _atomics = <InlineAtomic>[];
  final _map = TextSourceMapBuilder();
  final _decorations = <InlineDecoration>[];

  /// Decorated inline elements open here, innermost last.
  final _openDecorations = <_OpenDecoration>[];

  /// Whether the current line has content: whitespace at a line start is
  /// dropped, not collapsed.
  bool _lineHasContent = false;

  /// Collapsible whitespace seen after content, not yet emitted: it
  /// becomes one space if more content follows on the line.
  _PendingSpace? _pendingSpace;

  /// A forced break not yet emitted: a break at the very end of a
  /// paragraph makes no empty line, as in the browser.
  ({int node, int nodeStart, int nodeLength})? _pendingBreak;

  /// Whitespace dropped while a break is pending: mapped after the
  /// break once it is placed, so segments stay in paragraph order.
  final _droppedAfterBreak = <({int node, int start, int length})>[];

  int _lastChar = -1;

  /// Nothing collected yet: no text, atomic or line break.
  bool get isEmpty => _length == 0 && _pendingBreak == null;

  /// Columns since the last line break, for tab stops in preserved text.
  int _column = 0;

  /// Whether the next letter starts a word, for `capitalize`.
  bool _atWordStart = true;

  void _append(String s, ComputedStyle style, int link) {
    if (!identical(_runStyle, style) || _runLink != link) {
      _closeRun();
      _runStyle = style;
      _runLink = link;
      _runStart = _length;
    }
    _text.write(s);
    _length += s.length;
    if (s.isNotEmpty) _lastChar = s.codeUnitAt(s.length - 1);
  }

  void _closeRun() {
    final style = _runStyle;
    if (style != null && _length > _runStart) {
      _runs.add(InlineRun(_runStart, _length, style, link: _runLink));
    }
  }

  void addText(int node, ComputedStyle style, int link) {
    final data = doc.textOf(node);
    final ws = style.whiteSpace;
    final n = data.length;
    var i = 0;
    while (i < n) {
      final c = data.codeUnitAt(i);
      if (ws.collapses && _isCollapsible(c)) {
        var j = i;
        var sawBreak = false;
        while (j < n && _isCollapsible(data.codeUnitAt(j))) {
          if (data.codeUnitAt(j) == 0x0A) sawBreak = true;
          j++;
        }
        if (ws == CssWhiteSpace.preLine && sawBreak) {
          _addPreLineBreaks(node, data, i, j, style, link);
        } else {
          _addCollapsible(node, i, j, sawBreak, style, link);
        }
        i = j;
      } else if (ws.collapses) {
        var j = i;
        while (j < n && !_isCollapsible(data.codeUnitAt(j))) {
          j++;
        }
        _emitText(data, i, j, node, style, link);
        i = j;
      } else {
        // Preserved: spaces as they are, tabs to the next stop, line
        // feeds as forced breaks.
        var j = i;
        while (j < n &&
            data.codeUnitAt(j) != 0x09 &&
            data.codeUnitAt(j) != 0x0A) {
          j++;
        }
        if (j > i) {
          _emitText(data, i, j, node, style, link);
          i = j;
          continue;
        }
        if (c == 0x0A) {
          _flushPending(-1);
          _emitBreak(node, i, 1);
        } else {
          _flushPending(0x20);
          _contentStarts();
          final spaces = 8 - _column % 8;
          _map.add(_length, spaces, node, i, 1);
          _append(' ' * spaces, style, link);
          _column += spaces;
          _lineHasContent = true;
          _atWordStart = true;
        }
        i++;
      }
    }
  }

  void _addCollapsible(
    int node,
    int start,
    int end,
    bool sawBreak,
    ComputedStyle style,
    int link,
  ) {
    if (!_lineHasContent) {
      // Whitespace at the start of a line is removed.
      _mapDropped(node, start, end - start);
      return;
    }
    final pending = _pendingSpace ??= _PendingSpace(style, link);
    pending.ranges.add((node: node, start: start, end: end));
    pending.sawSegmentBreak |= sawBreak;
  }

  /// `pre-line`: spaces around a line feed are removed, each line feed
  /// is a forced break.
  void _addPreLineBreaks(
    int node,
    String data,
    int start,
    int end,
    ComputedStyle style,
    int link,
  ) {
    _dropPending();
    var dropFrom = start;
    for (var k = start; k < end; k++) {
      if (data.codeUnitAt(k) != 0x0A) continue;
      if (k > dropFrom) _mapDropped(node, dropFrom, k - dropFrom);
      _flushPendingBreak();
      _pendingBreak = (node: node, nodeStart: k, nodeLength: 1);
      _lineHasContent = false;
      _column = 0;
      dropFrom = k + 1;
    }
    if (end > dropFrom) _mapDropped(node, dropFrom, end - dropFrom);
  }

  /// Source characters that render nothing, at the current position.
  void _mapDropped(int node, int start, int length) {
    if (_pendingBreak != null) {
      _droppedAfterBreak.add((node: node, start: start, length: length));
    } else {
      _map.add(_length, 0, node, start, length);
    }
  }

  void _mapDroppedAfterBreak() {
    for (final d in _droppedAfterBreak) {
      _map.add(_length, 0, d.node, d.start, d.length);
    }
    _droppedAfterBreak.clear();
  }

  /// Emits the pending space before content starting with [next], or
  /// drops it: a segment break between two East Asian wide characters
  /// (or next to a zero-width space) disappears, CSS Text 3 §4.1.3.
  void _flushPending(int next) {
    _flushPendingBreak();
    final pending = _pendingSpace;
    if (pending == null) return;
    _pendingSpace = null;
    final drop =
        pending.sawSegmentBreak &&
        ((_lastChar == 0x200B || next == 0x200B) ||
            (_isWideCjk(_lastChar) && _isWideCjk(next)));
    final first = pending.ranges.first;
    if (drop) {
      for (final r in pending.ranges) {
        _map.add(_length, 0, r.node, r.start, r.end - r.start);
      }
      return;
    }
    _map.add(_length, 1, first.node, first.start, first.end - first.start);
    for (final r in pending.ranges.skip(1)) {
      _map.add(_length + 1, 0, r.node, r.start, r.end - r.start);
    }
    _append(' ', pending.style, pending.link);
    _column++;
    _atWordStart = true;
  }

  void _dropPending() {
    final pending = _pendingSpace;
    if (pending == null) return;
    _pendingSpace = null;
    for (final r in pending.ranges) {
      _map.add(_length, 0, r.node, r.start, r.end - r.start);
    }
  }

  void _flushPendingBreak() {
    final pending = _pendingBreak;
    if (pending == null) return;
    _pendingBreak = null;
    final style = _runStyle ?? blockStyle;
    _map.add(_length, 1, pending.node, pending.nodeStart, pending.nodeLength);
    _append('\n', style, _runLink);
    _mapDroppedAfterBreak();
  }

  void _emitBreak(int node, int nodeStart, int nodeLength) {
    _flushPendingBreak();
    _pendingBreak = (node: node, nodeStart: nodeStart, nodeLength: nodeLength);
    _lineHasContent = false;
    _column = 0;
    _atWordStart = true;
  }

  void _emitText(
    String data,
    int start,
    int end,
    int node,
    ComputedStyle style,
    int link,
  ) {
    _flushPending(data.codeUnitAt(start));
    _contentStarts();
    final transform = style.textTransform;
    final hyphenator = style.hyphens == CssHyphens.auto
        ? breaks?.hyphenatorFor(node)
        : null;
    if (transform == CssTextTransform.none && hyphenator != null) {
      _emitHyphenated(data, start, end, node, style, link, hyphenator);
      _atWordStart = _endsAtWordStart(data, end);
    } else if (transform == CssTextTransform.none) {
      _map.add(_length, end - start, node, start, end - start);
      _append(data.substring(start, end), style, link);
      _atWordStart = _endsAtWordStart(data, end);
    } else {
      _emitTransformed(data, start, end, node, style, link, transform);
    }
    _column += end - start;
    _lineHasContent = true;
  }

  /// Text `[start, end)` of [node] with a soft hyphen (U+00AD, not in the
  /// document) at each break of its words, for the layout to hyphenate
  /// at.
  void _emitHyphenated(
    String data,
    int start,
    int end,
    int node,
    ComputedStyle style,
    int link,
    Hyphenator hyphenator,
  ) {
    var at = start;
    void emitTo(int to) {
      if (to <= at) return;
      _map.add(_length, to - at, node, at, to - at);
      _append(data.substring(at, to), style, link);
      at = to;
    }

    final limits = breaks!.limits;
    var i = start;
    while (i < end) {
      if (!_isWordLetter(data.codeUnitAt(i))) {
        i++;
        continue;
      }
      final wordStart = i;
      while (i < end && _isWordLetter(data.codeUnitAt(i))) {
        i++;
      }
      if (i - wordStart < limits.minWord) continue;
      for (final offset in hyphenator.breaks(
        data.substring(wordStart, i),
        minBefore: limits.minBefore,
        minAfter: limits.minAfter,
      )) {
        emitTo(wordStart + offset);
        _append(softHyphen, style, link);
      }
    }
    emitTo(end);
  }

  /// Whether [unit] is a letter of the scripts the patterns cover (Latin,
  /// Greek, Cyrillic: below U+0530); anything else ends a word. Faster
  /// than `\p{L}`, which costs more than hyphenating.
  static bool _isWordLetter(int unit) {
    if (unit < 0x80) {
      return (unit >= 0x61 && unit <= 0x7A) || (unit >= 0x41 && unit <= 0x5A);
    }
    if (unit < 0x100) {
      return unit >= 0xC0 && unit != 0xD7 && unit != 0xF7 ||
          unit == 0xAA ||
          unit == 0xB5 ||
          unit == 0xBA;
    }
    if (unit <= 0x2C1) return true;
    if (unit < 0x370) return false;
    if (unit < 0x400) {
      return unit != 0x374 &&
          unit != 0x375 &&
          unit != 0x37E &&
          unit != 0x384 &&
          unit != 0x385 &&
          unit != 0x387 &&
          unit != 0x3F6;
    }
    if (unit < 0x530) return unit <= 0x481 || unit >= 0x48A;
    return false;
  }

  /// Applies `text-transform` code point by code point, so a change of
  /// length (ß → SS) maps the new characters to the one they came from.
  void _emitTransformed(
    String data,
    int start,
    int end,
    int node,
    ComputedStyle style,
    int link,
    CssTextTransform transform,
  ) {
    var i = start;
    while (i < end) {
      final unit = data.codeUnitAt(i);
      final width = (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < end) ? 2 : 1;
      final original = data.substring(i, i + width);
      final rune = original.runes.first;
      final isLetter = _isLetter(rune);
      String out;
      switch (transform) {
        case CssTextTransform.uppercase:
          out = _upperCase(rune, original);
        case CssTextTransform.lowercase:
          out = original.toLowerCase();
        case CssTextTransform.capitalize:
          out = _atWordStart && isLetter
              ? _titleCase(rune, original)
              : original;
        case CssTextTransform.none:
          out = original;
      }
      if (isLetter || _isDigit(rune)) {
        _atWordStart = false;
      } else if (_isSpaceLike(rune)) {
        _atWordStart = true;
      }
      _map.add(_length, out.length, node, i, width);
      _append(out, style, link);
      i += width;
    }
  }

  void addBreak(int br) {
    _dropPending();
    _emitBreak(br, 0, 0);
  }

  /// An element that stands for one character (`<wbr>`).
  void addElementCharacter(
    String char,
    int node,
    ComputedStyle style,
    int link,
  ) {
    _flushPending(char.codeUnitAt(0));
    _contentStarts();
    _map.add(_length, char.length, node, 0, 0);
    _append(char, style, link);
  }

  void addImage(
    int node,
    ComputedStyle style,
    String src,
    String? alt,
    int link,
  ) {
    _flushPending(0xFFFC);
    _contentStarts();
    _atomics.add(
      InlineImage(_length, node, style, src: src, alt: alt, link: link),
    );
    _map.add(_length, 1, node, 0, 0);
    _append(objectReplacementCharacter, style, link);
    _lineHasContent = true;
    _atWordStart = false;
    _column++;
  }

  /// A formula, laid out by the math layout: one character here, [text]
  /// for copying and search.
  void addMath(
    int node,
    ComputedStyle style,
    MathNode math,
    String text,
    int link,
  ) {
    _flushPending(0xFFFC);
    _contentStarts();
    _atomics.add(
      InlineMath(_length, node, style, math: math, text: text, link: link),
    );
    _map.add(_length, 1, node, 0, 0);
    _append(objectReplacementCharacter, style, link);
    _lineHasContent = true;
    _atWordStart = false;
    _column++;
  }

  /// Raised or lowered text, laid out on its own: one character here.
  void addInlineText(
    int node,
    ComputedStyle style,
    ParagraphBox paragraph,
    int link, {
    required double parentFontSize,
    bool isInlineBlock = false,
  }) {
    _flushPending(0xFFFC);
    _contentStarts();
    _atomics.add(
      InlineText(
        _length,
        node,
        style,
        paragraph: paragraph,
        parentFontSize: parentFontSize,
        link: link,
        isInlineBlock: isInlineBlock,
      ),
    );
    _map.add(_length, 1, node, 0, 0);
    _append(objectReplacementCharacter, style, link);
    _lineHasContent = true;
    _atWordStart = false;
    _column++;
  }

  /// Text that is not in the document (quotes, markers, `content`): laid
  /// out, never mapped; with [transform], under the style's
  /// `text-transform`.
  void addGenerated(
    String text,
    ComputedStyle style,
    int link, {
    bool transform = false,
  }) {
    if (transform) text = _transformedText(text, style.textTransform);
    if (text.isEmpty) return;
    _flushPending(text.codeUnitAt(0));
    _contentStarts();
    _append(text, style, link);
    _lineHasContent = true;
    _atWordStart = _isSpaceLike(text.runes.last);
    _column += text.length;
  }

  /// An image of `content`: laid out as the document's are, never mapped.
  void addGeneratedImage(int node, ComputedStyle style, String src, int link) {
    _flushPending(0xFFFC);
    _contentStarts();
    _atomics.add(InlineImage(_length, node, style, src: src, link: link));
    _append(objectReplacementCharacter, style, link);
    _lineHasContent = true;
    _atWordStart = false;
    _column++;
  }

  /// An empty inline block of its own size: not in the document's text.
  void addInlineBox(int node, ComputedStyle style, int link) {
    _flushPending(0xFFFC);
    _contentStarts();
    _atomics.add(InlineBox(_length, node, style, link: link));
    _append(objectReplacementCharacter, style, link);
    _lineHasContent = true;
    _atWordStart = false;
    _column++;
  }

  /// [text] under [transform], code point by code point.
  String _transformedText(String text, CssTextTransform transform) {
    if (transform == CssTextTransform.none) return text;
    final out = StringBuffer();
    var wordStart = _atWordStart;
    for (final rune in text.runes) {
      final original = String.fromCharCode(rune);
      out.write(switch (transform) {
        CssTextTransform.uppercase => _upperCase(rune, original),
        CssTextTransform.lowercase => original.toLowerCase(),
        CssTextTransform.capitalize when wordStart && _isLetter(rune) =>
          _titleCase(rune, original),
        _ => original,
      });
      if (_isLetter(rune) || _isDigit(rune)) {
        wordStart = false;
      } else if (_isSpaceLike(rune)) {
        wordStart = true;
      }
    }
    return out.toString();
  }

  /// The room an inline element's start or end takes: not in the
  /// document, and no content for whitespace at a line start.
  void addSpacer(
    int node,
    ComputedStyle style,
    int link, {
    required bool isStart,
  }) {
    _flushPending(0xFFFC);
    _contentStarts();
    _atomics.add(InlineSpacer(_length, node, style, isStart: isStart));
    _append(objectReplacementCharacter, style, link);
  }

  /// Starts element [node]'s decoration at its first content.
  void openDecoration(int node, ComputedStyle style) =>
      _openDecorations.add(_OpenDecoration(node, style));

  /// Ends [node]'s decoration here; a paragraph that did not see it open
  /// (a block inside the element began this one) is decorated from its
  /// start.
  void closeDecoration(int node, ComputedStyle style) {
    final i = _openDecorations.lastIndexWhere((o) => o.node == node);
    if (i < 0) {
      if (_length > 0) {
        _decorations.add(InlineDecoration(0, _length, style, node));
      }
      return;
    }
    _end(_openDecorations.removeAt(i));
  }

  void _end(_OpenDecoration open) {
    final start = open.start;
    if (start >= 0 && _length > start) {
      _decorations.add(InlineDecoration(start, _length, open.style, open.node));
    }
  }

  /// Open decorations waiting for content start here.
  void _contentStarts() {
    for (final open in _openDecorations) {
      if (open.start < 0) open.start = _length;
    }
  }

  ParagraphBox? build({required bool indentFirstLine}) {
    _dropPending();
    final trailingBreak = _pendingBreak;
    if (trailingBreak != null) {
      _pendingBreak = null;
      _map.add(
        _length,
        0,
        trailingBreak.node,
        trailingBreak.nodeStart,
        trailingBreak.nodeLength,
      );
      _mapDroppedAfterBreak();
    }
    _closeRun();
    if (_length == 0) return null;
    // Elements a block inside them split: decorated to here.
    for (final open in _openDecorations) {
      _end(open);
    }
    _openDecorations.clear();
    // Outer elements first, so inner ones paint over them.
    _decorations.sort(
      (a, b) => a.start != b.start ? a.start - b.start : b.end - a.end,
    );
    return ParagraphBox(
      blockStyle,
      blockNode,
      text: _text.toString(),
      runs: List.unmodifiable(_runs),
      atomics: List.unmodifiable(_atomics),
      sourceMap: _map.build(),
      indentFirstLine: indentFirstLine,
      isProse: isProse,
      decorations: List.unmodifiable(_decorations),
    );
  }

  static bool _isCollapsible(int c) => c == 0x20 || c == 0x09 || c == 0x0A;

  /// Upper case with Unicode's unconditional special casing, which
  /// `String.toUpperCase` leaves out: ß → SS, ligatures → letters.
  static String _upperCase(int rune, String original) =>
      _specialUpper[rune] ?? original.toUpperCase();

  /// Title case: digraphs have their own title forms (ǆ → ǅ).
  static String _titleCase(int rune, String original) =>
      _titleForms[rune] ?? _upperCase(rune, original);

  static bool _endsAtWordStart(String data, int end) =>
      end == 0 || _isSpaceLike(data.codeUnitAt(end - 1));

  static bool _isSpaceLike(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0xA0 || c == 0x3000;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  /// Letters that have case, or any alphabetic script: the cases
  /// `capitalize` cares about. Approximated without Unicode tables: a
  /// character that changes under upper or lower case is a letter.
  static bool _isLetter(int rune) {
    if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
      return true;
    }
    if (rune < 0xC0) return false;
    if (_specialUpper.containsKey(rune) || _titleForms.containsKey(rune)) {
      return true;
    }
    final s = String.fromCharCode(rune);
    return s.toUpperCase() != s || s.toLowerCase() != s;
  }

  /// East Asian Width F, W or H, Hangul excepted: ideographs, kana, CJK
  /// punctuation and full-width forms.
  static bool _isWideCjk(int c) =>
      (c >= 0x2E80 && c <= 0x303E) ||
      (c >= 0x3041 && c <= 0x33FF) ||
      (c >= 0x3400 && c <= 0x4DBF) ||
      (c >= 0x4E00 && c <= 0x9FFF) ||
      (c >= 0xF900 && c <= 0xFAFF) ||
      (c >= 0xFE30 && c <= 0xFE4F) ||
      (c >= 0xFF00 && c <= 0xFF60) ||
      (c >= 0xFFE0 && c <= 0xFFE6) ||
      (c >= 0xFF61 && c <= 0xFFDC);
}

/// Unicode SpecialCasing.txt, the unconditional upper-case mappings.
const _specialUpper = <int, String>{
  0x00DF: 'SS',
  0x0149: '\u02BCN',
  0x01F0: 'J\u030C',
  0x0390: '\u0399\u0308\u0301',
  0x03B0: '\u03A5\u0308\u0301',
  0x0587: '\u0535\u0552',
  0x1E96: 'H\u0331',
  0x1E97: 'T\u0308',
  0x1E98: 'W\u030A',
  0x1E99: 'Y\u030A',
  0x1E9A: 'A\u02BE',
  0xFB00: 'FF',
  0xFB01: 'FI',
  0xFB02: 'FL',
  0xFB03: 'FFI',
  0xFB04: 'FFL',
  0xFB05: 'ST',
  0xFB06: 'ST',
  0xFB13: '\u0544\u0546',
  0xFB14: '\u0544\u0535',
  0xFB15: '\u0544\u053B',
  0xFB16: '\u054E\u0546',
  0xFB17: '\u0544\u053D',
};

/// Title-case forms that differ from upper case.
const _titleForms = <int, String>{
  0x00DF: 'Ss',
  0x01C4: '\u01C5',
  0x01C5: '\u01C5',
  0x01C6: '\u01C5',
  0x01C7: '\u01C8',
  0x01C8: '\u01C8',
  0x01C9: '\u01C8',
  0x01CA: '\u01CB',
  0x01CB: '\u01CB',
  0x01CC: '\u01CB',
  0x01F1: '\u01F2',
  0x01F2: '\u01F2',
  0x01F3: '\u01F2',
  0xFB00: 'Ff',
  0xFB01: 'Fi',
  0xFB02: 'Fl',
  0xFB03: 'Ffi',
  0xFB04: 'Ffl',
  0xFB05: 'St',
  0xFB06: 'St',
};

class _PendingSpace {
  _PendingSpace(this.style, this.link);

  final ComputedStyle style;
  final int link;
  final ranges = <({int node, int start, int end})>[];
  bool sawSegmentBreak = false;
}

/// A decorated inline element open in a paragraph: its start is set at
/// its first content, -1 until then.
class _OpenDecoration {
  _OpenDecoration(this.node, this.style);

  final int node;
  final ComputedStyle style;
  int start = -1;
}

/// An image `content` shows.
class _GeneratedImage {
  const _GeneratedImage(this.src);

  final String src;
}

/// CSS counters in scope while the boxes are built (CSS Lists 3 §4.5):
/// a counter reset on an element lives through its later siblings and
/// everything inside them, so each element's children open a scope, and
/// one reset among them lands in theirs.
class _Counters {
  final _scopes = <Map<String, int>>[{}];

  void push() => _scopes.add({});

  void pop() {
    if (_scopes.length > 1) _scopes.removeLast();
  }

  /// [style]'s `counter-reset`, `counter-increment` and `counter-set`, in
  /// that order; a counter used before any reset starts at 0 here.
  void apply(ComputedStyle style) {
    for (final (name, value) in style.counterReset) {
      _scopes.last[name] = value;
    }
    for (final (name, step) in style.counterIncrement) {
      final scope = _scopeOf(name) ?? (_scopes.last..[name] = 0);
      scope[name] = scope[name]! + step;
    }
    for (final (name, value) in style.counterSet) {
      (_scopeOf(name) ?? _scopes.last)[name] = value;
    }
  }

  Map<String, int>? _scopeOf(String name) {
    for (var i = _scopes.length - 1; i >= 0; i--) {
      if (_scopes[i].containsKey(name)) return _scopes[i];
    }
    return null;
  }

  /// The innermost counter [name]'s value, 0 when there is none.
  int value(String name) => _scopeOf(name)?[name] ?? 0;

  /// Every counter [name] in scope, outermost first: `counters()`.
  List<int> values(String name) => [
    for (final scope in _scopes) ?scope[name],
  ];
}

/// The hyphenation of one section's text: [limits], and each text's
/// hyphenator by its element's language (`lang`, else `xml:lang`, up
/// the tree; the root carries the book's).
class _WordBreaks {
  _WordBreaks(this.doc, this.limits);

  final ContentDocument doc;
  final TextHyphenation limits;
  final _languages = <int, String?>{};
  final _hyphenators = <int, Hyphenator?>{};

  Hyphenator? hyphenatorFor(int textNode) {
    final element = doc.parentOf(textNode);
    return _hyphenators.containsKey(element)
        ? _hyphenators[element]
        : _hyphenators[element] = Hyphenator.forLanguage(_languageOf(element));
  }

  String? _languageOf(int element) {
    if (element == ContentDocument.none) return null;
    if (_languages.containsKey(element)) return _languages[element];
    final own =
        doc.attributeOf(element, 'xml:lang') ??
        doc.attributeOf(element, 'lang');
    return _languages[element] = own ?? _languageOf(doc.parentOf(element));
  }
}
