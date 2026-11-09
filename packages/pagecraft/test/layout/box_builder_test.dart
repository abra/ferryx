import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// A section from [body] markup with the user-agent sheet and [css].
({ContentDocument doc, SectionBoxes boxes}) build(
  String body, {
  String css = '',
  TextHyphenation hyphenation = const TextHyphenation(),
}) {
  final doc = ContentDocument.parseXml(
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:xlink="http://www.w3.org/1999/xlink" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>T</title></head>'
    '<body>$body</body></html>',
  );
  final styles = StyleResolver([
    CssSheetSource(
      CssStyleSheet.parse(cssUserAgentStyleSheet),
      CssOrigin.userAgent,
    ),
    CssSheetSource(CssStyleSheet.parse(css), CssOrigin.author),
  ]).resolve(doc);
  return (
    doc: doc,
    boxes: buildSectionBoxes(doc, styles, hyphenation: hyphenation),
  );
}

/// The boxes below `<body>`, one line each, indented by depth.
String describe(String body, {String css = ''}) {
  final (:doc, :boxes) = build(body, css: css);
  final html = boxes.root;
  final bodyBox = html.children.single as BlockBox;
  final out = <String>[];
  void walk(LayoutBox box, int depth) {
    final pad = '  ' * depth;
    switch (box) {
      case ParagraphBox(:final text, :final indentFirstLine):
        final shown = text
            .replaceAll('\n', '⏎')
            .replaceAll(objectReplacementCharacter, '▣');
        out.add('$pad"$shown"${indentFirstLine ? '' : ' (no indent)'}');
      case TableCellBox():
        out.add(
          '${pad}cell ${doc.localNameOf(box.node)}'
          '${box.columnSpan > 1 ? ' colspan ${box.columnSpan}' : ''}',
        );
        for (final child in box.children) {
          walk(child, depth + 1);
        }
      case BlockBox(:final children, :final marker):
        out.add(
          '$pad${doc.localNameOf(box.node)}${marker == null ? '' : ' [$marker]'}',
        );
        for (final child in children) {
          walk(child, depth + 1);
        }
      case ImageBox(:final src, :final viewBox):
        out.add(
          '${pad}image $src${viewBox == null ? '' : ' ${viewBox.width.toInt()}x${viewBox.height.toInt()}'}',
        );
      case FloatBox(:final content, :final left):
        out.add('${pad}float ${left ? 'left' : 'right'}');
        walk(content, depth + 1);
      case TableBox(:final rows, :final caption):
        out.add('${pad}table ${box.columnCount} columns');
        if (caption != null) walk(caption, depth + 1);
        for (final row in rows) {
          out.add('$pad  row${row.isHeader ? ' (header)' : ''}');
          for (final cell in row.cells) {
            walk(cell, depth + 2);
          }
        }
    }
  }

  for (final child in bodyBox.children) {
    walk(child, 0);
  }
  return out.join('\n');
}

/// The text of the only paragraph [body] makes.
String text(String body, {String css = ''}) =>
    build(body, css: css).boxes.paragraphs.single.text;

