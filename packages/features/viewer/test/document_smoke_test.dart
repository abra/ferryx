import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/pagecraft.dart';
import 'package:pagecraft/testing.dart';
import 'package:viewer_feature/src/document_format.dart';
import 'package:viewer_feature/src/document_page_image.dart';
import 'package:viewer_feature/src/document_session.dart';

import 'support/document_fixtures.dart';

const _appearance = DocumentAppearance(
  style: BookStyle(),
  fonts: BookFonts(),
  settings: TextPageSettings(),
  textScaler: TextScaler.noScaling,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(preparePdfEngineForTests);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ferryx-document-smoke-');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<String> write(String name, List<int> bytes) async {
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  for (final (name, bytes) in [
    ('book.epub', epubFixture()),
    ('book.fb2', fb2Fixture()),
    ('book.fbz', zippedFb2Fixture()),
    ('book.fb2.zip', zippedFb2Fixture()),
    ('book.mobi', mobiFixture()),
    ('book.azw3', mobiFixture(kf8: true)),
  ]) {
    test('$name opens, loads its text and lays out a real page', () async {
      final session = await openDocumentSession(
        await write(name, bytes),
        documentFormatOf(name)!,
        _appearance,
      );
      try {
        final controller = session.textController!;
        expect((await controller.source.section(0)).text, contains(smokeText));
        controller.setViewport(const Size(640, 480));
        await session.goTo(0);
        expect(session.error, isNull);
        expect(session.ready, isTrue);
        expect(controller.spreadAt(0)!.pages, isNotEmpty);
        await session.last();
        expect(session.index, session.count - 1);
        await session.first();
        expect(session.index, 0);
      } finally {
        await session.close();
      }
    });
  }

  test('EPUB navigation follows linear sections at both edges', () async {
    final session = await openDocumentSession(
      await write(
        'reading-order.epub',
        epubReadingOrderFixture([false, true, true, false]),
      ),
      DocumentFormat.epub,
      _appearance,
    );
    try {
      session.textController!.setViewport(const Size(640, 480));
      await session.goTo(1);
      expect(session.canPrevious, isFalse);
      expect(session.canNext, isTrue);
      await session.next();
      expect(session.index, 2);
      expect(session.canPrevious, isTrue);
      expect(session.canNext, isFalse);
      await session.previous();
      expect(session.index, 1);
      expect(session.canPrevious, isFalse);

      await session.goTo(0);
      expect(session.canPrevious, isFalse);
      expect(session.canNext, isTrue);
      await session.next();
      expect(session.index, 1);
      await session.goTo(3);
      expect(session.canPrevious, isTrue);
      expect(session.canNext, isFalse);
      await session.previous();
      expect(session.index, 2);
    } finally {
      await session.close();
    }
  });

  test('EPUB without linear sections has no adjacent section', () async {
    final session = await openDocumentSession(
      await write('nonlinear.epub', epubReadingOrderFixture([false, false])),
      DocumentFormat.epub,
      _appearance,
    );
    try {
      session.textController!.setViewport(const Size(640, 480));
      for (var index = 0; index < 2; index++) {
        await session.goTo(index);
        expect(session.ready, isTrue);
        expect(session.canPrevious, isFalse);
        expect(session.canNext, isFalse);
        await session.next();
        await session.previous();
        expect(session.index, index);
      }
    } finally {
      await session.close();
    }
  });

  test('FB2 trailing notes do not leave Next enabled', () async {
    final session = await openDocumentSession(
      await write('notes.fb2', fb2Fixture(notes: true)),
      DocumentFormat.fb2,
      _appearance,
    );
    try {
      final controller = session.textController!;
      controller.setViewport(const Size(640, 480));
      expect(controller.source.isLinear(session.count - 1), isFalse);
      await session.goTo(0);
      expect(session.canNext, isTrue);
      await session.next();
      expect(session.index, 1);
      expect(session.canPrevious, isTrue);
      expect(session.canNext, isFalse);
      await session.previous();
      expect(session.index, 0);
      expect(session.canPrevious, isFalse);
    } finally {
      await session.close();
    }
  });

  for (final (name, bytes, pages) in [
    ('book.cbz', comicFixture(), 2),
    ('book.pdf', pdfFixture(), 2),
    ('book.djvu', djvuFixture(), 1),
  ]) {
    test('$name opens and renders pixels through its bundled engine', () async {
      final session = await openDocumentSession(
        await write(name, bytes),
        documentFormatOf(name)!,
        _appearance,
      );
      try {
        expect(session.count, pages);
        expect(session.ready, isTrue);
        final info = await _resolve(
          session.fixedPages!.pageImage(0, targetWidth: 120),
        );
        try {
          expect(info.image.width, greaterThan(0));
          expect(info.image.height, greaterThan(0));
          final rgba = await info.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(rgba, isNotNull);
          if (name != 'book.cbz') {
            final red = [
              for (var i = 0; i < rgba!.lengthInBytes; i += 4) rgba.getUint8(i),
            ];
            expect(red.any((value) => value < 80), isTrue, reason: 'artwork');
            expect(red.any((value) => value > 240), isTrue, reason: 'paper');
          }
        } finally {
          info.dispose();
        }
        await session.last();
        expect(session.index, pages - 1);
        await session.first();
        expect(session.index, 0);
      } finally {
        await session.close();
      }
    });
  }

  test('fixed-layout EPUB reports its explicit unsupported reason', () async {
    await expectLater(
      openDocumentSession(
        await write('fixed.epub', epubFixture(fixed: true)),
        DocumentFormat.epub,
        _appearance,
      ),
      throwsA(
        isA<UnsupportedTextBookException>().having(
          (e) => e.reason,
          'reason',
          TextBookUnsupported.fixedLayout,
        ),
      ),
    );
  });

  test(
    'vertical EPUB reports unsupported layout after loading its chapter',
    () async {
      final session = await openDocumentSession(
        await write('vertical.epub', epubFixture(vertical: true)),
        DocumentFormat.epub,
        _appearance,
      );
      try {
        session.textController!.setViewport(const Size(640, 480));
        await expectLater(
          session.goTo(0),
          throwsA(isA<UnsupportedTextBookException>()),
        );
        expect(
          session.error,
          isA<UnsupportedTextBookException>().having(
            (e) => e.reason,
            'reason',
            TextBookUnsupported.verticalWriting,
          ),
        );
      } finally {
        await session.close();
      }
    },
  );

  for (final format in DocumentFormat.values) {
    test('damaged ${format.name} reports an exception', () async {
      await expectLater(
        openDocumentSession(
          await write('damaged.${format.name}', utf8.encode('not a document')),
          format,
          _appearance,
        ),
        throwsA(isA<Exception>()),
      );
    });
  }

  for (final (width, height) in [(1000, 30000), (4000, 4000)]) {
    test('comic $width by $height decodes within both image budgets', () async {
      final provider = DocumentComicPageImage(
        source: FakeComicSource([encodeSolidPng(width, height)]),
        pageIndex: 0,
        targetWidth: 4096,
      );
      final info = await _resolve(provider);
      try {
        final image = info.image;
        expect(
          image.width * image.height,
          lessThanOrEqualTo(DocumentComicPageImage.maxPixels),
        );
        expect(image.width, lessThanOrEqualTo(DocumentComicPageImage.maxSide));
        expect(image.height, lessThanOrEqualTo(DocumentComicPageImage.maxSide));
        expect(image.width / image.height, closeTo(width / height, 0.002));
        expect(image.width, greaterThan(0));
        expect(image.height, greaterThan(0));
      } finally {
        info.dispose();
        await provider.evict();
      }
    });
  }
}

Future<ImageInfo> _resolve(ImageProvider provider) {
  final completer = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info);
    },
    onError: (Object error, StackTrace? stack) {
      stream.removeListener(listener);
      completer.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
