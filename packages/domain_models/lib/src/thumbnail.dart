import 'dart:typed_data';

import 'file_entry.dart';
import 'location.dart';

class ThumbnailRequest {
  const ThumbnailRequest({
    required this.location,
    required this.entry,
    required this.targetWidth,
  });
  final Location location;
  final FileEntry entry;
  final int targetWidth;
}

/// A visible cell's interest in a shared request. Cancelling a queued lease
/// avoids starting work; an active decoder still releases its resources.
abstract interface class ThumbnailLease {
  Future<Uint8List?> get bytes;
  void cancel();
}

abstract interface class ThumbnailProvider {
  ThumbnailLease acquire(ThumbnailRequest request);
}
