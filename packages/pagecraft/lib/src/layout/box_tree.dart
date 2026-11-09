/// The box tree of a section: what the browser's CSS box generation was
/// to foliate-js, and the input of the layout.
///
/// A section becomes blocks in document order. A block container holds
/// either blocks or one paragraph of inline content, never both: inline
/// content beside blocks is wrapped in anonymous paragraphs, as CSS wraps
/// it in anonymous block boxes. A paragraph is flat: its text after
/// whitespace processing, style runs over it, atomic inlines (images) at
/// object-replacement characters, and a [TextSourceMap] back to the
/// document. Tables keep rows and cells.
///
/// Pure Dart and immutable: built in an isolate with the document and
/// its styles, handed to the layout on the UI isolate.
library;

import '../css/computed_style.dart';
import 'text_source_map.dart';

/// The character an atomic inline occupies in a paragraph's text, as in
/// Flutter's placeholders.
const objectReplacementCharacter = '\uFFFC';

/// A place a word may break with a hyphen: `&shy;` in a book, or what
/// automatic hyphenation puts in a paragraph's text (not the document's).
const softHyphen = '\u00AD';

/// A box: its computed style and the element it comes from.
sealed class LayoutBox {
  const LayoutBox(this.style, this.node);

  final ComputedStyle style;

  /// The element's index in the `ContentDocument`; for an anonymous
  /// paragraph, its containing block's element.
  final int node;
}

/// A block container. Its [children] are blocks, paragraphs, images and
/// tables; a list item also has a [marker].
class BlockBox extends LayoutBox {
  const BlockBox(
    super.style,
    super.node,
    this.children, {
    this.marker,
    this.isProse = false,
    this.isHeading = false,
  });

  final List<LayoutBox> children;

  /// `h1`–`h6`: kept with what follows across a page break.
  final bool isHeading;

  /// The list item's marker text (`1. `, `•`), or null.
  final String? marker;

  /// Body text: a `p`, `li`, `blockquote`, `dd` or `font`, or a `div`
  /// holding only text and phrasing elements. The reader's line height,
  /// paragraph spacing, indent and alignment apply to prose, as
  /// foliate-js applies them to these elements.
  final bool isProse;
}

/// One paragraph: a run of inline content laid out as lines.
///
/// [style] is the containing block's: alignment, indent, line height and
/// direction come from it; each run has its own style for the text.
class ParagraphBox extends LayoutBox {
  const ParagraphBox(
    super.style,
    super.node, {
    required this.text,
    required this.runs,
    required this.atomics,
    required this.sourceMap,
    required this.indentFirstLine,
    this.isProse = false,
    this.decorations = const [],
  });

  /// The text to lay out: whitespace collapsed or preserved per
  /// `white-space`, `\n` for forced breaks, U+FFFC for atomic inlines.
  final String text;

  /// Inline elements with a background, border or padding, outer ones
  /// first: drawn under the text where their text falls.
  final List<InlineDecoration> decorations;

  /// Style runs covering [text] end to end, in order.
  final List<InlineRun> runs;

  /// Images and other atomic inlines, by offset in [text].
  final List<InlineAtomic> atomics;
  final TextSourceMap sourceMap;

  /// Whether `text-indent` applies: only the first line of a block's
  /// first box gets it.
  final bool indentFirstLine;

  /// Whether the containing block is prose ([BlockBox.isProse]).
  final bool isProse;

  /// The paragraph from text offset [from] on, every offset in it
  /// counted from there: what a paragraph's lines beside a float are
  /// followed by. It has no first-line indent.
  ParagraphBox tail(int from) {
    if (from == 0) return this;
    return ParagraphBox(
      style,
      node,
      text: text.substring(from),
      runs: [
        for (final run in runs)
          if (run.end > from)
            InlineRun(
              (run.start > from ? run.start : from) - from,
              run.end - from,
              run.style,
              link: run.link,
            ),
      ],
      atomics: [
        for (final atomic in atomics)
          if (atomic.offset >= from) atomic.movedTo(atomic.offset - from),
      ],
      sourceMap: sourceMap.tail(from),
      indentFirstLine: false,
      isProse: isProse,
      decorations: [
        for (final decoration in decorations)
          if (decoration.end > from)
            InlineDecoration(
              (decoration.start > from ? decoration.start : from) - from,
              decoration.end - from,
              decoration.style,
              decoration.node,
            ),
      ],
    );
  }

  /// The text of `[start, end)` as a reader sees it: raised text (a
  /// footnote number) in place of its placeholder, images left out, as
  /// browsers copy a selection.
  String plainText(int start, int end) => _plainText(
    start,
    end,
  ).replaceAll(softHyphen, '');

