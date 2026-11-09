import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  List<String> types(String css) =>
      tokenizeCss(css).map((t) => t.type.name).toList();

  test('tokenizes the token kinds of a style rule', () {
    expect(
      types('p.x#y > a[href="u"]:first-child { color: red !important; }'),
      [
        'ident',
        'delim',
        'ident',
        'hash',
        'whitespace',
        'delim',
        'whitespace',
        'ident',
        'openSquare',
        'ident',
        'delim',
        'string',
        'closeSquare',
        'colon',
        'ident',
        'whitespace',
        'openBrace',
        'whitespace',
        'ident',
        'colon',
        'whitespace',
        'ident',
        'whitespace',
        'delim',
        'ident',
        'semicolon',
        'whitespace',
        'closeBrace',
      ],
    );
  });

  test('numbers, percentages and dimensions carry values and units', () {
    final tokens = tokenizeCss('1.5em -2PX +.5 10% 1e3 3E-2px 7');
    final numeric = tokens.where((t) => !t.isWhitespace).toList();
    expect(numeric.map((t) => t.type.name), [
      'dimension',
      'dimension',
      'number',
      'percentage',
      'number',
      'dimension',
      'number',
    ]);
    expect(numeric.map((t) => t.number), [1.5, -2, 0.5, 10, 1000, 0.03, 7]);
    expect(numeric.map((t) => t.unit), ['em', 'px', '', '', '', 'px', '']);
    expect(numeric.map((t) => t.isInteger), [
      false,
      true,
      false,
      true,
      false,
      false,
      true,
    ]);
  });

  test('strings decode escapes and a newline makes a bad string', () {
    final tokens = tokenizeCss(
      '"a\\"b\\41 c\\\nd" \'x\' "bad\nrest',
    );
    expect(tokens[0].type, CssTokenType.string);
    expect(tokens[0].value, 'a"bAcd');
    expect(tokens[2].value, 'x');
    expect(tokens[4].type, CssTokenType.badString);
    expect(tokens.last.type, CssTokenType.ident);
    expect(tokens.last.value, 'rest');
  });

  test('url() with and without quotes, and bad urls', () {
    final tokens = tokenizeCss(
      'url(a.png) url( "b.png" ) URL(  c.png  ) url(d e) url(f',
    ).where((t) => !t.isWhitespace).toList();
    expect(tokens[0].type, CssTokenType.url);
    expect(tokens[0].value, 'a.png');
    expect(tokens[1].type, CssTokenType.function);
    expect(tokens[1].value, 'url');
    expect(tokens[2].type, CssTokenType.string);
    expect(tokens[3].type, CssTokenType.closeParen);
    expect(tokens[4].type, CssTokenType.url);
    expect(tokens[4].value, 'c.png');
    expect(tokens[5].type, CssTokenType.badUrl);
    expect(tokens[6].type, CssTokenType.url);
    expect(tokens[6].value, 'f', reason: 'eof ends the url');
  });

  test('hashes know whether they are ids, at-keywords and functions', () {
    final tokens = tokenizeCss('#id #1a @media rgb(1,2,3) -webkit-x --var');
    expect(tokens[0].isId, isTrue);
    expect(tokens[2].isId, isFalse);
    expect(tokens[2].value, '1a');
    expect(tokens[4].type, CssTokenType.atKeyword);
    expect(tokens[4].value, 'media');
    expect(tokens[6].type, CssTokenType.function);
    expect(tokens[6].value, 'rgb');
    expect(tokens[14].value, '-webkit-x');
    expect(tokens[16].value, '--var');
  });

  test('identifiers decode escapes, including code points above BMP', () {
    final tokens = tokenizeCss(r'\31 23 a\62 c \1F600 x');
    expect(tokens[0].value, '123');
    expect(tokens[2].value, 'abc');
    expect(tokens[4].value, '\u{1F600}x');
  });

  test('comments vanish and CDO/CDC are tokens', () {
    expect(types('a/*x*/b <!-- --> /* unterminated'), [
      'ident',
      'ident',
      'whitespace',
      'cdo',
      'whitespace',
      'cdc',
      'whitespace',
    ]);
  });

  test('line endings and NUL are preprocessed', () {
    expect(tokenizeCss('"a\r\nb"').first.type, CssTokenType.badString);
    expect(tokenizeCss('"a\rb"').first.type, CssTokenType.badString);
    // NUL becomes U+FFFD, which, being non-ASCII, starts an identifier.
    final nul = tokenizeCss('\u0000').single;
    expect(nul.type, CssTokenType.ident);
    expect(nul.value, '\uFFFD');
  });

  test('every token prints back to CSS', () {
    const css = 'a.b#c[d="e"]:f(g) { h: 1px 2% 3 url(x) "s" , !important; }';
    expect(tokenizeCss(css).join(), css);
  });
}
