import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/layout/line_exclusions.dart';
import 'package:pagecraft/all_formats.dart';

/// The test font draws every glyph as a square one font size wide, with
/// ascent 0.75 and descent 0.25 of it: layouts are exact numbers.
const ten = BookStyle(fontScale: 10 / 16, lineHeight: 1.8);

class Section {
  Section(this.doc, this.boxes, this.styler);

  final ContentDocument doc;
  final SectionBoxes boxes;
  final InlineStyler styler;

  List<ParagraphBox> get paragraphs => boxes.paragraphs.toList();

  ParagraphLayout layout(
    ParagraphBox box, {
    double width = 100,
    Map<String, Size> images = const {},
    double maxImageHeight = 1000,
    bool listItem = false,
    List<FloatArea> floats = const [],
  }) {
    final layout = ParagraphLayout.layout(
      box,
      width: width,
      listItem: listItem,
      exclusions: floats.isEmpty ? null : LineExclusions(floats),
      environment: TextLayoutEnvironment(
        styler: styler,
        imageSize: (src) => images[src],
        maxImageHeight: maxImageHeight,
      ),
    );
    addTearDown(layout.dispose);
    return layout;
  }
}

Section section(
  String body, {
  String css = '',
  BookStyle book = ten,
  BookFonts fonts = const BookFonts(),
}) {
  final doc = ContentDocument.parseXml(
    '<html xmlns="http://www.w3.org/1999/xhtml"><body>$body</body></html>',
  );
  final styles =
      StyleResolver([
        CssSheetSource(
          CssStyleSheet.parse(cssUserAgentStyleSheet),
          CssOrigin.userAgent,
        ),
        CssSheetSource(CssStyleSheet.parse(css), CssOrigin.author),
        ...readerSheetSources(book),
      ]).resolve(
        doc,
        options: StyleResolverOptions(rootFontSize: book.rootFontSize),
      );
  return Section(
    doc,
    buildSectionBoxes(doc, styles, hyphenation: book.hyphenation),
    InlineStyler(bookStyle: book, fonts: fonts),
  );
}

