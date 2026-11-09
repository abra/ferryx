import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

import 'package:pagecraft/testing.dart';

void main() {
  late FakeComicSource source;

  setUp(() {
    source = FakeComicSource([
      encodeSolidPng(600, 900),
      encodeSolidPng(200, 300),
      Uint8List.fromList(List.filled(64, 0x41)),
    ]);
  });

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
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

  testWidgets(
    'decodes a wide page down to the target width, keeping its ratio',
    (tester) async {
      await tester.runAsync(() async {
        final info = await resolve(
          ComicPageImage(source: source, pageIndex: 0, targetWidth: 300),
        );
        expect(info.image.width, 300);
        expect(info.image.height, 450);
        expect(source.readCounts, {0: 1});
      });
    },
  );

  testWidgets('a page narrower than the target keeps its own size', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final info = await resolve(
        ComicPageImage(source: source, pageIndex: 1, targetWidth: 1000),
      );
      expect(info.image.width, 200);
      expect(info.image.height, 300);
    });
  });

  testWidgets(
    'the same page and width share one decode through the image cache',
    (tester) async {
      await tester.runAsync(() async {
        final a = ComicPageImage(
          source: source,
          pageIndex: 0,
          targetWidth: 300,
        );
        final b = ComicPageImage(
          source: source,
          pageIndex: 0,
          targetWidth: 300,
        );
        expect(a, b);
        expect(a.hashCode, b.hashCode);
        await resolve(a);
        await resolve(b);
        expect(source.readCounts, {0: 1});
        expect(PaintingBinding.instance.imageCache.containsKey(b), isTrue);

        // Another width or another source is another image.
        expect(
          a,
          isNot(ComicPageImage(source: source, pageIndex: 0, targetWidth: 240)),
        );
        expect(
          a,
          isNot(
            ComicPageImage(
              source: FakeComicSource(source.pages),
              pageIndex: 0,
              targetWidth: 300,
            ),
          ),
        );
        await resolve(
          ComicPageImage(source: source, pageIndex: 0, targetWidth: 240),
        );
        expect(source.readCounts, {0: 2});
      });
    },
  );

  testWidgets(
    'undecodable bytes report an error without affecting other pages',
    (tester) async {
      await tester.runAsync(() async {
        await expectLater(
          resolve(
            ComicPageImage(source: source, pageIndex: 2, targetWidth: 300),
          ),
          throwsA(isA<Exception>()),
        );
        final info = await resolve(
          ComicPageImage(source: source, pageIndex: 1, targetWidth: 300),
        );
        expect(info.image.width, 200);
      });
    },
  );

  testWidgets('a failed read reports the source error', (tester) async {
    await tester.runAsync(() async {
      source.failWith = const PagecraftException(
        'Damaged local header: 001.png',
      );
      await expectLater(
        resolve(ComicPageImage(source: source, pageIndex: 0, targetWidth: 300)),
        throwsA(isA<PagecraftException>()),
      );
    });
  });

  testWidgets('maxBytes refuses a page before it is read', (tester) async {
    await tester.runAsync(() async {
      await expectLater(
        resolve(
          ComicPageImage(
            source: source,
            pageIndex: 0,
            targetWidth: 300,
            maxBytes: 16,
          ),
        ),
        throwsA(isA<PagecraftException>()),
      );
      expect(source.readCounts, isEmpty);
    });
  });

  testWidgets('thumbnails use the WebView reader\'s preview width and budget', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final thumbnail = ComicPageImage(
        source: source,
        pageIndex: 0,
        targetWidth: ComicPageImage.thumbnailWidth,
        maxBytes: ComicPageImage.thumbnailMaxBytes,
      );
      final info = await resolve(thumbnail);
      expect(info.image.width, 240);
      expect(info.image.height, 360);
      expect(ComicPageImage.thumbnailMaxBytes, 16 * 1024 * 1024);
    });
  });

  test('describes itself for diagnostics', () {
    final provider = ComicPageImage(
      source: source,
      pageIndex: 3,
      targetWidth: 300,
    );
    expect(provider.toString(), 'ComicPageImage(page: 3, targetWidth: 300)');
    expect(
      () => ComicPageImage(source: source, pageIndex: 0, targetWidth: 0),
      throwsAssertionError,
    );
  });
}