  String _plainText(int start, int end) {
    if (atomics.isEmpty) return text.substring(start, end);
    final out = StringBuffer();
    var at = start;
    for (final atomic in atomics) {
      final offset = atomic.offset;
      if (offset < start) continue;
      if (offset >= end) break;
      out.write(text.substring(at, offset));
      if (atomic is InlineText) {
        final inner = atomic.paragraph;
        out.write(inner.plainText(0, inner.text.length));
      } else if (atomic is InlineMath) {
        out.write(atomic.text);
      }
      at = offset + 1;
    }
    out.write(text.substring(at, end));
    return out.toString();
  }

  /// The paragraphs of raised or lowered text inside this one.
  Iterable<ParagraphBox> get nestedParagraphs sync* {
    for (final atomic in atomics) {
      if (atomic is InlineText) yield atomic.paragraph;
    }
  }
}

/// A range of a paragraph's text with one style.
class InlineRun {
  const InlineRun(this.start, this.end, this.style, {this.link = -1});

  final int start;
  final int end;
  final ComputedStyle style;

  /// The `<a href>` element the run is inside, or -1.
  final int link;

  @override
  String toString() => '[$start, $end)${link >= 0 ? ' link $link' : ''}';
}

/// An inline element's background, border and padding over text
/// `[start, end)` of its paragraph, its start and end spacers included:
/// CSS's inline box, sliced where its lines break.
class InlineDecoration {
  const InlineDecoration(this.start, this.end, this.style, this.node);

  final int start;
  final int end;
  final ComputedStyle style;
  final int node;

  @override
  String toString() => '[$start, $end)';
}

/// Something laid out as one unit inside a line.
sealed class InlineAtomic {
  const InlineAtomic(this.offset, this.node, this.style);

  /// Its U+FFFC's offset in the paragraph text.
  final int offset;
  final int node;
  final ComputedStyle style;

  /// The same atomic at [offset].
  InlineAtomic movedTo(int offset);
}

/// An inline image. [src] is as written, relative to the section.
class InlineImage extends InlineAtomic {
  const InlineImage(
    super.offset,
    super.node,
    super.style, {
    required this.src,
    this.alt,
    this.link = -1,
  });

  final String src;
  final String? alt;
  final int link;

  @override
  InlineImage movedTo(int offset) =>
      InlineImage(offset, node, style, src: src, alt: alt, link: link);
}

/// Text raised or lowered off the baseline (`vertical-align: super`,
/// `sub` or a length): its own small paragraph, placed in the line as one
/// unit, because a text span cannot move its baseline in Flutter.
/// Footnote references and exponents are the usual case.
///
/// An inline block ([isInlineBlock], `display: inline-block` around
/// inline content) is one too: its paragraph is laid out at the block's
/// width, inside its padding and border, and the line holds the block.
class InlineText extends InlineAtomic {
  const InlineText(
    super.offset,
    super.node,
    super.style, {
    required this.paragraph,
    required this.parentFontSize,
    this.link = -1,
    this.isInlineBlock = false,
  });

  /// The font size `super` and `sub` are measured against: the parent
  /// box's, as CSS says.
  final double parentFontSize;

  /// The raised text, styled by its own runs; [paragraph]'s style is the
  /// shifted element's, which says how far.
  final ParagraphBox paragraph;
  final int link;
  final bool isInlineBlock;

  @override
  InlineText movedTo(int offset) => InlineText(
    offset,
    node,
    style,
    paragraph: paragraph,
    parentFontSize: parentFontSize,
    link: link,
    isInlineBlock: isInlineBlock,
  );
}

/// A formula (MathML): its element tree, laid out as one unit of the line
/// by the math layout. [text] is what a reader copies and searches: the
/// `alttext`, else the formula's characters in order.
class InlineMath extends InlineAtomic {
  const InlineMath(
    super.offset,
    super.node,
    super.style, {
    required this.math,
    required this.text,
    this.link = -1,
  });

  final MathNode math;
  final String text;
  final int link;

  @override
  InlineMath movedTo(int offset) =>
      InlineMath(offset, node, style, math: math, text: text, link: link);
}

/// A MathML element as the math layout reads it: its local name,
/// attributes (names lowercased), and either its children (layout
/// elements) or its text (token elements: `mi`, `mn`, `mo`, `mtext`,
/// `ms`), white space collapsed and trimmed as MathML says.
class MathNode {
  const MathNode(
    this.name, {
    this.attributes = const {},
    this.children = const [],
    this.text = '',
  });

  final String name;
  final Map<String, String> attributes;
  final List<MathNode> children;
  final String text;

  String? operator [](String attribute) => attributes[attribute];

