import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/article/article_document.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  group('the document', () {
    test('is cleaned as the shell cleaned it, inside its <main>', () {
      final html = articleDocumentHtml(
        '<section style="color: red"><p id="block-0" data-rf-block-id="block-0" '
        'onclick="x()" style="margin: 0">A <span data-rf-sentence="0">b</span>'
        '<font color="red">c</font><script>alert(1)</script>'
        '<style>p { color: red }</style><svg><text>no</text></svg></p></section>'
        '<!-- a comment -->'
        '<p><a href="javascript:alert(1)">x</a> <a href="https://e.org/?a=1&amp;b=2">y</a>'
        ' <a href="#block-0">z</a></p>'
        '<img src="images/pic-1.png" alt="kept"/><img src="https://e.org/x.png"/>'
        '<img src="images/../x.png"/>',
      );
      final doc = ContentDocument.parseHtml(html);
      final content = doc.elementIndexById(ArticleAnchor.contentId);
      expect(doc.localNameOf(content), 'main');
      final names = [
        for (final n in doc.descendantsOf(content))
          if (doc.isElement(n)) doc.localNameOf(n),
      ];
      expect(names, [
        'main',
        'p',
        'span',
        'p',
        'a',
        'a',
        'a',
        'img',
        'img',
        'img',
      ]);
      expect(textContentOf(doc, content), 'A bcx y z');
      final p = doc.elementIndexById('block-0');
      expect(doc.attributeOf(p, 'style'), isNull);
      expect(doc.attributeOf(p, 'onclick'), isNull);
      expect(doc.attributeOf(p, 'data-rf-block-id'), 'block-0');
      final links = [
        for (final n in doc.descendantsOf(content))
          if (doc.isElement(n) && doc.localNameOf(n) == 'a')
            doc.attributeOf(n, 'href'),
      ];
      expect(links, [null, 'https://e.org/?a=1&b=2', '#block-0']);
      final sources = [
        for (final n in doc.descendantsOf(content))
          if (doc.isElement(n) && doc.localNameOf(n) == 'img')
            doc.attributeOf(n, 'src'),
      ];
      expect(sources, ['images/pic-1.png', null, null]);
    });

    test('its contents: headings as a tree, else blocks spread over it', () {
      final withHeadings = ContentDocument.parseHtml(
        articleDocumentHtml(
          '<h1 id="t">Title</h1><h2 id="a">A</h2><h3 id="a1">A one</h3>'
          '<h2 id="b">B</h2><h2>No id</h2><h4 id="c">  C   deep </h4>',
        ),
      );
      String outline(List<BookNavItem> items, [String pad = '']) => [
        for (final item in items)
          '$pad${item.label} ${item.href}\n'
              '${outline(item.subitems ?? const [], '$pad  ')}',
      ].join();
      expect(
        outline(articleToc(withHeadings)),
        'Title #t\n'
        '  A #a\n'
        '    A one #a1\n'
        '  B #b\n'
        '    C deep #c\n',
      );
      final long = 'x' * 50;
      final blocks = ContentDocument.parseHtml(
        articleDocumentHtml(
          [
            for (var i = 0; i < 30; i++)
              '<p id="block-$i" data-rf-block-id="block-$i">'
                  '${i == 0 ? '$long one two three four five six seven eight nine ten' : long}</p>',
            '<p id="short" data-rf-block-id="short">short</p>',
          ].join(),
        ),
      );
      final toc = articleToc(blocks);
      expect(toc, hasLength(10), reason: 'every third of 30');
      expect(toc.first.href, '#block-0');
      expect(toc.first.label, endsWith('...'));
      expect(toc.first.label.length, lessThanOrEqualTo(75));
      expect(toc[1].href, '#block-3');
    });
  });

  group('the source', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('article-');
      Directory('${dir.path}/images').createSync();
      File('${dir.path}/images/pic.png').writeAsBytesSync([1, 2, 3]);
      File('${dir.path}/secret.txt').writeAsStringSync('no');
      File('${dir.path}/article.html').writeAsStringSync(
        '<h1 id="t">Title</h1><p>Text <img src="images/pic.png"/></p>',
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('is one section of the cleaned article, its pictures only', () async {
      final source = await ArticleTextSource.open('${dir.path}/article.html');
      addTearDown(source.close);
      expect(source.sectionCount, 1);
      final section = await source.section(0);
      expect(section.mediaType, 'text/html');
      expect(section.text, contains('<main id="article-content">'));
      expect(source.toc.single.label, 'Title');
      expect(source.defaultStyleSheets, [articleStyleSheet]);
      final key = source.imageKey(section.href, 'images/pic.png');
      expect(await source.readImage(key), [1, 2, 3]);
      expect(await source.readImage('secret.txt'), isNull);
      expect(await source.readImage('images/../secret.txt'), isNull);
      expect(await source.readImage('images/missing.png'), isNull);
      final target = await source.resolveHref('#t');
      expect(target?.index, 0);
      expect(source.isExternal('#t'), isFalse);
      expect(source.isExternal('https://e.org'), isTrue);
    });
  });
}
