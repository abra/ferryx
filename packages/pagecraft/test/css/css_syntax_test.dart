import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  test('parses qualified rules with declarations', () {
    final sheet = CssStyleSheet.parse('''
      p, div.x { color: red; margin : 1em 0 !important ; }
      h1{font-size:2em}
    ''');
    expect(sheet.rules, hasLength(2));
    final p = sheet.rules[0] as CssQualifiedRule;
    expect(p.prelude.join(), 'p, div.x');
    expect(p.declarations.map((d) => d.toString()), [
      'color: red;',
      'margin: 1em 0 !important;',
    ]);
    final h1 = sheet.rules[1] as CssQualifiedRule;
    expect(h1.declarations.single.name, 'font-size');
    expect(h1.declarations.single.isImportant, isFalse);
  });

  test('parses at-rules: statements, rule blocks and declaration blocks', () {
    final sheet = CssStyleSheet.parse('''
      @charset "utf-8";
      @import url(a.css) screen;
      @media print { p { display: none } }
      @font-face { font-family: "F"; src: url(f.ttf) format("truetype"); }
      @page { margin: 1cm }
      @unknown thing;
    ''');
    final names = sheet.rules.map((r) => (r as CssAtRule).name).toList();
    expect(names, [
      'charset',
      'import',
      'media',
      'font-face',
      'page',
      'unknown',
    ]);
    final import = sheet.rules[1] as CssAtRule;
    expect(import.prelude.join(), 'url(a.css) screen');
    expect(import.rules, isNull);
    final media = sheet.rules[2] as CssAtRule;
    expect(media.prelude.join(), 'print');
    expect(media.rules!.single, isA<CssQualifiedRule>());
    final fontFace = sheet.rules[3] as CssAtRule;
    expect(fontFace.declarations!.map((d) => d.name), ['font-family', 'src']);
    expect(
      fontFace.declarations![1].value.join(),
      'url(f.ttf) format("truetype")',
    );
  });

  test('recovers from errors the way the spec says', () {
    final sheet = CssStyleSheet.parse('''
      p { color: red; : broken; margin 1em; padding: 1em !; width: 1px }
      } q { x: 1 }
      r { a: "bad
      string; b: 2 }
      s { c: url(bad url); d: 3; @nested { e: 4 } f: 5 }
      t { g: 6
    ''');
    final rules = sheet.rules.whereType<CssQualifiedRule>().toList();
    // A stray `}` joins the next prelude (the selector parser then drops
    // that rule, as browsers do); a rule cut off by the end is kept.
    expect(rules.map((r) => r.prelude.join()), ['p', '} q', 'r', 's', 't']);
    // `padding: 1em !` is syntactically a declaration; the property
    // grammar rejects it later, as the spec splits the two.
    expect(rules[0].declarations.map((d) => d.toString()), [
      'color: red;',
      'padding: 1em !;',
      'width: 1px;',
    ]);
    expect(rules[1].declarations.single.name, 'x');
    expect(rules[2].declarations.map((d) => d.name), ['b']);
    expect(rules[3].declarations.map((d) => d.name), ['d', 'f']);
    expect(rules[4].declarations.single.name, 'g');
  });

  test('blocks and functions nest inside values', () {
    final sheet = CssStyleSheet.parse('a { b: calc(1px + (2 * 3)) [x] {y} }');
    final value =
        (sheet.rules.single as CssQualifiedRule).declarations.single.value;
    expect(value.join(), 'calc(1px + (2 * 3)) [x] {y}');
    final calc = value[0] as CssFunctionValue;
    expect(calc.name, 'calc');
    expect(
      calc.arguments.whereType<CssBlockValue>().single.open,
      CssTokenType.openParen,
    );
  });

  test('a declaration list and loose component values parse on their own', () {
    final declarations = parseCssDeclarations(
      'color:red;;font-weight: bold !IMPORTANT',
    );
    expect(declarations.map((d) => d.toString()), [
      'color: red;',
      'font-weight: bold !important;',
    ]);
    expect(parseCssComponentValues(' a > b ').join(), ' a > b ');
  });

  test('top-level CDO and CDC are ignored, nested ones are selectors', () {
    final sheet = CssStyleSheet.parse(
      '<!-- p { a: 1 } --> @media all { <!-- q { b: 2 } }',
    );
    expect(sheet.rules, hasLength(2));
    final media = sheet.rules[1] as CssAtRule;
    expect((media.rules!.single as CssQualifiedRule).prelude.join(), '<!-- q');
  });
}
