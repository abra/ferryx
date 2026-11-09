/// The reader's settings for reflowable books, and where each one acts.
///
/// foliate-js applies the same settings with CSS injected into every
/// section (`getCSS` in `book.js`), followed by the host's own CSS
/// (`customCSS`). pagecraft splits them by what can carry them: rules plain
/// CSS expresses, the colour override among them, go into
/// [foliateStyleSheet], and [BookStyle.readerStyleSheet] follows it, both
/// after the book's own sheets in the author origin as in the WebView
/// ([readerSheetSources]); the per-paragraph rules
/// foliate-js writes with `:has()` and `!important` on body text (line
/// height, indent, paragraph spacing, alignment, weight and family) are
/// applied by the layout to prose paragraphs, where the structure is
/// known (`ParagraphBox.isProse`). Pure Dart.
library;

import 'package:meta/meta.dart';

import '../css/css_media.dart';
import '../css/css_syntax.dart';
import '../css/style_resolver.dart';

/// How a reflowable book is styled on top of its own CSS.
@immutable
class BookStyle {
  const BookStyle({
    this.fontScale = 1.4,
    this.fontFamily,
    this.fontWeight = 400,
    this.letterSpacing = 0,
    this.lineHeight = 1.8,
    this.paragraphSpacing = 1.0,
    this.textIndent = 0,
    this.textColor = 0xFF000000,
    this.backgroundColor = 0xFFFFFFFF,
    this.justify = true,
    this.overrideFont = true,
    this.overrideColor = true,
    this.useBookLayout = true,
    this.readerStyleSheet = '',
    this.wholePixelLineHeights = false,
    this.glyphLineBoxes = false,
    this.hyphenate = false,
    this.hyphenateLimitBefore = 2,
    this.hyphenateLimitAfter = 2,
    this.hyphenateLimitLines,
    this.media = const CssMediaEnvironment(),
  });

  /// The root font size in units of 16 px: `1.4` is 22.4 px.
  final double fontScale;

  /// The family for body text, as the host registered it; null keeps
  /// the book's fonts. `system` asks for the platform's UI font.
  final String? fontFamily;

  /// The weight of body text, 100–900 (bold stays bold).
  final int fontWeight;

  /// Extra space between letters, in px.
  final double letterSpacing;

  /// Line height of body text and headings, as a factor of font size.
  final double lineHeight;

  /// Space between paragraphs in em, split above and below.
  final double paragraphSpacing;

  /// First-line indent of body text, in em.
  final double textIndent;

  /// `0xAARRGGBB`.
  final int textColor;
  final int backgroundColor;

  /// Justify body text; otherwise it starts at the line start.
  final bool justify;

  /// Body text takes [fontFamily] and [fontWeight].
  final bool overrideFont;

  /// Text takes [textColor]; text backgrounds and borders lose their
  /// colours. Images keep theirs.
  final bool overrideColor;

  /// Body text takes [lineHeight], [textIndent], [paragraphSpacing] and
  /// the alignment.
  final bool useBookLayout;

  /// Line heights are whole pixels, cut down, as WebKit computes them
  /// (`line-height: 1.6` at 16px is 25px there): the iOS WebView reader's
  /// pages. Without it they are what the text engine makes of the exact
  /// value, which is Chromium's within a rounding.
  final bool wholePixelLineHeights;

  /// Lines are never shorter than their glyphs: a line box holds the
  /// ascent and descent of its fonts (each in whole pixels) even when
  /// `line-height` asks for less, as WebKit lays out the WebView reader's
  /// pages under foliate-js's `-webkit-line-box-contain: block glyphs
  /// replaced`. Chromium ignores that property.
  final bool glyphLineBoxes;

  /// With [useBookLayout], body text is hyphenated (foliate-js's
  /// `hyphens: var(--readflex-hyphens)` on prose: `auto`, else `manual`);
  /// without it, text is hyphenated where the book asks.
  final bool hyphenate;

  /// Hyphenation limits with [useBookLayout], matching the former reader's
  /// `-webkit-hyphenate-limit-before`, `-after` and `-lines` settings.
  /// Pagecraft applies them to all hyphenated text ([hyphenation]).
  final int hyphenateLimitBefore;
  final int hyphenateLimitAfter;
  final int? hyphenateLimitLines;

  /// How `hyphens: auto` text is hyphenated: the limits above with
  /// [useBookLayout], the engine's defaults without.
  TextHyphenation get hyphenation => useBookLayout
      ? TextHyphenation(
          minBefore: hyphenateLimitBefore,
          minAfter: hyphenateLimitAfter,
          maxLines: hyphenateLimitLines,
        )
      : const TextHyphenation();

  /// The host's CSS over the book and these settings, as foliate-js's
  /// `customCSS`: after [foliateStyleSheet], so its rules win ties with
  /// foliate-js's. Uses the same supported CSS subset as the book's sheets,
  /// including custom properties, `var()` and length math such as `calc()`.
  final String readerStyleSheet;