void main() {
  group('lines', () {
    test('prose wraps at the width with the reader\'s line height', () {
      final s = section('<p>aaaa bbbb cccc</p>');
      final layout = s.layout(s.paragraphs.single);
      expect(layout.lines, hasLength(2));
      expect(layout.height, 36);
      expect(layout.lineTop(0), 0);
      expect(layout.lineTop(1), 18);
      expect(layout.lineTop(2), 36);
      expect(layout.lineAtY(20), 1);
      expect(layout.lineAt(11), 1);
      expect(
        layout.firstBaseline,
        closeTo(4 + 7.5, 1e-9),
        reason: 'half-leading 4',
      );
    });

    test('line heights in whole pixels, cut down, as WebKit makes them', () {
      // 16px × 1.6 is 25.6px: Flutter makes it 26, WebKit 25.
      const book = BookStyle(fontScale: 1, lineHeight: 1.6);
      String body(int words) =>
          '<p>${List.filled(words, 'word').join(' ')}</p>';
      final exact = section(body(40), book: book);
      double pitch(ParagraphLayout l) => l.lineTop(2) - l.lineTop(1);
      final exactLayout = exact.layout(exact.paragraphs.single);
      expect(pitch(exactLayout), 26, reason: 'Flutter rounds a line');
      final webKit = section(
        body(40),
        book: book.copyWith(wholePixelLineHeights: true),
      );
      final layout = webKit.layout(webKit.paragraphs.single);
      expect(pitch(layout), 25);
      expect(layout.lineTop(3) - layout.lineTop(1), 50);
      // Outside prose too: the book's own line height.
      final heading = section(
        '<div><dfn>${List.filled(20, 'word').join(' ')}</dfn></div>',
        css: 'div { font-size: 20px; line-height: 1.33 }',
        book: book.copyWith(wholePixelLineHeights: true),
      );
      final h1 = heading.layout(heading.paragraphs.single);
      expect(pitch(h1), 26, reason: '26.6px cut to 26');
    });

    test('glyph line boxes: lines hold their ink, as WebKit\'s do', () {
      // The test font's ascent and descent are 0.75 and 0.25 em. Lines of
      // 0.8 em put CSS's box from 0.65 em above the baseline to 0.15 below.
      const css = 'h1 { font-size: 20px; line-height: 0.8 }';
      // The book's heading line height, not the reader's.
      final book = ten.copyWith(useBookLayout: false, glyphLineBoxes: true);
      double secondLine(BookFonts fonts, {BookStyle? style}) {
        final s = section(
          '<h1>a b</h1>',
          css: css,
          book: style ?? book,
          fonts: fonts,
        );
        return s.layout(s.paragraphs.single, width: 20).lineTop(1);
      }

      BookFonts inked(double ascent, double descent) => BookFonts(
        serif: 'Inked',
        ink: {'Inked': FontInk(ascent: ascent, descent: descent)},
      );
      // Ink to the font's ascent and descent: a whole em.
      expect(secondLine(inked(0.75, 0.25)), closeTo(20, 0.01));
      // Only the descent sticks out: 0.65 + 0.2 em.
      expect(secondLine(inked(0.6, 0.2)), closeTo(17, 0.01));
      // Ink inside CSS's box changes nothing.
      expect(secondLine(inked(0.5, 0.1)), closeTo(16, 0.01));
      // Unknown ink, or not WebKit's lines: the line height as asked.
      expect(secondLine(const BookFonts(serif: 'Unknown')), closeTo(16, 0.01));
      expect(
        secondLine(
          inked(0.75, 0.25),
          style: book.copyWith(glyphLineBoxes: false),
        ),
        closeTo(16, 0.01),
      );
    });

    test('glyph line boxes hold the glyphs a run has, not the font\'s '
        'tallest', () {
      // CSS's box: 0.65 em above the baseline, 0.15 below. NotoSans's
      // glyphs: x 0.536/0, H 0.714/0, g 0.546/-0.24, its tallest 0.765.
      final ink = fontInkOf(
        File('test/fixtures/fonts/NotoSans-Ascii.ttf').readAsBytesSync(),
      )!;
      final fonts = BookFonts(serif: 'Inked', ink: {'Inked': ink});
      final book = ten.copyWith(useBookLayout: false, glyphLineBoxes: true);
      // Flutter rounds a line's height to a whole pixel.
      double firstLine(String text) {
        final s = section(
          '<h1>$text</h1>',
          css: 'h1 { font-size: 100px; line-height: 0.8 }',
          book: book,
          fonts: fonts,
        );
        return s.layout(s.paragraphs.single, width: 400).lines.single.height;
      }

      expect(firstLine('x x'), 80, reason: 'inside the box');
      expect(firstLine('H H'), closeTo(100 * (0.714 + 0.15), 0.5));
      expect(firstLine('g g'), closeTo(100 * (0.65 + 0.24), 0.5));
      expect(
        firstLine('x <b>g</b>'),
        closeTo(100 * (0.65 + 0.24), 0.5),
        reason: 'each run holds its own glyphs',
      );
      // One run over two lines: each line holds its own glyphs.
      final s = section(
        '<h1>xg x</h1>',
        css: 'h1 { font-size: 100px; line-height: 0.8 }',
        book: book,
        fonts: fonts,
      );
      final lines = s.layout(s.paragraphs.single, width: 300).lines;
      expect(lines, hasLength(2));
      expect(lines[0].height, closeTo(100 * (0.65 + 0.24), 0.5));
      expect(lines[1].height, 80);
    });

    test('text outside prose keeps the book\'s line height', () {
      final s = section(
        '<h2>aaaa bbbb cccc</h2>',
        css: 'h2 { font-size: 10px; margin: 0 }',
      );
      final layout = s.layout(s.paragraphs.single);
      expect(
        layout.lineTop(1),
        18,
        reason: 'headings take the reader\'s line height through CSS',
      );
      final plain = section('<section>aaaa bbbb cccc</section>');
      final normal = plain.layout(plain.paragraphs.single);
      expect(normal.lineTop(1), 10, reason: 'normal: the font\'s own');
      final own = section(
        '<p>aaaa bbbb cccc</p>',
        book: ten.copyWith(useBookLayout: false),
        css: 'p { line-height: 2 }',
      );
      expect(own.layout(own.paragraphs.single).lineTop(1), 20);
    });

    test('a block with font-size 0 lays its children out without a strut', () {
      final s = section(
        '<div style="font-size: 0"><span style="font-size: 10px">ab</span> </div>',
      );
      final layout = s.layout(s.paragraphs.single);
      expect(
        layout.height,
        18,
        reason: 'a text-only div is prose: 10 px × 1.8',
      );
      expect(
        s.styler.strut(s.paragraphs.single.style, prose: false),
        StrutStyle.disabled,
      );
    });

    test('line tops follow the strut and tall runs, with no gaps', () {
      final s = section(
        '<p>abc <span style="font-size: 30px">BIG</span> def ghi jkl</p>',
      );
      final layout = s.layout(s.paragraphs.single, width: 150);
      for (var i = 0; i < layout.lines.length; i++) {
        expect(layout.lineTop(i + 1), greaterThan(layout.lineTop(i)));
        expect(
          layout.lines[i].baseline,
          inExclusiveRange(layout.lineTop(i), layout.lineTop(i + 1)),
        );
      }
      expect(layout.lineTop(layout.lines.length), layout.height);
      final big = layout.boxesFor(4, 7);
      final line = layout.lineAt(4);
      for (final b in big) {
        expect(b.top, greaterThanOrEqualTo(layout.lineTop(line) - 0.5));
        expect(b.bottom, lessThanOrEqualTo(layout.lineTop(line + 1) + 0.5));
      }
    });
  });

  group('indent and alignment', () {
    test('prose takes the reader\'s indent on its first line only', () {
      final s = section(
        '<p>aaaa bbbb cccc</p>',
        book: ten.copyWith(textIndent: 2),
      );
      final layout = s.layout(s.paragraphs.single);
      expect(layout.boxesFor(0, 1).single.left, 20);
      // The caret goes to the nearer edge of the glyph at 20–30.
      expect(layout.positionAt(const Offset(22, 5)).offset, 0);
      expect(layout.positionAt(const Offset(28, 5)).offset, 1);
      expect(
        layout.positionAt(const Offset(5, 5)).offset,
        0,
        reason: 'in the indent',
      );
      // 20 + "aaaa bbbb" would be 110 wide: "bbbb" opens line two, at
      // the edge.
      expect(layout.lines, hasLength(2));
      expect(layout.lineAt(5), 1);
      expect(layout.boxesFor(5, 6).single.left, 0);
      expect(layout.wordAt(1), const TextRange(start: 0, end: 4));
    });

    test(
      'no indent for centred text, list items and image-only paragraphs',
      () {
        final book = ten.copyWith(textIndent: 2);
        final centred = section(
          '<p style="text-align: center">a</p>',
          book: book,
        );
        expect(centred.layout(centred.paragraphs.single).atomics, isEmpty);
        expect(
          centred.styler.firstLineIndent(
            centred.paragraphs.single,
            100,
            listItem: false,
          ),
          0,
        );
        final li = section('<ul><li>a</li></ul>', book: book);
        expect(
          li.styler.firstLineIndent(li.paragraphs.single, 100, listItem: true),
          0,
        );
        final image = section('<p><img src="i.png"/></p>', book: book);
        expect(
          image.styler.firstLineIndent(
            image.paragraphs.single,
            100,
            listItem: false,
          ),
          0,
        );
        final p = section('<p>a</p>', book: book);
        expect(
          p.styler.firstLineIndent(p.paragraphs.single, 100, listItem: false),
          20,
        );
      },
    );

    test('the book\'s own indent applies outside the reader\'s layout', () {
      final s = section(
        '<p>a</p><section>b</section>',
        css: 'p { text-indent: 30px } section { text-indent: 10% }',
        book: ten.copyWith(useBookLayout: false),
      );
      final [p, sec] = s.paragraphs;
      expect(s.styler.firstLineIndent(p, 200, listItem: false), 30);
      expect(s.styler.firstLineIndent(sec, 200, listItem: false), 20);
      expect(
        s.styler.firstLineIndent(p, 40, listItem: false),
        20,
        reason: 'at most half the width',
      );
    });

    test(
      'centred, right-aligned and RTL lines sit against the block width',
      () {
        final s = section(
          '<p style="text-align: center">ab</p><p align="right">ab</p>'
          '<p dir="rtl">ab</p><p>ab</p>',
        );
        final lefts = [
          for (final p in s.paragraphs)
            s.layout(p, width: 100).boxesFor(0, 1).single.left,
        ];
        // In the RTL paragraph the Latin run "ab" still reads left to
        // right, pushed against the right edge: "a" starts at 80.
        expect(lefts, [40, 80, 80, 0]);
        final image = section(
          '<p style="text-align: center"><img src="i.png"/></p>',
        );
        final layout = image.layout(
          image.paragraphs.single,
          images: const {'i.png': Size(40, 20)},
        );
        expect(layout.atomics.single.rect.left, 30);
      },
    );

    test('prose justifies or starts; the book\'s centring and right stay', () {
      final s = section(
        '<p>a</p><p style="text-align: center">b</p><p align="right">c</p>'
        '<p style="text-align: left">d</p><h1>e</h1>',
      );
      final aligns = [
        for (final p in s.paragraphs)
          s.styler.textAlign(p.style, prose: p.isProse),
      ];
      expect(aligns, [
        TextAlign.justify,
        TextAlign.center,
        TextAlign.right,
        TextAlign.justify,
        TextAlign.start,
      ]);
      final start = section('<p>a</p>', book: ten.copyWith(justify: false));
      expect(
        start.styler.textAlign(start.paragraphs.single.style, prose: true),
        TextAlign.start,
      );
    });
  });

  group('text styles', () {
    TextStyle styleOf(Section s, int paragraph, int run) {
      final p = s.paragraphs[paragraph];
      return s.styler.textStyle(p.runs[run].style, p.style, prose: p.isProse);
    }

    test('body text takes the reader\'s weight; bold keeps its own', () {
      final s = section(
        '<p>a<b>b</b></p><h1>h</h1>',
        book: ten.copyWith(fontWeight: 300),
      );
      expect(styleOf(s, 0, 0).fontWeight, FontWeight.w300);
      expect(styleOf(s, 0, 0).fontVariations, [
        const ui.FontVariation('wght', 300),
        const ui.FontVariation('opsz', 10),
      ]);
      expect(styleOf(s, 0, 1).fontWeight, FontWeight.w700);
      expect(
        styleOf(s, 1, 0).fontWeight,
        FontWeight.w700,
        reason: 'headings are not prose',
      );
      // foliate-js's rule names `font` too: a MOBI 6 title in `<b><font>`
      // is body text again; a bold publisher class on a paragraph goes.
      final mobi = section(
        '<p><b><font color="#000">t</font></b></p><p class="x">x</p>',
        css: '.x { font-weight: bold }',
        book: ten.copyWith(fontWeight: 300),
      );
      expect(styleOf(mobi, 0, 0).fontWeight, FontWeight.w300);
      expect(styleOf(mobi, 1, 0).fontWeight, FontWeight.w300);
      final own = section(
        '<p><b><font>t</font></b></p>',
        book: ten.copyWith(fontWeight: 300, overrideFont: false),
      );
      expect(styleOf(own, 0, 0).fontWeight, FontWeight.w700);
    });

    test('the reader\'s family replaces the book\'s as foliate-js\'s reset '
        'does: code, pre, kbd and samp keep theirs', () {
      const fonts = BookFonts(
        serif: 'Serif Face',
        monospace: 'Mono Face',
        fallback: ['Symbols'],
      );
      final s = section(
        '<p>a<code>c</code><span class="code">s</span><kbd>k</kbd></p>',
        css:
            'p { font-family: "Book Font", sans-serif } '
            '.code { font-family: monospace }',
        book: ten.copyWith(fontFamily: 'Literata'),
        fonts: fonts,
      );
      expect(styleOf(s, 0, 0).fontFamily, 'Literata');
      expect(styleOf(s, 0, 0).fontFamilyFallback, ['Serif Face', 'Symbols']);
      expect(styleOf(s, 0, 1).fontFamily, 'Mono Face');
      expect(
        styleOf(s, 0, 2).fontFamily,
        'Literata',
        reason: 'a publisher\'s monospace span is a span',
      );
      expect(styleOf(s, 0, 3).fontFamily, 'Mono Face');
      final own = section(
        '<p>a</p>',
        css: 'p { font-family: "Book Font", sans-serif }',
        book: ten.copyWith(overrideFont: false, fontFamily: 'Literata'),
        fonts: fonts,
      );
      expect(styleOf(own, 0, 0).fontFamily, 'Book Font');
      expect(styleOf(own, 0, 0).fontFamilyFallback, ['Symbols']);
    });

    test('colours: the reader\'s text colour, or the book\'s own', () {
      const css = 'p { color: #102030 } mark { background-color: yellow }';
      final over = section(
        '<p>a<mark>m</mark></p>',
        css: css,
        book: ten.copyWith(textColor: 0xFF445566),
      );
      expect(styleOf(over, 0, 0).color, const Color(0xFF445566));
      expect(over.paragraphs.single.decorations, isEmpty);
      final own = section(
        '<p>a<mark>m</mark></p>',
        css: css,
        book: ten.copyWith(overrideColor: false),
      );
      expect(styleOf(own, 0, 0).color, const Color(0xFF102030));
      // Inline backgrounds are decorations, painted under highlights.
      expect(styleOf(own, 0, 1).backgroundColor, isNull);
      final mark = own.layout(own.paragraphs.single).inlineDecorations;
      expect(mark.single.background, 0xFFFFFF00);
      final hidden = section(
        '<p>a<span style="visibility: hidden">h</span></p>',
      );
      expect(styleOf(hidden, 0, 1).color, const Color(0x00000000));
    });

    test('the contrast guard repairs reader colours that do not read', () {
      // The reader's links in its accent: 3.6:1 on the light page, 6:1 on
      // the dark one.
      const reader = 'a { color: #b86a2d !important }';
      final light = section(
        '<p>a <a href="#x">link</a></p>',
        book: ten.copyWith(
          textColor: 0xFF292521,
          backgroundColor: 0xFFF7F1E6,
          readerStyleSheet: reader,
        ),
      );
      expect(styleOf(light, 0, 1).color, const Color(0xFF292521));
      final dark = section(
        '<p>a <a href="#x">link</a></p>',
        book: ten.copyWith(
          textColor: 0xFFF1E7D9,
          backgroundColor: 0xFF1D1916,
          readerStyleSheet: 'a { color: #d08a4a !important }',
        ),
      );
      expect(styleOf(dark, 0, 1).color, const Color(0xFFD08A4A));
      // On the reader's code panel the panel is the background.
      final code = section(
        '<p>a <code>c</code></p>',
        book: ten.copyWith(
          textColor: 0xFF292521,
          backgroundColor: 0xFFF7F1E6,
          readerStyleSheet: 'code { background: #000000 !important }',
        ),
      );
      expect(styleOf(code, 0, 1).color, const Color(0xFFFFFFFF));
      // The book's own colours are left alone without the override.
      final own = section(
        '<p style="color: #fafafa">a</p>',
        book: ten.copyWith(overrideColor: false, backgroundColor: 0xFFFFFFFF),
      );
      expect(styleOf(own, 0, 0).color, const Color(0xFFFAFAFA));
    });

    test('fonts with an optical size axis are drawn at their size', () {
      final s = section(
        '<p>a <span id="big" style="font-size: 30px">b</span> '
        '<span style="font-optical-sizing: none">c <b>d</b></span>'
        '<span style="font-size: 0">e</span></p>',
      );
      final p = s.paragraphs.single;
      List<FontVariation> variations(int run) => s.styler
          .textStyle(p.runs[run].style, p.style, prose: true)
          .fontVariations!;
      expect(variations(0), contains(const FontVariation('opsz', 10)));
      expect(variations(1), contains(const FontVariation('opsz', 30)));
      expect(
        p.runs.map((r) => p.text.substring(r.start, r.end)),
        ['a ', 'b', ' ', 'c ', 'd', 'e'],
      );
      expect(variations(3).where((v) => v.axis == 'opsz'), isEmpty);
      expect(
        variations(4),
        [const FontVariation('wght', 700)],
        reason: 'none, inherited by the bold run',
      );
      expect(variations(5).where((v) => v.axis == 'opsz'), isEmpty);
    });

    test('decorations, italic, small caps and spacing', () {
      final s = section(
        '<p><a href="#x">l</a><i>i</i><span style="font-variant: small-caps; letter-spacing: 2px; word-spacing: 3px; text-decoration: line-through overline">s</span></p>',
      );
      expect(styleOf(s, 0, 0).decoration, TextDecoration.underline);
      expect(styleOf(s, 0, 1).fontStyle, FontStyle.italic);
      final span = styleOf(s, 0, 2);
      expect(span.fontFeatures, [const ui.FontFeature.enable('smcp')]);
      expect(span.letterSpacing, 2);
      expect(span.wordSpacing, 3);
      expect(
        span.decoration,
        TextDecoration.combine([
          TextDecoration.overline,
          TextDecoration.lineThrough,
        ]),
      );
    });
  });

  group('atomics', () {
    test('images take their intrinsic size, scaled into the column and page', () {
      final s = section(
        '<p>a<img src="small.png"/>b<img src="wide.png"/><img src="tall.png"/>'
        '<img src="unknown.png"/><img src="half.png" style="width: 50%"/></p>',
      );
      final layout = s.layout(
        s.paragraphs.single,
        width: 100,
        maxImageHeight: 50,
        images: const {
          'small.png': Size(20, 10),
          'wide.png': Size(400, 100),
          'tall.png': Size(10, 200),
          'half.png': Size(10, 10),
        },
      );
      final sizes = [for (final a in layout.atomics) a.rect.size];
      expect(sizes, const [
        Size(20, 10),
        Size(100, 25),
        Size(2.5, 50),
        Size.zero,
        Size(50, 50),
      ]);
      expect(
        layout.atomics.first.rect.bottom,
        closeTo(layout.firstBaseline, 1e-6),
        reason: 'an image sits on the baseline',
      );
    });

    test('image size rules: CSS width and height, max-width, ratio', () {
      final s = section(
        '<p><img id="a" src="a" style="width: 30px"/><img id="b" src="b" style="height: 20px"/>'
        '<img id="c" src="c" style="width: 10px; height: 10px"/><img id="d" src="d" style="max-width: 20%"/></p>',
      );
      Size size(String id, Size? intrinsic) {
        final node = s.doc.elementIndexById(id);
        final atomic = s.paragraphs.single.atomics.firstWhere(
          (a) => a.node == node,
        );
        return ParagraphLayout.imageSize(
          atomic.style,
          intrinsic,
          maxWidth: 200,
          maxHeight: 1000,
        );
      }

      expect(size('a', const Size(60, 40)), const Size(30, 20));
      expect(size('b', const Size(60, 40)), const Size(30, 20));
      expect(size('c', const Size(60, 40)), const Size(10, 10));
      final d = size('d', const Size(60, 40));
      expect(d.width, 40);
      expect(d.height, closeTo(80 / 3, 1e-9));
      expect(size('a', null), Size.zero, reason: 'no ratio without the image');
      expect(size('c', null), const Size(10, 10));
    });

    test('raised text sits above the baseline, lowered text below', () {
      final s = section(
        '<p>x<sup>2</sup>y<sub>3</sub></p>',
        css: 'p { font-size: 12px }',
      );
      final layout = s.layout(s.paragraphs.single, width: 200);
      final [sup, sub] = layout.atomics;
      final baseline = layout.firstBaseline;
      final supBaseline = sup.rect.top + sup.text!.firstBaseline;
      final subBaseline = sub.rect.top + sub.text!.firstBaseline;
      expect(supBaseline, closeTo(baseline - (12 / 3 + 1), 0.01));
      expect(subBaseline, closeTo(baseline + (12 / 5 + 1), 0.01));
      expect(
        sup.rect.width,
        closeTo(10, 0.01),
        reason: 'one glyph at the smaller size',
      );
      expect(sup.text!.box.text, '2');
    });

    test('position: relative moves text without opening up the line', () {
      // How publishers raise note numbers: no vertical-align, an offset.
      const css =
          'p { font-size: 12px; line-height: 20px } '
          'sup { vertical-align: baseline; position: relative; top: -0.5em }';
      final plain = section('<p>xy</p>', css: css);
      final noted = section('<p>x<sup>2</sup>y</p>', css: css);
      final plainLayout = plain.layout(plain.paragraphs.single, width: 200);
      final layout = noted.layout(noted.paragraphs.single, width: 200);
      expect(layout.height, plainLayout.height, reason: 'same line height');
      final sup = layout.atomics.single;
      final supBaseline = sup.rect.top + sup.text!.firstBaseline;
      // 0.5em of the sup's own font (12px / 1.2).
      expect(supBaseline, closeTo(layout.firstBaseline - 5, 0.01));
      expect(sup.text!.box.text, '2');
    });

    test('relative offsets: left over right, percentages of the width', () {
      final s = section(
        '<p>x<span>a</span><em>b</em><i>c</i>y</p>',
        css:
            'p { font-size: 10px } '
            'span { position: relative; left: 3px; right: 50px } '
            'em { position: relative; right: 10% } '
            'i { position: relative; bottom: 2px; top: 10% }',
      );
      final layout = s.layout(s.paragraphs.single, width: 200);
      final [a, b, c] = layout.atomics;
      // The test font's glyphs are one font size wide: x, then a at 10.
      expect(a.rect.left, closeTo(10 + 3, 0.01));
      expect(b.rect.left, closeTo(20 - 20, 0.01));
      // A vertical percentage has no height to be of: bottom applies.
      final baseline = layout.firstBaseline;
      expect(c.rect.top + c.text!.firstBaseline, closeTo(baseline - 2, 0.01));
    });

    test('inline padding, border and margin take room at the edges', () {
      final s = section(
        '<p>a <code>bc</code> d</p>',
        css:
            'p { font-size: 10px } '
            'code { padding: 2px 3px; border: 1px solid; margin: 0 2px; '
            'background: #eee }',
        book: ten.copyWith(overrideColor: false),
      );
      final layout = s.layout(s.paragraphs.single, width: 200);
      // "a " is 20px; the start takes margin 2, border 1, padding 3.
      final b = layout.boxesFor(3, 4).single.toRect();
      expect(b.left, closeTo(20 + 6, 0.01));
      final [box] = layout.inlineDecorations;
      expect(box.rect.left, closeTo(20 + 2, 0.01), reason: 'after the margin');
      expect(box.rect.right, closeTo(20 + 6 + 20 + 4, 0.01));
      // The test font's content area is the glyph square: 7.5 above the
      // baseline and 2.5 below, then padding and border.
      expect(box.rect.top, closeTo(layout.firstBaseline - 7.5 - 2 - 1, 0.01));
      expect(box.background, 0xFFEEEEEE);
      expect(box.borderWidth, const CssEdges(1.0, 1.0, 1.0, 1.0));
    });

    test('vertical padding paints around the text, not into the line', () {
      const body = '<p>a <code>bc</code> d</p>';
      final plain = section(body, css: 'p { font-size: 10px }');
      final padded = section(
        body,
        css: 'p { font-size: 10px } code { padding: 8px 0; background: red }',
        book: ten.copyWith(overrideColor: false),
      );
      final a = plain.layout(plain.paragraphs.single, width: 200);
      final b = padded.layout(padded.paragraphs.single, width: 200);
      expect(b.height, a.height);
      expect(b.inlineDecorations.single.rect.height, closeTo(10 + 16, 0.01));
    });

    test('a decoration over two lines is sliced: edges at its ends only', () {
      final s = section(
        '<p>aa <code>bb cc dd</code></p>',
        css:
            'p { font-size: 10px } '
            'code { border: 2px solid; border-radius: 3px }',
      );
      final layout = s.layout(s.paragraphs.single, width: 70);
      expect(layout.lines.length, greaterThan(1));
      final fragments = layout.inlineDecorations;
      expect(fragments.length, layout.lines.length);
      final first = fragments.first;
      final last = fragments.last;
      expect(first.borderWidth, const CssEdges(2.0, 0.0, 2.0, 2.0));
      expect(last.borderWidth, const CssEdges(2.0, 2.0, 2.0, 0.0));
      expect(first.radius.topRight, CssRadius.zero);
      expect(
        first.radius.topLeft,
        const CssRadius(CssLength.px(3), CssLength.px(3)),
      );
      expect(last.rect.top, greaterThan(first.rect.top));
    });

    test('an offset of zero or auto keeps the text in the line', () {
      final s = section(
        '<p>x<span>a</span>y</p>',
        css: 'span { position: relative; top: 0; left: auto }',
      );
      final layout = s.layout(s.paragraphs.single, width: 200);
      expect(layout.atomics, isEmpty);
      expect(layout.box.text, 'xay');
    });
  });

  group('beside floats', () {
    // Ten 10-px glyphs fit a 100-px line; lines are 18 px apart.
    const text = 'aaaa bbbb cccc dddd eeee ffff';
    const leftFloat = FloatArea(Rect.fromLTWH(0, 0, 50, 36), left: true);

    test('lines beside a float start after it; lines below take the width', () {
      final s = section('<p>$text</p>');
      final layout = s.layout(s.paragraphs.single, floats: [leftFloat]);
      // Two lines start beside the float (tops 0 and 18), each with
      // a word in the 50 px it leaves; the rest are full width.
      expect(layout.lines, hasLength(4));
      expect(layout.lineStart(1), 5);
      expect(layout.lineStart(2), 10);
      expect(layout.lineStart(3), 20);
      expect(layout.lineTop(2), 36);
      expect(layout.height, 72);
      expect(layout.boxesFor(0, 1).single.left, 50);
      // Glyph boxes start below the line's top by the half-leading, 4.
      expect(
        layout.boxesFor(5, 6).single.toRect().topLeft,
        const Offset(50, 22),
      );
      expect(
        layout.boxesFor(10, 11).single.toRect().topLeft,
        const Offset(0, 40),
      );
      expect(layout.lines[0].left, greaterThanOrEqualTo(50));
      expect(layout.lines[2].baseline, greaterThan(36));
      expect(layout.lineAt(12), 2);
      expect(layout.lineAtY(40), 2);
    });

    test('positions, words and boxes run across the bands', () {
      final s = section('<p>$text</p>');
      final layout = s.layout(s.paragraphs.single, floats: [leftFloat]);
      expect(layout.positionAt(const Offset(52, 5)).offset, 0);
      expect(layout.positionAt(const Offset(58, 23)).offset, 6);
      expect(layout.positionAt(const Offset(12, 40)).offset, 11);
      expect(
        layout.positionAt(const Offset(10, 5)).offset,
        0,
        reason: 'over the float: the line\'s start',
      );
      expect(layout.wordAt(6), const TextRange(start: 5, end: 9));
      expect(layout.wordAt(11), const TextRange(start: 10, end: 14));
      final boxes = layout.boxesFor(6, 12);
      expect(boxes.first.toRect().topLeft, const Offset(60, 22));
      expect(boxes.last.toRect().top, 40);
      expect(layout.caretBottom(10).dy, closeTo(54, 1));
    });

    test('a right float shortens the lines at their end', () {
      final s = section('<p>$text</p>');
      const right = FloatArea(Rect.fromLTWH(50, 0, 50, 36), left: false);
      final layout = s.layout(s.paragraphs.single, floats: [right]);
      expect(layout.lineStart(1), 5);
      expect(layout.boxesFor(0, 1).single.left, 0);
      for (final b in layout.boxesFor(0, 10)) {
        expect(b.right, lessThanOrEqualTo(50.5));
      }
    });

    test('justified lines beside a float are justified to its edge', () {
      final s = section('<p>aa bb cc dd ee ff gg hh ii jj</p>');
      final layout = s.layout(
        s.paragraphs.single,
        floats: const [FloatArea(Rect.fromLTWH(0, 0, 30, 18), left: true)],
      );
      // "aa bb" fills the 70 px beside the float: justified, its last
      // glyph ends at the right edge, though the band's text goes on.
      expect(layout.lineStart(1), 6);
      expect(layout.boxesFor(4, 5).single.right, closeTo(100, 0.5));
    });

    test('too little room beside a float: the lines start below it', () {
      final s = section('<p>$text</p>');
      final layout = s.layout(
        s.paragraphs.single,
        floats: const [FloatArea(Rect.fromLTWH(0, 0, 95, 30), left: true)],
      );
      expect(layout.lineTop(0), 30);
      expect(
        layout.boxesFor(0, 1).single.toRect().topLeft,
        const Offset(0, 34),
      );
      expect(layout.height, 30 + 3 * 18);
      expect(layout.positionAt(const Offset(2, 10)).offset, 0);
    });

    test('atomics keep their own atomic and move with their band', () {
      final s = section(
        '<p>aaaa bbbb <img src="x.png"/> cccc dddd</p>',
      );
      final layout = s.layout(
        s.paragraphs.single,
        images: {'x.png': const Size(10, 10)},
        floats: [leftFloat],
      );
      final image = layout.atomics.single;
      expect(image.atomic, s.paragraphs.single.atomics.single);
      expect(image.rect.top, greaterThanOrEqualTo(36));
    });

    test('each band paints its own lines only', () async {
      final s = section('<p>$text</p>');
      final layout = s.layout(s.paragraphs.single, floats: [leftFloat]);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      layout
        ..paintDecorations(canvas, Offset.zero)
        ..paint(canvas, Offset.zero);
      final image = recorder.endRecording().toImageSync(100, 100);
      addTearDown(image.dispose);
      final bytes = (await image.toByteData())!;
      int alphaAt(int x, int y) => bytes.getUint8((y * 100 + x) * 4 + 3);
      expect(alphaAt(55, 10), greaterThan(0), reason: '"a" at 50–60');
      expect(alphaAt(5, 10), 0, reason: 'nothing over the float');
      // The first band's painter has the whole text, on lines it does
      // not use: "eeee" would be drawn below the paragraph.
      expect(alphaAt(55, 78), 0);
    });

    test('no floats: one band, as before', () {
      final s = section('<p>$text</p>');
      final plain = s.layout(s.paragraphs.single);
      final empty = s.layout(
        s.paragraphs.single,
        floats: const [FloatArea(Rect.fromLTWH(0, 0, 50, 0), left: true)],
      );
      expect(plain.lines, hasLength(3));
      expect(empty.lines, hasLength(3));
      expect(empty.boxesFor(0, 1).single.left, 0);
    });
  });

  group('inline blocks', () {
    PlacedAtomic block(ParagraphLayout layout) => layout.atomics.single;

    test('its width, padding, border and margins take room in the line', () {
      final s = section(
        '<p>aa <span style="display: inline-block; width: 30px; padding: 2px; '
        'border: 1px solid red; margin: 0 3px">b</span> c</p>',
      );
      final layout = s.layout(s.paragraphs.single);
      final placed = block(layout);
      expect(placed.rect.width, 30 + 2 * 2 + 2 * 1 + 2 * 3);
      expect(placed.textAt, const Offset(3 + 1 + 2, 1 + 2));
      expect(placed.text!.width, 30);
      // "aa ", the block, a space: "c".
      expect(layout.boxesFor(5, 6).single.left, 30 + placed.rect.width + 10);
    });

    test('without a width it shrinks to its text, which wraps inside it', () {
      final s = section(
        '<p>a <span style="display: inline-block">bb</span> '
        '<span style="display: inline-block; width: 20px">cc dd</span></p>',
      );
      final layout = s.layout(s.paragraphs.single);
      final [shrunk, narrow] = layout.atomics;
      expect(shrunk.rect.width, 20);
      expect(narrow.text!.lines, hasLength(2));
      // Two lines tall, on the line's baseline by its last line: the
      // line opens up above.
      expect(narrow.rect.height, narrow.text!.height);
      expect(
        narrow.rect.top + narrow.text!.lines.last.baseline,
        closeTo(layout.lines.single.baseline, 0.5),
      );
      expect(layout.height, greaterThan(narrow.rect.height));
    });

    test('percentages are of the paragraph, beside a float too', () {
      final s = section(
        '<p><span style="display: inline-block; width: 40%">aaa</span></p>',
      );
      final layout = s.layout(
        s.paragraphs.single,
        floats: const [FloatArea(Rect.fromLTWH(0, 0, 50, 36), left: true)],
      );
      final placed = block(layout);
      expect(placed.rect.width, 40);
      expect(placed.rect.left, 50);
      expect(placed.text!.lines, hasLength(1));
    });

    test('vertical-align super raises it as it raises text', () {
      final s = section(
        '<p>a <span style="display: inline-block">b</span>'
        '<span style="display: inline-block; vertical-align: super">c</span>'
        '</p>',
      );
      final [plain, raised] = s.layout(s.paragraphs.single).atomics;
      expect(raised.rect.top, lessThan(plain.rect.top));
    });

    test('its background is painted, its images found', () {
      final s = section(
        '<p>a <span style="display: inline-block; background: red; '
        'padding: 2px">b<img src="i.png"/></span></p>',
      );
      final layout = s.layout(
        s.paragraphs.single,
        images: {'i.png': const Size(10, 10)},
      );
      final placed = block(layout);
      final image = layout.images.single;
      expect(image.src, 'i.png');
      expect(image.rect.left, placed.rect.left + 2 + 10);
      final recorder = ui.PictureRecorder();
      layout.paintDecorations(Canvas(recorder), Offset.zero);
      recorder.endRecording().dispose();
    });
  });

  group('hyphenation', () {
    final hyphenated = ten.copyWith(hyphenate: true, justify: false);

    /// Each line's text, a shown hyphen as `-`.
    List<String> lines(ParagraphLayout layout) {
      final text = layout.box.text;
      return [
        for (var i = 0; i < layout.lines.length; i++)
          String.fromCharCodes([
            for (
              var at = layout.lineStart(i);
              at <
                  (i + 1 < layout.lines.length
                      ? layout.lineStart(i + 1)
                      : text.length);
              at++
            )
              if (text.codeUnitAt(at) != 0xAD)
                text.codeUnitAt(at)
              else if (layout.showsHyphenAt(at))
                0x2D,
          ]).trimRight(),
      ];
    }

    test('a word breaks at a line end with a hyphen that takes room', () {
      final s = section('<p lang="en">cc hyphenation</p>', book: hyphenated);
      final layout = s.layout(s.paragraphs.single);
      expect(lines(layout), ['cc hyphen-', 'ation']);
      expect(layout.lines.first.width, 100, reason: 'the hyphen is drawn');
      expect(layout.boxesFor(10, 11).single.toRect().width, 10);
    });

    test('a hyphen that does not fit breaks the word earlier', () {
      final s = section('<p lang="en">cc hyphenation</p>', book: hyphenated);
      // "cc hyphen-" is 100 wide; "cc hy-" fits and "phenation" after it.
      final layout = s.layout(s.paragraphs.single, width: 95);
      expect(lines(layout), ['cc hy-', 'phenation']);
    });

    test('lines after a moved line are decided again', () {
      final s = section(
        '<p lang="en">cc hyphenation hyphenation hyphenation</p>',
        book: hyphenated,
      );
      final layout = s.layout(s.paragraphs.single, width: 95);
      expect(lines(layout), [
        'cc hy-',
        'phenation',
        'hyphen-',
        'ation hy-',
        'phenation',
      ]);
    });

    test('justified text breaks where start-aligned text does', () {
      const body =
          '<p lang="en">cc hyphenation hyphenation hyphenation hyphenation</p>';
      final start = section(body, book: hyphenated);
      final justified = section(body, book: hyphenated.copyWith(justify: true));
      for (final width in [80.0, 95.0, 100.0, 130.0]) {
        expect(
          lines(justified.layout(justified.paragraphs.single, width: width)),
          lines(start.layout(start.paragraphs.single, width: width)),
          reason: 'at $width',
        );
      }
    });

    test('a hyphen that does not fit gives way to the text\'s own', () {
      final s = section(
        '<p lang="en">cc self-hyphenation</p>',
        book: hyphenated,
      );
      // "cc self-hy-" is 110 wide: the line ends after "self-".
      expect(lines(s.layout(s.paragraphs.single, width: 105)), [
        'cc self-',
        'hyphen-',
        'ation',
      ]);
    });

    test('a word hyphenated across lines is one word', () {
      final s = section('<p lang="en">cc hyphenation</p>', book: hyphenated);
      final layout = s.layout(s.paragraphs.single);
      final word = layout.wordAt(13);
      expect(word, const TextRange(start: 3, end: 16));
      expect(layout.box.plainText(word.start, word.end), 'hyphenation');
      expect(layout.wordAt(4), word);
      expect(layout.wordAt(0), const TextRange(start: 0, end: 2));
    });

    test('no hyphenation without the setting; the book\'s soft hyphens', () {
      final plain = section(
        '<p lang="en">cc hyphenation</p>',
        book: ten.copyWith(justify: false),
      );
      expect(lines(plain.layout(plain.paragraphs.single)), [
        'cc',
        'hyphenatio',
        'n',
      ]);
      final shy = section(
        '<p lang="en">cc hyphen&#xAD;ation</p>',
        book: ten.copyWith(justify: false),
      );
      expect(lines(shy.layout(shy.paragraphs.single)), ['cc hyphen-', 'ation']);
      final none = section(
        '<p lang="en" style="hyphens: none">cc hyphen&#xAD;ation</p>',
        book: ten.copyWith(justify: false, useBookLayout: false),
      );
      expect(
        lines(none.layout(none.paragraphs.single)),
        [
          'cc',
          'hyphenatio',
          'n',
        ],
        reason: 'hyphens: none ignores soft hyphens',
      );
    });

    test('at most hyphenateLimitLines lines in a row end hyphenated', () {
      const body =
          '<p lang="en">hyphenation hyphenation hyphenation hyphenation</p>';
      final free = section(body, book: hyphenated);
      expect(lines(free.layout(free.paragraphs.single, width: 90)), [
        'hyphen-',
        'ation hy-',
        'phenation',
        'hyphen-',
        'ation hy-',
        'phenation',
      ]);
      final limited = section(
        body,
        book: hyphenated.copyWith(hyphenateLimitLines: 1),
      );
      expect(lines(limited.layout(limited.paragraphs.single, width: 90)), [
        'hyphen-',
        'ation',
        'hyphen-',
        'ation',
        'hyphen-',
        'ation',
        'hyphen-',
        'ation',
      ]);
    });
  });

  group('book style', () {
    test('equality, copies and what needs a new cascade', () {
      const a = BookStyle();
      expect(a.copyWith(), a);
      expect(a.copyWith(fontWeight: 500), isNot(a));
      expect(
        a.copyWith(fontFamily: 'X').copyWith(clearFontFamily: true).fontFamily,
        isNull,
      );
      expect(a.rootFontSize, closeTo(22.4, 1e-9));
      expect(a.copyWith(fontScale: 1.2).restylesFrom(a), isTrue);
      expect(a.copyWith(lineHeight: 1.2).restylesFrom(a), isTrue);
      expect(a.copyWith(textIndent: 1).restylesFrom(a), isFalse);
      // The colour override is a user style sheet rule.
      expect(a.copyWith(textColor: 0xFF00FF00).restylesFrom(a), isTrue);
      expect(a.copyWith(overrideColor: false).restylesFrom(a), isTrue);
      final own = a.copyWith(overrideColor: false);
      expect(own.copyWith(textColor: 0xFF00FF00).restylesFrom(own), isFalse);
      expect(a.copyWith(readerStyleSheet: 'p {}').restylesFrom(a), isTrue);
      expect(a.copyWith(readerStyleSheet: 'p {}'), isNot(a));
      // Hyphenation: the prose rule and the soft hyphens are prepared
      // with the boxes; the line limit is the layout's.
      expect(a.copyWith(hyphenate: true).restylesFrom(a), isTrue);
      final bookLayout = a.copyWith(useBookLayout: false);
      expect(
        bookLayout.copyWith(hyphenate: true).restylesFrom(bookLayout),
        isFalse,
      );
      expect(a.copyWith(hyphenateLimitBefore: 3).restylesFrom(a), isTrue);
      expect(a.copyWith(hyphenateLimitLines: 2).restylesFrom(a), isFalse);
      expect(a.copyWith(hyphenateLimitLines: 2), isNot(a));
    });

    test('hyphenation limits are foliate-js\'s prose rule\'s', () {
      const webKit = BookStyle(
        hyphenateLimitBefore: 3,
        hyphenateLimitAfter: 2,
        hyphenateLimitLines: 2,
      );
      expect(
        webKit.hyphenation,
        const TextHyphenation(minBefore: 3, minAfter: 2, maxLines: 2),
      );
      expect(
        webKit.copyWith(useBookLayout: false).hyphenation,
        const TextHyphenation(),
        reason: 'the rule is not there without the book layout',
      );
    });

    test('hyphens on prose as foliate-js\'s rule sets them', () {
      const body =
          '<p id="p">a</p><div id="d">b <b>c</b></div>'
          '<div id="block"><p>d</p></div><li id="li">e</li>'
          '<section class="x"><p id="own">f</p></section><h1 id="h">g</h1>';
      const css = '.x p { hyphens: none }';
      CssHyphens of(Section s, String id) => s.boxes.paragraphs
          .firstWhere(
            (p) =>
                p.node == s.doc.elementIndexById(id) ||
                s.doc.parentOf(p.node) == s.doc.elementIndexById(id),
            orElse: () => throw StateError(id),
          )
          .style
          .hyphens;
      final on = section(body, css: css, book: ten.copyWith(hyphenate: true));
      expect(of(on, 'p'), CssHyphens.auto);
      expect(of(on, 'd'), CssHyphens.auto, reason: 'a div of inline text');
      expect(of(on, 'li'), CssHyphens.auto);
      expect(of(on, 'own'), CssHyphens.none, reason: 'the book\'s rule wins');
      expect(of(on, 'h'), CssHyphens.manual, reason: 'headings keep theirs');
      final off = section(body, css: css);
      expect(of(off, 'p'), CssHyphens.manual);
      final book = section(
        '<p id="p" style="hyphens: auto">a</p>',
        book: ten.copyWith(hyphenate: true, useBookLayout: false),
      );
      expect(of(book, 'p'), CssHyphens.auto, reason: 'the book\'s own');
      final rule = foliateStyleSheet(const BookStyle(hyphenate: true));
      expect(rule, contains('hyphens: auto'));
      expect(
        foliateStyleSheet(const BookStyle(useBookLayout: false)),
        isNot(contains('hyphens')),
      );
      expect(
        on.boxes.paragraphs.any(
          (p) => p.node == on.doc.elementIndexById('block'),
        ),
        isFalse,
      );
    });

    test('the family override names the reader\'s family as CSS', () {
      expect(
        foliateStyleSheet(const BookStyle(fontFamily: 'system')),
        contains('font-family: system-ui !important'),
      );
      expect(
        foliateStyleSheet(const BookStyle(fontFamily: 'My "Font"')),
        contains(r'font-family: "My \"Font\"" !important'),
      );
      for (final style in const [
        BookStyle(fontFamily: 'book'),
        BookStyle(),
        BookStyle(fontFamily: 'Literata', overrideFont: false),
      ]) {
        expect(foliateStyleSheet(style), isNot(contains('font-family')));
      }
      // A new family or override is a new cascade.
      const a = BookStyle(fontFamily: 'Literata');
      expect(a.copyWith(fontFamily: 'Open Sans').restylesFrom(a), isTrue);
      expect(a.copyWith(overrideFont: false).restylesFrom(a), isTrue);
      expect(a.copyWith(fontWeight: 500).restylesFrom(a), isTrue);
    });

    test('the user style sheet does what foliate-js\'s CSS does', () {
      final s = section(
        '<div style="padding: 0 5%; margin: 0 2em" id="w"><pre id="pre">a  b</pre>'
        '<aside xmlns:epub="http://www.idpf.org/2007/ops" epub:type="footnote">note</aside>'
        '<ul><li><p id="lp">x</p></li></ul></div><h1 id="h">h</h1>',
        css:
            'body { margin: 3em; font-size: 0.5em; background: #fff '
            'url(paper.png) } p { text-indent: 3em }',
      );
      final texts = [for (final p in s.paragraphs) p.text];
      expect(texts, ['a  b', 'x', 'h'], reason: 'footnote asides are hidden');
      final pre = s.paragraphs.first;
      expect(pre.style.whiteSpace, CssWhiteSpace.preWrap);
      final body = s.boxes.root.children.single as BlockBox;
      expect(body.style.margin.top, CssLength.zero);
      expect(body.style.fontSize, 10, reason: 'body stays at the root size');
      expect(
        body.style.backgroundColor >> 24,
        0,
        reason: 'the page draws the reader\'s background',
      );
      expect(body.style.backgroundImage, isNull);
      final wrapper = body.children.first as BlockBox;
      expect(wrapper.style.padding.left, CssLength.zero);
      expect(wrapper.style.margin.right, CssLength.zero);
      expect(
        s.paragraphs[1].style.textIndent,
        CssLength.zero,
        reason: 'li > p',
      );
      expect(s.paragraphs[2].style.lineHeight, const CssLineHeight.factor(1.8));
    });
  });

  group('fonts', () {
    test('generic families map, embedded fonts by name, fallback last', () {
      const fonts = BookFonts(
        serif: 'Literata',
        sansSerif: 'Open Sans',
        monospace: 'Mono',
        fallback: ['Noto Sans Symbols'],
        bookFamilies: {'book serif': 'pagecraft-1-Book Serif'},
      );
      void expectChain(
        List<String> css,
        String? family,
        List<String> fallback,
      ) {
        final resolved = fonts.resolve(css);
        expect(resolved.family, family, reason: '$css');
        expect(resolved.fallback, fallback, reason: '$css');
      }

      expectChain(['serif'], 'Literata', ['Noto Sans Symbols']);
      expectChain(
        ['Book Serif', 'serif'],
        'pagecraft-1-Book Serif',
        ['Literata', 'Noto Sans Symbols'],
      );
      // Unknown names pass through for the platform; the serif default
      // follows them.
      expectChain(['Georgia'], 'Georgia', ['Literata', 'Noto Sans Symbols']);
      expect(fonts.resolve(['sans-serif', 'monospace']).family, 'Open Sans');
      expect(const BookFonts().resolve(['serif']), (
        family: null,
        fallback: const <String>[],
      ));
      expect(fonts.withBookFamilies(const {}).bookFamilies, isEmpty);
      expect(fonts, fonts.withBookFamilies(fonts.bookFamilies));
    });
  });
}
