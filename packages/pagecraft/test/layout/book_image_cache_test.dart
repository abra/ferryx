import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  final files = <String, Uint8List>{
    'wide.png': encodeSolidPng(400, 200),
    'small.png': encodeSolidPng(20, 10),
    'not-an-image.bin': Uint8List.fromList(List.filled(64, 7)),
    'diagram.svg': Uint8List.fromList(
      '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20">'
              '<rect width="40" height="20" fill="#ff0000"/></svg>'
          .codeUnits,
    ),
    'broken.svg': Uint8List.fromList(
      '<svg width="10" height="10"><g'.codeUnits,
    ),
  };
  late List<String> reads;
  Future<Uint8List?> read(String key) async {
    reads.add(key);
    return files[key];
  }

  setUp(() => reads = []);

  testWidgets('probes sizes from headers, once each', (tester) async {
    final cache = BookImageCache(read: read);
    addTearDown(cache.dispose);
    final sizes = await tester.runAsync(
      () => cache.probe([
        'wide.png',
        'small.png',
        'missing.png',
        'not-an-image.bin',
        'wide.png',
      ]),
    );
    expect(sizes, {
      'wide.png': const Size(400, 200),
      'small.png': const Size(20, 10),
    });
    expect(cache.sizeOf('missing.png'), isNull);
    await tester.runAsync(() => cache.probe(['wide.png']));
    expect(reads.where((k) => k == 'wide.png'), hasLength(1));
  });

  testWidgets('decodes at the drawn width and tells listeners', (tester) async {
    final cache = BookImageCache(read: read);
    addTearDown(cache.dispose);
    var notified = 0;
    cache.addListener(() => notified++);
    expect(cache.image('wide.png', 100), isNull, reason: 'decoding starts');
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && cache.image('wide.png', 100) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    final image = cache.image('wide.png', 100)!;
    expect(image.width, 100);
    expect(image.height, 50, reason: 'the ratio is kept');
    expect(notified, 1);
    expect(cache.decodedBytes, 100 * 50 * 4);

    // A larger request decodes again; never above the image's own size.
    expect(
      cache.image('wide.png', 1000),
      same(image),
      reason: 'the small one meanwhile',
    );
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 100 && cache.image('wide.png', 1000)!.width == 100;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    expect(cache.image('wide.png', 1000)!.width, 400);
    expect(
      cache.decodedBytes,
      400 * 200 * 4,
      reason: 'the old decode is freed',
    );
  });

  testWidgets('keeps decoded pixels within the budget, least recent out', (
    tester,
  ) async {
    final cache = BookImageCache(read: read, budgetBytes: 400 * 200 * 4);
    addTearDown(cache.dispose);
    Future<void> decode(String key, int width) async {
      await tester.runAsync(() async {
        cache.image(key, width);
        for (var i = 0; i < 100 && cache.image(key, width) == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
    }

    await decode('small.png', 20);
    await decode('wide.png', 400);
    expect(cache.decodedBytes, 400 * 200 * 4, reason: 'the small image went');
    expect(cache.image('wide.png', 400), isNotNull);
  });

  testWidgets('an SVG is drawn sharp at the drawn width', (tester) async {
    final cache = BookImageCache(read: read);
    addTearDown(cache.dispose);
    final sizes = await tester.runAsync(() => cache.probe(['diagram.svg']));
    expect(sizes, {'diagram.svg': const Size(40, 20)});
    cache.image('diagram.svg', 200);
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && cache.image('diagram.svg', 200) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    final image = cache.image('diagram.svg', 200)!;
    expect(image.width, 200, reason: 'larger than its own size: a vector');
    expect(image.height, 100);
    final pixels = (await tester.runAsync(image.toByteData))!;
    expect(pixels.getUint32(0), 0xFF0000FF, reason: 'red, opaque');
    cache.image('broken.svg', 20);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    expect(cache.image('broken.svg', 20), isNull);
  });

  testWidgets('an undecodable image stays empty', (tester) async {
    final cache = BookImageCache(read: read);
    addTearDown(cache.dispose);
    cache.image('not-an-image.bin', 50);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(cache.image('not-an-image.bin', 50), isNull);
    expect(cache.decodedBytes, 0);
  });
}