  /// The window the book's media queries and viewport units see.
  final CssMediaEnvironment media;

  /// The size `medium` and `1rem` mean, in px.
  double get rootFontSize => 16 * fontScale;

  BookStyle copyWith({
    double? fontScale,
    String? fontFamily,
    bool clearFontFamily = false,
    int? fontWeight,
    double? letterSpacing,
    double? lineHeight,
    double? paragraphSpacing,
    double? textIndent,
    int? textColor,
    int? backgroundColor,
    bool? justify,
    bool? overrideFont,
    bool? overrideColor,
    bool? useBookLayout,
    String? readerStyleSheet,
    bool? wholePixelLineHeights,
    bool? glyphLineBoxes,
    bool? hyphenate,
    int? hyphenateLimitBefore,
    int? hyphenateLimitAfter,
    int? hyphenateLimitLines,
    CssMediaEnvironment? media,
  }) => BookStyle(
    fontScale: fontScale ?? this.fontScale,
    fontFamily: clearFontFamily ? null : fontFamily ?? this.fontFamily,
    fontWeight: fontWeight ?? this.fontWeight,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    lineHeight: lineHeight ?? this.lineHeight,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    textIndent: textIndent ?? this.textIndent,
    textColor: textColor ?? this.textColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    justify: justify ?? this.justify,
    overrideFont: overrideFont ?? this.overrideFont,
    overrideColor: overrideColor ?? this.overrideColor,
    useBookLayout: useBookLayout ?? this.useBookLayout,
    readerStyleSheet: readerStyleSheet ?? this.readerStyleSheet,
    wholePixelLineHeights: wholePixelLineHeights ?? this.wholePixelLineHeights,
    glyphLineBoxes: glyphLineBoxes ?? this.glyphLineBoxes,
    hyphenate: hyphenate ?? this.hyphenate,
    hyphenateLimitBefore: hyphenateLimitBefore ?? this.hyphenateLimitBefore,
    hyphenateLimitAfter: hyphenateLimitAfter ?? this.hyphenateLimitAfter,
    hyphenateLimitLines: hyphenateLimitLines ?? this.hyphenateLimitLines,
    media: media ?? this.media,
  );

  /// Whether a change from [other] needs a new cascade: these settings
  /// reach the reader's style sheets, the root font size or the media
  /// queries. The rest only
  /// changes how the boxes are laid out.
  bool restylesFrom(BookStyle other) =>
      other.fontScale != fontScale ||
      other.fontFamily != fontFamily ||
      other.overrideFont != overrideFont ||
      (overrideFont && other.fontWeight != fontWeight) ||
      other.letterSpacing != letterSpacing ||
      other.lineHeight != lineHeight ||
      other.useBookLayout != useBookLayout ||
      other.overrideColor != overrideColor ||
      (overrideColor && other.textColor != textColor) ||
      other.readerStyleSheet != readerStyleSheet ||
      other.media != media ||
      (useBookLayout && other.hyphenate != hyphenate) ||
      other.hyphenateLimitBefore != hyphenateLimitBefore ||
      other.hyphenateLimitAfter != hyphenateLimitAfter;

  @override
  bool operator ==(Object other) =>
      other is BookStyle &&
      other.fontScale == fontScale &&
      other.fontFamily == fontFamily &&
      other.fontWeight == fontWeight &&
      other.letterSpacing == letterSpacing &&
      other.lineHeight == lineHeight &&
      other.paragraphSpacing == paragraphSpacing &&
      other.textIndent == textIndent &&
      other.textColor == textColor &&
      other.backgroundColor == backgroundColor &&
      other.justify == justify &&
      other.overrideFont == overrideFont &&
      other.overrideColor == overrideColor &&
      other.useBookLayout == useBookLayout &&
      other.readerStyleSheet == readerStyleSheet &&
      other.wholePixelLineHeights == wholePixelLineHeights &&
      other.glyphLineBoxes == glyphLineBoxes &&
      other.hyphenate == hyphenate &&
      other.hyphenateLimitBefore == hyphenateLimitBefore &&
      other.hyphenateLimitAfter == hyphenateLimitAfter &&
      other.hyphenateLimitLines == hyphenateLimitLines &&
      other.media == media;

  @override
  int get hashCode => Object.hash(
    fontScale,
    fontFamily,
    fontWeight,
    letterSpacing,
    lineHeight,
    paragraphSpacing,
    textIndent,
    textColor,
    backgroundColor,
    justify,
    overrideFont,
    overrideColor,
    useBookLayout,
    readerStyleSheet,
    wholePixelLineHeights,
    glyphLineBoxes,
    Object.hash(
      hyphenate,
      hyphenateLimitBefore,
      hyphenateLimitAfter,
      hyphenateLimitLines,
    ),
    media,
  );
}

