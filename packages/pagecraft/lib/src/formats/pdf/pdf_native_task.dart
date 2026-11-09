import 'dart:async';

import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> _nativeTasks = Zone.root.run(() => Future<void>.value());

/// Orders document work and disposal across Pagecraft's PDFium entry points.
Future<T> runPdfDocumentTask<T>(Future<T> Function() task) {
  final result = Completer<T>();
  // The process-wide queue must outlive a caller's widget/test zone. Only
  // delivery of the result belongs to that caller; native work stays outside it.
  Zone.root.run(() {
    _nativeTasks = _nativeTasks.then((_) async {
      try {
        result.complete(await task());
      } catch (error, stackTrace) {
        // A request failure reaches its caller without poisoning the queue.
        result.completeError(error, stackTrace);
      }
    });
  });
  return result.future;
}

/// Runs a Pagecraft native task while the engine's PDFium worker is paused.
///
/// PDFium permits only one caller at a time. The engine's pause hook does not
/// serialize external callbacks, so metadata and text metrics share this queue.
Future<T> runPdfNativeDocumentTask<T>(
  PdfDocument document,
  FutureOr<T> Function(int nativeDocumentHandle) task,
) {
  return runPdfDocumentTask(
    () => document.useNativeDocumentHandle(task),
  );
}