  /// Its token characters in document order.
  String get plainText =>
      children.isEmpty ? text : children.map((c) => c.plainText).join();

  @override
  String toString() => children.isEmpty
      ? '<$name>$text</$name>'
      : '<$name>${children.join()}</$name>';
}

/// The room an inline element's start or end takes in its line: its
/// horizontal margin, border and padding on that side ([style]'s). Not
/// in the document, never selected or copied.
class InlineSpacer extends InlineAtomic {
  const InlineSpacer(
    super.offset,
    super.node,
    super.style, {
    required this.isStart,
  });

  /// The element's start (left in left-to-right text); else its end.
  final bool isStart;

  @override
  InlineSpacer movedTo(int offset) =>
      InlineSpacer(offset, node, style, isStart: isStart);
}

/// An empty inline block with a size of its own (`display: inline-block`
/// with a width or height): a bullet drawn by `::before`, a colour
/// swatch. Its background and borders are [style]'s; it sits on the
/// baseline by its bottom margin edge.
class InlineBox extends InlineAtomic {
  const InlineBox(super.offset, super.node, super.style, {this.link = -1});

  final int link;

  @override
  InlineBox movedTo(int offset) => InlineBox(offset, node, style, link: link);
}

/// A block-level image: an `<img>` with a block display or a float, or
/// an SVG wrapper around one `<image>` (cover pages).
class ImageBox extends LayoutBox {
  const ImageBox(
    super.style,
    super.node, {
    required this.src,
    this.alt,
    this.viewBox,
    this.link = -1,
  });

  final String src;
  final String? alt;

  /// The SVG wrapper's view box size, which gives the image its aspect
  /// ratio when the wrapper scales it.
  final ({double width, double height})? viewBox;
  final int link;
}

/// A float (CSS 2.1 §9.5): an element taken out of the flow and put at
/// the [left] or right edge of its containing block where it was met,
/// with the lines beside it shortened. [content] is the element's own
/// box: an image, a table, or a block around its content (a float is
/// blockified, even a `<span>`).
class FloatBox extends LayoutBox {
  const FloatBox(super.style, super.node, this.content, {required this.left});

  final LayoutBox content;

  /// At the left edge; else the right.
  final bool left;
}

/// A table: an optional caption and rows in display order (header rows,
/// body rows, footer rows).
class TableBox extends LayoutBox {
  const TableBox(super.style, super.node, this.rows, {this.caption});

  final List<TableRowBox> rows;
  final BlockBox? caption;

  /// The number of columns the rows span.
  int get columnCount {
    var columns = 0;
    for (final row in rows) {
      var span = 0;
      for (final cell in row.cells) {
        span += cell.columnSpan;
      }
      if (span > columns) columns = span;
    }
    return columns;
  }
}

class TableRowBox {
  const TableRowBox(this.style, this.node, this.cells, {this.isHeader = false});

  final ComputedStyle style;
  final int node;
  final List<TableCellBox> cells;

  /// From `<thead>`: repeated when a table breaks across pages.
  final bool isHeader;
}

class TableCellBox extends BlockBox {
  const TableCellBox(
    super.style,
    super.node,
    super.children, {
    this.columnSpan = 1,
    this.rowSpan = 1,
  });

  final int columnSpan;
  final int rowSpan;
}

/// The boxes of one section, and what the layout needs to fetch before
/// it starts.
class SectionBoxes {
  const SectionBoxes(
    this.root, {
    required this.imageSources,
    this.raisedElements = const {},
    this.writingMode = CssWritingMode.horizontalTb,
  });

  final BlockBox root;

  /// The body's writing mode: the section's lines, as the browser lays
  /// them out.
  final CssWritingMode writingMode;

  /// Every image source the boxes reference, as written, once each.
  final List<String> imageSources;

  /// Shown elements aligned up (`vertical-align` super, top, text-top or
  /// a length): what foliate-js's `isSuper` asks of a note reference.
  final Set<int> raisedElements;

  /// Every paragraph in document order.
  Iterable<ParagraphBox> get paragraphs sync* {
    yield* _paragraphsOf(root);
  }

  static Iterable<ParagraphBox> _paragraphsOf(LayoutBox box) sync* {
    switch (box) {
      case ParagraphBox():
        yield box;
      case BlockBox(:final children):
        for (final child in children) {
          yield* _paragraphsOf(child);
        }
      case TableBox(:final caption, :final rows):
        if (caption != null) yield* _paragraphsOf(caption);
        for (final row in rows) {
          for (final cell in row.cells) {
            yield* _paragraphsOf(cell);
          }
        }
      case FloatBox(:final content):
        yield* _paragraphsOf(content);
      case ImageBox():
        break;
    }
  }
}
