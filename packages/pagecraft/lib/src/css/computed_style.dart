/// The computed style of an element: every supported property resolved
/// to the value layout uses. Relative font sizes and `em` lengths are in
/// px, percentages stay percentages (layout knows what they refer to),
/// keywords are enums. Immutable, with value equality so the resolver
/// can share one instance between elements that compute the same.
library;

import 'css_custom_properties.dart';
import 'css_properties.dart' show CssContentItem;
import 'css_values.dart';

enum CssDisplay {
  block,
  inline,
  inlineBlock,
  none,
  listItem,
  table,
  inlineTable,
  tableRowGroup,
  tableHeaderGroup,
  tableFooterGroup,
  tableRow,
  tableCell,
  tableCaption,
  tableColumn,
  tableColumnGroup,
  ruby,
  rubyBase,
  rubyText,
  contents;

  /// Whether the element starts a block of its own in the flow.
  bool get isBlockLevel => switch (this) {
    block || listItem || table || tableCaption => true,
    _ => false,
  };

  static CssDisplay fromKeyword(String keyword) => switch (keyword) {
    'block' => block,
    'inline' => inline,
    'inline-block' => inlineBlock,
    'none' => none,
    'list-item' => listItem,
    'table' => table,
    'inline-table' => inlineTable,
    'table-row-group' => tableRowGroup,
    'table-header-group' => tableHeaderGroup,
    'table-footer-group' => tableFooterGroup,
    'table-row' => tableRow,
    'table-cell' => tableCell,
    'table-caption' => tableCaption,
    'table-column' => tableColumn,
    'table-column-group' => tableColumnGroup,
    'ruby' => ruby,
    'ruby-base' => rubyBase,
    'ruby-text' => rubyText,
    'contents' => contents,
    _ => inline,
  };
}

enum CssTextAlign { start, end, left, right, center, justify }

enum CssFontStyle { normal, italic, oblique }

enum CssPageBreak { auto, always, avoid, left, right }

enum CssFloat { none, left, right }

enum CssClear { none, left, right, both }

enum CssWhiteSpace {
  normal,
  nowrap,
  pre,
  preWrap,
  preLine;

  /// Whether runs of whitespace collapse to one space.
  bool get collapses => this == normal || this == nowrap || this == preLine;

  /// Whether line breaks in the source are honored.
  bool get preservesNewlines =>
      this == pre || this == preWrap || this == preLine;

  bool get wraps => this != nowrap && this != pre;
}

enum CssTextTransform { none, capitalize, uppercase, lowercase }

enum CssHyphens { none, manual, auto }

enum CssDirection { ltr, rtl }

enum CssUnicodeBidi {
  normal,
  embed,
  isolate,
  bidiOverride,
  isolateOverride,
  plaintext,
}

enum CssVerticalAlign {
  baseline,
  sub,
  sup,
  textTop,
  textBottom,
  middle,
  top,
  bottom,
  length,
}

enum CssBorderStyle {
  none,
  hidden,
  solid,
  dashed,
  dotted,
  double,
  groove,
  ridge,
  inset,
  outset,
}

/// `writing-mode`; the SVG values map onto these.
enum CssWritingMode {
  horizontalTb,
  verticalRl,
  verticalLr;

  bool get isVertical => this != horizontalTb;
}

/// `overflow-wrap` (and its old name `word-wrap`).
enum CssOverflowWrap { normal, breakWord, anywhere }

enum CssWordBreak { normal, breakAll, keepAll }

enum CssPosition { static, relative, absolute, fixed, sticky }

enum CssBoxSizing { contentBox, borderBox }

enum CssCaptionSide { top, bottom }

/// `overflow-x` and `overflow-y`.
enum CssOverflow {
  visible,
  hidden,
  clip,
  scroll,
  auto;

  /// Whether the box scrolls what overflows it.
  bool get scrolls => this == scroll || this == auto;
}

/// The intrinsic sizes `width` can be (CSS Sizing 3 §3.2).
enum CssSizeKeyword { minContent, maxContent, fitContent }

/// One value per corner, clockwise from the top left.
class CssCorners<T> {
  const CssCorners(
    this.topLeft,
    this.topRight,
    this.bottomRight,
    this.bottomLeft,
  );

  const CssCorners.all(T value) : this(value, value, value, value);

  final T topLeft;
  final T topRight;
  final T bottomRight;
  final T bottomLeft;

  @override
  bool operator ==(Object other) =>
      other is CssCorners<T> &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() => '($topLeft $topRight $bottomRight $bottomLeft)';
}

