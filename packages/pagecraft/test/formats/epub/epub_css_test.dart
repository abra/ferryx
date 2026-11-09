import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  String rewrite(String css) =>
      rewriteEpubCss(css, windowWidth: 400, windowHeight: 800);

  test('pixels become sixteenths of an em', () {
    expect(
      rewrite('p { margin: 32px 0 -8px; }'),
      'p { margin: 2em 0 -0.5em; }',
    );
    expect(
      rewrite('h1 { border: 1px solid; font-size: 12.5PX }'),
      'h1 { border: 0.0625em solid; font-size: 0.78125em }',
    );
    expect(
      rewrite('@media (max-width: 600px) {}'),
      '@media (max-width: 37.5em) {}',
    );
  });

  test('viewport units become pixels of the window, then ems', () {
    // 5vw of 400 is 20px, which is 1.25em.
    expect(
      rewrite('p { margin-left: 5vw; height: 10vh }'),
      'p { margin-left: 1.25em; height: 5em }',
    );
  });

  test('-epub- prefixes go', () {
    expect(
      rewrite('p {-epub-hyphens: auto; -epub-writing-mode: vertical-rl}'),
      'p {hyphens: auto; writing-mode: vertical-rl}',
    );
    expect(rewrite('.x-epub-y { }'), '.x-epub-y { }', reason: 'not a prefix');
  });

  test('URLs stay as they are', () {
    expect(
      rewrite('div { background: url(img/icon-16px.png) 4px; }'),
      'div { background: url(img/icon-16px.png) 0.25em; }',
    );
    expect(
      rewrite('@import "a-12px.css"; p{top:1px}'),
      '@import "a-12px.css"; p{top:0.0625em}',
    );
  });
}
