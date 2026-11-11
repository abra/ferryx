import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:pagecraft/pdf.dart';

typedef ThumbnailLoader = Future<Uint8List?> Function(ThumbnailRequest request);
typedef _Key = (Location, int?, DateTime?, int, int);

/// Two decoders at most, with reference-counted in-flight work and a bounded
/// LRU of encoded thumbnails. Scrolling away cancels queued work immediately.
class ThumbnailService
    with WidgetsBindingObserver
    implements ThumbnailProvider {
  ThumbnailService({
    required FileRepository files,
    ThumbnailLoader? loader,
    this.maxEntries = 256,
    this.maxBytes = 8 * 1024 * 1024,
    this.parallel = 2,
  }) : assert(maxEntries > 0 && maxBytes > 0 && parallel > 0),
       _loader = loader ?? _RepositoryLoader(files).load {
    WidgetsBinding.instance.addObserver(this);
  }

  static const maxSourceBytes = 64 * 1024 * 1024;
  static const maxEncodedBytes = 1024 * 1024;
  static const _extensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'bmp',
    'pdf',
  };
  final ThumbnailLoader _loader;
  final int maxEntries, maxBytes, parallel;
  final _cache = <_Key, Uint8List?>{};
  final _jobs = <_Key, _Job>{};
  final _queue = Queue<_Job>();
  final _active = <Future<void>>{};
  int _cachedBytes = 0;
  bool _disposed = false;

  @override
  ThumbnailLease acquire(ThumbnailRequest request) {
    final entry = request.entry;
    if (_disposed ||
        !request.location.isNative ||
        entry.isDir ||
        entry.isParent ||
        !_extensions.contains(entry.extension.toLowerCase()) ||
        (entry.size ?? 0) > maxSourceBytes) {
      return _Lease(Future.value(), () {});
    }
    final target = request.targetWidth.clamp(64, 512);
    final key = (
      request.location,
      entry.size,
      entry.modified,
      entry.modified == null ? identityHashCode(entry) : 0,
      target,
    );
    if (_cache.containsKey(key)) {
      final cached = _cache.remove(key);
      _cache[key] = cached;
      return _Lease(Future.value(cached), () {});
    }
    var job = _jobs[key];
    if (job == null) {
      job = _Job(
        key,
        ThumbnailRequest(
          location: request.location,
          entry: entry,
          targetWidth: target,
        ),
      );
      _jobs[key] = job;
      _queue.add(job);
      scheduleMicrotask(_pump);
    }
    job.users++;
    final interest = job;
    return _Lease(job.result.future, () {
      if (_disposed) return;
      interest.users--;
      if (interest.users == 0 && !interest.started) {
        _queue.remove(interest);
        _jobs.remove(key);
        if (!interest.result.isCompleted) interest.result.complete();
      }
    });
  }

  void _pump() {
    if (_disposed) return;
    while (_active.length < parallel.clamp(1, 4) && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      job.started = true;
      late final Future<void> running;
      running = _run(job).whenComplete(() {
        _active.remove(running);
        _pump();
      });
      _active.add(running);
    }
  }

  Future<void> _run(_Job job) async {
    Uint8List? bytes;
    try {
      final loaded = await _loader(job.request);
      if (loaded != null && loaded.length <= maxEncodedBytes) {
        bytes = loaded.asUnmodifiableView();
      }
    } on Object {
      // Unsupported or damaged files keep their ordinary icon.
    } finally {
      if (!_disposed && job.users > 0) {
        _cache[job.key] = bytes;
        _cachedBytes += bytes?.length ?? 0;
        while (_cache.length > maxEntries || _cachedBytes > maxBytes) {
          _cachedBytes -= _cache.remove(_cache.keys.first)?.length ?? 0;
        }
      }
      if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
      if (!job.result.isCompleted) job.result.complete(bytes);
    }
  }

  @override
  void didHaveMemoryPressure() {
    _cache.clear();
    _cachedBytes = 0;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    didHaveMemoryPressure();
    for (final job in _jobs.values) {
      job.users = 0;
      if (!job.started && !job.result.isCompleted) job.result.complete();
    }
    _queue.clear();
    await Future.wait(_active.toList());
    _jobs.clear();
  }
}

class _RepositoryLoader {
  const _RepositoryLoader(this.files);
  final FileRepository files;
  Future<Uint8List?> load(ThumbnailRequest request) async {
    final size = await files.fileSize(request.location);
    if (size > ThumbnailService.maxSourceBytes || size == 0) return null;
    final spec = CoverThumbnailSpec(
      maxWidth: request.targetWidth,
      maxHeight: request.targetWidth,
    );
    if (request.entry.extension.toLowerCase() == 'pdf') {
      final lease = files.preparePreview(request.location);
      try {
        final path = await lease.path;
        await initializePdfEngine();
        return (await readPdfMetadata(path, spec: spec)).cover?.bytes;
      } finally {
        await lease.close();
      }
    }
    final bytes = await files.readRange(
      request.location,
      0,
      ThumbnailService.maxSourceBytes + 1,
    );
    if (bytes.length > ThumbnailService.maxSourceBytes) return null;
    return (await encodeCoverThumbnail(bytes, spec: spec))?.bytes;
  }
}

class _Job {
  _Job(this.key, this.request);
  final _Key key;
  final ThumbnailRequest request;
  final result = Completer<Uint8List?>();
  int users = 0;
  bool started = false;
}

class _Lease implements ThumbnailLease {
  _Lease(this.bytes, this._cancel);
  @override
  final Future<Uint8List?> bytes;
  final void Function() _cancel;
  bool _cancelled = false;
  @override
  void cancel() {
    if (!_cancelled) {
      _cancelled = true;
      _cancel();
    }
  }
}
