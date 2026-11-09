import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  /// `name: value` → the longhands it yields, as `name=value` strings.
  List<String> expand(String declaration) {
    final parsed = parseCssDeclarations(declaration).single;
    return [
      for (final d in parseCssDeclaration(parsed))
        '${d.property.name}=${d.value}${d.isImportant ? '!' : ''}',
    ];
  }

  test('longhands parse their grammar and reject the rest', () {
    expect(expand('font-size: 12px'), ['font-size=12.0px']);
    expect(expand('font-size: x-large'), ['font-size=x-large']);
    expect(expand('font-size: -1px'), isEmpty);
    expect(expand('font-size: bold'), isEmpty);
    expect(expand('font-weight: 700'), ['font-weight=700.0']);
    expect(expand('font-weight: bolder'), ['font-weight=bolder']);
    expect(expand('font-weight: 1001'), isEmpty);
    expect(expand('color: #fff'), ['color=#ffffffff']);
    expect(expand('color: nope'), isEmpty);
    expect(expand('line-height: 1.4'), ['line-height=1.4']);
    expect(expand('line-height: 150%'), ['line-height=150.0%']);
    expect(expand('line-height: -1'), isEmpty);
    expect(expand('margin-left: auto'), ['margin-left=auto']);
    expect(expand('margin-left: -1em'), ['margin-left=-1.0em']);
    expect(expand('padding-left: -1em'), isEmpty);
    expect(expand('display: flex'), ['display=block']);
    expect(expand('display: inline-flex'), ['display=inline-block']);
    expect(expand('display: sideways'), isEmpty);
    expect(expand('text-align: justify'), ['text-align=justify']);
    expect(expand('text-indent: 5%'), ['text-indent=5.0%']);
    expect(expand('page-break-before: always'), ['page-break-before=always']);
    expect(expand('break-before: page'), ['page-break-before=always']);
    expect(expand('break-inside: avoid-column'), ['page-break-inside=avoid']);
    expect(expand('width: 50%'), ['width=50.0%']);
    expect(expand('max-width: none'), ['max-width=none']);
    expect(expand('float: inline-end'), ['float=inline-end']);
    expect(expand('letter-spacing: 1%'), isEmpty);
    expect(expand('vertical-align: super'), ['vertical-align=super']);
    expect(expand('vertical-align: -0.5em'), ['vertical-align=-0.5em']);
    expect(expand('list-style-type: "•"'), ['list-style-type="•"']);
    expect(expand('widows: 3'), ['widows=3.0']);
    expect(expand('widows: 0'), isEmpty);
    expect(expand('unknown-property: 1'), isEmpty);
    expect(expand('color: red !important'), ['color=#ffff0000!']);
  });

  test('CSS-wide keywords pass through, also for shorthands', () {
    expect(expand('color: inherit'), ['color=inherit']);
    expect(expand('margin: initial'), [
      'margin-top=initial',
      'margin-right=initial',
      'margin-bottom=initial',
      'margin-left=initial',
    ]);
    expect(expand('font: unset'), hasLength(6));
  });

  test('margin, padding and border shorthands', () {
    expect(expand('margin: 1em'), [
      'margin-top=1.0em',
      'margin-right=1.0em',
      'margin-bottom=1.0em',
      'margin-left=1.0em',
    ]);
    expect(expand('margin: 1em auto'), [
      'margin-top=1.0em',
      'margin-right=auto',
      'margin-bottom=1.0em',
      'margin-left=auto',
    ]);
    expect(expand('padding: 1px 2px 3px'), [
      'padding-top=1.0px',
      'padding-right=2.0px',
      'padding-bottom=3.0px',
      'padding-left=2.0px',
    ]);
    expect(expand('padding: 1px 2px 3px 4px'), [
      'padding-top=1.0px',
      'padding-right=2.0px',
      'padding-bottom=3.0px',
      'padding-left=4.0px',
    ]);
    expect(expand('padding: 1px 2px 3px 4px 5px'), isEmpty);
    expect(expand('padding: 1px -2px'), isEmpty);
    expect(expand('border-width: thin thick'), [
      'border-top-width=1.0px',
      'border-right-width=5.0px',
      'border-bottom-width=1.0px',
      'border-left-width=5.0px',
    ]);
    expect(expand('border: 1px solid red'), [
      'border-top-width=1.0px',
      'border-top-style=solid',
      'border-top-color=#ffff0000',
      'border-right-width=1.0px',
      'border-right-style=solid',
      'border-right-color=#ffff0000',
      'border-bottom-width=1.0px',
      'border-bottom-style=solid',
      'border-bottom-color=#ffff0000',
      'border-left-width=1.0px',
      'border-left-style=solid',
      'border-left-color=#ffff0000',
    ]);
    expect(expand('border-top: solid'), [
      'border-top-width=3.0px',
      'border-top-style=solid',
      'border-top-color=currentcolor',
    ]);
    expect(expand('border: 1px wavy'), isEmpty);
    expect(expand('border-color: red blue'), hasLength(4));
  });

  test('font shorthand', () {
    expect(expand('font: 12px serif'), [
      'font-style=normal',
      'font-variant=normal',
      'font-weight=normal',
      'font-size=12.0px',
      'line-height=normal',
      'font-family=serif',
    ]);
    expect(
      expand('font: italic small-caps bold 1.2em/1.5 "Noto Serif", serif'),
      [
        'font-style=italic',
        'font-variant=small-caps',
        'font-weight=bold',
        'font-size=1.2em',
        'line-height=1.5',
        'font-family=Noto Serif, serif',
      ],
    );
    expect(expand('font: 700 large/120% Arial'), [
      'font-style=normal',
      'font-variant=normal',
      'font-weight=700.0',
      'font-size=large',
      'line-height=120.0%',
      'font-family=Arial',
    ]);
    expect(expand('font: 12px'), isEmpty, reason: 'a family is required');
    expect(expand('font: serif'), isEmpty);
    expect(
      expand('font: menu'),
      isEmpty,
      reason: 'system fonts are not supported',
    );
    expect(expand('font: 12px/ serif'), isEmpty);
  });

  test('background images: source, size, repeat and position', () {
    expect(expand('background-image: url(a.png)'), [
      'background-image=url(a.png)',
    ]);
    expect(expand('background-image: url("b c.png")'), [
      'background-image=url(b c.png)',
    ]);
    expect(expand('background-image: none'), ['background-image=none']);
    expect(
      expand('background-image: linear-gradient(red, blue)'),
      isEmpty,
      reason: 'gradients are not drawn',
    );
    expect(expand('background-size: cover'), ['background-size=cover']);
    expect(expand('background-size: 90px auto'), [
      'background-size=90.0px auto',
    ]);
    expect(expand('background-size: auto 50%'), [
      'background-size=auto 50.0%',
    ]);
    expect(expand('background-size: auto'), ['background-size=auto']);
    expect(expand('background-size: -1px'), isEmpty);
    expect(expand('background-repeat: no-repeat'), [
      'background-repeat=no-repeat',
    ]);
    expect(expand('background-repeat: repeat no-repeat'), [
      'background-repeat=repeat-x',
    ]);
    expect(expand('background-repeat: round'), ['background-repeat=repeat']);
    expect(expand('background-repeat: sideways'), isEmpty);
    expect(expand('background-position: center'), [
      'background-position=50.0% 50.0%',
    ]);
    expect(expand('background-position: top'), [
      'background-position=50.0% 0.0%',
    ]);
    expect(expand('background-position: top right'), [
      'background-position=100.0% 0.0%',
    ]);
    expect(expand('background-position: 0px center'), [
      'background-position=0.0px 50.0%',
    ]);
    expect(expand('background-position: left right'), isEmpty);
  });

  test('background, text-decoration and list-style shorthands', () {
    expect(expand('background: #eee'), [
      'background-color=#ffeeeeee',
      'background-image=none',
      'background-repeat=repeat',
      'background-position=0.0% 0.0%',
      'background-size=auto',
    ]);
    expect(expand('background: url(x.png) no-repeat right top / 20px red'), [
      'background-color=#ffff0000',
      'background-image=url(x.png)',
      'background-repeat=no-repeat',
      'background-position=100.0% 0.0%',
      'background-size=20.0px auto',
    ]);
    expect(expand('background: url(x.png)').take(2), [
      'background-color=#00000000',
      'background-image=url(x.png)',
    ]);
    expect(
      expand('background: url("a.png") repeat-y fixed padding-box')[2],
      'background-repeat=repeat-y',
    );
    expect(expand('background: url(x.png) / 20px'), isEmpty);
    expect(expand('background: url(x.png) wobble'), isEmpty);
    expect(expand('text-decoration: none'), ['text-decoration-line=']);
    expect(expand('text-decoration: underline line-through'), [
      'text-decoration-line=underline line-through',
    ]);
    expect(expand('text-decoration: underline dotted red'), [
      'text-decoration-line=underline',
    ]);
    expect(expand('text-decoration: sideways'), isEmpty);
    expect(expand('list-style: square inside'), [
      'list-style-type=square',
      'list-style-position=inside',
    ]);
    expect(expand('list-style: none'), [
      'list-style-type=none',
      'list-style-position=outside',
    ]);
    expect(expand('list-style: url(b.png) circle'), [
      'list-style-type=circle',
      'list-style-position=outside',
    ]);
  });

  test('prefixed and legacy names set the property browsers read', () {
    expect(expand('-webkit-hyphens: auto'), ['hyphens=auto']);
    expect(expand('-epub-hyphens: none'), ['hyphens=none']);
    expect(expand('-moz-hyphens: auto'), ['hyphens=auto']);
    expect(expand('word-wrap: break-word'), ['overflow-wrap=break-word']);
    expect(expand('-ms-word-break: break-all'), ['word-break=break-all']);
    expect(expand('-epub-writing-mode: vertical-rl'), [
      'writing-mode=vertical-rl',
    ]);
    expect(expand('-webkit-box-sizing: border-box'), [
      'box-sizing=border-box',
    ]);
    expect(expand('-webkit-border-radius: 5px'), hasLength(4));
    // An alias still checks the value.
    expect(expand('-webkit-hyphens: sometimes'), isEmpty);
    // Not every prefix is an alias.
    expect(expand('-webkit-tap-highlight-color: transparent'), isEmpty);
  });

  test('text layout, tables and positioning longhands', () {
    expect(expand('writing-mode: tb-rl'), ['writing-mode=tb-rl']);
    expect(expand('writing-mode: diagonal'), isEmpty);
    expect(expand('overflow-wrap: anywhere'), ['overflow-wrap=anywhere']);
    expect(expand('word-break: keep-all'), ['word-break=keep-all']);
    expect(expand('border-collapse: collapse'), ['border-collapse=collapse']);
    expect(expand('border-spacing: 2px'), ['border-spacing=2.0px 2.0px']);
    expect(expand('border-spacing: 0 4px'), ['border-spacing=0.0px 4.0px']);
    expect(expand('border-spacing: 10%'), isEmpty);
    expect(expand('border-spacing: -1px'), isEmpty);
    expect(expand('caption-side: bottom'), ['caption-side=bottom']);
    expect(expand('position: relative'), ['position=relative']);
    expect(expand('position: floating'), isEmpty);
    expect(expand('top: -0.5em'), ['top=-0.5em']);
    expect(expand('left: 50%'), ['left=50.0%']);
    expect(expand('bottom: auto'), ['bottom=auto']);
    expect(expand('box-sizing: border-box'), ['box-sizing=border-box']);
    expect(expand('list-style-position: inside'), [
      'list-style-position=inside',
    ]);
    expect(expand('text-align: -webkit-match-parent'), ['text-align=inherit']);
    expect(expand('text-align: match-parent'), ['text-align=inherit']);
  });

  test('quotes: none, auto or pairs of strings', () {
    expect(expand('quotes: none'), ['quotes=none']);
    expect(expand('quotes: auto'), ['quotes=auto']);
    expect(expand('quotes: "«" "»" "„" "“"'), [
      'quotes="«" "»" "„" "“"',
    ]);
    expect(expand('quotes: "«"'), isEmpty);
    expect(expand('quotes: "«" auto'), isEmpty);
  });

  test('border-radius: corners clockwise, vertical radii after a slash', () {
    expect(expand('border-radius: 4px'), [
      'border-top-left-radius=4.0px 4.0px',
      'border-top-right-radius=4.0px 4.0px',
      'border-bottom-right-radius=4.0px 4.0px',
      'border-bottom-left-radius=4.0px 4.0px',
    ]);
    expect(expand('border-radius: 1px 2px 3px'), [
      'border-top-left-radius=1.0px 1.0px',
      'border-top-right-radius=2.0px 2.0px',
      'border-bottom-right-radius=3.0px 3.0px',
      'border-bottom-left-radius=2.0px 2.0px',
    ]);
    expect(expand('border-radius: 50% / 10px'), [
      'border-top-left-radius=50.0% 10.0px',
      'border-top-right-radius=50.0% 10.0px',
      'border-bottom-right-radius=50.0% 10.0px',
      'border-bottom-left-radius=50.0% 10.0px',
    ]);
    expect(expand('border-top-left-radius: 2px 6px'), [
      'border-top-left-radius=2.0px 6.0px',
    ]);
    expect(expand('border-radius: -1px'), isEmpty);
    expect(expand('border-radius: 1px 2px 3px 4px 5px'), isEmpty);
  });

  test('inset sets the four offsets as margin does', () {
    expect(expand('inset: 1px auto'), [
      'top=1.0px',
      'right=auto',
      'bottom=1.0px',
      'left=auto',
    ]);
  });

  test('whitespace and case do not matter', () {
    expect(expand('  MARGIN  :  1EM  2Em '), [
      'margin-top=1.0em',
      'margin-right=2.0em',
      'margin-bottom=1.0em',
      'margin-left=2.0em',
    ]);
    expect(expand('Display: BLOCK'), ['display=block']);
  });
}
