import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pagecraft/all_formats.dart';

import 'package:pagecraft/testing.dart';

void main() {
  late FakeComicSource source;

  setUp(() {
    source = FakeComicSource([
      encodeSolidPng(600, 900, rgba: 0x3498DBFF),
      Uint8List.fromList(List.filled(32, 1)),
    ]);
  });

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  Widget thumbnail(int page) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 80,
        height: 120,
        child: ComicPageThumbnail(
          source: source,
          page: page,
          semanticLabel: 'Page ${page + 1}',
        ),
      ),
    ),
  );

  testWidgets('decodes the page at the preview width', (tester) async {
    await tester.pumpWidget(thumbnail(0));
    await tester.runAsync(() async {
      await precacheImage(
        ComicPageImage(
          source: source,
          pageIndex: 0,
          targetWidth: ComicPageImage.thumbnailWidth,
          maxBytes: ComicPageImage.thumbnailMaxBytes,
        ),
        tester.element(find.byType(ComicPageThumbnail)),
      );
    });
    await tester.pump();
    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(image.width, 240);
    expect(image.height, 360);
    expect(find.bySemanticsLabel('Page 1'), findsOneWidget);
    expect(source.readCounts, {0: 1});
  });

  testWidgets('an undecodable page shows the placeholder', (tester) async {
    await tester.pumpWidget(thumbnail(1));
    await tester.runAsync(() async {
      await precacheImage(
        ComicPageImage(
          source: source,
          pageIndex: 1,
          targetWidth: ComicPageImage.thumbnailWidth,
          maxBytes: ComicPageImage.thumbnailMaxBytes,
        ),
        tester.element(find.byType(ComicPageThumbnail)),
        onError: (_, _) {},
      );
    });
    await tester.pump();
    expect(find.byType(ColoredBox), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('an oversized page is refused before reading', (tester) async {
    source.pages[0] = Uint8List(ComicPageImage.thumbnailMaxBytes + 1);
    await tester.pumpWidget(thumbnail(0));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ColoredBox), findsOneWidget);
    expect(source.readCounts, isEmpty);
  });
}
