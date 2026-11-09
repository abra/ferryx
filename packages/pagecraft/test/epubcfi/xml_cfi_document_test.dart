import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  const source = '''
<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<body id="body"><?pi ignored?><p id="p" class="x">a<!--c-->b<![CDATA[<d>]]></p><p id="p"/></body>
</html>''';

  test('exposes elements and character data, nothing else', () {
    final document = XmlCfiDocument.parse(source);
    final root = document.root;
    expect(root.isElement, isTrue);
    expect(root.parent, isNull);
    expect(root.id, isNull);
    // Whitespace text, body, whitespace text.
    expect(root.children.map((c) => c.isElement), [false, true, false]);
    final body = root.children[1];
    expect(body.id, 'body');
    expect(
      body.children.map((c) => c.isElement),
      [true, true],
      reason: 'the processing instruction is not a child',
    );
    final p = body.children[0];
    expect(p.attribute('class'), 'x');
    expect(p.attribute('missing'), isNull);
    expect(
      p.children.map((c) => c.text),
      ['a', 'b', '<d>'],
      reason: 'the comment is gone, CDATA is character data',
    );
    expect(p.children.first.parent, same(p));
    expect(p.children.first.attribute('class'), isNull);
    expect(
      identical(p.children, p.children),
      isTrue,
      reason: 'wrappers are built once per node',
    );
  });

  test('finds elements by id, the first of duplicates', () {
    final document = XmlCfiDocument.parse(source);
    expect(document.elementById('body'), same(document.root.children[1]));
    expect(
      document.elementById('p'),
      same(document.root.children[1].children[0]),
    );
    expect(document.elementById('nope'), isNull);
  });

  test('describes nodes for diagnostics', () {
    final document = XmlCfiDocument.parse(source);
    expect(document.root.children[1].toString(), '<body id="body">');
    expect(
      document.root.children[1].children[0].children[0].toString(),
      '"a"',
    );
  });
}
