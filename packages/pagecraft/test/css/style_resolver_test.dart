import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// The cascade, as a table: a stylesheet and a document, and what each
/// element must compute to.
void main() {
  final ua = CssSheetSource(
    CssStyleSheet.parse(cssUserAgentStyleSheet),
    CssOrigin.userAgent,
  );

  /// Resolves [body] inside an XHTML document with [author] CSS and an
  /// optional [user] sheet; returns the style of the element with [id].
  ComputedStyle style(
    String body,
    String id, {
    String author = '',
    String user = '',
    StyleResolverOptions options = const StyleResolverOptions(),
    CssMediaEnvironment media = const CssMediaEnvironment(),
  }) {
    final doc = ContentDocument.parseXml(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body>$body</body></html>',
    );
    final resolver = StyleResolver(media: media, [
      ua,
      if (user.isNotEmpty)
        CssSheetSource(CssStyleSheet.parse(user), CssOrigin.user),
      CssSheetSource(CssStyleSheet.parse(author), CssOrigin.author),
    ]);
    return resolver.resolve(doc, options: options)[doc.elementIndexById(id)];
  }

  group('user-agent defaults', () {
    test('block, inline, hidden and list elements', () {
      expect(style('<p id="x">a</p>', 'x').display, CssDisplay.block);
      expect(style('<em id="x">a</em>', 'x').display, CssDisplay.inline);
      expect(
        style('<ul><li id="x">a</li></ul>', 'x').display,
        CssDisplay.listItem,
      );
      expect(
        style('<p><script id="x">a</script></p>', 'x').display,
        CssDisplay.none,
      );
      expect(
        style('<p id="x" hidden="hidden">a</p>', 'x').display,
        CssDisplay.none,
      );
    });

    test('headings, emphasis and code', () {
      final h1 = style('<h1 id="x">a</h1>', 'x');
      expect(h1.fontSize, 32);
      expect(h1.fontWeight, 700);
      expect(h1.margin.top, const CssLength.px(32 * 0.67));
      expect(style('<section><h1 id="x">a</h1></section>', 'x').fontSize, 24);
      final em = style('<p><em id="x">a</em></p>', 'x');
      expect(em.fontStyle, CssFontStyle.italic);
      expect(em.fontWeight, 400);
      expect(style('<p><strong id="x">a</strong></p>', 'x').isBold, isTrue);
      final code = style('<pre id="x">a</pre>', 'x');
      expect(code.fontFamily, ['monospace']);
      expect(code.whiteSpace, CssWhiteSpace.pre);
      expect(
        style('<p><sup id="x">a</sup></p>', 'x').verticalAlign,
        CssVerticalAlign.sup,
      );
      expect(
        style('<p><sup id="x">a</sup></p>', 'x').fontSize,
        closeTo(16 / 1.2, 1e-9),
      );
      expect(style('<p><a id="x" href="#">a</a></p>', 'x').underline, isTrue);
      expect(
        style('<p><a id="x">a</a></p>', 'x').underline,
        isFalse,
        reason: 'no href',
      );
      expect(style('<p><s id="x">a</s></p>', 'x').lineThrough, isTrue);
    });

    test('lists and quotes', () {
      final ul = style('<ul id="x"><li>a</li></ul>', 'x');
      expect(ul.padding.left, const CssLength.px(40));
      expect(ul.listStyleType, 'disc');
      expect(style('<ol><li id="x">a</li></ol>', 'x').listStyleType, 'decimal');
      expect(
        style(
          '<ul><li><ul><li id="x">a</li></ul></li></ul>',
          'x',
        ).listStyleType,
        'circle',
      );
      expect(
        style('<blockquote id="x">a</blockquote>', 'x').margin.left,
        const CssLength.px(40),
      );
      expect(
        style('<blockquote id="x">a</blockquote>', 'x').margin.top,
        const CssLength.px(16),
      );
    });
  });

  group('cascade', () {
    test('specificity and order decide between author rules', () {
      const css =
          'p { color: red } .a { color: green } #i { color: blue } p { font-size: 20px } p { font-size: 10px }';
      expect(
        style('<p id="i" class="a">a</p>', 'i', author: css).color,
        0xFF0000FF,
      );
      expect(style('<p id="i" class="a">a</p>', 'i', author: css).fontSize, 10);
      expect(
        style(
          '<p id="i" class="a">a</p>',
          'i',
          author: 'p { color: red } .a { color: green }',
        ).color,
        0xFF008000,
      );
    });

    test('origins and importance', () {
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: 'p { color: red }',
          user: 'p { color: blue }',
        ).color,
        0xFFFF0000,
        reason: 'author beats user',
      );
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: 'p { color: red }',
          user: 'p { color: blue !important }',
        ).color,
        0xFF0000FF,
        reason: 'user important beats author',
      );
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: 'p { color: red !important }',
          user: 'p { color: blue !important }',
        ).color,
        0xFF0000FF,
        reason: 'user important beats author important',
      );
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: '#i { color: red } p { color: green !important }',
        ).color,
        0xFF008000,
        reason: 'important beats specificity',
      );
      expect(
        style(
          '<em id="i">a</em>',
          'i',
          user: 'em { font-style: normal }',
        ).fontStyle,
        CssFontStyle.normal,
        reason: 'user beats the user-agent sheet',
      );
    });

    test('inline style beats every author rule, not user important', () {
      expect(
        style(
          '<p id="i" style="color: red">a</p>',
          'i',
          author: '#i { color: green }',
        ).color,
        0xFFFF0000,
      );
      expect(
        style(
          '<p id="i" style="color: red">a</p>',
          'i',
          author: '#i { color: green !important }',
        ).color,
        0xFF008000,
      );
      expect(
        style(
          '<p id="i" style="color: red !important">a</p>',
          'i',
          author: '#i { color: green !important }',
        ).color,
        0xFFFF0000,
      );
      expect(
        style(
          '<p id="i" style="color: red !important">a</p>',
          'i',
          user: 'p { color: blue !important }',
        ).color,
        0xFF0000FF,
      );
    });

    test('presentational attributes sit below author rules', () {
      expect(
        style('<p id="i" align="center">a</p>', 'i').textAlign,
        CssTextAlign.center,
      );
      expect(
        style(
          '<p id="i" align="center">a</p>',
          'i',
          author: 'p { text-align: left }',
        ).textAlign,
        CssTextAlign.left,
      );
      expect(
        style(
          '<p><img id="i" width="200" height="50%" align="left"/></p>',
          'i',
        ).width,
        const CssLength.px(200),
      );
      expect(
        style(
          '<p><img id="i" width="200" height="50%" align="left"/></p>',
          'i',
        ).height,
        const CssLength.percent(50),
      );
      expect(
        style('<p><img id="i" align="left"/></p>', 'i').float,
        CssFloat.left,
      );
      expect(
        style('<p id="i" height="2em" width="1em">a</p>', 'i').margin.top,
        const CssLength.px(32),
      );
      expect(
        style('<p id="i" height="2em" width="1em">a</p>', 'i').textIndent,
        const CssLength.px(16),
      );
      expect(
        style(
          '<p><font id="i" size="5" color="ff0000" face="Arial">a</font></p>',
          'i',
        ).fontSize,
        24,
      );
      expect(
        style(
          '<p><font id="i" size="+1" color="ff0000" face="Arial">a</font></p>',
          'i',
        ).fontSize,
        18,
      );
      expect(
        style(
          '<p><font id="i" size="5" color="ff0000" face="Arial">a</font></p>',
          'i',
        ).color,
        0xFFFF0000,
      );
      expect(
        style(
          '<p><font id="i" size="5" color="ff0000" face="Arial">a</font></p>',
          'i',
        ).fontFamily,
        ['Arial'],
      );
      expect(
        style(
          '<table id="i" bgcolor="yellow"><tr><td>a</td></tr></table>',
          'i',
        ).backgroundColor,
        0xFFFFFF00,
      );
      expect(
        style('<p id="i" dir="rtl">a</p>', 'i').direction,
        CssDirection.rtl,
      );
    });

    test('media blocks for print are skipped, others apply', () {
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: '@media print { p { color: red } }',
        ).color,
        0xFF000000,
      );
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: '@media screen { p { color: red } }',
        ).color,
        0xFFFF0000,
      );
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: '@media all and (min-width: 1px) { p { color: red } }',
        ).color,
        0xFFFF0000,
      );
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: '@media not print { p { color: red } }',
        ).color,
        0xFFFF0000,
      );
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: '@media print, screen { p { color: red } }',
        ).color,
        0xFFFF0000,
      );
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: '@media only print { p { color: red } }',
        ).color,
        0xFF000000,
      );
    });

    test('an invalid declaration leaves the earlier valid one', () {
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: 'p { color: red; color: nope }',
        ).color,
        0xFFFF0000,
      );
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          author: 'p { color: red } p:unknown { color: blue }',
        ).color,
        0xFFFF0000,
      );
    });
  });

  group('inheritance and computation', () {
    test('inherited properties flow down, others reset', () {
      const body =
          '<div id="d" style="color: red; margin: 10px; text-align: center; font-weight: bold"><p id="p">a<em id="e">b</em></p></div>';
      final p = style(body, 'p');
      expect(p.color, 0xFFFF0000);
      expect(p.textAlign, CssTextAlign.center);
      expect(p.fontWeight, 700);
      expect(
        p.margin.top,
        const CssLength.px(16),
        reason: 'the UA margin, not the parent\'s',
      );
      final e = style(body, 'e');
      expect(e.fontStyle, CssFontStyle.italic);
      expect(e.margin.top, CssLength.zero);
    });

    test('inherit, initial and unset', () {
      const body =
          '<div style="color: red; margin-top: 10px"><p id="a" style="margin-top: inherit">a</p><p id="b" style="color: initial">b</p><p id="c" style="color: unset; margin-top: unset">c</p></div>';
      expect(style(body, 'a').margin.top, const CssLength.px(10));
      expect(style(body, 'b').color, 0xFF000000);
      expect(style(body, 'c').color, 0xFFFF0000);
      expect(style(body, 'c').margin.top, CssLength.zero);
    });

    test('font sizes: keywords, em chains, rem, percent, larger', () {
      expect(style('<p id="i">a</p>', 'i').fontSize, 16);
      expect(
        style(
          '<p id="i">a</p>',
          'i',
          options: const StyleResolverOptions(rootFontSize: 20),
        ).fontSize,
        20,
      );
      expect(
        style('<p id="i" style="font-size: large">a</p>', 'i').fontSize,
        18,
      );
      expect(
        style(
          '<div style="font-size: 20px"><p id="i" style="font-size: 1.5em">a</p></div>',
          'i',
        ).fontSize,
        30,
      );
      expect(
        style(
          '<div style="font-size: 20px"><p id="i" style="font-size: 150%">a</p></div>',
          'i',
        ).fontSize,
        30,
      );
      expect(
        style(
          '<div style="font-size: 20px"><p id="i" style="font-size: 2rem">a</p></div>',
          'i',
        ).fontSize,
        32,
      );
      expect(
        style(
          '<div style="font-size: 2em"><p id="i" style="font-size: 2em">a</p></div>',
          'i',
        ).fontSize,
        64,
      );
      expect(
        style(
          '<div style="font-size: 20px"><p id="i" style="font-size: larger">a</p></div>',
          'i',
        ).fontSize,
        24,
      );
      expect(
        style(
          '<p id="i" style="font-size: 10vw">a</p>',
          'i',
          options: const StyleResolverOptions(viewportWidth: 300),
        ).fontSize,
        30,
      );
    });

    test('lengths resolve em against the element\'s own size', () {
      final p = style(
        '<p id="i" style="font-size: 20px; margin: 1em 5%; text-indent: 2em; padding-left: 1rem">a</p>',
        'i',
      );
      expect(p.margin.top, const CssLength.px(20));
      expect(p.margin.right, const CssLength.percent(5));
      expect(p.textIndent, const CssLength.px(40));
      expect(p.padding.left, const CssLength.px(16));
    });

    test('line height: normal, number, length and percent', () {
      expect(style('<p id="i">a</p>', 'i').lineHeight, CssLineHeight.normal);
      expect(
        style('<p id="i" style="line-height: 1.5">a</p>', 'i').lineHeight,
        const CssLineHeight.factor(1.5),
      );
      expect(
        style('<p id="i" style="line-height: 24px">a</p>', 'i').lineHeight,
        const CssLineHeight.px(24),
      );
      expect(
        style('<p id="i" style="line-height: 150%">a</p>', 'i').lineHeight,
        const CssLineHeight.px(24),
      );
      expect(
        style('<p id="i" style="line-height: 1.5em">a</p>', 'i').lineHeight,
        const CssLineHeight.px(24),
      );
      // A number inherits as a factor, a percentage as the computed px.
      expect(
        style(
          '<div style="line-height: 150%"><p id="i" style="font-size: 32px">a</p></div>',
          'i',
        ).lineHeight,
        const CssLineHeight.px(24),
      );
      expect(
        style(
          '<div style="line-height: 1.5"><p id="i" style="font-size: 32px">a</p></div>',
          'i',
        ).lineHeight.resolve(32),
        48,
      );
    });

    test('font weight: bold, bolder, lighter, numbers', () {
      expect(
        style('<p id="i" style="font-weight: bold">a</p>', 'i').fontWeight,
        700,
      );
      expect(
        style('<p id="i" style="font-weight: 350">a</p>', 'i').fontWeight,
        350,
      );
      expect(
        style(
          '<b><em id="i" style="font-weight: bolder">a</em></b>',
          'i',
        ).fontWeight,
        900,
      );
      expect(
        style('<p id="i" style="font-weight: bolder">a</p>', 'i').fontWeight,
        700,
      );
      expect(
        style(
          '<b><em id="i" style="font-weight: lighter">a</em></b>',
          'i',
        ).fontWeight,
        400,
      );
    });

    test('colors: currentcolor and transparent', () {
      final p = style(
        '<p id="i" style="color: red; border: 1px solid; background: transparent">a</p>',
        'i',
      );
      expect(p.borderColor.top, 0xFFFF0000);
      expect(p.borderWidth.top, 1);
      expect(p.borderStyle.top, CssBorderStyle.solid);
      expect(p.backgroundColor, 0);
      final q = style(
        '<p id="i" style="border: 2px dashed blue; border-left-style: none">a</p>',
        'i',
      );
      expect(q.borderWidth.left, 0, reason: 'none zeroes the width');
      expect(q.borderWidth.right, 2);
      expect(q.borderColor.right, 0xFF0000FF);
      expect(
        style(
          '<p id="i" style="background-color: currentcolor; color: green">a</p>',
          'i',
        ).backgroundColor,
        0xFF008000,
      );
    });

    test('page breaks, floats, decoration, spacing, white-space', () {
      final p = style(
        '<p id="i" style="page-break-before: always; break-after: avoid-page; page-break-inside: avoid; float: right; text-decoration: underline overline; letter-spacing: 0.1em; word-spacing: 2px; white-space: pre-wrap; text-transform: uppercase; hyphens: auto; vertical-align: 20%">a</p>',
        'i',
      );
      expect(p.pageBreakBefore, CssPageBreak.always);
      expect(p.pageBreakAfter, CssPageBreak.avoid);
      expect(p.avoidPageBreakInside, isTrue);
      expect(p.float, CssFloat.right);
      expect(p.underline, isTrue);
      expect(p.overline, isTrue);
      expect(p.lineThrough, isFalse);
      expect(p.letterSpacing, closeTo(1.6, 1e-9));
      expect(p.wordSpacing, 2);
      expect(p.whiteSpace, CssWhiteSpace.preWrap);
      expect(p.textTransform, CssTextTransform.uppercase);
      expect(p.hyphens, CssHyphens.auto);
      expect(p.verticalAlign, CssVerticalAlign.length);
      expect(p.verticalAlignLength, const CssLength.percent(20));
    });

    test('widths and heights keep auto, none and percentages', () {
      final p = style(
        '<p id="i" style="width: 50%; max-width: 30em; min-height: 10px">a</p>',
        'i',
      );
      expect(p.width, const CssLength.percent(50));
      expect(p.height, isNull);
      expect(p.maxWidth, const CssLength.px(480));
      expect(p.maxHeight, isNull);
      expect(p.minHeight, const CssLength.px(10));
      expect(p.minWidth, CssLength.zero);
    });
  });

  group('background images', () {
    test('url() is relative to its style sheet; size, repeat, position', () {
      final doc = ContentDocument.parseXml(
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<div id="a">a</div><div id="b" style="background-image: url(c.png)">'
        'b</div></body></html>',
      );
      final styles = StyleResolver([
        ua,
        CssSheetSource(
          CssStyleSheet.parse(
            'div { background: url(../Images/info.png) no-repeat 0 center '
            '/ 2em auto }',
          ),
          CssOrigin.author,
          baseHref: 'OPS/Styles/book.css',
        ),
      ]).resolve(doc);
      final a = styles[doc.elementIndexById('a')].backgroundImage!;
      expect(a.source, '/OPS/Images/info.png');
      expect(a.repeatX, isFalse);
      expect(a.repeatY, isFalse);
      expect(a.x, CssLength.zero);
      expect(a.y, const CssLength.percent(50));
      expect(a.width, const CssLength.px(32));
      expect(a.height, isNull);
      final b = styles[doc.elementIndexById('b')].backgroundImage!;
      expect(b.source, 'c.png', reason: 'an inline style has no base');
      expect(b.repeatX, isFalse, reason: 'the sheet\'s repeat still holds');
    });

    test('none, and not inherited', () {
      const author = 'div { background-image: url(a.png) }';
      expect(
        style(
          '<div><p id="x">a</p></div>',
          'x',
          author: author,
        ).backgroundImage,
        isNull,
      );
      expect(
        style(
          '<div id="x">a</div>',
          'x',
          author: '$author div { background-image: none }',
        ).backgroundImage,
        isNull,
      );
    });
  });

  group('custom properties', () {
    test('var() takes an inherited custom property', () {
      const author =
          ':root { --text: #112233; --mono: "Code", monospace; '
          '--pad: 3px } '
          'p { color: var(--text) } code { font-family: var(--mono) } '
          'em { padding-left: var(--pad) }';
      const body = '<p id="p">a <code id="c">b</code> <em id="e">c</em></p>';
      expect(style(body, 'p', author: author).color, 0xFF112233);
      expect(style(body, 'c', author: author).fontFamily, [
        'Code',
        'monospace',
      ]);
      expect(
        style(body, 'e', author: author).padding.left,
        const CssLength.px(3),
      );
    });

    test('an element\'s own value wins; its children inherit it', () {
      const author =
          ':root { --c: red } div { --c: blue } p { color: var(--c) }';
      expect(
        style('<div><p id="x">a</p></div>', 'x', author: author).color,
        0xFF0000FF,
      );
      expect(style('<p id="x">a</p>', 'x', author: author).color, 0xFFFF0000);
    });

    test('a fallback stands in for what is missing', () {
      expect(
        style(
          '<p id="x">a</p>',
          'x',
          author: 'p { color: var(--none, var(--neither, #00ff00)) }',
        ).color,
        0xFF00FF00,
      );
    });

    test('nothing to substitute: the declaration is unset', () {
      const author =
          'div { color: #123456; margin-top: 7px } '
          'p { color: var(--none); margin-top: var(--none) }';
      final p = style('<div><p id="x">a</p></div>', 'x', author: author);
      expect(p.color, 0xFF123456, reason: 'inherited');
      expect(p.margin.top, CssLength.zero, reason: 'initial');
      expect(
        style(
          '<p id="x">a</p>',
          'x',
          author: ':root { --w: red } p { margin-top: var(--w) }',
        ).margin.top,
        CssLength.zero,
        reason: 'a value the property does not take',
      );
    });

    test('a cycle makes its custom properties invalid', () {
      expect(
        style(
          '<p id="x">a</p>',
          'x',
          author:
              ':root { --a: var(--b); --b: var(--a) } '
              'p { color: var(--a, #0000ff) }',
        ).color,
        0xFF0000FF,
      );
    });

    test('custom properties refer to each other; initial drops one', () {
      const author =
          ':root { --base: 4px; --double: calc(var(--base) * 2); '
          '--gone: 1px } div { --gone: initial } '
          'p { padding-left: var(--double); padding-right: var(--gone, 9px) }';
      final p = style('<div><p id="x">a</p></div>', 'x', author: author);
      expect(p.padding.left, const CssLength.px(8));
      expect(p.padding.right, const CssLength.px(9));
    });

    test('shorthands take their parts from the substituted value', () {
      final p = style(
        '<p id="x">a</p>',
        'x',
        author: ':root { --m: 1px 2px 3px } p { margin: var(--m) }',
      );
      expect(p.margin.top, const CssLength.px(1));
      expect(p.margin.right, const CssLength.px(2));
      expect(p.margin.bottom, const CssLength.px(3));
      expect(p.margin.left, const CssLength.px(2));
    });

    test('inline styles use them too; equal sets compare equal', () {
      final doc = ContentDocument.parseXml(
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<p id="a" style="--x: 5px; padding-top: var(--x)">a</p>'
        '<p id="b" style="--x: 5px; padding-top: var(--x)">b</p>'
        '</body></html>',
      );
      final styles = StyleResolver([ua]).resolve(doc);
      final a = styles[doc.elementIndexById('a')];
      final b = styles[doc.elementIndexById('b')];
      expect(a.padding.top, const CssLength.px(5));
      expect(a.customProperties, b.customProperties);
      expect(a.customProperties.hashCode, b.customProperties.hashCode);
      expect(a, b);
    });
  });

  group('style sharing', () {
    test('siblings that match the same rules share one style object', () {
      final doc = ContentDocument.parseXml(
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '${List.filled(50, '<p class="a b">x</p>').join()}'
        '<p class="b a">y</p><p class="a">z</p>'
        '<p class="a b" style="color: red">w</p><p class="a b" align="center">v</p>'
        '<div><p class="a b">nested</p></div></body></html>',
      );
      final styles = StyleResolver([
        ua,
        CssSheetSource(
          CssStyleSheet.parse(
            '.a { font-size: 20px } .b { color: blue } div .a { color: green }',
          ),
          CssOrigin.author,
        ),
      ]).resolve(doc);
      final body = doc.firstChildOf(0);
      final ps = doc.childrenOf(body).toList();
      for (final p in ps.take(51)) {
        expect(
          styles[p],
          same(styles[ps.first]),
          reason: 'class order does not matter',
        );
      }
      expect(styles[ps[51]].color, 0xFF000000);
      expect(
        styles[ps[52]].color,
        0xFFFF0000,
        reason: 'inline style is part of the key',
      );
      expect(
        styles[ps[53]].textAlign,
        CssTextAlign.center,
        reason: 'so are presentational attributes',
      );
      final nested = doc.firstChildOf(ps[54]);
      expect(styles[nested].color, 0xFF008000);
      expect(styles[ps.first].color, 0xFF0000FF);
      expect(styles[ps.first].fontSize, 20);
    });

    test('many inline declarations keep their order above author rules', () {
      final declarations = [
        for (var i = 0; i < 40; i++) 'margin-left: ${i}px',
      ].join('; ');
      final p = style(
        '<p id="i" style="$declarations; color: red">a</p>',
        'i',
        author: '#i { color: blue; margin-left: 999px }',
      );
      expect(p.color, 0xFFFF0000);
      expect(p.margin.left, const CssLength.px(39));
    });
  });

  group('flow-relative properties', () {
    const quote =
        'blockquote { border-inline-start: 3px solid #f00; '
        'padding-inline-start: 1em; margin-inline: 0 2px; '
        'max-inline-size: 100%; }';

    test('inline sides are left and right in left-to-right text', () {
      final q = style('<blockquote id="x">a</blockquote>', 'x', author: quote);
      expect(q.borderWidth.left, 3);
      expect(q.borderStyle.left, CssBorderStyle.solid);
      expect(q.borderColor.left, 0xFFFF0000);
      expect(q.borderWidth.right, 0, reason: 'no border style');
      expect(q.padding.left, const CssLength.px(16));
      expect(q.padding.right, CssLength.zero);
      expect(q.margin.left, CssLength.zero);
      expect(q.margin.right, const CssLength.px(2));
      expect(q.maxWidth, const CssLength.percent(100));
    });

    test('and right and left in right-to-left text, inherited or own', () {
      final inherited = style(
        '<div dir="rtl"><blockquote id="x">a</blockquote></div>',
        'x',
        author: quote,
      );
      expect(inherited.borderWidth.right, 3);
      expect(inherited.padding.right, const CssLength.px(16));
      expect(inherited.padding.left, CssLength.zero);
      expect(inherited.margin.left, const CssLength.px(2));
      final own = style(
        '<p id="x">a</p>',
        'x',
        author: 'p { direction: rtl; padding-inline-end: 4px }',
      );
      expect(own.padding.left, const CssLength.px(4));
    });

    test('block sides are the top and the bottom', () {
      final p = style(
        '<p id="x">a</p>',
        'x',
        author: 'p { margin-block: 3px 5px; border-block-end: 1px solid }',
      );
      expect(p.margin.top, const CssLength.px(3));
      expect(p.margin.bottom, const CssLength.px(5));
      expect(p.borderWidth.bottom, 1);
    });

    test('the later of a logical and a physical declaration wins', () {
      expect(
        style(
          '<p id="x">a</p>',
          'x',
          author: 'p { margin-left: 5px; margin-inline-start: 7px }',
        ).margin.left,
        const CssLength.px(7),
      );
      expect(
        style(
          '<p id="x">a</p>',
          'x',
          author: 'p { margin-inline-start: 7px; margin-left: 5px }',
        ).margin.left,
        const CssLength.px(5),
      );
    });
  });

  group('conditional rules', () {
    int color(String author, {CssMediaEnvironment? media}) => style(
      '<p id="x">a</p>',
      'x',
      author: author,
      media: media ?? const CssMediaEnvironment(),
    ).color;

    test('@media queries are evaluated against the environment', () {
      expect(
        color('@media (max-device-width: 480px) { p { color: red } }'),
        0xFFFF0000,
      );
      expect(
        color(
          '@media (max-device-width: 480px) { p { color: red } }',
          media: const CssMediaEnvironment(deviceWidth: 820),
        ),
        0xFF000000,
      );
      expect(
        color('@media (prefers-color-scheme: dark) { p { color: red } }'),
        0xFF000000,
      );
      expect(
        color(
          '@media (prefers-color-scheme: dark) { p { color: red } }',
          media: const CssMediaEnvironment(darkColorScheme: true),
        ),
        0xFFFF0000,
      );
    });

    test('Kindle-only blocks do not apply', () {
      expect(color('@media amzn-mobi { p { color: red } }'), 0xFF000000);
      expect(color('@media amzn-kf8 { p { color: red } }'), 0xFF000000);
      expect(color('@media not amzn-mobi { p { color: red } }'), 0xFFFF0000);
    });

    test('@supports applies what pagecraft supports, nested blocks too', () {
      expect(
        color('@supports (display: flex) { p { color: red } }'),
        0xFFFF0000,
      );
      expect(
        color('@supports (transform: none) { p { color: red } }'),
        0xFF000000,
      );
      expect(
        color(
          '@supports not (transform: none) { @media screen { p { color: red } } }',
        ),
        0xFFFF0000,
      );
    });
  });

  group('tables, positioning and text layout', () {
    test('writing-mode, with the SVG values, inherits', () {
      expect(
        style(
          '<p id="x">a</p>',
          'x',
          author: 'body { writing-mode: tb-rl }',
        ).writingMode,
        CssWritingMode.verticalRl,
      );
      expect(
        style(
          '<p id="x">a</p>',
          'x',
          author: 'html { -epub-writing-mode: vertical-lr }',
        ).writingMode,
        CssWritingMode.verticalLr,
      );
      expect(
        style('<p id="x">a</p>', 'x').writingMode,
        CssWritingMode.horizontalTb,
      );
    });

    test('table borders: collapse and spacing inherit, from the UA too', () {
      final cell = style(
        '<table><tr><td id="x">a</td></tr></table>',
        'x',
        author: 'table { border-collapse: collapse }',
      );
      expect(cell.borderCollapse, isTrue);
      final separate = style('<table id="x"><tr><td>a</td></tr></table>', 'x');
      expect(separate.borderCollapse, isFalse);
      expect(separate.borderSpacingX, 2);
      expect(separate.borderSpacingY, 2);
      expect(separate.boxSizing, CssBoxSizing.borderBox);
      final spaced = style(
        '<table id="x"><tr><td>a</td></tr></table>',
        'x',
        author: 'table { border-spacing: 0.5em 0 }',
      );
      expect(spaced.borderSpacingX, 8);
      expect(spaced.borderSpacingY, 0);
      expect(
        style(
          '<table><caption id="x">c</caption></table>',
          'x',
          author: 'table { caption-side: bottom }',
        ).captionSide,
        CssCaptionSide.bottom,
      );
    });

    test('overflow: one keyword for both axes or x then y; not inherited', () {
      CssOverflow x(String css) => style(
        '<table id="x"><tr><td>a</td></tr></table>',
        'x',
        author: 'table { $css }',
      ).overflowX;
      expect(x(''), CssOverflow.visible);
      expect(x('overflow: auto'), CssOverflow.auto);
      expect(x('overflow: hidden scroll'), CssOverflow.hidden);
      expect(x('overflow-x: scroll'), CssOverflow.scroll);
      expect(x('overflow: clip'), CssOverflow.clip);
      expect(x('overflow: sideways'), CssOverflow.visible, reason: 'invalid');
      expect(x('overflow: auto auto auto'), CssOverflow.visible);
      expect(CssOverflow.auto.scrolls, isTrue);
      expect(CssOverflow.scroll.scrolls, isTrue);
      expect(CssOverflow.hidden.scrolls, isFalse);
      expect(
        style(
          '<div style="overflow: auto"><p id="x">a</p></div>',
          'x',
        ).overflowX,
        CssOverflow.visible,
      );
    });

    test('width as an intrinsic size: no length, the keyword kept', () {
      ComputedStyle table(String width) => style(
        '<table id="x"><tr><td>a</td></tr></table>',
        'x',
        author: 'table { width: $width }',
      );
      final max = table('max-content');
      expect(max.width, isNull);
      expect(max.widthKeyword, CssSizeKeyword.maxContent);
      expect(table('min-content').widthKeyword, CssSizeKeyword.minContent);
      expect(table('fit-content').widthKeyword, CssSizeKeyword.fitContent);
      final set = table('20px');
      expect(set.width, const CssLength.px(20));
      expect(set.widthKeyword, isNull);
      expect(table('auto').widthKeyword, isNull);
      // A later length wins over a keyword before it.
      final later = style(
        '<table id="x" style="width: 10%"><tr><td>a</td></tr></table>',
        'x',
        author: 'table { width: max-content }',
      );
      expect(later.width, const CssLength.percent(10));
      expect(later.widthKeyword, isNull);
    });

    test('position and offsets: em in px, percentages kept, auto null', () {
      final sup = style(
        '<p><sup id="x">1</sup></p>',
        'x',
        author: 'sup { position: relative; top: -0.5em; left: 10% }',
      );
      expect(sup.position, CssPosition.relative);
      // sup's font is `smaller`: 16px / 1.2.
      expect(sup.offsets.top, const CssLength.px(-0.5 * 16 / 1.2));
      expect(sup.offsets.left, const CssLength.percent(10));
      expect(sup.offsets.right, isNull);
      expect(sup.offsets.bottom, isNull);
      // Offsets do not inherit.
      expect(
        style(
          '<div style="position: relative; top: 2px"><p id="x">a</p></div>',
          'x',
        ).offsets.top,
        isNull,
      );
    });

    test('corner radii resolve em and keep percentages', () {
      final box = style(
        '<p id="x">a</p>',
        'x',
        author: 'p { border-radius: 0.5em 50% / 4px }',
      );
      expect(
        box.borderRadius.topLeft,
        const CssRadius(CssLength.px(8), CssLength.px(4)),
      );
      expect(
        box.borderRadius.topRight,
        const CssRadius(CssLength.percent(50), CssLength.px(4)),
      );
      expect(style('<p id="x">a</p>', 'x').borderRadius.topLeft.isZero, isTrue);
    });

    test('box-sizing, wrapping, quotes and list markers', () {
      expect(
        style(
          '<p id="x">a</p>',
          'x',
          author: 'p { -moz-box-sizing: border-box }',
        ).boxSizing,
        CssBoxSizing.borderBox,
      );
      final wrapped = style(
        '<p id="x">a</p>',
        'x',
        author: 'body { word-wrap: break-word; word-break: break-all }',
      );
      expect(wrapped.overflowWrap, CssOverflowWrap.breakWord);
      expect(wrapped.wordBreak, CssWordBreak.breakAll);
      expect(
        style(
          '<p><q id="x">a</q></p>',
          'x',
          author: 'q { quotes: none }',
        ).quotes,
        isEmpty,
      );
      expect(
        style(
          '<p><q id="x">a</q></p>',
          'x',
          author: 'p { quotes: "«" "»" }',
        ).quotes,
        ['«', '»'],
      );
      expect(style('<p><q id="x">a</q></p>', 'x').quotes, isNull);
      expect(
        style(
          '<ul><li id="x">a</li></ul>',
          'x',
          author: 'ul { list-style: square inside }',
        ).listStyleInside,
        isTrue,
      );
    });

    test('text-align: match-parent takes the parent alignment', () {
      expect(
        style(
          '<div style="text-align: right"><p id="x">a</p></div>',
          'x',
          author: 'p { text-align: center; text-align: -webkit-match-parent }',
        ).textAlign,
        CssTextAlign.right,
      );
    });

    test('viewport units resolve against the environment', () {
      expect(
        style(
          '<p id="x">a</p>',
          'x',
          author: 'p { margin-left: 10vw; margin-top: 10vh }',
          options: const StyleResolverOptions(
            viewportWidth: 400,
            viewportHeight: 800,
          ),
        ).margin.left,
        const CssLength.px(40),
      );
    });
  });

  group('ComputedStyles', () {
    test('text nodes take the parent style and identical styles are shared', () {
      final doc = ContentDocument.parseXml(
        '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>one</p><p>two</p><p class="x">three</p></body></html>',
      );
      final styles = StyleResolver([
        ua,
        CssSheetSource(
          CssStyleSheet.parse('.x { color: red }'),
          CssOrigin.author,
        ),
      ]).resolve(doc);
      final body = doc.firstChildOf(0);
      final p1 = doc.childAt(body, 0);
      final p2 = doc.childAt(body, 1);
      final p3 = doc.childAt(body, 2);
      expect(styles[doc.firstChildOf(p1)], same(styles[p1]));
      expect(styles[p1], same(styles[p2]));
      expect(styles[p3], isNot(same(styles[p1])));
      expect(styles.distinctStyleCount, 4, reason: 'html, body, p, p.x');
      expect(styles.rootFontSize, 16);
    });
  });
}
