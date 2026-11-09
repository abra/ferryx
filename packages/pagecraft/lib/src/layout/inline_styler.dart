import 'dart:collection';

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../css/css_values.dart';
import '../fonts/font_ink.dart';
import 'book_fonts.dart';
import 'book_style.dart';
import 'box_tree.dart';
import 'contrast_guard.dart';

/// Turns computed styles into Flutter text styles under one [BookStyle]
/// and [BookFonts], applying the reader's settings to prose the way
/// foliate-js's injected CSS does:
///
/// * family: from the cascade, where the reader's is a rule of
///   `foliateStyleSheet` on the elements foliate-js's typography reset
///   lists;
/// * weight and line height: prose runs that inherit their block's
///   value take the reader's (bold, and a span with its own line height,
///   keep theirs, as an inherited `!important` value loses to a declared
///   one); line heights in whole pixels as WebKit's when the style asks;
/// * alignment: prose takes justify or start, except text the book
///   centres or sets to the right;
/// * indent: prose takes the reader's indent, except centred text, list
///   items and paragraphs holding only images;
/// * optical size: a font with an `opsz` axis is drawn at the design for
///   its size (`font-optical-sizing: auto`), as browsers draw it;
/// * colours come from the cascade, where the reader's override is a
///   rule of `foliateStyleSheet`; text that does not
///   read on its background takes the reader's colour (the contrast
///   guard).
///
/// Styles are interned by the cascade, so results are cached by
/// identity: a chapter needs a few dozen text styles, not one per run.
class InlineStyler {
  InlineStyler({required this.bookStyle, required this.fonts});

  final BookStyle bookStyle;
  final BookFonts fonts;

  final _textStyles = HashMap<ComputedStyle, TextStyle>.identity();

  /// Prose styles depend on the block too: by block, then by run style.
  final _proseTextStyles =
      HashMap<ComputedStyle, HashMap<ComputedStyle, TextStyle>>.identity();

  /// Styles whose line height [BookStyle.glyphLineBoxes] raised, with
  /// what it was raised from: a run's own text may need less.
  final _raised = HashMap<TextStyle, _GlyphContainment>.identity();
  final _byInk = HashMap<TextStyle, HashMap<double, TextStyle>>.identity();

  final _hyphenWidths = <TextScaler, HashMap<TextStyle, double>>{};

