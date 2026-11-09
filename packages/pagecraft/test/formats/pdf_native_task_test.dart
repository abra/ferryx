import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/pdf.dart';
import 'package:pagecraft/src/formats/pdf/pdf_native_task.dart';
import 'package:pagecraft/src/formats/pdf/pdf_text_metrics.dart';
import 'package:pagecraft/testing.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

void main() {
  setUpAll(preparePdfEngineForTests);

  late PdfBook book;

  setUp(() async {
    book = await PdfBook.open('test/fixtures/pdf/unembedded_cyrillic.pdf');
  });

  tearDown(() => book.close());

  test('native escape hatches cannot overlap', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final order = <String>[];
    int? firstHandle;
    final first = runPdfNativeDocumentTask(book.document, (handle) async {
      firstHandle = handle;
      order.add('first start');
      entered.complete();
      await release.future;
      order.add('first end');
    });
    await entered.future;
    expect(firstHandle, isNonZero);
    final second = runPdfNativeDocumentTask(book.document, (_) {
      order.add('second');
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(order, ['first start']);
    } finally {
      release.complete();
    }
    await Future.wait([first, second]);
    expect(order, ['first start', 'first end', 'second']);
  });

  test('a failed native task does not poison later requests', () async {
    final failed = runPdfNativeDocumentTask<void>(book.document, (_) {
      throw StateError('request failure');
    });
    final handled = expectLater(failed, throwsStateError);
    final following = runPdfNativeDocumentTask(book.document, (handle) {
      return handle != 0;
    });
    await handled;
    expect(await following, isTrue);
    final layer = await PdfTextLayer.load(book, 0);
    expect(layer.charBoxes.first.height, greaterThan(9));
  });

  test('concurrent metrics and rendering share the native worker', () async {
    final page = book.document.pages.first;
    final structured = await page.loadStructuredText();
    final requests = [
      for (var i = 0; i < 3; i++)
        loadPdfTextSelectionRects(book.document, 0, structured.fullText),
    ];
    final render = page.render(width: 120, height: 160);
    final cells = await Future.wait(requests);
    for (final result in cells) {
      expect(result, isNotNull);
      expect(result!.length, structured.fullText.length);
      expect(result.first!.height, greaterThan(9));
    }
    final image = await render;
    expect(image, isNotNull);
    image!.dispose();
  });

  test('closing waits for accepted metrics and remains idempotent', () async {
    final document = book.document;
    final text = await document.pages.first.loadStructuredText();
    final metrics = loadPdfTextSelectionRects(document, 0, text.fullText);
    final close = book.close();
    final repeatedClose = book.close();
    final result = await metrics;
    expect(result, isNotNull);
    expect(result!.first!.height, greaterThan(9));
    await Future.wait([close, repeatedClose]);
    await expectLater(
      loadPdfTextSelectionRects(document, 0, text.fullText),
      throwsStateError,
    );
  });

  test('a suspended caller zone cannot stall later native work', () async {
    final caller = _SuspendedZone();
    String? delivered;
    Zone? deliveredZone;
    final first = caller.zone.run(
      () => runPdfDocumentTask(() async => 'first'),
    );
    caller.zone.run(() {
      unawaited(
        first.then((value) {
          delivered = value;
          deliveredZone = Zone.current;
        }),
      );
    });

    final following = await runPdfDocumentTask(
      () async => 'following',
    ).timeout(const Duration(seconds: 2));
    expect(following, 'following');
    expect(delivered, isNull, reason: 'the caller has not pumped its zone');
    caller.flush();
    expect(delivered, 'first');
    expect(deliveredZone, same(caller.zone));
    expect(caller.errors, isEmpty);
  });

  test(
    'a failed task reaches its caller error zone without blocking work',
    () async {
      final caller = _SuspendedZone();
      final failure = StateError('native request failure');
      Object? deliveredError;
      StackTrace? deliveredTrace;
      Zone? deliveredZone;
      final failed = caller.zone.run(
        () => runPdfDocumentTask<int>(() async => throw failure),
      );
      caller.zone.run(() {
        unawaited(
          failed.then<void>(
            (_) => fail('the native request must fail'),
            onError: (Object error, StackTrace trace) {
              deliveredError = error;
              deliveredTrace = trace;
              deliveredZone = Zone.current;
            },
          ),
        );
      });

      final following = await runPdfDocumentTask(
        () async => 42,
      ).timeout(const Duration(seconds: 2));
      expect(following, 42);
      expect(deliveredError, isNull);
      caller.flush();
      expect(deliveredError, same(failure));
      expect(deliveredTrace, isNotNull);
      expect(deliveredZone, same(caller.zone));
      expect(caller.errors, isEmpty);
    },
  );
}

class _SuspendedZone {
  final _microtasks = <void Function()>[];
  final errors = <Object>[];

  late final zone = Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, callback) {
        _microtasks.add(() => zone.runGuarded(callback));
      },
      handleUncaughtError: (self, parent, zone, error, stackTrace) {
        errors.add(error);
      },
    ),
  );

  void flush() {
    while (_microtasks.isNotEmpty) {
      _microtasks.removeAt(0)();
    }
  }
}
