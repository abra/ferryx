import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/layout/column_decoration.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  const area = Rect.fromLTWH(10, 20, 200, 100);
  const icon = Size(40, 20);

  test('a decoration\'s padding box is inside its borders', () {
    const decoration = ColumnDecoration(
      rect: Rect.fromLTWH(0, 0, 100, 50),
      background: 0,
      borderWidth: CssEdges(1, 2, 3, 4),
      borderStyle: CssEdges.all(CssBorderStyle.solid),
      borderColor: CssEdges.all(0),
    );
    expect(decoration.paddingBox, const Rect.fromLTRB(4, 1, 98, 47));
  });

  test('an image that does not repeat sits at its position', () {
    Rect only(CssLength x, CssLength y) => backgroundTiles(
      CssBackgroundImage('i.png', repeatX: false, repeatY: false, x: x, y: y),
      icon,
      area,
    ).single;
    expect(
      only(const CssLength.percent(0), const CssLength.percent(0)),
      const Rect.fromLTWH(10, 20, 40, 20),
    );
    expect(
      only(const CssLength.percent(50), const CssLength.percent(50)),
      const Rect.fromLTWH(90, 60, 40, 20),
      reason: 'its centre on the box\'s',
    );
    expect(
      only(const CssLength.percent(100), const CssLength.px(5)),
      const Rect.fromLTWH(170, 25, 40, 20),
    );
  });

  test('a set width keeps the ratio; cover and contain fill the box', () {
    Size sizeOf(CssBackgroundImage image) =>
        backgroundTiles(image, icon, area).first.size;
    expect(
      sizeOf(
        const CssBackgroundImage(
          'i.png',
          width: CssLength.px(80),
          repeatX: false,
          repeatY: false,
        ),
      ),
      const Size(80, 40),
    );
    expect(
      sizeOf(
        const CssBackgroundImage(
          'i.png',
          height: CssLength.percent(50),
          repeatX: false,
          repeatY: false,
        ),
      ),
      const Size(100, 50),
    );
    expect(
      sizeOf(
        const CssBackgroundImage(
          'i.png',
          fit: CssBackgroundFit.cover,
          repeatX: false,
          repeatY: false,
        ),
      ),
      const Size(200, 100),
    );
    expect(
      sizeOf(
        const CssBackgroundImage(
          'i.png',
          fit: CssBackgroundFit.contain,
          repeatX: false,
          repeatY: false,
        ),
      ),
      const Size(200, 100),
    );
    expect(
      sizeOf(
        const CssBackgroundImage(
          'i.png',
          fit: CssBackgroundFit.contain,
          repeatX: false,
          repeatY: false,
        ),
      ),
      sizeOf(
        const CssBackgroundImage(
          'i.png',
          fit: CssBackgroundFit.cover,
          repeatX: false,
          repeatY: false,
        ),
      ),
      reason: 'the ratio of the box is the image\'s',
    );
  });

  test('repeated tiles cover the box from the position, both ways', () {
    final tiles = backgroundTiles(
      const CssBackgroundImage(
        'i.png',
        x: CssLength.percent(50),
        y: CssLength.percent(0),
      ),
      icon,
      area,
    );
    // 200 px from x 90 both ways: tiles at 10, 50, 90, 130, 170; five
    // rows of 20 px.
    expect(tiles, hasLength(5 * 5));
    expect(tiles.map((t) => t.left).toSet(), {10, 50, 90, 130, 170});
    expect(tiles.map((t) => t.top).toSet(), {20, 40, 60, 80, 100});
    final across = backgroundTiles(
      const CssBackgroundImage('i.png', repeatY: false),
      icon,
      area,
    );
    expect(across, hasLength(5));
    expect(across.every((t) => t.top == 20), isTrue);
  });

  test('only what is visible, and never too many tiles', () {
    final tiles = backgroundTiles(
      const CssBackgroundImage('i.png'),
      icon,
      area,
      visible: const Rect.fromLTRB(0, 0, 1000, 45),
    );
    expect(tiles.map((t) => t.top).toSet(), {20, 40});
    expect(
      backgroundTiles(
        const CssBackgroundImage('i.png'),
        const Size(1, 1),
        area,
        limit: 50,
      ),
      hasLength(50),
    );
    expect(
      backgroundTiles(const CssBackgroundImage('i.png'), Size.zero, area),
      isEmpty,
    );
  });

  test('the boxes list a block\'s background image among the images', () {
    final doc = ContentDocument.parseXml(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
      '<div style="background-image: url(note.png)">a</div></body></html>',
    );
    final styles = StyleResolver([
      CssSheetSource(
        CssStyleSheet.parse(cssUserAgentStyleSheet),
        CssOrigin.userAgent,
      ),
    ]).resolve(doc);
    expect(buildSectionBoxes(doc, styles).imageSources, ['note.png']);
  });
}
