import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/layout/math_layout.dart';
import 'package:pagecraft/all_formats.dart';

/// The test font draws every glyph as a square one font size wide, its
/// ascent 0.75 and descent 0.25 of it: formulas lay out to exact numbers.
void main() {
  const style = TextStyle(fontSize: 20, color: Color(0xFF000000));

  MathNode mi(String text) => MathNode('mi', text: text);
  MathNode mn(String text) => MathNode('mn', text: text);
  MathNode mo(String text, {Map<String, String> attributes = const {}}) =>
      MathNode('mo', text: text, attributes: attributes);
  MathNode row(List<MathNode> children) => MathNode('mrow', children: children);
  MathNode node(String name, List<MathNode> children) =>
      MathNode(name, children: children);

  MathLayout layOut(MathNode math, {bool display = false}) {
    final layout = MathLayout.layout(
      MathNode('math', children: [math]),
      style,
      display: display,
    );
    addTearDown(layout.dispose);
    return layout;
  }

  test('tokens: one em a glyph on the baseline', () {
    final x = layOut(mi('x'));
    expect(x.width, 20);
    expect(x.ascent, closeTo(15, 0.5));
    expect(x.descent, closeTo(5, 0.5));
    expect(layOut(mn('42')).width, 40);
    expect(layOut(mi('sin')).width, 60);
  });

  test('relations get thick spaces, binary operators medium, a sign none', () {
    // x = y: 5/18 em on each side of "=".
    expect(
      layOut(row([mi('x'), mo('='), mi('y')])).width,
      closeTo(60 + 2 * 20 * 5 / 18, 1e-3),
    );
    // a + b: 4/18 em on each side.
    expect(
      layOut(row([mi('a'), mo('+'), mi('b')])).width,
      closeTo(60 + 2 * 20 * 4 / 18, 1e-3),
    );
    // −a: a sign before its operand takes no space.
    expect(layOut(row([mo('-'), mi('a')])).width, 40);
    // In a script no binary or relation spacing.
    final script = layOut(
      node('msup', [
        mi('x'),
        row([mi('a'), mo('+'), mi('b')]),
      ]),
    );
    expect(script.width, closeTo(20 + 20 * 0.04 + 3 * 20 * 0.71, 1e-3));
    expect(
      layOut(
        row([
          mi('a'),
          mo('=', attributes: {'lspace': '0', 'rspace': '0'}),
          mi('b'),
        ]),
      ).width,
      60,
      reason: 'lspace and rspace override',
    );
  });

  test('a fraction puts its numerator above the axis and its denominator '
      'below, smaller in text style', () {
    final fraction = layOut(node('mfrac', [mi('a'), mi('b')]));
    final small = 20 * 0.71;
    // Its width: the wider part and a pad each side.
    expect(fraction.width, closeTo(small + 2 * 20 * 0.12, 1e-3));
    expect(fraction.ascent, greaterThan(small));
    expect(fraction.descent, greaterThan(small * 0.5));
    final display = layOut(
      node('mfrac', [mi('a'), mi('b')]),
      display: true,
    );
    expect(display.width, closeTo(20 + 2 * 20 * 0.12, 1e-3));
    expect(display.height, greaterThan(fraction.height));
  });

  test('scripts are smaller, raised and lowered, apart from each other', () {
    final base = layOut(mi('x'));
    final sup = layOut(node('msup', [mi('x'), mn('2')]));
    final sub = layOut(node('msub', [mi('x'), mn('2')]));
    final both = layOut(node('msubsup', [mi('x'), mi('i'), mn('2')]));
    expect(sup.width, closeTo(20 + 20 * 0.04 + 20 * 0.71, 1e-3));
    expect(sup.ascent, greaterThan(base.ascent));
    expect(sub.descent, greaterThan(base.descent));
    expect(both.height, greaterThan(sup.height));
    expect(both.width, sup.width);
  });

  test('a large operator takes its limits above and below in display '
      'style, beside it in text', () {
    final sum = node('munderover', [mo('∑'), mi('i'), mi('n')]);
    final display = layOut(sum, display: true);
    final text = layOut(sum);
    expect(display.width, lessThan(text.width), reason: 'stacked');
    expect(display.height, greaterThan(text.height));
    // msubsup on ∑ in display style stacks too.
    final scripted = layOut(
      node('msubsup', [mo('∑'), mi('i'), mi('n')]),
      display: true,
    );
    expect(scripted.width, closeTo(display.width, 1e-3));
  });

  test('a radical is taller and wider than its content; an index sits '
      'over its hook', () {
    final content = layOut(mi('x'));
    final root = layOut(node('msqrt', [mi('x')]));
    expect(root.ascent, greaterThan(content.ascent + 20 * 0.12));
    expect(root.width, greaterThan(content.width + 20 * 0.5));
    final cube = layOut(node('mroot', [mi('x'), mn('3')]));
    expect(cube.width, greaterThanOrEqualTo(root.width));
  });

  test('fences stretch around tall content', () {
    final flat = layOut(row([mo('('), mi('a'), mo(')')]));
    final tall = layOut(
      row([
        mo('('),
        node('mfrac', [mi('a'), mi('b')]),
        mo(')'),
      ]),
      display: true,
    );
    expect(flat.width, 60);
    expect(tall.height, greaterThan(flat.height * 1.5));
    expect(
      layOut(node('mfenced', [mi('a'), mi('b')])).width,
      closeTo(5 * 20 + 20 * 3 / 18, 1e-3),
      reason: '(a,b) with a thin space after the comma',
    );
  });

  test('a table centres its cells on the axis', () {
    final table = layOut(
      MathNode(
        'mtable',
        children: [
          MathNode(
            'mtr',
            children: [
              node('mtd', [mi('a')]),
              node('mtd', [mn('10')]),
            ],
          ),
          MathNode(
            'mtr',
            children: [
              node('mtd', [mi('c')]),
              node('mtd', [mi('d')]),
            ],
          ),
        ],
      ),
    );
    expect(table.width, closeTo(20 + 40 + 20 * 0.8, 1e-3));
    // Two rows of 20 and a gap: half above the axis, half below.
    expect(
      table.ascent - 20 * 0.25,
      closeTo(table.descent + 20 * 0.25, 0.5),
    );
  });

  test('a phantom takes its room; everything paints and disposes', () {
    final phantom = layOut(node('mphantom', [mi('x')]));
    expect(phantom.width, 20);
    final formula = layOut(
      row([
        node('msqrt', [
          node('mfrac', [mi('a'), mi('b')]),
        ]),
        MathNode(
          'menclose',
          attributes: const {'notation': 'box circle updiagonalstrike'},
          children: [mi('x')],
        ),
        node('mover', [mi('x'), mo('¯')]),
      ]),
      display: true,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    formula.paint(canvas, Offset.zero);
    phantom.paint(canvas, Offset.zero);
    recorder.endRecording().dispose();
  });

  test('the book: a formula in a line, its text for copying', () {
    final doc = ContentDocument.parseXml(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
      '<p>Area <math xmlns="http://www.w3.org/1998/Math/MathML">'
      '<msup><mi>r</mi><mn> 2 </mn></msup>'
      '<annotation encoding="TeX">r^2</annotation></math> and '
      '<math xmlns="http://www.w3.org/1998/Math/MathML" alttext="pi"><mi>π</mi></math>.</p>'
      '<math xmlns="http://www.w3.org/1998/Math/MathML" display="block">'
      '<mi>E</mi></math></body></html>',
    );
    final styles = StyleResolver([
      CssSheetSource(
        CssStyleSheet.parse(cssUserAgentStyleSheet),
        CssOrigin.userAgent,
      ),
    ]).resolve(doc);
    final boxes = buildSectionBoxes(doc, styles);
    final [inline, block] = boxes.paragraphs.toList();
    final [r2, pi] = inline.atomics.cast<InlineMath>();
    expect(r2.math.children.single.name, 'msup');
    expect(r2.math.children.single.children.last.text, '2');
    expect(r2.text, 'r2', reason: 'no annotation');
    expect(pi.text, 'pi', reason: 'the alttext');
    expect(inline.plainText(0, inline.text.length), 'Area r2 and pi.');
    expect(block.style.textAlign, CssTextAlign.center);
    expect(block.atomics.single, isA<InlineMath>());
  });
}