/// A corner's radii: horizontal and vertical, each px or a percentage of
/// the box's width or height.
class CssRadius {
  const CssRadius(this.x, this.y);

  static const zero = CssRadius(CssLength.zero, CssLength.zero);

  final CssLength x;
  final CssLength y;

  bool get isZero => x.isZero || y.isZero;

  @override
  bool operator ==(Object other) =>
      other is CssRadius && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => x == y ? '$x' : '$x/$y';
}

/// One value per edge.
class CssEdges<T> {
  const CssEdges(this.top, this.right, this.bottom, this.left);

  const CssEdges.all(T value) : this(value, value, value, value);

  final T top;
  final T right;
  final T bottom;
  final T left;

  @override
  bool operator ==(Object other) =>
      other is CssEdges<T> &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);

  @override
  String toString() => '($top $right $bottom $left)';
}

/// `line-height`: a factor of the font size (`normal` and numbers) or a
/// length in px.
class CssLineHeight {
  const CssLineHeight.factor(this.factor) : px = null;

  const CssLineHeight.px(this.px) : factor = null;

  /// `normal`: the font's own line gap. Layout substitutes the font
  /// metrics; 1.2 is the usual stand-in.
  static const normal = CssLineHeight.factor(null);

  final double? factor;
  final double? px;

  bool get isNormal => factor == null && px == null;

  /// The line height in px for [fontSize], taking [normalFactor] for
  /// `normal`.
  double resolve(double fontSize, {double normalFactor = 1.2}) =>
      px ?? (factor ?? normalFactor) * fontSize;

  @override
  bool operator ==(Object other) =>
      other is CssLineHeight && other.factor == factor && other.px == px;

  @override
  int get hashCode => Object.hash(factor, px);

  @override
  String toString() => px != null
      ? '${px}px'
      : factor == null
      ? 'normal'
      : '$factor';
}

/// How a background image is sized (`background-size`).
enum CssBackgroundFit {
  /// Its own size, or [CssBackgroundImage.width] and `height`.
  auto,

  /// As small as covers the box.
  cover,

  /// As large as fits in the box.
  contain,
}

/// A box's background image (CSS Backgrounds 3): its [source] as the
/// section's images are written, its size, how it repeats and where it
/// starts in the padding box.
class CssBackgroundImage {
  const CssBackgroundImage(
    this.source, {
    this.fit = CssBackgroundFit.auto,
    this.width,
    this.height,
    this.repeatX = true,
    this.repeatY = true,
    this.x = const CssLength.percent(0),
    this.y = const CssLength.percent(0),
  });

  final String source;
  final CssBackgroundFit fit;

  /// With [CssBackgroundFit.auto]: the set width and height; null is
  /// `auto`.
  final CssLength? width;
  final CssLength? height;
  final bool repeatX;
  final bool repeatY;

  /// `background-position`: percentages place the image's own point at
  /// the box's.
  final CssLength x;
  final CssLength y;

  @override
  bool operator ==(Object other) =>
      other is CssBackgroundImage &&
      other.source == source &&
      other.fit == fit &&
      other.width == width &&
      other.height == height &&
      other.repeatX == repeatX &&
      other.repeatY == repeatY &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode =>
      Object.hash(source, fit, width, height, repeatX, repeatY, x, y);

  @override
  String toString() => 'url($source)';
}

class ComputedStyle {
  const ComputedStyle({
    required this.fontFamily,
    required this.fontSize,
    required this.fontStyle,
    required this.fontWeight,
    required this.smallCaps,
    this.opticalSizing = true,
    required this.color,
    required this.backgroundColor,
    this.backgroundImage,
    required this.textAlign,
    required this.textIndent,
    required this.lineHeight,
    required this.margin,
    required this.padding,
    required this.borderWidth,
    required this.borderStyle,
    required this.borderColor,
    required this.display,
    required this.pageBreakBefore,
    required this.pageBreakAfter,
    required this.avoidPageBreakInside,
    required this.width,
    required this.height,
    required this.maxWidth,
    required this.maxHeight,
    required this.minWidth,
    required this.minHeight,
    required this.float,
    required this.clear,
    required this.underline,
    required this.overline,
    required this.lineThrough,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.whiteSpace,
    required this.verticalAlign,
    required this.verticalAlignLength,
    required this.textTransform,
    required this.hyphens,
    required this.direction,
    required this.unicodeBidi,
    required this.listStyleType,
    required this.visible,
    required this.widows,
    required this.orphans,
    this.writingMode = CssWritingMode.horizontalTb,
    this.overflowWrap = CssOverflowWrap.normal,
    this.wordBreak = CssWordBreak.normal,
    this.borderCollapse = false,
    this.borderSpacingX = 0,
    this.borderSpacingY = 0,
    this.captionSide = CssCaptionSide.top,
    this.overflowX = CssOverflow.visible,
    this.widthKeyword,
    this.position = CssPosition.static,
    this.offsets = const CssEdges<CssLength?>.all(null),
    this.borderRadius = const CssCorners.all(CssRadius.zero),
    this.boxSizing = CssBoxSizing.contentBox,
    this.quotes,
    this.listStyleInside = false,
    this.content,
    this.counterReset = const [],
    this.counterIncrement = const [],
    this.counterSet = const [],
    this.customProperties = CssCustomProperties.empty,
  });