  /// The width of a hyphen (`-`) in [style]: what a hyphenated line ends
  /// with.
  double hyphenWidth(TextStyle style, TextScaler scaler) =>
      (_hyphenWidths[scaler] ??= HashMap.identity())[style] ??= () {
        final painter = TextPainter(
          text: TextSpan(text: '-', style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }();

  /// Whether a run with [style] takes the line height of its own glyphs
  /// ([BookStyle.glyphLineBoxes] raised the font's): its lines may differ.
  bool holdsGlyphs(
    ComputedStyle style,
    ComputedStyle block, {
    required bool prose,
  }) => _raised.containsKey(textStyle(style, block, prose: prose));

  /// The text style of a run with [style] in a paragraph whose block has
  /// [block]'s style; with the run's [text] `[start, end)`, its line
  /// height holds the ink of those glyphs, not the font's tallest.
  TextStyle textStyle(
    ComputedStyle style,
    ComputedStyle block, {
    required bool prose,
    String? text,
    int start = 0,
    int? end,
  }) {
    final TextStyle base;
    if (!prose) {
      base = _textStyles[style] ??= _convert(style, prose: false, block: block);
    } else {
      final byStyle = _proseTextStyles[block] ??=
          HashMap<ComputedStyle, TextStyle>.identity();
      base = byStyle[style] ??= _convert(style, prose: true, block: block);
    }
    final raised = _raised[base];
    if (raised == null || text == null) return base;
    final height = raised.heightOf(text, start, end ?? text.length);
    if (height == base.height) return base;
    return (_byInk[base] ??= HashMap())[height] ??= base.copyWith(
      height: height,
    );
  }

  TextStyle _convert(
    ComputedStyle s, {
    required bool prose,
    required ComputedStyle block,
  }) {
    final book = bookStyle;
    final layout = prose && book.useBookLayout;
    final weight =
        prose && book.overrideFont && s.fontWeight == block.fontWeight
        ? book.fontWeight
        : s.fontWeight;
    final family = _family(s.fontFamily);
    final factor = _snap(
      layout && s.lineHeight == block.lineHeight
          ? book.lineHeight
          : _lineHeightFactor(s),
      s.fontSize,
    );
    final containment = _containment(factor, s, family);
    final lineHeight = containment?.fontWideHeight ?? factor;
    // The reader's colours reach the computed style through the user
    // sheets (`foliateStyleSheet`), as foliate-js's CSS does; what still
    // does not read on its background is repaired as the WebView's
    // contrast guard repairs it.
    final color = s.visible ? _readable(s, block) : 0x00000000;
    // Backgrounds of inline elements are their decorations
    // (`ParagraphLayout.paintDecorations`), under highlights and text.
    final style = TextStyle(
      inherit: false,
      color: Color(color),
      fontSize: s.fontSize,
      fontWeight: _fontWeight(weight),
      fontVariations: [
        FontVariation.weight(weight.toDouble()),
        // As browsers draw a font with an optical size axis.
        if (s.opticalSizing && s.fontSize > 0)
          FontVariation.opticalSize(s.fontSize),
      ],
      fontStyle: s.isItalic ? FontStyle.italic : FontStyle.normal,
      fontFamily: family.family,
      fontFamilyFallback: family.fallback,
      letterSpacing: s.letterSpacing == 0 ? null : s.letterSpacing,
      wordSpacing: s.wordSpacing == 0 ? null : s.wordSpacing,
      height: lineHeight,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: _decoration(s),
      decorationColor: Color(color),
      fontFeatures: s.smallCaps ? const [FontFeature.enable('smcp')] : null,
    );
    if (containment != null && lineHeight != factor) {
      _raised[style] = containment;
    }
    return style;
  }

  /// The strut of a paragraph: the line box every line starts from, as
  /// the block's own font and line height give CSS its strut.
  StrutStyle strut(ComputedStyle block, {required bool prose}) {
    // `font-size: 0` hides the white space between inline blocks; such a
    // block sets no line box of its own.
    if (block.fontSize <= 0) return StrutStyle.disabled;
    final family = _family(block.fontFamily);
    return StrutStyle(
      fontFamily: family.family,
      fontFamilyFallback: family.fallback,
      fontSize: block.fontSize,
      height: _snap(
        prose && bookStyle.useBookLayout
            ? bookStyle.lineHeight
            : _lineHeightFactor(block),
        block.fontSize,
      ),
      leadingDistribution: TextLeadingDistribution.even,
      fontWeight: _fontWeight(block.fontWeight),
      fontStyle: block.isItalic ? FontStyle.italic : FontStyle.normal,
    );
  }

  /// The alignment of a paragraph in [block].
  TextAlign textAlign(ComputedStyle block, {required bool prose}) {
    final own = block.textAlign;
    if (prose && bookStyle.useBookLayout) {
      switch (own) {
        case CssTextAlign.center:
          return TextAlign.center;
        case CssTextAlign.right:
          return TextAlign.right;
        case CssTextAlign.end:
          return TextAlign.end;
        case CssTextAlign.start || CssTextAlign.left || CssTextAlign.justify:
          return bookStyle.justify ? TextAlign.justify : TextAlign.start;
      }
    }
    return switch (own) {
      CssTextAlign.start => TextAlign.start,
      CssTextAlign.end => TextAlign.end,
      CssTextAlign.left => TextAlign.left,
      CssTextAlign.right => TextAlign.right,
      CssTextAlign.center => TextAlign.center,
      CssTextAlign.justify => TextAlign.justify,
    };
  }

  /// The first-line indent of [paragraph] laid out [width] wide, in px.
  /// Negative indents (hanging) are not drawn in v1.
  double firstLineIndent(
    ParagraphBox paragraph,
    double width, {
    required bool listItem,
  }) {
    if (!paragraph.indentFirstLine || _onlyAtomics(paragraph)) return 0;
    final block = paragraph.style;
    final align = textAlign(block, prose: paragraph.isProse);
    if (align == TextAlign.center) return 0;
    double indent;
    if (paragraph.isProse && bookStyle.useBookLayout) {
      if (listItem) return 0;
      indent = bookStyle.textIndent * block.fontSize;
    } else {
      final length = block.textIndent;
      indent = px(length, width);
    }
    return indent > 0 ? indent.clamp(0, width / 2) : 0;
  }

  /// Whether the text is nothing but images and the space between them,
  /// which foliate-js keeps unindented.
  static bool _onlyAtomics(ParagraphBox paragraph) {
    if (paragraph.atomics.isEmpty) return false;
    final text = paragraph.text;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c != 0xFFFC && c != 0x20 && c != 0x0A && c != 0xA0) return false;
    }
    return paragraph.atomics.every((a) => a is InlineImage);
  }

  /// The reader's family reaches [families] through `foliateStyleSheet`,
  /// as foliate-js's typography reset does.
  ({String? family, List<String> fallback}) _family(List<String> families) =>
      fonts.resolve(families);

