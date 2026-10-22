/// Why a call into the core failed; Views map it to a message.
enum FerryxErrorKind {
  notFound,
  permissionDenied,
  alreadyExists,
  notADirectory,
  isADirectory,
  notEmpty,
  unsupported,
  cancelled,
  invalidName,
  invalidPattern,
  io,
}

class FerryxException implements Exception {
  const FerryxException(this.kind, this.message, {this.path});

  final FerryxErrorKind kind;

  /// The core's own words (an OS error, a path); shown under the kind's
  /// localized title.
  final String message;
  final String? path;

  @override
  String toString() => 'FerryxException(${kind.name}: $message)';
}
