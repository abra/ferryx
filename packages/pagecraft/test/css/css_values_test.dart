import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  CssComponentValue single(String css) =>
      cssWithoutWhitespace(parseCssComponentValues(css)).single;

  group('CssLength', () {
    test('parses units, converting absolute ones to px', () {
      expect(CssLength.parse(single('12px')), const CssLength.px(12));
      expect(CssLength.parse(single('12PT')), const CssLength.px(16));
      expect(CssLength.parse(single('1in')), const CssLength.px(96));
      expect(CssLength.parse(single('2.54cm')), const CssLength.px(96));
      expect(CssLength.parse(single('1pc')), const CssLength.px(16));
      expect(
        CssLength.parse(single('1.5em')),
        const CssLength(1.5, CssLengthUnit.em),
      );
      expect(
        CssLength.parse(single('2rem')),
        const CssLength(2, CssLengthUnit.rem),
      );
      expect(CssLength.parse(single('50%')), const CssLength.percent(50));
      expect(CssLength.parse(single('0')), CssLength.zero);
      expect(
        CssLength.parse(single('10vw')),
        const CssLength(10, CssLengthUnit.vw),
      );
    });

    test('rejects what is not a length', () {
      expect(CssLength.parse(single('12')), isNull);
      expect(CssLength.parse(single('12furlongs')), isNull);
      expect(CssLength.parse(single('auto')), isNull);
      expect(CssLength.parse(single('50%'), allowPercent: false), isNull);
      expect(CssLength.parse(single('"12px"')), isNull);
    });

    test('resolves relative units against the context', () {
      const context = CssLengthContext(
        fontSize: 20,
        rootFontSize: 16,
        viewportWidth: 400,
        viewportHeight: 800,
      );
      double px(String css, {double percentOf = 0}) =>
          CssLength.parse(single(css))!.toPx(context, percentOf: percentOf);
      expect(px('1.5em'), 30);
      expect(px('2rem'), 32);
      expect(px('1ex'), 10);
      expect(px('2ch'), 20);
      expect(px('10vw'), 40);
      expect(px('10vh'), 80);
      expect(px('10vmin'), 40);
      expect(px('10vmax'), 80);
      expect(px('25%', percentOf: 200), 50);
      expect(px('3px'), 3);
    });
  });

  group('math functions', () {
    const context = CssLengthContext(
      fontSize: 10,
      rootFontSize: 16,
      viewportWidth: 400,
      viewportHeight: 800,
    );
    CssLength? parse(String css) => CssLength.parse(single(css));
    double px(String css, {double percentOf = 0}) =>
        InlineStyler.px(parse(css)!.computedIn(context), percentOf);

    test('calc() adds, subtracts, multiplies and divides lengths', () {
      expect(px('calc(10px + 2em)'), 30);
      expect(px('calc(1rem - 6px)'), 10);
      expect(px('calc(2 * 3px + 1vw)'), 10);
      expect(px('calc(10px * 3 / 2)'), 15);
      expect(px('calc((1em + 5px) * 2)'), 30);
      expect(px('calc(0.35em + 1vw)'), closeTo(7.5, 1e-9));
      expect(px('calc(-1 * 4px)'), -4);
    });

    test('percentages wait for the layout, which says what they are of', () {
      final length = parse('calc(100% - 20px + 1em)')!.computedIn(context);
      expect(length.hasPercent, isTrue);
      expect(length.isPercent, isFalse);
      expect(InlineStyler.px(length, 200), 190);
      expect(InlineStyler.px(length, 100), 90);
      expect(
        parse('calc(10px + 1em)')!.computedIn(context),
        const CssLength.px(20),
        reason: 'no percentage left: a px length',
      );
    });

    test('min(), max() and clamp(), percentages too', () {
      expect(px('min(10px, 2em, 50px)'), 10);
      expect(px('max(10px, 2em)'), 20);
      expect(px('clamp(10px, 5vw, 30px)'), 20);
      expect(px('clamp(10px, 1vw, 30px)'), 10);
      expect(px('clamp(10px, 10vw, 30px)'), 30);
      expect(px('min(50%, 300px)', percentOf: 400), 200);
      expect(px('min(50%, 300px)', percentOf: 800), 300);
      expect(px('calc(min(10px, 5%) * 2)', percentOf: 100), 10);
    });

    test('what is not a length is no length', () {
      for (final css in [
        'calc(1px + 2)',
        'calc(1px * 2px)',
        'calc(2 / 1px)',
        'calc(1px / 0)',
        'calc(1 + 2)',
        'calc(1px -2px)',
        'calc(1px +)',
        'calc()',
        'min(1px, 2)',
        'clamp(1px, 2px)',
        'calc(1px foo)',
        'attr(x)',
      ]) {
        expect(parse(css), isNull, reason: css);
      }
      expect(
        CssLength.parse(single('calc(10% + 1px)'), allowPercent: false),
        isNull,
      );
    });

    test('equal math functions are equal lengths', () {
      expect(parse('calc(1px + 2em)'), parse('calc(1px + 2em)'));
      expect(parse('calc(1px + 2em)'), isNot(parse('calc(2em + 1px)')));
      expect(
        parse('calc(1px + 2em)').hashCode,
        parse('calc(1px + 2em)').hashCode,
      );
    });
  });

  group('CssColor', () {
    CssColor? color(String css) => CssColor.parse(single(css));

    test('named, hex and functional colors', () {
      expect(color('red'), const CssColor(0xFFFF0000));
      expect(color('RebeccaPurple'), const CssColor(0xFF663399));
      expect(color('transparent'), CssColor.transparent);
      expect(color('currentColor'), CssColor.currentColor);
      expect(color('#abc'), const CssColor(0xFFAABBCC));
      expect(color('#abcd'), const CssColor(0xDDAABBCC));
      expect(color('#102030'), const CssColor(0xFF102030));
      expect(color('#10203080'), const CssColor(0x80102030));
      expect(color('rgb(1, 2, 3)'), const CssColor(0xFF010203));
      expect(color('rgb(1 2 3)'), const CssColor(0xFF010203));
      expect(color('rgba(255, 0, 0, 0.5)'), const CssColor(0x80FF0000));
      expect(color('rgb(255 0 0 / 50%)'), const CssColor(0x80FF0000));
      expect(color('rgb(100%, 0%, 50%)'), const CssColor(0xFFFF0080));
      expect(color('rgb(300, -5, 3.6)'), const CssColor(0xFFFF0004));
      expect(color('hsl(0, 100%, 50%)'), const CssColor(0xFFFF0000));
      expect(color('hsl(120deg 100% 25%)'), const CssColor(0xFF008000));
      expect(color('hsla(240, 100%, 50%, 0.5)'), const CssColor(0x800000FF));
      expect(color('hsl(0, 0%, 50%)'), const CssColor(0xFF808080));
    });

    test('rejects malformed colors', () {
      for (final css in [
        '#ab',
        '#abcde',
        '#ggg',
        'rgb(1,2)',
        'rgb(a,b,c)',
        'rgb(1,2,3,4,5)',
        'notacolor',
        '12',
        'hsl(1px,2,3)',
      ]) {
        expect(color(css), isNull, reason: css);
      }
    });
  });

  group('font families', () {
    List<String>? families(String css) =>
        cssParseFontFamilies(parseCssComponentValues(css));

    test('strings, identifier runs and generics', () {
      expect(families('"Times New Roman", Georgia, serif'), [
        'Times New Roman',
        'Georgia',
        'serif',
      ]);
      expect(families('Times New Roman , SANS-SERIF'), [
        'Times New Roman',
        'sans-serif',
      ]);
      expect(families("'Book Antiqua'"), ['Book Antiqua']);
    });

    test('rejects empty and malformed lists', () {
      expect(families(''), isNull);
      expect(families('a,'), isNull);
      expect(families('"a" b'), isNull);
      expect(families('12'), isNull);
      expect(families('""'), isNull);
    });
  });
}
