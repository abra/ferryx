import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../../pagecraft_exception.dart';
import 'djvu_native.dart';

/// One worker owns one decoder context. Requests are processed in port order;
/// closing rejects new work and drains accepted operations before releasing it.
class DjvuWorker {
  DjvuWorker._();

  final _replies = ReceivePort();
  final _ready = Completer<SendPort>();
  final _pending = <int, Completer<Object?>>{};
  final _queued = Queue<List<Object?>>();
  SendPort? _port;
  int? _activeId;
  Isolate? _isolate;
  int _nextId = 0;
  bool _closing = false;
  bool _stopped = false;
  Future<void>? _closeFuture;

  static Future<({DjvuWorker worker, Map<String, Object?> metadata})> open(
    String path, {
    required Duration timeout,
  }) async {
    final worker = DjvuWorker._();
    worker._replies.listen(worker._receive);
    try {
      worker._isolate = await Isolate.spawn(
        _runDecoder,
        worker._replies.sendPort,
        onError: worker._replies.sendPort,
        onExit: worker._replies.sendPort,
        debugName: 'pagecraft-djvu',
      );
      await worker._ready.future;
      final metadata = await worker.request('open', [
        path,
        timeout.inMilliseconds,
      ]);
      return (
        worker: worker,
        metadata: (metadata as Map).cast<String, Object?>(),
      );
    } on Object {
      worker._stop();
      rethrow;
    }
  }

  Future<Object?> request(String operation, List<Object?> arguments) {
    if (_closing || _stopped) {
      return Future.error(StateError('DjVu document is closed'));
    }
    return _send(operation, arguments);
  }

  Future<Object?> _send(String operation, List<Object?> arguments) {
    if (_stopped) return Future.error(StateError('DjVu worker stopped'));
    final id = _nextId++;
    final reply = Completer<Object?>();
    _pending[id] = reply;
    _queued.add([id, operation, arguments]);
    _dispatchNext();
    return reply.future;
  }

  void _dispatchNext() {
    final port = _port;
    if (_stopped || port == null || _activeId != null || _queued.isEmpty) {
      return;
    }
    final command = _queued.removeFirst();
    _activeId = command[0] as int;
    // Keep at most one native response buffer in flight to this isolate.
    port.send(command);
  }

  void _receive(Object? message) {
    if (message is SendPort) {
      _port = message;
      _ready.complete(message);
      _dispatchNext();
    } else if (message is List && message.length == 3 && message[0] is int) {
      final reply = _pending.remove(message[0]);
      if (reply == null) return;
      _activeId = null;
      if (message[1] == true) {
        reply.complete(message[2]);
      } else {
        reply.completeError(PagecraftException(message[2] as String));
      }
      _dispatchNext();
    } else {
      // Errors and exit notifications share this port, preserving decoder reply
      // order before its normal exit. Native exceptions never cross the C ABI.
      final error = PagecraftException(
        message is List
            ? 'DjVu worker failed: ${message.first}'
            : 'DjVu worker stopped',
      );
      if (!_ready.isCompleted) _ready.completeError(error);
      _stop(error);
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closing = true;
    if (_stopped) return;
    try {
      await _send('close', const []);
    } finally {
      _stop();
    }
  }

  void _stop([Object? error]) {
    if (_stopped) return;
    _stopped = true;
    _isolate?.kill(priority: Isolate.immediate);
    _replies.close();
    for (final reply in _pending.values) {
      reply.completeError(error ?? StateError('DjVu worker stopped'));
    }
    _pending.clear();
    _queued.clear();
  }
}

void _runDecoder(SendPort replies) {
  final commands = ReceivePort();
  final session = _DecoderSession();
  replies.send(commands.sendPort);
  commands.listen((Object? message) {
    final request = message as List;
    final id = request[0] as int;
    final operation = request[1] as String;
    try {
      final value = session.perform(
        operation,
        (request[2] as List).cast<Object?>(),
      );
      replies.send([id, true, value]);
    } on Object catch (error) {
      replies.send([
        id,
        false,
        error is PagecraftException ? error.message : '$error',
      ]);
    } finally {
      if (operation == 'close') commands.close();
    }
  });
}

class _DecoderSession {
  Pointer<Void> _document = nullptr;

  Object? perform(String operation, List<Object?> arguments) {
    return switch (operation) {
      'open' => _open(arguments[0] as String, arguments[1] as int),
      'render' => _render(arguments.cast<int>()),
      'text' => _readJson(djvuText(_document, arguments[0] as int)),
      'close' => _close(),
      _ => throw StateError('Unknown DjVu operation'),
    };
  }

  Map<String, Object?> _open(String path, int timeoutMs) {
    if (_document != nullptr) throw StateError('DjVu document is already open');
    final nativePath = path.toNativeUtf8();
    try {
      _document = djvuOpen(nativePath.cast(), timeoutMs);
    } finally {
      calloc.free(nativePath);
    }
    if (_document == nullptr) _fail();
    try {
      final count = djvuPageCount(_document);
      if (count <= 0 || count > 100000) {
        throw const PagecraftException(
          'DjVu document has an invalid page count',
        );
      }
      final info = calloc<Int32>(3);
      final pages = <List<int>>[];
      try {
        for (var page = 0; page < count; page++) {
          if (djvuPageInfo(_document, page, info, info + 1, info + 2) == 0) {
            _fail();
          }
          pages.add([info[0], info[1], info[2]]);
        }
      } finally {
        calloc.free(info);
      }
      return {
        'pages': pages,
        'toc': _readJson(djvuOutline(_document)),
        'metadata': _readJson(djvuMetadata(_document)),
      };
    } on Object {
      _close();
      rethrow;
    }
  }

  TransferableTypedData _render(List<int> arguments) {
    final [page, fullWidth, fullHeight, x, y, width, height] = arguments;
    final pixels = djvuRender(
      _document,
      page,
      fullWidth,
      fullHeight,
      x,
      y,
      width,
      height,
    );
    if (pixels == nullptr) _fail();
    try {
      // Transfer owns its copied bytes before the native allocation is freed.
      return TransferableTypedData.fromList([
        pixels.asTypedList(width * height * 4),
      ]);
    } finally {
      djvuFree(pixels.cast());
    }
  }

  Object? _readJson(Pointer<Char> value) {
    if (value == nullptr) _fail();
    try {
      return jsonDecode(value.cast<Utf8>().toDartString());
    } finally {
      djvuFree(value.cast());
    }
  }

  Never _fail() {
    final message = djvuLastError();
    throw PagecraftException(
      message == nullptr
          ? 'DjVu decoder failed'
          : message.cast<Utf8>().toDartString(),
    );
  }

  Null _close() {
    if (_document != nullptr) {
      djvuClose(_document);
      _document = nullptr;
    }
    return null;
  }
}
