import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

const fixtures = 'test/fixtures/pdf';

void main() {
  late PdfBook book;

  setUpAll(preparePdfEngineForTests);

  setUp(() async {
    book = await PdfBook.open('$fixtures/text_outline.pdf');
  });

  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await book.close();
  });

  Future<ImageInfo> resolve(ImageProvider provider) {
    final completer = Completer<ImageInfo>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info);
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  group('PdfPageImage', () {
    test('renders a page at the target width, keeping its ratio', () async {
      final info = await resolve(
        PdfPageImage(book: book, pageIndex: 0, targetWidth: 306),
      );
      expect(info.image.width, 306);
      expect(info.image.height, 396);
      info.dispose();
    });

    test('a rotated page renders landscape', () async {
      final info = await resolve(
        PdfPageImage(book: book, pageIndex: 1, targetWidth: 396),
      );
      expect(info.image.width, 396);
      expect(info.image.height, 306);
      info.dispose();
    });

    test(
      'draws black text on a white page in the right channel order',
      () async {
        final info = await resolve(
          PdfPageImage(book: book, pageIndex: 0, targetWidth: 306),
        );
        final stats = await _pixelStats(info.image);
        info.dispose();
        expect(stats.white, greaterThan(stats.total * 0.9));
        expect(stats.dark, greaterThan(50), reason: 'the text is drawn');
        expect(stats.tinted, 0, reason: 'grey text has equal channels');
      },
    );

    test('is one cache key per book object, page and width', () {
      final a = PdfPageImage(book: book, pageIndex: 0, targetWidth: 300);
      expect(a, PdfPageImage(book: book, pageIndex: 0, targetWidth: 300));
      expect(
        a.hashCode,
        PdfPageImage(book: book, pageIndex: 0, targetWidth: 300).hashCode,
      );
      expect(
        a,
        isNot(PdfPageImage(book: book, pageIndex: 1, targetWidth: 300)),
      );
      expect(
        a,
        isNot(PdfPageImage(book: book, pageIndex: 0, targetWidth: 301)),
      );
    });

    test('bounds the render to the pixel budget', () {
      final page = PdfPageImage(book: book, pageIndex: 0, targetWidth: 10000);
      expect(
        page.targetWidth * page.targetHeight,
        lessThanOrEqualTo(PdfPageImage.maxPixels),
      );
      expect(page.targetWidth, greaterThan(2000));
      expect(boundedPdfRenderWidth(1000, 612 / 792), 1000);
      expect(boundedPdfRenderWidth(1000, 1), 1000);
      expect(boundedPdfRenderWidth(3000, 1), 2449);
    });

    test('fails on the stream once the book is closed', () async {
      final provider = PdfPageImage(book: book, pageIndex: 0, targetWidth: 100);
      await book.close();
      await expectLater(resolve(provider), throwsStateError);
    });
  });

  group('PdfPageTile', () {
    test('renders the same pixels as that region of the whole page', () async {
      final whole = await resolve(
        PdfPageImage(book: book, pageIndex: 0, targetWidth: 400),
      );
      final tile = await resolve(
        PdfPageTile(
          book: book,
          pageIndex: 0,
          fullWidth: 400,
          region: (x: 40, y: 30, width: 160, height: 60),
        ),
      );
      expect(tile.image.width, 160);
      expect(tile.image.height, 60);
      final wholePixels = (await whole.image.toByteData())!;
      final tilePixels = (await tile.image.toByteData())!;
      var mismatches = 0;
      var inked = 0;
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 160; x++) {
          final tileOffset = ((y * 160) + x) * 4;
          final wholeOffset = (((y + 30) * 400) + x + 40) * 4;
          if (tilePixels.getUint32(tileOffset) !=
              wholePixels.getUint32(wholeOffset)) {
            mismatches++;
          }
          if (tilePixels.getUint8(tileOffset) < 0x80) inked++;
        }
      }
      whole.dispose();
      tile.dispose();
      expect(inked, greaterThan(100), reason: 'the tile covers the text');
      expect(mismatches, lessThan(160 * 60 ~/ 100));
    });

    test('refuses a tile over the pixel budget', () {
      expect(
        () => PdfPageTile(
          book: book,
          pageIndex: 0,
          fullWidth: 10000,
          region: (x: 0, y: 0, width: 3000, height: 3000),
        ),
        throwsAssertionError,
      );
    });

    test('is one cache key per region', () {
      PdfPageTile tile(int x) => PdfPageTile(
        book: book,
        pageIndex: 0,
        fullWidth: 800,
        region: (x: x, y: 0, width: 10, height: 10),
      );
      expect(tile(1), tile(1));
      expect(tile(1).hashCode, tile(1).hashCode);
      expect(tile(1), isNot(tile(2)));
    });
  });

  group('PdfPageThumbnail', () {
    testWidgets('shows the page rendered at the thumbnail width', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 120,
              height: 160,
              child: PdfPageThumbnail(
                book: book,
                page: 2,
                semanticLabel: 'Page 3',
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          final raw = tester.widget<RawImage>(find.byType(RawImage));
          if (raw.image != null) break;
        }
      });
      final raw = tester.widget<RawImage>(find.byType(RawImage));
      expect(raw.image, isNotNull);
      expect(raw.image!.width, PdfPageImage.thumbnailWidth);
      expect(raw.image!.height, 360);
      expect(find.bySemanticsLabel('Page 3'), findsOneWidget);
    });
  });
}

Future<({int total, int white, int dark, int tinted})> _pixelStats(
  ui.Image image,
) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var white = 0;
  var dark = 0;
  var tinted = 0;
  final total = image.width * image.height;
  for (var i = 0; i < total; i++) {
    final r = data.getUint8(i * 4);
    final g = data.getUint8(i * 4 + 1);
    final b = data.getUint8(i * 4 + 2);
    if (r > 250 && g > 250 && b > 250) white++;
    if (r < 80 && g < 80 && b < 80) dark++;
    if ((r - g).abs() > 8 || (g - b).abs() > 8) tinted++;
  }
  return (total: total, white: white, dark: dark, tinted: tinted);
}