/// How text with `hyphens: auto` is hyphenated: words of [minWord]
/// letters or more, with at least [minBefore] letters before a break and
/// [minAfter] after it (or what the language asks, if more), and at most
/// [maxLines] lines in a row ending with a hyphen (null: no limit).
/// Defaults are Chromium's (`hyphenate-limit-chars: auto`), which WebKit's
/// defaults also give for words of five letters.
@immutable
class TextHyphenation {
  const TextHyphenation({
    this.minWord = 5,
    this.minBefore = 2,
    this.minAfter = 2,
    this.maxLines,
  });

  final int minWord;
  final int minBefore;
  final int minAfter;
  final int? maxLines;

  @override
  bool operator ==(Object other) =>
      other is TextHyphenation &&
      other.minWord == minWord &&
      other.minBefore == minBefore &&
      other.minAfter == minAfter &&
      other.maxLines == maxLines;

  @override
  int get hashCode => Object.hash(minWord, minBefore, minAfter, maxLines);
}

/// The sheets foliate-js put after a book's own: its `getCSS`
/// ([foliateStyleSheet]) and the host's `customCSS`
/// ([BookStyle.readerStyleSheet]), in one `<style>` at the end of the
/// head. Author origin, last: they cascade against the book by
/// importance, specificity and order, as they did in the WebView.
List<CssSheetSource> readerSheetSources(BookStyle style) => [
  CssSheetSource(
    CssStyleSheet.parse(foliateStyleSheet(style)),
    CssOrigin.author,
  ),
  if (style.readerStyleSheet.isNotEmpty)
    CssSheetSource(
      CssStyleSheet.parse(style.readerStyleSheet),
      CssOrigin.author,
    ),
];

/// foliate-js's injected CSS for [style] (`getCSS` in `book.js`): the
/// parts plain CSS carries.
String foliateStyleSheet(BookStyle style) {
  final headings = style.useBookLayout
      ? 'h1, h2, h3, h4, h5, h6 { line-height: ${style.lineHeight} !important; }'
      : '';
  // Not important: a book's more specific rule keeps its hyphenation.
  final hyphens = style.useBookLayout
      ? '''
p, li, blockquote, dd, div:not(:has(*:not(b, a, em, i, strong, u, span))), font {
  hyphens: ${style.hyphenate ? 'auto' : 'manual'};
}'''
      : '';
  // foliate-js keeps the override's specificity low so the host's colours
  // (links, code, quotes) win; what still does not read is repaired by
  // the layout's contrast guard. Pictures and formulas keep their own.
  final colors = style.overrideColor
      ? '''
html { color: ${_cssColor(style.textColor)} !important; }
body *:not(:where(svg, svg *, math, math *, img, picture, picture *, canvas,
    video, audio, iframe, object, embed)) {
  color: inherit !important;
  background-color: transparent !important;
  border-color: currentColor !important;
}'''
      : '';
  // foliate-js's typography reset: elements a publisher styles get the
  // reader's family; code, pre, kbd and samp are not among them and keep
  // theirs.
  final family = style.fontFamily;
  final fonts = style.overrideFont && family != null && family != 'book'
      ? '''
html, body, p, li, blockquote, dd, dt, dl, div, span, font, section, article,
h1, h2, h3, h4, h5, h6, td, th, caption, ol, ul {
  font-family: ${family == 'system' ? 'system-ui' : _cssString(family)} !important;
}'''
      : '';
  // foliate-js's body text weight, on the elements its rule names: a
  // `<font>` inside `<b>` (MOBI 6 titles) is body text again. Its
  // `div:not(:has(…))` part is the layout's (`ParagraphBox.isProse`).
  final weight = style.overrideFont
      ? 'p, li, blockquote, dd, font { font-weight: ${style.fontWeight} !important; }'
      : '';
  return '''
html { letter-spacing: ${style.letterSpacing}px; }
$colors
$fonts
$weight
/* The page has its own margins and the reader's background; the body
   adds none. */
html, body { background-image: none !important; background-color: transparent !important; }
body { font-size: 1em !important; margin: 0 !important; padding: 0 !important; }
/* Publisher wrappers with horizontal padding would narrow some books. */
body > div, body > section, body > article, body > main {
  padding-left: 0 !important; padding-right: 0 !important;
  margin-left: 0 !important; margin-right: 0 !important;
}
li > p, ol > p, ul > p { text-indent: 0 !important; }
pre { white-space: pre-wrap !important; margin-left: 0 !important; margin-right: 0 !important; }
aside[epub\\:type~="endnote"], aside[epub\\:type~="footnote"],
aside[epub\\:type~="note"], aside[epub\\:type~="rearnote"] { display: none; }
$headings
$hyphens
''';
}

/// `0xAARRGGBB` as `#rrggbbaa`.
String _cssColor(int argb) {
  String hex(int v) => v.toRadixString(16).padLeft(2, '0');
  return '#${hex(argb >> 16 & 0xFF)}${hex(argb >> 8 & 0xFF)}'
      '${hex(argb & 0xFF)}${hex(argb >> 24 & 0xFF)}';
}

/// [value] as a CSS string.
String _cssString(String value) =>
    '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