  final List<String> fontFamily;

  /// In px.
  final double fontSize;
  final CssFontStyle fontStyle;

  /// 1–1000.
  final int fontWeight;
  final bool smallCaps;

  /// `font-optical-sizing: auto`: a font with an optical size axis
  /// (`opsz`) is drawn at the design for its size, as browsers draw it.
  final bool opticalSizing;

  /// `0xAARRGGBB`.
  final int color;
  final int backgroundColor;
  final CssBackgroundImage? backgroundImage;
  final CssTextAlign textAlign;

  /// px or a percentage of the containing block's width.
  final CssLength textIndent;
  final CssLineHeight lineHeight;

  /// px or a percentage; null is `auto`.
  final CssEdges<CssLength?> margin;
  final CssEdges<CssLength> padding;

  /// In px; 0 when the style is `none` or `hidden`.
  final CssEdges<double> borderWidth;
  final CssEdges<CssBorderStyle> borderStyle;
  final CssEdges<int> borderColor;
  final CssDisplay display;
  final CssPageBreak pageBreakBefore;
  final CssPageBreak pageBreakAfter;
  final bool avoidPageBreakInside;

  /// px or a percentage; null is `auto`.
  final CssLength? width;
  final CssLength? height;

  /// px or a percentage; null is `none`.
  final CssLength? maxWidth;
  final CssLength? maxHeight;
  final CssLength minWidth;
  final CssLength minHeight;
  final CssFloat float;
  final CssClear clear;
  final bool underline;
  final bool overline;
  final bool lineThrough;

  /// In px; 0 is `normal`.
  final double letterSpacing;
  final double wordSpacing;
  final CssWhiteSpace whiteSpace;
  final CssVerticalAlign verticalAlign;

  /// For [CssVerticalAlign.length]: px or a percentage of the line height.
  final CssLength? verticalAlignLength;
  final CssTextTransform textTransform;
  final CssHyphens hyphens;
  final CssDirection direction;
  final CssUnicodeBidi unicodeBidi;

  /// A keyword (`disc`, `decimal`, `none`) or a literal marker string.
  final String listStyleType;
  final bool visible;
  final int widows;
  final int orphans;
  final CssWritingMode writingMode;
  final CssOverflowWrap overflowWrap;
  final CssWordBreak wordBreak;

  /// `border-collapse: collapse`: a table's cells share their borders.
  final bool borderCollapse;

  /// `border-spacing` between separated cells, in px.
  final double borderSpacingX;
  final double borderSpacingY;
  final CssCaptionSide captionSide;
  final CssOverflow overflowX;

  /// `width` as an intrinsic size; [width] is null with it. Tables size
  /// by it; other boxes take it as `auto`.
  final CssSizeKeyword? widthKeyword;
  final CssPosition position;

  /// `top`, `right`, `bottom`, `left`: px or a percentage; null is
  /// `auto`.
  final CssEdges<CssLength?> offsets;
  final CssCorners<CssRadius> borderRadius;
  final CssBoxSizing boxSizing;

  /// `quotes`: open and close marks by nesting level, alternating; empty
  /// for `none`, null for `auto` (the language's).
  final List<String>? quotes;

  /// `list-style-position: inside`: the marker starts the first line.
  final bool listStyleInside;

  /// What a `::before` or `::after` with this style shows; null for
  /// `normal` and `none`, which make no box.
  final List<CssContentItem>? content;

  /// Counters the element starts, steps and sets, with their values.
  final List<(String, int)> counterReset;
  final List<(String, int)> counterIncrement;
  final List<(String, int)> counterSet;

  /// The custom properties (`--name`) the element has, its own and
  /// inherited, for `var()`.
  final CssCustomProperties customProperties;

