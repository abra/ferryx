import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// Glyphs of the test font are squares one font size wide; at 10 px
/// with line height 1.8 a prose line is 18 tall, and paragraph spacing
/// 1.0 gives prose 5 px margins above and below.
const ten = BookStyle(fontScale: 10 / 16, lineHeight: 1.8);

ColumnLayout column(
  String body, {
  String css = '',
  BookStyle book = ten,
  double width = 100,
  double pageHeight = 1000,
  Map<String, Size> images = const {},
}) {
  final doc = ContentDocument.parseXml(
    '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:xlink="http://www.w3.org/1999/xlink">'
    '<body>$body</body></html>',
  );
  final styles =
      StyleResolver([
        CssSheetSource(
          CssStyleSheet.parse(cssUserAgentStyleSheet),
          CssOrigin.userAgent,
        ),
        CssSheetSource(CssStyleSheet.parse(css), CssOrigin.author),
        ...readerSheetSources(book),
      ]).resolve(
        doc,
        options: StyleResolverOptions(rootFontSize: book.rootFontSize),
      );
  final layout = ColumnLayout.layout(
    buildSectionBoxes(doc, styles),
    width: width,
    pageHeight: pageHeight,
    bookStyle: book,
    text: TextLayoutEnvironment(
      styler: InlineStyler(bookStyle: book, fonts: const BookFonts()),
      imageSize: (src) => images[src],
      maxImageHeight: pageHeight,
    ),
  );
  addTearDown(layout.dispose);
  return layout;
}

List<double> tops(ColumnLayout c) => [for (final p in c.paragraphs) p.rect.top];