void main() {
  group('block structure', () {
    test('inline content beside blocks goes into anonymous paragraphs', () {
      expect(
        describe('<div>a<p>b</p>c<span>d</span></div>'),
        'div\n'
        '  "a"\n'
        '  p\n'
        '    "b"\n'
        '  "cd" (no indent)',
      );
    });

    test('a block inside an inline splits it', () {
      expect(
        describe('<p><span>a <em>b<div>c</div>d</em> e</span></p>'),
        'p\n'
        '  "a b"\n'
        '  div\n'
        '    "c"\n'
        '  "d e" (no indent)',
      );
    });

    test('whitespace-only content makes no paragraph', () {
      expect(
        describe('\n  <p>a</p>\n  <p> </p>\n  <div>\n</div>\n'),
        'p\n  "a"\np\ndiv',
      );
    });

    test('display none, skipped elements and display contents', () {
      expect(
        describe(
          '<p>a<span style="display:none">hidden</span>b</p>'
          '<div style="display: contents"><p>c</p></div>'
          '<video src="v.mp4">fallback</video><script>x()</script>',
        ),
        'p\n  "ab"\np\n  "c"',
      );
    });

    test('lists number their items', () {
      expect(
        describe(
          '<ul><li>a</li><li>b<ul><li>c</li></ul></li></ul>'
          '<ol start="3"><li>x</li><li value="10">y</li><li>z</li></ol>'
          '<ol reversed="reversed"><li>p</li><li>q</li></ol>'
          '<ol style="list-style-type: upper-roman"><li>r</li><li>s</li></ol>'
          '<ul style="list-style: none"><li>t</li></ul>'
          '<ul style=\'list-style-type: "→ "\'><li>u</li></ul>',
        ),
        'ul\n'
        '  li [•]\n'
        '    "a"\n'
        '  li [•]\n'
        '    "b"\n'
        '    ul\n'
        '      li [◦]\n'
        '        "c"\n'
        'ol\n'
        '  li [3. ]\n'
        '    "x"\n'
        '  li [10. ]\n'
        '    "y"\n'
        '  li [11. ]\n'
        '    "z"\n'
        'ol\n'
        '  li [2. ]\n'
        '    "p"\n'
        '  li [1. ]\n'
        '    "q"\n'
        'ol\n'
        '  li [I. ]\n'
        '    "r"\n'
        '  li [II. ]\n'
        '    "s"\n'
        'ul\n'
        '  li\n'
        '    "t"\n'
        'ul\n'
        '  li [→ ]\n'
        '    "u"',
      );
    });

    test('tables: caption, header and footer order, spans, loose cells', () {
      expect(
        describe(
          '<table><caption>Cap</caption>'
          '<tfoot><tr><td>f</td></tr></tfoot>'
          '<tbody><tr><td colspan="2">a</td><td>b</td></tr></tbody>'
          '<thead><tr><th>h1</th><th>h2</th></tr></thead>'
          '<tr><td>c</td></tr>'
          '<td>loose</td></table>',
        ),
        'table 3 columns\n'
        '  caption\n'
        '    "Cap"\n'
        '  row (header)\n'
        '    cell th\n'
        '      "h1"\n'
        '    cell th\n'
        '      "h2"\n'
        '  row\n'
        '    cell td colspan 2\n'
        '      "a"\n'
        '    cell td\n'
        '      "b"\n'
        '  row\n'
        '    cell td\n'
        '      "c"\n'
        '  row\n'
        '    cell td\n'
        '      "loose"\n'
        '  row\n'
        '    cell td\n'
        '      "f"',
      );
    });

    test('images: inline, block, floated and SVG wrappers', () {
      final (:doc, :boxes) = build(
        '<p>a <img src="i.png" alt="I"/> b</p>'
        '<p><img src="block.png" style="display:block"/></p>'
        '<p><img src="float.png" style="float:right"/>text</p>'
        '<div><svg viewBox="0 0 600 800"><image width="600" height="800" xlink:href="cover.jpg"/></svg></div>'
        '<svg><rect width="1" height="1"/></svg>'
        '<p><img alt="no source"/></p>'
        '<p><img recindex="00012"/></p>',
      );
      expect(boxes.imageSources, [
        'i.png',
        'block.png',
        'float.png',
        'cover.jpg',
        startsWith('data:image/svg+xml;base64,'),
        'recindex:00012',
      ]);
      final paragraphs = boxes.paragraphs.toList();
      expect(paragraphs.first.text, 'a $objectReplacementCharacter b');
      final image = paragraphs.first.atomics.single as InlineImage;
      expect(image.offset, 2);
      expect(image.src, 'i.png');
      expect(image.alt, 'I');
      expect(doc.localNameOf(image.node), 'img');
      expect(
        describe(
          '<p><img src="block.png" style="display:block"/></p>'
          '<p><img src="float.png" style="float:right"/>text</p>'
          '<div><svg viewBox="0 0 600 800"><image width="600" height="800" xlink:href="cover.jpg"/></svg></div>'
          '<svg><rect width="1" height="1"/></svg>'
          '<div><svg><image width="30" height="40" href="a.png"/></svg></div>',
        ),
        'p\n'
        '  image block.png\n'
        'p\n'
        '  float right\n'
        '    image float.png\n'
        '  "text"\n'
        'div\n'
        '  image cover.jpg 600x800\n'
        '"▣" (no indent)\n'
        'div\n'
        '  image a.png 30x40',
        reason: 'an SVG of its own drawing is an image of itself',
      );
    });

    test(
      'raised and lowered text becomes one atomic with its own paragraph',
      () {
        final (:doc, :boxes) = build(
          '<p>E = mc<sup>2</sup> and H<sub> 2 </sub>O'
          '<a href="#n"><span style="vertical-align: super; font-size: 0.6em">'
          '<b>12</b><img src="i.png"/></span></a>'
          '<span style="vertical-align: middle">m</span>'
          '<span style="vertical-align: 0">z</span></p>',
        );
        final paragraph = boxes.paragraphs.single;
        expect(
          paragraph.text,
          'E = mc\uFFFC and H\uFFFCO\uFFFCmz',
          reason: 'middle and zero stay on the baseline',
        );
        final texts = paragraph.atomics.whereType<InlineText>().toList();
        expect(texts.map((t) => t.paragraph.text), ['2', '2', '12\uFFFC']);
        expect(texts.map((t) => t.style.verticalAlign), [
          CssVerticalAlign.sup,
          CssVerticalAlign.sub,
          CssVerticalAlign.sup,
        ]);
        expect(doc.attributeOf(texts.last.link, 'href'), '#n');
        expect(texts.last.paragraph.atomics.single, isA<InlineImage>());
        expect(texts.first.parentFontSize, 16);
        expect(texts.first.style.fontSize, closeTo(16 / 1.2, 1e-9));
        expect(texts.last.paragraph.runs.first.style.isBold, isTrue);
        expect(paragraph.nestedParagraphs, hasLength(3));
        expect(boxes.imageSources, ['i.png']);
        final two = texts.first.paragraph.sourceMap.toSource(0)!;
        expect(doc.textOf(two.node), '2');
        expect(
          paragraph.sourceMap.toSource(6),
          (node: texts.first.node, offset: 0),
          reason: 'the atomic stands for the element',
        );
      },
    );

    test('links reach inline runs, images and blocks inside them', () {
      final (:doc, :boxes) = build(
        '<p>a <a href="#n1">note <img src="x.png"/></a> b</p>'
        '<a href="#c"><div>block link</div></a>',
      );
      final paragraphs = boxes.paragraphs.toList();
      final runs = paragraphs.first.runs;
      final linked = [
        for (final r in runs)
          if (r.link >= 0) r,
      ];
      expect(linked.map((r) => r.link).toSet(), hasLength(1));
      expect(doc.attributeOf(linked.first.link, 'href'), '#n1');
      expect(
        paragraphs.first.text.substring(linked.first.start, linked.last.end),
        'note $objectReplacementCharacter',
        reason: 'the image has its own style run, under the same link',
      );
      expect(
        (paragraphs.first.atomics.single as InlineImage).link,
        linked.first.link,
      );
      expect(doc.attributeOf(paragraphs.last.runs.single.link, 'href'), '#c');
    });

    test('quotes for q follow language and nesting', () {
      expect(text('<p><q>a <q>b</q></q></p>'), '“a ‘b’”');
      expect(text('<p lang="ru"><q>a <q>b</q></q></p>'), '«a „b“»');
      expect(text('<p xml:lang="de-AT"><q>a</q></p>'), '„a“');
      expect(text('<p><q lang="ja">a</q></p>'), '「a」');
      // Deeper than the pairs go, the last pair repeats.
      expect(text('<p><q>a <q>b <q>c</q></q></q></p>'), '“a ‘b ‘c’’”');
    });

    test('quotes: none, or the book\'s pairs by nesting', () {
      expect(text('<p><q>a</q></p>', css: 'q { quotes: none }'), 'a');
      expect(
        text(
          '<p><q>a <q>b</q></q></p>',
          css: 'p { quotes: "<" ">" "[" "]" }',
        ),
        '<a [b]>',
      );
    });

    test('decorated inline elements: their range, spacers at their edges', () {
      final (doc: _, :boxes) = build(
        '<p>a <code>b c</code> d</p>',
        css: 'code { background: #eee; padding: 0 4px }',
      );
      final p = boxes.paragraphs.single;
      expect(p.text, 'a \uFFFCb c\uFFFC d');
      expect(p.decorations.map((d) => d.toString()), ['[2, 7)']);
      final spacers = p.atomics.whereType<InlineSpacer>().toList();
      expect(spacers.map((a) => (a.offset, a.isStart)), [
        (2, true),
        (6, false),
      ]);
      expect(p.plainText(0, p.text.length), 'a b c d', reason: 'not copied');
    });

    test('a border alone decorates without taking room in the line', () {
      final (doc: _, :boxes) = build(
        '<p>x <a href="#n">y z</a> w</p>',
        css: 'a { border-bottom: 1px solid }',
      );
      final p = boxes.paragraphs.single;
      expect(p.text, 'x y z w');
      expect(p.decorations.map((d) => d.toString()), ['[2, 5)']);
      expect(p.atomics, isEmpty);
    });

    test('a margin takes room without a decoration', () {
      final (doc: _, :boxes) = build(
        '<p>x<span>y</span></p>',
        css: 'span { margin-left: 5px }',
      );
      final p = boxes.paragraphs.single;
      expect(p.text, 'x\uFFFCy\uFFFC');
      expect(p.decorations, isEmpty);
    });

    test('nested decorations: outer first; a block inside splits them', () {
      final (doc: _, boxes: nested) = build(
        '<p><code>a<em>b</em></code></p>',
        css: 'code, em { background: #eee }',
      );
      expect(
        nested.paragraphs.single.decorations.map((d) => d.toString()),
        ['[0, 2)', '[1, 2)'],
      );
      final (doc: _, boxes: split) = build(
        '<p><span>a<div>b</div>c</span></p>',
        css: 'span { background: #eee }',
      );
      final [a, b, c] = split.paragraphs.toList();
      expect(a.decorations.map((d) => d.toString()), ['[0, 1)']);
      expect(b.decorations, isEmpty, reason: 'the block is not the span');
      expect(c.decorations.map((d) => d.toString()), ['[0, 1)']);
    });

    test('::before and ::after: strings, attributes, transforms', () {
      expect(
        text(
          '<p class="by">Name</p>',
          css:
              '.by::before { content: "\\2014  " } .by::after { content: "." }',
        ),
        '— Name.',
      );
      expect(
        text(
          '<p><a href="x.html">link</a></p>',
          css: 'a::after { content: " (" attr(href) ")" }',
        ),
        'link (x.html)',
      );
      expect(
        text(
          '<p>tip</p>',
          css: 'p::before { content: "pro "; text-transform: uppercase }',
        ),
        'PRO tip',
      );
      // Print features browsers drop leave no content.
      expect(
        text(
          '<p>a</p>',
          css: 'p::after { content: target-counter(attr(href), page) }',
        ),
        'a',
      );
    });

    test('generated text is not the document\'s', () {
      final (:doc, :boxes) = build(
        '<p>a</p>',
        css: 'p::before { content: ">" }',
      );
      final p = boxes.paragraphs.single;
      expect(p.text, '>a');
      final a = doc.firstChildOf(p.node);
      // The generated mark maps to where the document's text begins.
      expect(p.sourceMap.toSource(0), (node: a, offset: 0));
      expect(p.sourceMap.toParagraph(a, 0), 1);
    });

    test('counters: reset, increment, nesting with counters()', () {
      final (doc: _, :boxes) = build(
        '<ol><li>a</li><li>b</li></ol>'
        '<section><h2>x</h2><section><h2>y</h2><h2>z</h2></section></section>',
        css:
            'ol { counter-reset: n; list-style: none } '
            'li::before { counter-increment: n; content: counter(n) ". " } '
            'section { counter-reset: s } '
            'h2::before { counter-increment: s; '
            'content: counters(s, ".", upper-roman) " " }',
      );
      expect(boxes.paragraphs.map((p) => p.text), [
        '1. a',
        '2. b',
        'I x',
        'I.I y',
        'I.II z',
      ]);
    });

    test('a block ::before is a block of its own', () {
      expect(
        describe(
          '<div class="note"><p>body</p></div>',
          css: '.note::before { content: "Note"; display: block }',
        ),
        'div\n'
        '  div\n'
        '    "Note"\n'
        '  p\n'
        '    "body"',
      );
      // Empty and out of the flow: nothing.
      expect(
        describe(
          '<div class="x"><p>body</p></div>',
          css:
              '.x::after { content: ""; display: table; clear: both } '
              '.x::before { content: "*"; position: absolute }',
        ),
        'div\n'
        '  p\n'
        '    "body"',
      );
    });

    test('q takes its quotes from content; none takes them away', () {
      expect(text('<p><q>a</q></p>'), '“a”');
      expect(
        text('<p><q>a</q></p>', css: 'q::before, q::after { content: none }'),
        'a',
      );
      expect(
        text('<p><q>a</q></p>', css: 'q:before { content: "" }'),
        'a”',
      );
    });

    test('an empty sized inline-block is a box; an image is content', () {
      final (doc: _, :boxes) = build(
        '<ul><li>a</li></ul><p class="c">x<span class="sw"></span></p>',
        css:
            'li::before { content: ""; display: inline-block; width: 4px; '
            'height: 4px; background: red } '
            '.sw { display: inline-block; width: 8px; height: 8px } '
            '.c::after { content: url(i.png) }',
      );
      final [li, p] = boxes.paragraphs.toList();
      expect(li.atomics.single, isA<InlineBox>());
      expect(li.text, '\uFFFCa');
      expect(p.atomics.whereType<InlineBox>(), hasLength(1));
      final image = p.atomics.whereType<InlineImage>().single;
      expect(image.src, 'i.png');
      expect(boxes.imageSources, contains('i.png'));
    });

    test('content images are relative to their style sheet', () {
      final doc = ContentDocument.parseXml(
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<section>x</section></body></html>',
      );
      final styles = StyleResolver([
        CssSheetSource(
          CssStyleSheet.parse(cssUserAgentStyleSheet),
          CssOrigin.userAgent,
        ),
        CssSheetSource(
          CssStyleSheet.parse('section::after { content: url(img/f.png) }'),
          CssOrigin.author,
          baseHref: 'OEBPS/css/book.css',
        ),
      ]).resolve(doc);
      final boxes = buildSectionBoxes(doc, styles);
      expect(boxes.imageSources, ['/OEBPS/css/img/f.png']);
    });

    test('list markers outside, or inside starting the first line', () {
      expect(
        describe('<ul><li>a</li></ul>'),
        'ul\n'
        '  li [•]\n'
        '    "a"',
      );
      expect(
        describe(
          '<ol style="list-style-position: inside"><li><p>a</p></li><li>b</li></ol>',
        ),
        'ol\n'
        '  li\n'
        '    p\n'
        '      "1. a"\n'
        '  li\n'
        '    "2. b"',
      );
      // An item with no line of its own keeps no marker.
      expect(
        describe('<ul style="list-style: inside"><li></li><li>b</li></ul>'),
        'ul\n'
        '  li\n'
        '  li\n'
        '    "• b"',
      );
    });

    test('runs split where the style or the link changes', () {
      final (doc: _, :boxes) = build('<p>a <b>b</b><b>c</b> <i>d</i></p>');
      final paragraph = boxes.paragraphs.single;
      expect(paragraph.text, 'a bc d');
      expect(paragraph.runs.map((r) => r.toString()), [
        '[0, 2)',
        '[2, 4)',
        '[4, 5)',
        '[5, 6)',
      ]);
      expect(paragraph.runs[1].style.isBold, isTrue);
      expect(paragraph.runs[3].style.isItalic, isTrue);
      expect(
        identical(paragraph.runs[0].style, paragraph.runs[2].style),
        isTrue,
      );
    });

    test('prose: paragraphs, list items, quotes and text-only divs', () {
      final (:doc, :boxes) = build(
        '<p>p</p><div>plain <b>div</b></div><div>div <img src="x"/></div>'
        '<blockquote>q<p>qp</p></blockquote><ul><li>li</li></ul>'
        '<h1>h</h1><section>s</section><dl><dd>dd</dd></dl>',
      );
      final prose = {
        for (final p in boxes.paragraphs)
          doc.textContentOf(p.node).trim(): p.isProse,
      };
      expect(prose, {
        'p': true,
        'plain div': true,
        'div': false,
        'qqp': true,
        'qp': true,
        'li': true,
        'h': false,
        's': false,
        'dd': true,
      });
      final body = boxes.root.children.single as BlockBox;
      final blocks = [for (final b in body.children) (b as BlockBox).isProse];
      expect(blocks, [true, true, false, true, false, false, false, false]);
      final headings = [
        for (final b in body.children) (b as BlockBox).isHeading,
      ];
      expect(headings, [false, false, false, false, false, true, false, false]);
    });

    test('text-indent applies to a block\'s first box only', () {
      final boxes = build('<div>a<p>b</p>c</div>').boxes.paragraphs.toList();
      expect(boxes.map((p) => p.indentFirstLine), [true, true, false]);
    });

    test('very deep nesting is flattened instead of overflowing', () {
      final open = List.filled(400, '<div><span>').join();
      final close = List.filled(400, '</span></div>').join();
      final (doc: _, :boxes) = build('$open deep text $close');
      expect(boxes.paragraphs.single.text, 'deep text');
    });
  });

  group('floats', () {
    test('a float before a line\'s first content leaves the flow', () {
      expect(
        describe(
          '<p><span style="float: left">I</span>n the beginning</p>'
          '<div style="float: right; width: 3em">side</div><p>after</p>',
        ),
        'p\n'
        '  float left\n'
        '    span\n'
        '      "I"\n'
        '  "n the beginning"\n'
        'float right\n'
        '  div\n'
        '    "side"\n'
        'p\n'
        '  "after"',
        reason: 'the paragraph beside a float keeps its indent',
      );
    });

    test('leading white space does not count as content', () {
      expect(
        describe(
          '<p>\n  <img src="a.png" style="float: left"/> text</p>',
        ),
        'p\n'
        '  float left\n'
        '    image a.png\n'
        '  "text"',
      );
    });

    test('a float inside a line stays there; an image ends the paragraph', () {
      expect(
        describe('<p>ab <span style="float: left">c</span> d</p>'),
        'p\n'
        '  "ab c d"',
      );
      expect(
        describe('<p>ab <img src="x.png" style="float: right"/> cd</p>'),
        'p\n'
        '  "ab"\n'
        '  float right\n'
        '    image x.png\n'
        '  "cd" (no indent)',
      );
    });

    test('absolute and fixed positions do not float', () {
      expect(
        describe(
          '<p><span style="float: left; position: absolute">a</span>b</p>',
        ),
        'p\n'
        '  "ab"',
      );
    });

    test('a floated table is the float\'s content', () {
      expect(
        describe(
          '<table style="float: left"><tr><td>a</td></tr></table><p>b</p>',
        ),
        'float left\n'
        '  table 1 columns\n'
        '    row\n'
        '      cell td\n'
        '        "a"\n'
        'p\n'
        '  "b"',
      );
    });

    test('the paragraphs of floats are in document order', () {
      final (doc: _, :boxes) = build(
        '<p><span style="float: left">I</span>n the</p>',
      );
      expect([for (final p in boxes.paragraphs) p.text], ['I', 'n the']);
    });
  });

  group('svg', () {
    String document(String src) {
      expect(src, startsWith('data:image/svg+xml;base64,'));
      return utf8.decode(base64.decode(src.substring(src.indexOf(',') + 1)));
    }

    test('an SVG in the markup is an image of itself', () {
      final (doc: _, :boxes) = build(
        '<p>a <svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" '
        'viewBox="0 0 2 1"><style>.c { fill: red } a &gt; b</style>'
        '<rect class="c" width="2" height="1" data-x="&quot;1&lt;2&quot;"/>'
        '<text>A &amp; B</text></svg> b</p>',
      );
      final paragraph = boxes.paragraphs.single;
      final image = paragraph.atomics.single as InlineImage;
      expect(boxes.imageSources, [image.src]);
      final svg = document(image.src);
      expect(svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
      expect(svg, contains('xmlns:xlink="http://www.w3.org/1999/xlink"'));
      expect(svg, contains('viewBox="0 0 2 1"'));
      expect(svg, contains('<style>.c { fill: red } a &gt; b</style>'));
      expect(svg, contains('data-x="&quot;1&lt;2&quot;"'));
      expect(svg, contains('<text>A &amp; B</text>'));
      expect(svg, endsWith('</svg>'));
      expect(paragraph.text, 'a $objectReplacementCharacter b');
    });

    test('a block-level SVG is a block image; a cover stays its image', () {
      final (doc: _, :boxes) = build(
        '<svg style="display: block" width="1" height="1"><circle r="1"/></svg>'
        '<div><svg viewBox="0 0 6 8"><image width="6" height="8" '
        'xlink:href="cover.jpg"/></svg></div>',
      );
      final images = [
        for (final box in (boxes.root.children.single as BlockBox).children)
          if (box is ImageBox) box else ...(box as BlockBox).children,
      ].whereType<ImageBox>().toList();
      expect(images.first.src, startsWith('data:image/svg+xml'));
      expect(document(images.first.src), contains('<circle r="1"/>'));
      expect(images.last.src, 'cover.jpg');
    });
  });

  group('inline blocks', () {
    test('an inline block around inline content is one unit of its line', () {
      final (doc: _, :boxes) = build(
        '<p>a <span style="display: inline-block; width: 3em">b <em>c</em>'
        '</span> d</p>',
      );
      final paragraph = boxes.paragraphs.first;
      expect(paragraph.text, 'a $objectReplacementCharacter d');
      final block = paragraph.atomics.single as InlineText;
      expect(block.isInlineBlock, isTrue);
      expect(block.paragraph.text, 'b c');
      expect(block.paragraph.indentFirstLine, isFalse);
      expect(paragraph.plainText(0, paragraph.text.length), 'a b c d');
    });

    test('around block-level content it stays inline content', () {
      expect(
        describe(
          '<p>a <span style="display: inline-block"><div>b</div></span> c</p>',
        ),
        'p\n'
        '  "a"\n'
        '  div\n'
        '    "b"\n'
        '  "c" (no indent)',
      );
    });

    test('an empty one with a size is still an inline box', () {
      final (doc: _, :boxes) = build(
        '<p>a<span style="display: inline-block; width: 1em"></span></p>',
      );
      expect(boxes.paragraphs.single.atomics.single, isA<InlineBox>());
    });
  });

  group('white space', () {
    test('collapses runs, across inline boundaries, and trims line ends', () {
      expect(
        text('<p>  a \n\t b  <em>  c</em>   <span> </span> d  </p>'),
        'a b c d',
      );
      expect(text('<p>a<em> </em> b</p>'), 'a b');
    });

    test('forced breaks drop the space before them and the one after', () {
      expect(text('<p>a <br/> b</p>'), 'a\nb');
      expect(text('<p>a<br/><br/>b</p>'), 'a\n\nb');
    });

    test('a trailing break makes no empty line; two make one', () {
      expect(text('<p>a<br/></p>'), 'a');
      expect(text('<p>a<br/><br/></p>'), 'a\n');
    });

    test('segment breaks between CJK characters disappear', () {
      expect(text('<p>中文\n中文</p>'), '中文中文');
      expect(text('<p>中文 \n 中文</p>'), '中文中文');
      expect(text('<p>中文\nabc</p>'), '中文 abc');
      expect(text('<p>中文 中文</p>'), '中文 中文', reason: 'only segment breaks');
      expect(text('<p>a\u200B\nb</p>'), 'a\u200Bb');
    });

    test('pre keeps spaces and line feeds and expands tabs to stops', () {
      expect(
        text('<pre>  a  b\n\tc\nxy\td</pre>'),
        '  a  b\n        c\nxy      d',
      );
      expect(
        text('<pre>a\n</pre>'),
        'a',
        reason: 'a final line feed makes no line',
      );
    });

    test(
      'pre-wrap keeps spaces; pre-line collapses spaces but keeps breaks',
      () {
        expect(text('<p style="white-space: pre-wrap">a  b\nc</p>'), 'a  b\nc');
        expect(
          text('<p style="white-space: pre-line">  a   b  \n  c </p>'),
          'a b\nc',
        );
      },
    );

    test('non-breaking and ideographic spaces never collapse', () {
      expect(
        text('<p>a\u00A0\u00A0 b\u3000\u3000c</p>'),
        'a\u00A0\u00A0 b\u3000\u3000c',
      );
    });

    test('wbr is a zero-width space', () {
      expect(text('<p>long<wbr/>word</p>'), 'long\u200Bword');
    });
  });

  group('text-transform', () {
    test('uppercase, lowercase and capitalize', () {
      expect(
        text('<p style="text-transform: uppercase">straße é</p>'),
        'STRASSE É',
      );
      expect(text('<p style="text-transform: lowercase">ÀB</p>'), 'àb');
      expect(
        text(
          '<p style="text-transform: capitalize">hello «world» 1st (x)-y <b>z</b>z</p>',
        ),
        'Hello «World» 1st (X)-y Zz',
      );
      expect(
        text('<p style="text-transform: capitalize">ǆungla ßa</p>'),
        'ǅungla Ssa',
      );
    });
  });

  group('source map', () {
    test('a paragraph\'s tail is the paragraph from its offset on', () {
      final (doc: _, :boxes) = build(
        '<p>  ab  <em style="background: red"> cd</em>\n ef '
        '<img src="i.png"/> gh</p>',
      );
      final paragraph = boxes.paragraphs.single;
      expect(paragraph.text, 'ab cd ef \uFFFC gh');
      expect(identical(paragraph.tail(0), paragraph), isTrue);
      for (var from = 1; from <= paragraph.text.length; from++) {
        final tail = paragraph.tail(from);
        final reason = 'from $from';
        expect(tail.text, paragraph.text.substring(from), reason: reason);
        expect(tail.indentFirstLine, isFalse, reason: reason);
        expect(tail.isProse, paragraph.isProse, reason: reason);
        if (tail.text.isNotEmpty) {
          expect(tail.runs.first.start, 0, reason: reason);
          expect(tail.runs.last.end, tail.text.length, reason: reason);
        }
        for (final atomic in tail.atomics) {
          expect(tail.text[atomic.offset], '\uFFFC', reason: reason);
          expect(atomic.node, paragraph.atomics.single.node, reason: reason);
        }
        for (final decoration in tail.decorations) {
          expect(decoration.start, greaterThanOrEqualTo(0), reason: reason);
          expect(
            decoration.end,
            paragraph.decorations.single.end - from,
            reason: reason,
          );
        }
        for (var i = 0; i <= tail.text.length; i++) {
          expect(
            tail.sourceMap.toSource(i),
            paragraph.sourceMap.toSource(from + i),
            reason: '$reason @ $i',
          );
          if (i == 0) continue;
          expect(
            tail.sourceMap.toSourceEnd(i),
            paragraph.sourceMap.toSourceEnd(from + i),
            reason: '$reason, end @ $i',
          );
        }
      }
    });

    /// Every source character either maps into the paragraph and back to
    /// itself, or (dropped whitespace) to a point at its neighbours.
    void expectRoundTrip(String body) {
      final (:doc, :boxes) = build(body);
      for (final paragraph in boxes.paragraphs) {
        final map = paragraph.sourceMap;
        for (var i = 0; i < paragraph.text.length; i++) {
          final source = map.toSource(i);
          if (source == null) continue;
          final back = map.toParagraph(source.node, source.offset);
          expect(back, isNotNull, reason: '$body @ $i');
          if (doc.isText(source.node)) {
            final char = paragraph.text[i];
            final original = doc.textOf(source.node);
            if (source.offset < original.length &&
                !RegExp(r'\s').hasMatch(char) &&
                char == original[source.offset]) {
              expect(back, i, reason: '$body @ $i "$char"');
            }
          }
        }
      }
    }

    test('maps copied, collapsed, dropped and transformed text', () {
      final (:doc, :boxes) = build('<p>  ab  <em> cd</em>\n ef  </p>');
      final paragraph = boxes.paragraphs.single;
      expect(paragraph.text, 'ab cd ef');
      final first = doc.firstChildOf(
        doc.elementIndexById('x') == -1 ? paragraph.node : 0,
      );
      expect(doc.textOf(first), '  ab  ');
      final em = doc.nextSiblingOf(first);
      final cd = doc.firstChildOf(em);
      final ef = doc.nextSiblingOf(em);
      final map = paragraph.sourceMap;
      expect(map.toSource(0), (
        node: first,
        offset: 2,
      ), reason: 'leading spaces dropped');
      expect(map.toSource(1), (node: first, offset: 3));
      expect(map.toSource(2), (
        node: first,
        offset: 4,
      ), reason: 'the collapsed space starts it');
      expect(map.toSource(3), (node: cd, offset: 1));
      expect(map.toSource(5), (node: ef, offset: 0));
      expect(map.toSource(8), (node: ef, offset: 4), reason: 'end of the text');
      // Range ends: the earlier segment wins at a boundary.
      expect(map.toSourceEnd(2), (node: first, offset: 4), reason: 'after ab');
      expect(
        map.toSourceEnd(3),
        (node: first, offset: 6),
        reason: 'after the whole collapsed run',
      );
      expect(map.toSourceEnd(5), (node: cd, offset: 3));
      expect(map.toSourceEnd(8), (node: ef, offset: 4));
      expect(map.toParagraph(first, 0), 0);
      expect(map.toParagraph(first, 3), 1);
      expect(
        map.toParagraph(first, 5),
        3,
        reason: 'inside the collapsed run: its end',
      );
      expect(
        map.toParagraph(cd, 0),
        3,
        reason: 'absorbed space: where it went',
      );
      expect(map.toParagraph(cd, 3), 5);
      expect(map.toParagraph(ef, 6), 8, reason: 'trailing spaces dropped');
      expect(
        map.toParagraph(em, 0),
        isNull,
        reason: 'elements without characters',
      );
      expect(map.firstNode, first);
      expect(map.lastNode, ef);
    });

    test('maps images, breaks and expanded characters to their sources', () {
      final (:doc, :boxes) = build(
        '<p style="text-transform: uppercase">ß<img src="a.png"/>b<br/>c</p>',
      );
      final paragraph = boxes.paragraphs.single;
      expect(paragraph.text, 'SS${objectReplacementCharacter}B\nC');
      final map = paragraph.sourceMap;
      final sharp = doc.firstChildOf(paragraph.node);
      final img = doc.nextSiblingOf(sharp);
      expect(map.toSource(0), (node: sharp, offset: 0));
      expect(map.toSource(1), (
        node: sharp,
        offset: 1,
      ), reason: 'the second S ends the ß');
      expect(map.toSource(2), (node: img, offset: 0));
      expect(doc.localNameOf(map.toSource(4)!.node), 'br');
      expect(map.toParagraph(sharp, 1), 2);
    });

    test('generated quotes have no source of their own', () {
      final (:doc, :boxes) = build('<p>a <q>b</q>c</p>');
      final paragraph = boxes.paragraphs.single;
      expect(paragraph.text, 'a “b”c');
      final a = doc.firstChildOf(paragraph.node);
      final q = doc.nextSiblingOf(a);
      final b = doc.firstChildOf(q);
      final map = paragraph.sourceMap;
      expect(
        map.toSource(2),
        (node: a, offset: 2),
        reason: 'before the opening quote: the end of the text before it',
      );
      expect(map.toSource(3), (node: b, offset: 0));
      expect(map.toSource(4), (node: b, offset: 1));
      expect(
        map.toSource(5),
        (node: doc.nextSiblingOf(q), offset: 0),
        reason: 'inside generated text: the next source',
      );
    });

    test('round trips over assorted markup', () {
      for (final body in [
        '<p>  a  b  </p>',
        '<p>a<em> b </em> c<br/> d</p>',
        '<pre>\ta\n  b\t</pre>',
        '<p style="white-space: pre-line"> a \n b </p>',
        '<p style="text-transform: capitalize">a ßb ǆ</p>',
        '<p style="white-space: pre-line">a \n  \n b<br/>  c</p>',
        '<p>中文\n中文 x <q>y</q> <img src="i"/> z</p>',
      ]) {
        expectRoundTrip(body);
      }
    });
  });

  group('hyphenation', () {
    /// The first paragraph's text with its soft hyphens as `|`.
    String breaks(
      String body, {
      String css = 'p { hyphens: auto }',
      TextHyphenation hyphenation = const TextHyphenation(),
    }) => build(
      body,
      css: css,
      hyphenation: hyphenation,
    ).boxes.paragraphs.first.text.replaceAll(softHyphen, '|');

    test('hyphens: auto puts soft hyphens at the language\'s breaks', () {
      expect(
        breaks('<p lang="en">hyphenation of <b>paragraphs</b></p>'),
        'hy|phen|ation of para|graphs',
      );
      expect(breaks('<p lang="ru">переменные</p>'), 'пе|ре|мен|ные');
    });

    test('the language comes from the nearest lang or xml:lang', () {
      expect(
        breaks(
          '<div lang="ru"><p>переменные <i lang="en">hyphenation</i></p></div>',
        ),
        'пе|ре|мен|ные hy|phen|ation',
      );
      expect(
        breaks('<p xml:lang="en" lang="ru">hyphenation</p>'),
        'hy|phen|ation',
        reason: 'xml:lang wins, as in XHTML',
      );
      expect(
        breaks('<p>hyphenation</p>'),
        'hyphenation',
        reason: 'no language',
      );
      expect(breaks('<p lang="ja">hyphenation</p>'), 'hyphenation');
    });

    test('only hyphens: auto; manual keeps the book\'s own soft hyphens', () {
      expect(breaks('<p lang="en">hyphenation</p>', css: ''), 'hyphenation');
      expect(
        breaks(
          '<p lang="en">hy&#xAD;phenation <span style="hyphens: manual">hyphenation</span></p>',
        ),
        'hy|phen|ation hyphenation',
      );
      expect(
        breaks('<p lang="en">hy&#xAD;phenation</p>', css: ''),
        'hy|phenation',
      );
    });

    test('words are runs of Latin, Greek and Cyrillic letters', () {
      expect(
        breaks('<p lang="de">Straßenbahnhaltestelle</p>'),
        'Stra|ßen|bahn|hal|te|stel|le',
      );
      expect(
        breaks('<p lang="en">hyphenation2hyphenation’hyphenation</p>'),
        'hy|phen|ation2hy|phen|ation’hy|phen|ation',
        reason: 'digits and apostrophes end a word',
      );
      expect(breaks('<p lang="en">日本語のhyphenation</p>'), '日本語のhy|phen|ation');
    });

    test('limits: shorter words and letters at the edges', () {
      expect(breaks('<p lang="en">open</p>'), 'open', reason: 'four letters');
      expect(
        breaks(
          '<p lang="ru">операторы</p>',
          hyphenation: const TextHyphenation(minBefore: 4),
        ),
        'опера|то|ры',
      );
      expect(
        breaks(
          '<p lang="en">hyphenation</p>',
          hyphenation: const TextHyphenation(minWord: 12),
        ),
        'hyphenation',
      );
    });

    test('soft hyphens are not the document\'s: maps and plain text', () {
      final (:doc, :boxes) = build(
        '<p lang="en">a hyphenation</p>',
        css: 'p { hyphens: auto }',
      );
      final paragraph = boxes.paragraphs.single;
      expect(paragraph.text, 'a hy\u00ADphen\u00ADation');
      expect(paragraph.plainText(0, paragraph.text.length), 'a hyphenation');
      final node = doc.firstChildOf(paragraph.node);
      final map = paragraph.sourceMap;
      expect(map.toSource(5), (node: node, offset: 4), reason: 'the p');
      expect(map.toSource(4), (node: node, offset: 4), reason: 'the hyphen');
      expect(map.toParagraph(node, 4), 5);
      expect(map.toParagraph(node, 12), 14);
    });
  });
}