  bool get isBold => fontWeight >= 600;

  bool get isItalic => fontStyle != CssFontStyle.normal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComputedStyle &&
          _sameFamilies(other.fontFamily, fontFamily) &&
          other.fontSize == fontSize &&
          other.fontStyle == fontStyle &&
          other.fontWeight == fontWeight &&
          other.smallCaps == smallCaps &&
          other.opticalSizing == opticalSizing &&
          other.color == color &&
          other.backgroundColor == backgroundColor &&
          other.backgroundImage == backgroundImage &&
          other.textAlign == textAlign &&
          other.textIndent == textIndent &&
          other.lineHeight == lineHeight &&
          other.margin == margin &&
          other.padding == padding &&
          other.borderWidth == borderWidth &&
          other.borderStyle == borderStyle &&
          other.borderColor == borderColor &&
          other.display == display &&
          other.pageBreakBefore == pageBreakBefore &&
          other.pageBreakAfter == pageBreakAfter &&
          other.avoidPageBreakInside == avoidPageBreakInside &&
          other.width == width &&
          other.height == height &&
          other.maxWidth == maxWidth &&
          other.maxHeight == maxHeight &&
          other.minWidth == minWidth &&
          other.minHeight == minHeight &&
          other.float == float &&
          other.clear == clear &&
          other.underline == underline &&
          other.overline == overline &&
          other.lineThrough == lineThrough &&
          other.letterSpacing == letterSpacing &&
          other.wordSpacing == wordSpacing &&
          other.whiteSpace == whiteSpace &&
          other.verticalAlign == verticalAlign &&
          other.verticalAlignLength == verticalAlignLength &&
          other.textTransform == textTransform &&
          other.hyphens == hyphens &&
          other.direction == direction &&
          other.unicodeBidi == unicodeBidi &&
          other.listStyleType == listStyleType &&
          other.visible == visible &&
          other.widows == widows &&
          other.orphans == orphans &&
          other.writingMode == writingMode &&
          other.overflowWrap == overflowWrap &&
          other.wordBreak == wordBreak &&
          other.borderCollapse == borderCollapse &&
          other.borderSpacingX == borderSpacingX &&
          other.borderSpacingY == borderSpacingY &&
          other.captionSide == captionSide &&
          other.overflowX == overflowX &&
          other.widthKeyword == widthKeyword &&
          other.position == position &&
          other.offsets == offsets &&
          other.borderRadius == borderRadius &&
          other.boxSizing == boxSizing &&
          _sameQuotes(other.quotes, quotes) &&
          other.listStyleInside == listStyleInside &&
          _sameList(other.content, content) &&
          _sameList(other.counterReset, counterReset) &&
          _sameList(other.counterIncrement, counterIncrement) &&
          _sameList(other.counterSet, counterSet) &&
          other.customProperties == customProperties;

  static bool _sameList<T>(List<T>? a, List<T>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameQuotes(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameFamilies(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
    Object.hashAll(fontFamily),
    fontSize,
    fontStyle,
    fontWeight,
    smallCaps,
    opticalSizing,
    color,
    backgroundColor,
    backgroundImage,
    textAlign,
    textIndent,
    lineHeight,
    margin,
    padding,
    borderWidth,
    borderStyle,
    borderColor,
    display,
    pageBreakBefore,
    pageBreakAfter,
    avoidPageBreakInside,
    width,
    height,
    maxWidth,
    maxHeight,
    minWidth,
    minHeight,
    float,
    clear,
    underline,
    overline,
    lineThrough,
    letterSpacing,
    wordSpacing,
    whiteSpace,
    verticalAlign,
    verticalAlignLength,
    textTransform,
    hyphens,
    direction,
    unicodeBidi,
    listStyleType,
    visible,
    widows,
    orphans,
    writingMode,
    overflowWrap,
    wordBreak,
    borderCollapse,
    borderSpacingX,
    borderSpacingY,
    captionSide,
    overflowX,
    widthKeyword,
    position,
    offsets,
    borderRadius,
    boxSizing,
    quotes == null ? null : Object.hashAll(quotes!),
    listStyleInside,
    content == null ? null : Object.hashAll(content!),
    Object.hashAll(counterReset),
    Object.hashAll(counterIncrement),
    Object.hashAll(counterSet),
    customProperties,
  ]);

  @override
  String toString() =>
      'ComputedStyle(${fontFamily.join(', ')} ${fontSize}px $fontWeight '
      '$fontStyle color #${color.toRadixString(16)} $display)';
}