  /// [s]'s colour, or the guard's repair under the reader's colours. The
  /// background is the page's under the block's and the run's own: with
  /// the override, only the reader's code panels have one.
  int _readable(ComputedStyle s, ComputedStyle block) {
    final book = bookStyle;
    if (!book.overrideColor) return s.color;
    var background = composite(block.backgroundColor, book.backgroundColor);
    if (!identical(s, block) && s.display == CssDisplay.inline) {
      background = composite(s.backgroundColor, background);
    }
    return readableTextColor(
      s.color,
      background: background | 0xFF000000,
      textColor: book.textColor,
    );
  }

  /// [factor] of [fontSize] as a whole number of pixels, cut down, under
  /// [BookStyle.wholePixelLineHeights]. Flutter's paragraphs round a line's
  /// height to the nearest pixel anyway: a whole-pixel height stays.
  double? _snap(double? factor, double fontSize) {
    if (factor == null || !bookStyle.wholePixelLineHeights || fontSize <= 0) {
      return factor;
    }
    return (fontSize * factor + 1e-6).floorToDouble() / fontSize;
  }

  /// How WebKit raises a line of [s] under [BookStyle.glyphLineBoxes]:
  /// the line box holds both CSS's box (the line height [factor] around
  /// the font's ascent and descent, half the leading on each side, which
  /// is negative when the line height is less than the font's) and the
  /// ink of the glyphs in it ([BookFonts.ink]). Null without the setting,
  /// a line height or the font's ink; `normal` holds the ink already.
  _GlyphContainment? _containment(
    double? factor,
    ComputedStyle s,
    ({String? family, List<String> fallback}) family,
  ) {
    if (factor == null || !bookStyle.glyphLineBoxes || s.fontSize <= 0) {
      return null;
    }
    final ink = family.family == null ? null : fonts.ink[family.family];
    if (ink == null) return null;
    final key = '${family.family}|${s.fontWeight}|${s.isItalic}';
    final (ascent, descent) = _glyphMetrics[key] ??= _measureGlyphs(
      family,
      s,
    );
    return _GlyphContainment(
      ink,
      factor: factor,
      top: (ascent - descent + factor) / 2,
      bottom: (descent - ascent + factor) / 2,
    );
  }

  /// A font's ascent and descent per em, by family, weight and style.
  final _glyphMetrics = HashMap<String, (double, double)>();

  static (double, double) _measureGlyphs(
    ({String? family, List<String> fallback}) family,
    ComputedStyle s,
  ) {
    const size = 100.0;
    final painter = TextPainter(
      text: TextSpan(
        text: 'x',
        style: TextStyle(
          fontFamily: family.family,
          fontFamilyFallback: family.fallback,
          fontSize: size,
          fontWeight: _fontWeight(s.fontWeight),
          fontStyle: s.isItalic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final line = painter.computeLineMetrics().first;
    painter.dispose();
    return (line.ascent / size, line.descent / size);
  }

  static double? _lineHeightFactor(ComputedStyle s) {
    final lineHeight = s.lineHeight;
    if (lineHeight.isNormal) return null;
    final px = lineHeight.px;
    if (px != null) return s.fontSize == 0 ? null : px / s.fontSize;
    return lineHeight.factor;
  }

  static FontWeight _fontWeight(int weight) =>
      FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)];

  static TextDecoration? _decoration(ComputedStyle s) {
    if (!s.underline && !s.overline && !s.lineThrough) return null;
    return TextDecoration.combine([
      if (s.underline) TextDecoration.underline,
      if (s.overline) TextDecoration.overline,
      if (s.lineThrough) TextDecoration.lineThrough,
    ]);
  }

  /// The text direction of [block].
  static TextDirection direction(ComputedStyle block) =>
      block.direction == CssDirection.rtl
      ? TextDirection.rtl
      : TextDirection.ltr;

  /// [length] in px against [percentOf].
  static double px(CssLength length, double percentOf) => switch (length) {
    CssLength(:final calc?) => calc.evaluate(null, percentOf),
    CssLength(isPercent: true) => length.value * percentOf / 100,
    _ => length.value,
  };
}

/// A line height raised to hold the ink of a font's glyphs: the CSS box
/// reaches [top] above the baseline and [bottom] below it, per em.
class _GlyphContainment {
  _GlyphContainment(
    this.ink, {
    required this.factor,
    required this.top,
    required this.bottom,
  });

  final FontInk ink;
  final double factor;
  final double top;
  final double bottom;

  /// The line height that holds the font's tallest and deepest glyphs.
  double get fontWideHeight => _holding(ink.ascent, ink.descent);

  /// The line height that holds the ink of text `[start, end)` of [text].
  double heightOf(String text, int start, int end) {
    final (:ascent, :descent) = ink.extentOf(text, start, end);
    return _holding(ascent, descent);
  }

  double _holding(double ascent, double descent) {
    final contained =
        (ascent > top ? ascent : top) + (descent > bottom ? descent : bottom);
    return contained > factor ? contained : factor;
  }
}
