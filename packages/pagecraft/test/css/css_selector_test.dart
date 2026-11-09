import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  final doc = ContentDocument.parseXml('''
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en-GB">
<body class="book">
  <section id="ch1" class="chapter first" epub:type="chapter" xmlns:epub="http://www.idpf.org/2007/ops">
    <h1>Title</h1>
    <p class="first-para">one</p>
    <p>two <em>em</em> <a href="https://x.org/a.html">link</a></p>
    <p lang="fr">trois</p>
    <div><p>nested</p><img src="a.png" alt=""/></div>
    <blockquote></blockquote>
  </section>
</body>
</html>''');

  /// The elements matching [selector], by a short description.
  List<String> matching(String selector) {
    final list = CssSelectorList.parseText(selector);
    if (list == null) return ['<invalid>'];
    final out = <String>[];
    for (final n in doc.descendantsOf(ContentDocument.rootIndex)) {
      if (!doc.isElement(n)) continue;
      if (list.selectors.any((s) => s.matches(doc, n))) {
        final id = doc.idOf(n);
        final text = doc.textContentOf(n).trim();
        out.add(
          '${doc.localNameOf(n)}${id == null ? '' : '#$id'}'
          '${text.isEmpty || text.length > 6 ? '' : ':$text'}',
        );
      }
    }
    return out;
  }

  test('type, universal, class, id and attribute selectors', () {
    expect(matching('h1'), ['h1:Title']);
    expect(matching('P'), ['p:one', 'p', 'p:trois', 'p:nested']);
    expect(matching('*'), hasLength(13));
    expect(matching('.first'), ['section#ch1']);
    expect(matching('.chapter.first'), ['section#ch1']);
    expect(matching('.chapte'), isEmpty);
    expect(matching('#ch1'), ['section#ch1']);
    expect(matching('section#ch1.chapter'), ['section#ch1']);
    expect(matching('[href]'), ['a:link']);
    expect(matching('[epub\\:type="chapter"]'), ['section#ch1']);
    expect(matching('[class~="first"]'), ['section#ch1']);
    expect(matching('[class~=first-para]'), ['p:one']);
    expect(matching('[lang|="fr"]'), ['p:trois']);
    expect(matching('[href^="https"]'), ['a:link']);
    expect(matching(r'[href$=".html"]'), ['a:link']);
    expect(matching('[href*="x.org"]'), ['a:link']);
    expect(matching('[alt=""]'), ['img']);
    expect(matching('[alt~=""]'), isEmpty);
  });

  test('combinators', () {
    expect(matching('section p'), ['p:one', 'p', 'p:trois', 'p:nested']);
    expect(matching('section > p'), ['p:one', 'p', 'p:trois']);
    expect(matching('body > p'), isEmpty);
    expect(matching('h1 + p'), ['p:one']);
    expect(matching('h1 ~ p'), ['p:one', 'p', 'p:trois']);
    expect(matching('p + p'), ['p', 'p:trois']);
    expect(matching('html body section div > p'), ['p:nested']);
    expect(matching('p em'), ['em:em']);
    expect(matching('p > a'), ['a:link']);
  });

  test('structural pseudo-classes', () {
    expect(matching(':root'), ['html']);
    expect(matching('p:first-child'), ['p:nested']);
    expect(matching('section :first-child'), ['h1:Title', 'em:em', 'p:nested']);
    expect(matching('section > :last-child'), ['blockquote']);
    expect(matching('p:only-child'), isEmpty);
    expect(matching('h1:only-child'), isEmpty);
    expect(matching('section > :nth-child(2)'), ['p:one']);
    expect(matching('section > :nth-child(odd)'), [
      'h1:Title',
      'p',
      'div:nested',
    ]);
    expect(matching('section > :nth-child(2n)'), [
      'p:one',
      'p:trois',
      'blockquote',
    ]);
    expect(matching('section > :nth-child(-n+2)'), ['h1:Title', 'p:one']);
    expect(matching('section > :nth-last-child(1)'), ['blockquote']);
    expect(matching('p:first-of-type'), ['p:one', 'p:nested']);
    expect(matching('section > p:last-of-type'), ['p:trois']);
    expect(matching(':empty'), ['img', 'blockquote']);
    expect(matching(':not(p)'), isNot(contains('p:one')));
    expect(matching('p:not(.first-para)'), ['p', 'p:trois', 'p:nested']);
    expect(matching(':lang(fr)'), ['p:trois']);
    expect(matching('p:lang(en)'), ['p:one', 'p', 'p:nested']);
    expect(matching(':lang("en-gb")'), hasLength(12));
  });

  test('pseudo-elements and dynamic pseudo-classes parse and never match', () {
    expect(matching('p::first-letter'), isEmpty);
    expect(matching('p:first-line'), isEmpty);
    expect(matching('a:hover'), isEmpty);
    expect(matching('a:visited, h1'), [
      'h1:Title',
    ], reason: 'the list survives');
  });

  test('every link is unvisited: :link and :any-link match an href', () {
    // A browser where nothing has been visited, as the WebView reader is.
    expect(matching('a:link'), ['a:link']);
    expect(matching(':any-link'), ['a:link']);
    expect(matching('a:link, a:visited'), ['a:link']);
    expect(matching('p:link'), isEmpty);
    final anchors = ContentDocument.parseXml(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
      '<a id="target">no href</a><a href="#target">to it</a>'
      '</body></html>',
    );
    final list = CssSelectorList.parseText('a:link')!;
    expect(
      [
        for (final n in anchors.descendantsOf(ContentDocument.rootIndex))
          if (anchors.isElement(n) &&
              list.selectors.any((s) => s.matches(anchors, n)))
            anchors.textContentOf(n),
      ],
      ['to it'],
    );
  });

  test('invalid selectors drop the whole list', () {
    for (final selector in [
      '',
      'p,',
      'p >',
      '> p',
      'p.',
      'p#1a',
      'p:unknown',
      'p:nth-child(x)',
      'p[',
      'p[a=]',
      'p[a=b c]',
      'p %',
      'p::',
      'p::before span',
      ':not(p, %)',
      ':has()',
      ':has(p::before)',
    ]) {
      expect(matching(selector), ['<invalid>'], reason: selector);
    }
  });

  test('of-type positions', () {
    expect(matching('p:nth-of-type(2)'), ['p']);
    expect(matching('section > p:nth-of-type(odd)'), ['p:one', 'p:trois']);
    expect(matching('section > p:nth-last-of-type(1)'), ['p:trois']);
    expect(matching('div > p:only-of-type'), ['p:nested']);
    expect(matching('section > p:only-of-type'), isEmpty);
    expect(matching('img:only-of-type'), ['img']);
  });

  test('namespace prefixes: types by local name, attributes as written', () {
    expect(matching('ns|h1'), ['h1:Title']);
    expect(matching('*|h1'), ['h1:Title']);
    expect(matching('|h1'), ['h1:Title']);
    expect(matching('svg|*'), hasLength(13));
    expect(matching('[epub|type~="chapter"]'), ['section#ch1']);
    expect(matching('[*|type="chapter"]'), ['section#ch1']);
    expect(matching('[|type="chapter"]'), isEmpty);
    expect(matching('[epub|type="Chapter" i]'), ['section#ch1']);
    expect(matching('[epub|type="Chapter"]'), isEmpty);
  });

  test(':not, :is and :where take selector lists', () {
    expect(matching('section > :not(p, h1, div)'), ['blockquote']);
    expect(matching(':not(section p)'), isNot(contains('p:one')));
    expect(matching(':is(h1, blockquote)'), ['h1:Title', 'blockquote']);
    expect(matching('div :where(p, img)'), ['p:nested', 'img']);
    // Forgiving: one bad selector does not spoil the list.
    expect(matching(':is(h1, %)'), ['h1:Title']);
  });

  test(':has: descendants, children and siblings', () {
    expect(matching('section:has(em)'), ['section#ch1']);
    expect(matching('p:has(> em)'), ['p']);
    expect(matching('div:has(> p + img)'), ['div:nested']);
    expect(matching('div:has(> img:only-child)'), isEmpty);
    expect(matching('h1:has(+ p.first-para)'), ['h1:Title']);
    expect(matching('h1:has(~ blockquote)'), ['h1:Title']);
    expect(matching('p:has(~ h1)'), isEmpty);
    // foliate-js's prose test: a div of nothing but phrasing.
    expect(
      matching('div:not(:has(*:not(b, a, em, i, strong, u, span)))'),
      isEmpty,
      reason: 'the div holds a p and an img',
    );
  });

  test('pseudo-elements style themselves, not the element', () {
    final selector = CssSelectorList.parseText(
      'p.first-para::before',
    )!.selectors.single;
    expect(selector.pseudoElement, 'before');
    final p = doc
        .descendantsOf(ContentDocument.rootIndex)
        .firstWhere((n) => doc.attributeOf(n, 'class') == 'first-para');
    expect(selector.matches(doc, p), isFalse);
    expect(selector.matchesOriginating(doc, p), isTrue);
    expect(
      CssSelectorList.parseText('q:after')!.selectors.single.pseudoElement,
      'after',
    );
  });

  test('specificity', () {
    int specificity(String s) =>
        CssSelectorList.parseText(s)!.selectors.single.specificity;
    expect(specificity('*'), 0);
    expect(specificity('p'), 1);
    expect(specificity('p em'), 2);
    expect(specificity('.a'), 1000);
    expect(specificity('p.a.b'), 2001);
    expect(specificity('#x'), 1000000);
    expect(specificity('#x .a p > em:first-child'), 1002002);
    expect(specificity('[href]'), 1000);
    expect(specificity(':not(.a)'), 1000);
    expect(specificity(':not(p)'), 1);
    expect(specificity('p::before'), 2);
    expect(specificity('a:hover'), 1001);
    expect(specificity(':nth-child(2n)'), 1000);
    expect(specificity(':nth-of-type(2n)'), 1000);
    expect(specificity(':is(p, #x)'), 1000000);
    expect(specificity(':where(p, #x)'), 0);
    expect(specificity(':not(p, .a)'), 1000);
    expect(specificity('div:has(> p)'), 2);
  });

  test('prints back', () {
    const text =
        'html > body.book section#ch1 p + em ~ a[href^="x"]:first-child:nth-child(2n+1):not(.x)::before, *';
    expect(CssSelectorList.parseText(text).toString(), text);
  });
}
