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

  /// An encrypted archive needs a password to be listed or read.
  passwordRequired,

  /// The password given does not open the archive.
  wrongPassword,

  // ─── Network ───

  /// The server refused the login.
  authFailed,

  /// The server could not be reached.
  hostUnreachable,

  /// The server did not answer in time.
  timedOut,

  /// The server's SSH key was not trusted.
  hostKeyUnknown,

  /// The server's SSH key is not the one on record: refused.
  hostKeyChanged,

  /// The connection to the server dropped.
  connectionLost,

  /// No connection to the server is open: connect first.
  notConnected,

  /// The server's certificate is not trusted.
  certificateInvalid;

  /// A connection to a server is gone or never was: connecting (again)
  /// may help.
  bool get needsConnection =>
      this == notConnected ||
      this == connectionLost ||
      this == hostUnreachable ||
      this == timedOut;
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
