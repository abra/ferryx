import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'text_window.dart';

/// A bounded result, including whether the window contains further matches.
class WindowSearchResult {
  const WindowSearchResult(this.matches, this.capped);

  final List<ViewerMatch> matches;
  final bool capped;
}

WindowSearchResult searchWindow({
  required List<String> lines,
  required Uint8List bytes,
  required String query,
  required bool hex,
}) {
  final matches = hex
      ? findInBytes(bytes, query, maxMatches: maxWindowMatches + 1)
      : findInLines(lines, query, maxMatches: maxWindowMatches + 1);
  final capped = matches.length > maxWindowMatches;
  if (capped) matches.removeLast();
  return WindowSearchResult(matches, capped);
}

typedef _Request = (SendPort, List<String>, Uint8List, String, bool);

void _search(_Request request) {
  request.$1.send(
    searchWindow(
      lines: request.$2,
      bytes: request.$3,
      query: request.$4,
      hex: request.$5,
    ),
  );
}

/// Source-window search with explicit cancellation of pending work.
abstract interface class WindowSearcher {
  Future<WindowSearchResult?> search({
    required List<String> lines,
    required Uint8List bytes,
    required String query,
    required bool hex,
  });

  void cancel();
}

/// One running search per viewer. Replacing it kills its isolate and resolves
/// its caller with null, including cancellation during isolate startup.
class WindowSearchWorker implements WindowSearcher {
  _SearchJob? _job;

  @override
  Future<WindowSearchResult?> search({
    required List<String> lines,
    required Uint8List bytes,
    required String query,
    required bool hex,
  }) {
    cancel();
    final job = _job = _SearchJob();
    job.start((job.port.sendPort, lines, bytes, query, hex));
    return job.result.future.whenComplete(() {
      if (identical(_job, job)) _job = null;
    });
  }

  @override
  void cancel() {
    _job?.finish(null);
    _job = null;
  }
}

class _SearchJob {
  final port = ReceivePort();
  final result = Completer<WindowSearchResult?>();
  Isolate? _isolate;

  void start(_Request request) {
    port.listen((message) {
      if (message is WindowSearchResult) {
        finish(message);
      } else {
        fail(StateError('Window search worker failed: $message'));
      }
    });
    unawaited(
      Isolate.spawn(
        _search,
        request,
        onExit: port.sendPort,
        onError: port.sendPort,
      ).then(
        (isolate) {
          if (result.isCompleted) {
            isolate.kill(priority: Isolate.immediate);
          } else {
            _isolate = isolate;
          }
        },
        onError: (Object error, StackTrace stack) => fail(error, stack),
      ),
    );
  }

  void finish(WindowSearchResult? value) {
    if (result.isCompleted) return;
    _stop();
    result.complete(value);
  }

  void fail(Object error, [StackTrace? stack]) {
    if (result.isCompleted) return;
    _stop();
    result.completeError(error, stack);
  }

  void _stop() {
    port.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}
