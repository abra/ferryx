import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/djvu.dart';

import 'djvu_fixture.dart';

void main() {
  late Directory directory;
  late DjvuBook book;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pagecraft-djvu-render-');
    final file = File('${directory.path}/original.djvu');
    await file.writeAsBytes(djvuFixtureBytes());
    book = await DjvuBook.open(file.path);
  });

  tearDown(() async {
    await book.close();
    await directory.delete(recursive: true);
  });

  test('renders portrait and landscape pages at the requested width', () async {
    final portrait = await book.renderPage(0, targetWidth: 300);
    expect(portrait.width, 300);
    expect(portrait.height, 450);
    expect(portrait.pixels.length, 300 * 450 * 4);
    final landscape = await book.renderPage(1, targetWidth: 450);
    expect(landscape.width, 450);
    expect(landscape.height, 300);
  });

  test(
    'decoded bytes contain white paper and black artwork with opaque alpha',
    () async {
      final page = await book.renderPage(0, targetWidth: 300);
      var paper = 0;
      var ink = 0;
      var tinted = 0;
      var transparent = 0;
      for (var index = 0; index < page.pixels.length; index += 4) {
        final red = page.pixels[index];
        final green = page.pixels[index + 1];
        final blue = page.pixels[index + 2];
        if (red > 245 && green > 245 && blue > 245) paper++;
        if (red < 80 && green < 80 && blue < 80) ink++;
        if (red != green || green != blue) tinted++;
        if (page.pixels[index + 3] != 255) transparent++;
      }
      expect(paper, greaterThan(page.width * page.height * 0.8));
      expect(ink, greaterThan(500));
      expect(tinted, 0, reason: 'bitonal pixels have equal RGB channels');
      expect(transparent, 0);
    },
  );

  test(
    'a zoom region has the same pixels as that area of the full render',
    () async {
      final whole = await book.renderPage(0, targetWidth: 300);
      const region = (x: 40, y: 210, width: 180, height: 90);
      final tile = await book.renderPage(0, targetWidth: 300, region: region);
      expect(tile.width, region.width);
      expect(tile.height, region.height);
      var mismatches = 0;
      var ink = 0;
      for (var y = 0; y < region.height; y++) {
        for (var x = 0; x < region.width; x++) {
          final tileOffset = (y * region.width + x) * 4;
          final wholeOffset = ((y + region.y) * whole.width + x + region.x) * 4;
          for (var channel = 0; channel < 4; channel++) {
            if (tile.pixels[tileOffset + channel] !=
                whole.pixels[wholeOffset + channel]) {
              mismatches++;
            }
          }
          if (tile.pixels[tileOffset] < 80) ink++;
        }
      }
      expect(
        ink,
        greaterThan(100),
        reason: 'the region intersects original artwork',
      );
      expect(mismatches, 0);
    },
  );

  test('full-page requests stay within the pixel budget', () async {
    final rendered = await book.renderPage(0, targetWidth: 10000);
    expect(rendered.width, lessThan(10000));
    expect(
      rendered.width * rendered.height,
      lessThanOrEqualTo(DjvuBook.maxPixels),
    );
    expect(rendered.pixels.length, rendered.width * rendered.height * 4);
    expect(rendered.width / rendered.height, closeTo(2 / 3, 0.001));
  });

  test('invalid page, size and region arguments are rejected', () async {
    await expectLater(book.renderPage(-1, targetWidth: 300), throwsRangeError);
    await expectLater(book.renderPage(3, targetWidth: 300), throwsRangeError);
    await expectLater(book.renderPage(0, targetWidth: 0), throwsRangeError);
    await expectLater(
      book.renderPage(
        0,
        targetWidth: 300,
        region: (x: 290, y: 10, width: 20, height: 20),
      ),
      throwsArgumentError,
    );
  });

  test('extreme page ratios respect both native axis and pixel bounds', () {
    for (final (ratio, requested) in [(1 / 65535, 10), (65535.0, 1000000)]) {
      final width = boundedDjvuRenderWidth(requested, ratio);
      final height = (width / ratio).round();
      expect(width, inInclusiveRange(1, 131072));
      expect(height, inInclusiveRange(1, 131072));
      expect(width * height, lessThanOrEqualTo(DjvuBook.maxPixels));
    }
    expect(boundedDjvuRenderWidth(1080, 0.7), 1080);
  });
}