void main() {
  group('blocks', () {
    test('prose margins collapse between paragraphs and stay at the top', () {
      final c = column('<p>aaaa</p><p>bbbb</p>');
      expect(tops(c), [5, 28]);
      expect(c.height, 51);
      expect(c.paragraphs.first.rect.width, 100);
    });

    test(
      'a parent\'s margin collapses with its first child\'s until padding stops it',
      () {
        final book = ten.copyWith(useBookLayout: false);
        expect(
          tops(
            column(
              '<div style="margin-top: 20px"><p style="margin: 5px 0">a</p></div>',
              book: book,
            ),
          ),
          [20],
        );
        expect(
          tops(
            column(
              '<div style="margin-top: 20px; padding-top: 3px"><p style="margin: 5px 0">a</p></div>',
              book: book,
            ),
          ),
          [28],
        );
        expect(
          tops(
            column(
              '<p style="margin: 0 0 10px">a</p><p style="margin: -4px 0 0">b</p>',
              book: book,
            ),
          ),
          [0, 16],
          reason: 'positive and negative margins add up',
        );
        expect(
          tops(
            column(
              '<p style="margin: 0 0 10px">a</p><div style="margin: 30px 0"></div><p style="margin: 0">b</p>',
              book: book,
            ),
          ),
          [0, 40],
          reason: 'an empty block\'s margins collapse through it',
        );
      },
    );

    test('padding, borders, widths and auto margins', () {
      final book = ten.copyWith(useBookLayout: false);
      // Inside a wrapper: the reader zeroes horizontal padding and
      // margins of the body's own children, as foliate-js does.
      final c = column(
        '<div><div style="padding: 4px 6px; border: 2px solid red; margin: 0"><p style="margin: 0">a</p></div>'
        '<div style="width: 40px; margin: 0 auto"><p style="margin: 0">b</p></div>'
        '<div style="max-width: 50%; margin: 0 0 0 auto"><p style="margin: 0">c</p></div></div>',
        book: book,
      );
      final [a, b, cc] = c.paragraphs.toList();
      expect(a.rect, const Rect.fromLTWH(8, 6, 84, 10));
      expect(b.rect.left, 30);
      expect(b.rect.width, 40);
      expect(cc.rect.left, 50);
      expect(cc.rect.width, 50);
      final decoration = c.decorations.single;
      expect(decoration.rect, const Rect.fromLTWH(0, 0, 100, 22));
      expect(decoration.borderWidth.top, 2);
      expect(
        decoration.borderColor.top,
        0xFF000000,
        reason: 'the reader\'s text colour',
      );
      final direct = column(
        '<div style="padding: 4px 6px; margin: 0 9px"><p style="margin: 0">a</p></div>',
        book: book,
      );
      expect(direct.paragraphs.single.rect, const Rect.fromLTWH(0, 4, 100, 10));
    });

    test('backgrounds show when the book keeps its colours', () {
      const css = 'div { background-color: #eeeeee } p { margin: 0 }';
      final over = column('<div><p>a</p></div>', css: css);
      expect(over.decorations, isEmpty);
      final own = column(
        '<div><p>a</p></div>',
        css: css,
        book: ten.copyWith(overrideColor: false),
      );
      expect(own.decorations.single.background, 0xFFEEEEEE);
      expect(
        own.decorations.single.rect.top,
        own.paragraphs.single.rect.top,
        reason: 'collapsed margins sit outside the box',
      );
    });

    test('list markers sit before the content on the first baseline', () {
      final c = column(
        '<ul style="margin: 0"><li>one</li><li>two</li></ul><ol><li>x</li></ol>',
      );
      final markers = c.items.whereType<ColumnMarker>().toList();
      expect(markers, hasLength(3));
      final first = c.paragraphs.first;
      expect(first.rect.left, 40, reason: 'the list\'s padding');
      expect(
        markers.first.rect.right,
        closeTo(40 - 5, 1e-9),
        reason: 'half an em before',
      );
      final markerBaseline =
          markers.first.rect.top +
          markers.first.painter.computeDistanceToActualBaseline(
            TextBaseline.alphabetic,
          );
      expect(
        markerBaseline,
        closeTo(first.rect.top + first.paragraph.firstBaseline, 1e-9),
      );
      expect(markers.last.painter.plainText, '1. ');
    });
  });

  group('math functions', () {
    test('calc() sizes a block against its containing block', () {
      final c = column(
        '<div><div style="width: calc(50% - 10px); '
        'margin-left: calc(1em + 5px); padding-left: min(10%, 3px)">a</div>'
        '</div>',
        book: ten.copyWith(useBookLayout: false),
      );
      final text = c.paragraphs.single;
      expect(text.rect.left, 10 + 5 + 3);
      expect(text.rect.width, 50 - 10, reason: 'the content box');
    });

    test('a height with a percentage is no height, as a percentage is not', () {
      final c = column(
        '<div><div style="height: calc(100% - 1px); background: red">a</div>'
        '<div style="height: calc(2em + 10px); background: red">b</div></div>',
        book: ten.copyWith(useBookLayout: false, overrideColor: false),
      );
      final heights = [for (final d in c.decorations) d.rect.height];
      expect(heights, [10, 30]);
    });
  });

  group('images', () {
    test('block images fit the column and the page, centred by auto margins', () {
      final c = column(
        '<img src="wide.png" style="display: block; margin: 0 auto"/>'
        '<img src="small.png" style="display: block; margin: 0 auto"/>'
        '<img src="right.png" style="float: right"/>'
        '<div><svg viewBox="0 0 50 100"><image width="50" height="100" xlink:href="cover.jpg"/></svg></div>',
        pageHeight: 80,
        images: const {
          'wide.png': Size(400, 100),
          'small.png': Size(20, 20),
          'right.png': Size(30, 10),
        },
      );
      final rects = [for (final i in c.items.whereType<ColumnImage>()) i.rect];
      expect(rects[0], const Rect.fromLTWH(0, 0, 100, 25));
      expect(rects[1], const Rect.fromLTWH(40, 25, 20, 20));
      expect(rects[2], const Rect.fromLTWH(70, 45, 30, 10));
      expect(
        rects[3],
        const Rect.fromLTWH(30, 55, 40, 80),
        reason: 'a cover fits the page',
      );
      expect(c.items.whereType<ColumnImage>().last.src, 'cover.jpg');
    });
  });

  group('floats', () {
    List<Rect> images(ColumnLayout c) => [
      for (final i in c.items.whereType<ColumnImage>()) i.rect,
    ];

    /// The left edge of each line of [text]'s first character on it.
    List<double> lineStarts(ColumnText text) => [
      for (var i = 0; i < text.paragraph.lines.length; i++)
        text.paragraph
            .boxesFor(
              text.paragraph.lineStart(i),
              text.paragraph.lineStart(i) + 1,
            )
            .first
            .left,
    ];

    test('a drop cap floats left; the lines beside it are shortened', () {
      final c = column(
        '<p><span style="float: left; font-size: 30px; line-height: 1">I'
        '</span>aaaa bbbb cccc dddd eeee ffff gggg</p>',
      );
      final [cap, text] = c.paragraphs.toList();
      expect(cap.paragraph.box.text, 'I');
      expect(cap.rect.top, text.rect.top, reason: 'at the first line');
      expect(cap.rect.left, 0);
      // Two lines start beside its 30 px (tops 5 and 23, before 35).
      expect(lineStarts(text).take(3), [30, 30, 0]);
      expect(text.paragraph.lineTop(2), 36);
    });

    test('text wraps beside a floated image, then takes the width', () {
      final c = column(
        '<p><img src="a.png" style="float: right"/>'
        'aaaa bbbb cccc dddd eeee ffff gggg</p>',
        images: const {'a.png': Size(50, 40)},
      );
      expect(images(c), [const Rect.fromLTWH(50, 5, 50, 40)]);
      final text = c.paragraphs.single;
      expect(text.rect.top, 5);
      // Lines starting by 45 hold one word in the 50 px left.
      expect(text.paragraph.lineStart(1), 5);
      expect(text.paragraph.lineStart(2), 10);
      expect(text.paragraph.lineStart(3), 15);
      for (final b in text.paragraph.boxesFor(0, 14)) {
        expect(b.right, lessThanOrEqualTo(50.5));
      }
      expect(text.paragraph.lineStart(4), 25, reason: 'full width below');
      expect(c.height, greaterThanOrEqualTo(45));
    });

    test('a float between blocks is as high as the next line, after the '
        'margins above it collapse', () {
      final c = column(
        '<h1 style="margin: 0 0 30px">T</h1>'
        '<img src="a.png" style="float: left"/>'
        '<p style="margin-top: 40px">aaaa</p>',
        book: ten.copyWith(useBookLayout: false),
        images: const {'a.png': Size(20, 20)},
      );
      final text = c.paragraphs.last;
      expect(images(c).single.top, text.rect.top);
      expect(lineStarts(text), [20]);
    });

    test('a float\'s own percentages are of its containing block', () {
      final c = column(
        // In a wrapper: foliate-js takes the side margins of the body's
        // children away.
        '<div><div style="float: left; width: 20%; margin-left: 10%">aa'
        '</div><p>bbbb cccc</p></div>',
      );
      final [side, text] = c.paragraphs.toList();
      expect(side.rect.left, 10);
      expect(side.rect.width, 20);
      expect(lineStarts(text).first, 30);
    });

    test('a negative top margin raises a float; its margin box may then '
        'shorten no line', () {
      final c = column(
        '<p><img src="a.png" style="float: left; margin-top: -30px"/>'
        'aaaa</p>',
        images: const {'a.png': Size(20, 20)},
      );
      expect(images(c).single.top, 5 - 30);
      expect(lineStarts(c.paragraphs.single), [0]);
    });

    test('floats stand side by side; one that does not fit goes below', () {
      final c = column(
        '<p><img src="a.png" style="float: left"/>'
        '<img src="b.png" style="float: left"/>'
        '<img src="c.png" style="float: left"/>aaaa</p>',
        images: const {
          'a.png': Size(40, 20),
          'b.png': Size(40, 30),
          'c.png': Size(40, 10),
        },
      );
      expect(images(c), [
        const Rect.fromLTWH(0, 5, 40, 20),
        const Rect.fromLTWH(40, 5, 40, 30),
        const Rect.fromLTWH(0, 35, 40, 10),
      ]);
      // 20 px left beside them: two glyphs a line.
      final text = c.paragraphs.single;
      expect(lineStarts(text).first, 80);
    });

    test('clear starts a block below the floats it names', () {
      final c = column(
        '<p><img src="a.png" style="float: left"/>a</p>'
        '<p style="clear: right">b</p>'
        '<p style="clear: left">c</p>',
        images: const {'a.png': Size(30, 60)},
      );
      final [a, b, cc] = c.paragraphs.toList();
      expect(a.rect.top, 5);
      expect(b.rect.top, 28, reason: 'no right float');
      expect(cc.rect.top, 70, reason: 'below the float, then its margin');
      expect(lineStarts(b), [30]);
    });

    test('a float with a width lays its content out at it', () {
      final c = column(
        '<div style="float: right; width: 40px">aaaa bbbb</div>'
        '<p>cccc dddd eeee</p>',
      );
      final [side, text] = c.paragraphs.toList();
      expect(side.rect.left, 60);
      expect(side.rect.width, 40);
      expect(side.paragraph.lines, hasLength(2));
      expect(text.paragraph.lineStart(1), 5);
    });

    test('the column holds its floats; images and tables go below them', () {
      final c = column(
        '<p><img src="a.png" style="float: left"/>a</p>'
        '<img src="b.png" style="display: block"/>',
        images: const {'a.png': Size(30, 60), 'b.png': Size(20, 20)},
      );
      expect(images(c).last.top, 65);
      final tall = column(
        '<p><img src="a.png" style="float: left"/>a</p>',
        images: const {'a.png': Size(30, 60)},
      );
      expect(tall.contentHeight, 65);
    });

    test('a page does not break beside a float', () {
      final c = column(
        '<p><img src="a.png" style="float: left"/>'
        '${List.filled(12, 'aaaa').join(' ')}</p>',
        images: const {'a.png': Size(40, 60)},
      );
      for (final b in c.breaks) {
        final inside = b.y > 5.5 && b.y < 64.5;
        expect(
          b.kind,
          inside ? ColumnBreakKind.avoid : ColumnBreakKind.allowed,
          reason: 'at ${b.y}',
        );
      }
      expect(
        c.breaks.where((b) => b.kind == ColumnBreakKind.allowed),
        isNotEmpty,
      );
    });

    test('a table cell\'s floats stay in the cell', () {
      final c = column(
        '<table><tr><td><img src="a.png" style="float: left"/>a</td></tr>'
        '</table><p>bbbb</p>',
        images: const {'a.png': Size(30, 40)},
      );
      final text = c.paragraphs.last;
      expect(lineStarts(text), [0]);
      expect(
        text.rect.top,
        greaterThanOrEqualTo(images(c).single.bottom),
        reason: 'the cell is as tall as its float',
      );
    });
  });

  group('box sizing and corners', () {
    test('border-box sizes count the padding and border', () {
      final c = column(
        // Not under the body: the reader's sheet unpads body > div.
        '<section><div style="width: 50px; padding: 5px; border: 2px solid; '
        'box-sizing: border-box"><p style="margin: 0">a</p></div>'
        '<div style="width: 50px; padding: 5px; border: 2px solid">'
        '<p style="margin: 0">b</p></div></section>',
        book: const BookStyle(fontScale: 10 / 16, useBookLayout: false),
      );
      final [a, b] = c.paragraphs.toList();
      expect(a.rect.width, 50 - 2 * (5 + 2));
      expect(b.rect.width, 50);
      final [first, second] = c.decorations.toList();
      expect(first.rect.width, 50);
      expect(second.rect.width, 50 + 2 * (5 + 2));
    });

    test('a set height with border-box includes the edges', () {
      final c = column(
        '<div style="height: 40px; padding: 5px; border: 1px solid; '
        'box-sizing: border-box"></div>',
      );
      expect(c.decorations.single.rect.height, 40);
    });

    test('decorations keep the corners\' radii', () {
      final c = column(
        '<div style="border: 1px solid; border-radius: 4px 50%">'
        '<p>a</p></div>',
      );
      final radius = c.decorations.single.radius;
      expect(radius.topLeft, const CssRadius(CssLength.px(4), CssLength.px(4)));
      expect(
        radius.topRight,
        const CssRadius(CssLength.percent(50), CssLength.percent(50)),
      );
    });
  });

  group('tables', () {
    // The test font: every glyph is 10px wide and tall; cells have the
    // user agent's 1px padding.
    const noLayout = BookStyle(fontScale: 10 / 16, useBookLayout: false);

    test('columns as wide as their content, when it fits', () {
      final c = column(
        '<table style="margin: 0; border-spacing: 0"><tr><td>a</td><td>bb</td></tr></table>',
        book: noLayout,
      );
      final [a, b] = c.paragraphs.toList();
      expect(a.rect.left, 1);
      expect(b.rect.left, 12 + 1);
      expect(b.rect.width, 20);
    });

    test('a set width shares its room in proportion to the content', () {
      final c = column(
        '<table style="margin: 0; width: 100%; border-spacing: 0"><tr><td>a</td><td>bbb</td></tr></table>',
        book: noLayout,
      );
      final [a, b] = c.paragraphs.toList();
      // Widest content 12 and 32 of 44: 100px in that proportion.
      expect(a.rect.width, closeTo(100 * 12 / 44 - 2, 1e-9));
      expect(b.rect.left, closeTo(100 * 12 / 44 + 1, 1e-9));
    });

    test('content too wide: from the narrowest towards the widest', () {
      final c = column(
        '<table style="margin: 0; border-spacing: 0"><tr><td>a b c d e</td><td>ffff ggg</td></tr></table>',
        book: noLayout,
      );
      final [a, b] = c.paragraphs.toList();
      // Narrowest 12 and 42, widest 92 and 82: the 46px over the narrowest
      // go 80:40.
      expect(a.rect.width, closeTo(12 + 46 * 80 / 120 - 2, 1e-9));
      expect(b.rect.width, closeTo(42 + 46 * 40 / 120 - 2, 1e-9));
      expect(b.paragraph.lines, hasLength(2), reason: 'wraps at a space');
    });

    test('rows as tall as their tallest cell: cells reach its bottom and '
        'centre their content', () {
      final c = column(
        '<table style="margin: 0; width: 100%; border-spacing: 0"><tr>'
        '<td style="border: 1px solid">a</td>'
        '<td style="border: 1px solid; vertical-align: top">bbbb bbbb bbbb</td>'
        '<td style="border: 1px solid; vertical-align: bottom">c</td>'
        '</tr><tr><td colspan="3">d</td></tr></table>',
        book: noLayout,
        width: 120,
      );
      final [a, b, cc, d] = c.paragraphs.toList();
      expect(b.paragraph.lines.length, greaterThan(1));
      final rowBottom = b.rect.bottom + 1 + 1;
      final cells = c.decorations.toList();
      expect(cells, hasLength(3));
      for (final cell in cells) {
        expect(cell.rect.top, 0);
        expect(cell.rect.bottom, rowBottom, reason: 'the row\'s height');
      }
      final inside = rowBottom - 2 * (1 + 1);
      expect(a.rect.top, closeTo(2 + (inside - 10) / 2, 1e-9));
      expect(b.rect.top, 2, reason: 'vertical-align: top');
      expect(cc.rect.bottom, rowBottom - 2, reason: 'vertical-align: bottom');
      expect(d.rect.top, rowBottom + 1, reason: 'the next row');
      expect(d.rect.width, closeTo(120 - 2, 1e-9), reason: 'spans the row');
      expect(c.breaks.map((b) => b.y), [rowBottom], reason: 'between rows');
    });

    test('separated borders: spacing around and between cells, the '
        'table\'s own border and padding outside it', () {
      final c = column(
        '<table style="margin: 0; border: 3px solid; padding: 4px; '
        'border-spacing: 5px 6px">'
        '<tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>',
        book: noLayout,
      );
      final [a, b, cc, d] = c.paragraphs.toList();
      // Border 3, padding 4, spacing 5; cells have 1px padding.
      expect(a.rect.left, 3 + 4 + 5 + 1);
      expect(b.rect.left, 3 + 4 + 5 + 12 + 5 + 1);
      expect(a.rect.top, 3 + 4 + 6 + 1);
      expect(cc.rect.top, a.rect.bottom + 1 + 6 + 1, reason: 'row spacing');
      expect(d.rect.left, b.rect.left);
      final table = c.decorations.single;
      expect(table.rect.left, 0);
      expect(table.rect.width, 3 + 4 + 5 + 12 + 5 + 12 + 5 + 4 + 3);
      expect(table.rect.top, 0);
      expect(table.rect.bottom, cc.rect.bottom + 1 + 6 + 4 + 3);
      expect(table.borderWidth, const CssEdges.all(3.0));
    });

    test('the user agent separates cells by 2px', () {
      final c = column(
        '<table style="margin: 0"><tr><td>a</td><td>bb</td></tr></table>',
        book: noLayout,
      );
      final [a, b] = c.paragraphs.toList();
      expect(a.rect.left, 2 + 1);
      expect(b.rect.left, 2 + 12 + 2 + 1);
    });

    test('collapsed borders: one line between cells, the wider winning', () {
      final c = column(
        '<table style="margin: 0; border-collapse: collapse; border: 4px solid">'
        '<tr><td style="border: 2px solid">a</td>'
        '<td style="border: 1px solid">b</td></tr></table>',
        book: noLayout,
      );
      final [a, b] = c.paragraphs.toList();
      final [first, second] = c.decorations.toList();
      // a: the table's 4px outside, its own 2px against b's 1px.
      expect(first.borderWidth, const CssEdges(4.0, 2.0, 4.0, 4.0));
      expect(second.borderWidth, const CssEdges(4.0, 4.0, 4.0, 2.0));
      // Each cell holds half of its borders: half the table's 4px stays
      // outside the first column.
      expect(a.rect.left, 2 + 2 + 1);
      final aColumn = 2 + 1 + 10 + 1 + 1;
      expect(b.rect.left, 2 + aColumn + 1 + 1);
      // The shared line is drawn centred on the grid line, by both.
      expect(first.rect.right, 2 + aColumn + 1);
      expect(second.rect.left, 2 + aColumn - 1);
      expect(first.rect.top, 0);
      expect(first.rect.left, 0);
      expect(c.height, first.rect.bottom, reason: 'the table\'s bottom');
    });

    test('collapsed borders: hidden suppresses, ties go by style', () {
      final c = column(
        '<table style="margin: 0; border-collapse: collapse"><tr>'
        '<td style="border: 1px solid; border-right: 3px hidden">a</td>'
        '<td style="border-left: 5px solid; border-right: 2px solid">b</td>'
        '<td style="border-left: 2px double">c</td></tr></table>',
        book: noLayout,
      );
      final [a, b, cc] = c.decorations.toList();
      expect(a.borderWidth.right, 0);
      expect(b.borderWidth.left, 0);
      expect(b.borderStyle.right, CssBorderStyle.double);
      expect(cc.borderStyle.left, CssBorderStyle.double);
    });

    test('a cell spanning rows takes their slots and ties them together', () {
      final c = column(
        '<table style="margin: 0; border-spacing: 0"><tr>'
        '<td rowspan="2" style="border: 1px solid">a</td><td>b</td></tr>'
        '<tr><td>c</td></tr><tr><td>d</td><td>e</td></tr></table>',
        book: noLayout,
      );
      final [a, b, cc, d, e] = c.paragraphs.toList();
      expect(cc.rect.left, b.rect.left, reason: 'c is in the second column');
      expect(d.rect.left, lessThan(a.rect.right));
      expect(e.rect.left, b.rect.left);
      final spanning = c.decorations.single;
      expect(spanning.rect.bottom, cc.rect.bottom + 1, reason: 'two rows');
      // A break before the third row, none between the two it spans.
      final breaks = c.breaks.map((b) => b.y).toList();
      expect(breaks, contains(d.rect.top - 1));
      expect(breaks, isNot(contains(cc.rect.top - 1)));
    });

    test('a cell spanning rows makes the last of them taller', () {
      final c = column(
        '<table style="margin: 0; border-spacing: 0"><tr>'
        '<td rowspan="2">a a a a a</td><td>b</td></tr>'
        '<tr><td>c</td></tr></table>',
        book: noLayout,
        width: 40,
      );
      final [a, _, cc] = c.paragraphs.toList();
      expect(a.paragraph.lines.length, greaterThan(2));
      expect(c.height, a.rect.bottom + 1, reason: 'as tall as the span');
      expect(cc.rect.bottom, lessThan(a.rect.bottom), reason: 'centred');
    });

    test('a caption goes above, or below with caption-side', () {
      final above = column(
        '<table style="margin: 0"><caption>t</caption><tr><td>a</td></tr></table>',
        book: noLayout,
      );
      expect(above.paragraphs.first.paragraph.box.text, 't');
      expect(
        above.paragraphs.first.rect.top,
        lessThan(above.paragraphs.last.rect.top),
      );
      final below = column(
        '<table style="margin: 0; caption-side: bottom"><caption>t</caption>'
        '<tr><td>a</td></tr></table>',
        book: noLayout,
      );
      final [cell, caption] = below.paragraphs.toList();
      expect(caption.paragraph.box.text, 't');
      expect(caption.rect.top, greaterThan(cell.rect.bottom));
    });

    test('row backgrounds lie under the cells', () {
      final c = column(
        '<table style="margin: 0; border-spacing: 0">'
        '<tr style="background: #eee"><td style="border: 1px solid">a</td></tr>'
        '</table>',
        book: noLayout.copyWith(overrideColor: false),
      );
      final [row, cell] = c.decorations.toList();
      expect(row.background, 0xFFEEEEEE);
      expect(row.rect, cell.rect);
    });

    test('max-width and min-width bound a table', () {
      final narrow = column(
        '<table style="margin: 0; border-spacing: 0; max-width: 50px"><tr>'
        '<td>a b c d e f g</td></tr></table>',
        book: noLayout,
      );
      expect(narrow.paragraphs.single.rect.width, 50 - 2);
      final wide = column(
        '<table style="margin: 0; border-spacing: 0; min-width: 80px"><tr>'
        '<td>a</td></tr></table>',
        book: noLayout,
      );
      expect(wide.paragraphs.single.rect.width, 80 - 2);
      expect(narrow.scrollers, isEmpty);
    });

    group('a table that scrolls', () {
      const scrolling = 'margin: 0; border-spacing: 0; overflow-x: auto';

      test('keeps its words whole, wider than the column', () {
        final c = column(
          '<table style="$scrolling"><tr><td>aaaaaa</td><td>bbbbbbb</td></tr>'
          '<tr><td>c</td><td>d</td></tr></table><p>after</p>',
          book: noLayout,
        );
        final [a, b, cc, d, after] = c.paragraphs.toList();
        // Its narrowest: 62 and 72, the words and the cells' padding.
        expect(a.rect.width, 60);
        expect(b.rect.left, 62 + 1);
        expect(b.rect.right, 134 - 1);
        expect(a.paragraph.lines, hasLength(1));
        expect(b.paragraph.lines, hasLength(1));
        final scroller = c.scrollers.single;
        expect(scroller.viewport.left, 0);
        expect(scroller.viewport.width, 100);
        expect(scroller.viewport.top, 0);
        expect(scroller.viewport.bottom, d.rect.bottom + 1);
        expect(scroller.contentLeft, 0);
        expect(scroller.contentWidth, 134);
        expect(scroller.minOffset, 0);
        expect(scroller.maxOffset, 34);
        for (final item in [a, b, cc, d]) {
          expect(item.scroller, same(scroller));
        }
        expect(after.scroller, isNull);
        expect(after.rect.width, 100);
        expect(c.decorations, isEmpty, reason: 'no borders or backgrounds');
      });

      test('as wide as max-content up to its max-width', () {
        final c = column(
          '<table style="$scrolling; width: max-content; max-width: 150px">'
          '<tr><td style="border: 1px solid">aaa bbb ccc ddd eee</td>'
          '<td>f</td></tr></table>',
          book: noLayout,
        );
        final scroller = c.scrollers.single;
        expect(scroller.contentWidth, 150);
        final [a, f] = c.paragraphs.toList();
        expect(a.paragraph.lines.length, greaterThan(1), reason: 'it wraps');
        expect(f.rect.right, 150 - 1);
        final cell = c.decorations.single;
        expect(cell.scroller, same(scroller));
      });

      test('that fits does not scroll', () {
        final c = column(
          '<table style="$scrolling"><tr><td>a</td><td>bb</td></tr></table>',
          book: noLayout,
        );
        expect(c.scrollers, isEmpty);
        expect(c.paragraphs.every((p) => p.scroller == null), isTrue);
        expect(c.paragraphs.last.rect.width, 20);
      });

      test('right to left: from the right edge, scrolled from it', () {
        final c = column(
          '<table dir="rtl" style="$scrolling"><tr><td>aaaaaa</td>'
          '<td>bbbbbbb</td></tr></table>',
          book: noLayout,
        );
        final scroller = c.scrollers.single;
        expect(scroller.contentLeft, 100 - 134);
        expect(scroller.minOffset, -34);
        expect(scroller.maxOffset, 0);
        // The content ends at the column's right edge.
        expect(c.paragraphs.last.rect.right, 100 - 1);
        expect(c.paragraphs.first.rect.left, 100 - 134 + 1);
      });

      test('its caption stays in the column; a table in it never scrolls '
          'alone', () {
        final c = column(
          '<table style="$scrolling"><caption>cap</caption><tr>'
          '<td><table style="$scrolling"><tr><td>aaaaaa</td><td>bbbbbbb</td>'
          '</tr></table></td></tr></table>',
          book: noLayout,
        );
        final scroller = c.scrollers.single;
        final [caption, a, b] = c.paragraphs.toList();
        expect(caption.scroller, isNull);
        expect(caption.rect.right, lessThanOrEqualTo(100));
        expect(a.scroller, same(scroller));
        expect(b.scroller, same(scroller));
        expect(scroller.viewport.top, caption.rect.bottom);
      });

      test('scrolls within its content', () {
        final c = column(
          '<table style="$scrolling"><tr><td>aaaaaa</td><td>bbbbbbb</td>'
          '</tr></table>',
          book: noLayout,
        );
        final scroller = c.scrollers.single;
        expect(scroller.canScroll(10), isTrue);
        expect(scroller.canScroll(-10), isFalse);
        scroller.scrollTo(100);
        expect(scroller.offset.value, 34);
        expect(scroller.canScroll(10), isFalse);
        expect(scroller.toView(const Offset(50, 5)), const Offset(16, 5));
        expect(scroller.toContent(const Offset(16, 5)), const Offset(50, 5));
        scroller.scrollTo(-5);
        expect(scroller.offset.value, 0);
      });
    });

    test('a table narrower than the column follows its margins', () {
      final centred = column(
        '<table style="margin: 0 auto; border-spacing: 0"><tr><td>a</td></tr></table>',
        book: noLayout,
      );
      expect(centred.paragraphs.single.rect.left, (100 - 12) / 2 + 1);
    });
  });

  group('breaks', () {
    test('lines are break opportunities, within orphans and widows', () {
      final c = column('<p>${List.filled(6, 'aaaa').join(' ')}</p>', width: 50);
      final paragraph = c.paragraphs.single;
      expect(paragraph.paragraph.lines, hasLength(6));
      expect(c.breaks.map((b) => b.y), [
        for (var i = 2; i <= 4; i++) paragraph.rect.top + 18.0 * i,
      ]);
    });

    test('forced breaks, headings kept with the next block, avoid inside', () {
      final c = column(
        '<p>a</p><h2 style="margin: 0">h</h2><p>b</p>'
        '<p style="page-break-before: always">c</p>'
        '<div style="page-break-inside: avoid"><p>d</p><p>e</p></div>',
      );
      final kinds = [for (final b in c.breaks) b.kind];
      expect(kinds, [
        ColumnBreakKind.allowed,
        ColumnBreakKind.avoid,
        ColumnBreakKind.forced,
        ColumnBreakKind.allowed,
        ColumnBreakKind.avoid,
      ]);
      final [_, _, b, cc, d, e] = c.paragraphs.toList();
      expect(c.breaks[1].y, b.rect.top, reason: 'after the heading');
      expect(c.breaks[2].y, cc.rect.top);
      expect(c.breaks[3].y, d.rect.top);
      expect(c.breaks[4].y, e.rect.top);
    });
  });

  group('pages', () {
    test('a break between blocks truncates their margins, as CSS does', () {
      // Lines of 20 px with 30 px after each: what fits is the content.
      final c = column(
        List.generate(5, (i) => '<p>p$i</p>').join(),
        css: 'p { margin: 0 0 30px; font-size: 10px; line-height: 20px }',
        book: ten.copyWith(useBookLayout: false),
      );
      expect(c.contentHeight, 220);
      expect(c.height, 250, reason: 'with the last margin');
      final pages = paginateColumn(c, pageHeight: 70);
      expect(pages, const [
        ColumnPage(0, 70),
        ColumnPage(100, 170),
        ColumnPage(200, 220),
      ], reason: 'the margin after the last line takes no page');
      expect(c.breaks.first.y, 50);
      expect(c.breaks.first.fit, 20);
    });

    test('pages cover the column end to end without overfilling', () {
      final c = column(
        List.generate(
          30,
          (i) => '<p>${List.filled(5, 'word').join(' ')}</p>',
        ).join(),
        width: 120,
      );
      final pages = paginateColumn(c, pageHeight: 200);
      expect(pages.first.top, 0);
      expect(pages.last.bottom, c.contentHeight);
      for (var i = 0; i < pages.length; i++) {
        expect(pages[i].height, lessThanOrEqualTo(200.5));
        expect(
          pages[i].height,
          greaterThan(100),
          reason: 'no half-empty pages here',
        );
        if (i > 0) {
          // Between pages only the margins the break truncated.
          expect(pages[i].top, greaterThanOrEqualTo(pages[i - 1].bottom));
          expect(
            c.items.where(
              (item) =>
                  item.rect.top < pages[i].top &&
                  item.rect.bottom > pages[i - 1].bottom,
            ),
            isEmpty,
          );
        }
      }
      // Every line is whole on one page.
      for (final p in c.paragraphs) {
        for (var line = 0; line < p.paragraph.lines.length; line++) {
          final top = p.rect.top + p.paragraph.lineTop(line);
          final bottom = p.rect.top + p.paragraph.lineTop(line + 1);
          final page = pages.firstWhere((pg) => pg.contains(top));
          expect(bottom, lessThanOrEqualTo(page.bottom + 0.5));
        }
      }
    });

    test('a forced break truncates the margins above it, as CSS does', () {
      // The page ends at the second line, its margin would overfill it.
      final c = column(
        '<p>a</p><p>b</p><p style="page-break-before: always">c</p>',
        css: 'p { margin: 0 0 30px; font-size: 10px; line-height: 20px }',
        book: ten.copyWith(useBookLayout: false),
      );
      final pages = paginateColumn(c, pageHeight: 75);
      expect(pages, const [ColumnPage(0, 70), ColumnPage(100, 120)]);
    });

    test('a forced break ends the page; nothing forces an empty first page', () {
      final c = column(
        '<p style="page-break-before: always">a</p><p style="page-break-before: always">b</p>',
      );
      final pages = paginateColumn(c, pageHeight: 500);
      expect(pages, hasLength(2));
      expect(pages[1].top, c.paragraphs.last.rect.top);
    });

    test('a heading does not end a page when a later break fits', () {
      final c = column(
        '${List.generate(5, (i) => '<p>p$i</p>').join()}<h2 style="margin: 0">h</h2><p>after</p><p>more</p>',
      );
      final heading = c.paragraphs.elementAt(5);
      final after = c.paragraphs.elementAt(6);
      final pageHeight = heading.rect.bottom + 2;
      final pages = paginateColumn(c, pageHeight: pageHeight);
      expect(
        pages.first.bottom,
        lessThanOrEqualTo(heading.rect.top + 0.5),
        reason: 'the heading moves to the next page with what follows',
      );
      expect(pages[1].contains(after.rect.top), isTrue);
    });

    test('content taller than a page with no break is cut at the page', () {
      final c = column(
        '<table><tr><td>${List.filled(40, 'x').join(' ')}</td></tr></table>',
        width: 60,
      );
      final pages = paginateColumn(c, pageHeight: 50);
      expect(pages.first.height, 50);
      expect(pages.last.bottom, c.height);
    });

    test('a task lays out in steps; the pages it decides never change', () {
      final body = List.generate(
        40,
        (i) => '<p>${List.filled(6, 'word$i').join(' ')}</p>',
      ).join();
      final whole = column(body, width: 120);
      final wholePages = paginateColumn(whole, pageHeight: 200);

      final doc = ContentDocument.parseXml(
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>$body</body></html>',
      );
      final styles =
          StyleResolver([
            CssSheetSource(
              CssStyleSheet.parse(cssUserAgentStyleSheet),
              CssOrigin.userAgent,
            ),
            ...readerSheetSources(ten),
          ]).resolve(
            doc,
            options: StyleResolverOptions(rootFontSize: ten.rootFontSize),
          );
      final task = ColumnLayoutTask(
        buildSectionBoxes(doc, styles),
        width: 120,
        pageHeight: 200,
        bookStyle: ten,
        text: TextLayoutEnvironment(
          styler: InlineStyler(bookStyle: ten, fonts: const BookFonts()),
          imageSize: (_) => null,
          maxImageHeight: 200,
        ),
      );
      addTearDown(task.column.dispose);
      expect(task.column.isComplete, isFalse);
      expect(paginateColumn(task.column, pageHeight: 200), isEmpty);

      expect(task.advance(untilHeight: 450), isFalse);
      expect(task.column.height, greaterThanOrEqualTo(450));
      final early = paginateColumn(task.column, pageHeight: 200);
      expect(early, isNotEmpty);
      expect(early, wholePages.take(early.length).toList());
      expect(early.last.top + 200, lessThanOrEqualTo(task.column.height + 0.5));

      var steps = 0;
      while (!task.advance(budget: Duration.zero)) {
        steps++;
      }
      expect(steps, greaterThan(10), reason: 'one paragraph per step');
      expect(task.column.isComplete, isTrue);
      expect(task.column.height, whole.height);
      expect(paginateColumn(task.column, pageHeight: 200), wholePages);
      expect(
        task.column.breaks.map((b) => b.y),
        whole.breaks.map((b) => b.y),
      );
    });

    test('open boxes show their decoration down to the laid-out height', () {
      final body =
          '<div style="border: 2px solid red; margin: 0">${List.generate(10, (i) => '<p>p$i</p>').join()}</div>';
      final doc = ContentDocument.parseXml(
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>$body</body></html>',
      );
      final styles =
          StyleResolver([
            CssSheetSource(
              CssStyleSheet.parse(cssUserAgentStyleSheet),
              CssOrigin.userAgent,
            ),
          ]).resolve(
            doc,
            options: StyleResolverOptions(rootFontSize: ten.rootFontSize),
          );
      final task = ColumnLayoutTask(
        buildSectionBoxes(doc, styles),
        width: 100,
        pageHeight: 200,
        bookStyle: ten,
        text: TextLayoutEnvironment(
          styler: InlineStyler(bookStyle: ten, fonts: const BookFonts()),
          imageSize: (_) => null,
          maxImageHeight: 200,
        ),
      );
      addTearDown(task.column.dispose);
      task.advance(untilHeight: 60);
      final open = task.column.decorations.single;
      expect(open.rect.bottom, task.column.height);
      task.advance();
      final closed = task.column.decorations.single;
      expect(open.rect.top, closed.rect.top, reason: 'the body\'s 8 px margin');
      expect(closed.rect.bottom, task.column.height - 8);
      expect(closed.rect.bottom, greaterThan(open.rect.bottom));
    });

    testWidgets('complete() finishes in slices, yielding between them', (
      tester,
    ) async {
      final doc = ContentDocument.parseXml(
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>${List.generate(50, (i) => '<p>paragraph $i</p>').join()}</body></html>',
      );
      final styles =
          StyleResolver([
            CssSheetSource(
              CssStyleSheet.parse(cssUserAgentStyleSheet),
              CssOrigin.userAgent,
            ),
          ]).resolve(
            doc,
            options: StyleResolverOptions(rootFontSize: ten.rootFontSize),
          );
      final task = ColumnLayoutTask(
        buildSectionBoxes(doc, styles),
        width: 100,
        pageHeight: 200,
        bookStyle: ten,
        text: TextLayoutEnvironment(
          styler: InlineStyler(bookStyle: ten, fonts: const BookFonts()),
          imageSize: (_) => null,
          maxImageHeight: 200,
        ),
      );
      addTearDown(task.column.dispose);
      var pauses = 0;
      await task.complete(
        slice: Duration.zero,
        pause: () async => pauses++,
      );
      expect(task.isComplete, isTrue);
      expect(task.column.paragraphs, hasLength(50));
      expect(
        pauses,
        50,
        reason:
            'a zero slice pauses after every paragraph; the last step '
            'closes the blocks around them',
      );
    });

    test('an empty column is one empty page', () {
      final c = column('');
      expect(paginateColumn(c, pageHeight: 100), [const ColumnPage(0, 0)]);
    });
  });
}
