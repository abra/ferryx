import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// The parser and the cascade must survive any input: real stylesheets
/// are mutated at random (characters deleted, inserted, duplicated,
/// truncated) and every result must parse and resolve without throwing.
void main() {
  const seeds = [
    '''
@charset "utf-8";
@import url("other.css") screen;
@font-face { font-family: "Book"; src: url(fonts/book.otf) format("opentype"); font-weight: 400; }
@media screen and (max-width: 600px) { p { margin: 0 } }
@page { margin: 1cm; }
html { font-size: 100%; }
body { margin: 0 5%; font-family: "Book", Georgia, serif; line-height: 1.4; color: #222; }
h1, h2, h3 { font-weight: bold; page-break-after: avoid; margin: 1.5em 0 0.5em; }
h1.title::before { content: "\\2014"; }
p { margin: 0; text-indent: 1.5em; text-align: justify; hyphens: auto; }
p.first, p:first-of-type, h1 + p { text-indent: 0; }
blockquote > p:not(.x) { font-style: italic; }
a[href^="http"]:hover { color: rgb(10%, 20%, 30%); text-decoration: underline dotted; }
img { max-width: 100%; height: auto; display: block; margin: 1em auto; }
.footnote { font-size: 0.8em; vertical-align: super; line-height: 0; }
table { border-collapse: collapse; width: 100% !important; }
td, th { border: 1px solid #ccc; padding: 0.25em 0.5em; }
ul li:nth-child(2n+1) { list-style: square inside; }
.dropcap { float: left; font-size: 3em; line-height: 0.8; margin: 0.1em 0.1em 0 0; }
[dir=rtl] { direction: rtl; unicode-bidi: embed; }
:root { --accent: hsl(200, 50%, 50%); }
.x { color: var(--accent); background: url("a.png") no-repeat, linear-gradient(red, blue); }
''',
    'p{color:red;margin:1em 2em 3em;font:italic bold 12px/1.5 "A B",serif}',
  ];
  const alphabet =
      r'{}()[];:,."'
      "'"
      r'/\*!@#%&-+=<> \n\tabcdefxyz0123456789éЖ';

  test('mutated stylesheets never throw while parsing or resolving', () {
    final random = Random(20261029);
    final doc = ContentDocument.parseXml(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body class="x"><h1 class="title">T</h1>'
      '<p class="first">a <a href="http://x">b</a> <span class="footnote">1</span></p>'
      '<blockquote><p>q</p><p class="x">r</p></blockquote>'
      '<ul><li>1</li><li>2</li><li>3</li></ul><table><tr><td>c</td></tr></table></body></html>',
    );
    final ua = CssSheetSource(
      CssStyleSheet.parse(cssUserAgentStyleSheet),
      CssOrigin.userAgent,
    );
    var rules = 0;
    for (var iteration = 0; iteration < 1500; iteration++) {
      var css = seeds[iteration % seeds.length];
      final mutations = 1 + random.nextInt(6);
      for (var m = 0; m < mutations; m++) {
        if (css.isEmpty) break;
        final at = random.nextInt(css.length);
        switch (random.nextInt(5)) {
          case 0:
            css =
                css.substring(0, at) +
                css.substring(min(css.length, at + 1 + random.nextInt(8)));
          case 1:
            css =
                css.substring(0, at) +
                alphabet[random.nextInt(alphabet.length)] +
                css.substring(at);
          case 2:
            final end = min(css.length, at + random.nextInt(20));
            css =
                css.substring(0, at) +
                css.substring(at, end) +
                css.substring(at);
          case 3:
            css = css.substring(0, at);
          default:
            final a = random.nextInt(css.length);
            final b = random.nextInt(css.length);
            final (lo, hi) = a < b ? (a, b) : (b, a);
            css = css.substring(0, lo) + css.substring(hi);
        }
      }
      late CssStyleSheet sheet;
      expect(
        () => sheet = CssStyleSheet.parse(css),
        returnsNormally,
        reason: css,
      );
      rules += sheet.rules.length;
      expect(
        () => StyleResolver([
          ua,
          CssSheetSource(sheet, CssOrigin.author),
        ]).resolve(doc),
        returnsNormally,
        reason: css,
      );
    }
    expect(rules, greaterThan(0));
  });

  test('random bytes tokenize and parse', () {
    final random = Random(7);
    for (var i = 0; i < 300; i++) {
      final length = random.nextInt(200);
      final css = String.fromCharCodes(
        List.generate(length, (_) => random.nextInt(0x3000)),
      );
      expect(() => tokenizeCss(css), returnsNormally);
      expect(() => CssStyleSheet.parse(css), returnsNormally);
      expect(() => CssSelectorList.parseText(css), returnsNormally);
      expect(() => parseCssDeclarations(css), returnsNormally);
    }
  });
}
