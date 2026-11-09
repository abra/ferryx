import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;

/// A local path for a document decoder. Close the decoder before releasing
/// this lease; remote and archive copies are deleted by [close].
abstract interface class PreviewFileLease {
  /// Starts preparation on first access and shares that result thereafter.
  Future<String> get path;

  /// Cancels preparation and waits for owned temporary files to be removed.
  /// Native source files are borrowed and are never removed. Idempotent.
  Future<void> close();
}

/// The core owns both the cancellation handle and any temporary copy.
class CorePreviewFileLease implements PreviewFileLease {
  CorePreviewFileLease(Location location, this._onClosed)
    : _id = rust.createPreviewFile(location: rust.locationToView(location));

  final int _id;
  final void Function(PreviewFileLease) _onClosed;
  Future<String>? _path;
  Future<void>? _closing;
  bool _closed = false;

  static const _cancelled = FerryxException(
    FerryxErrorKind.cancelled,
    'preview file lease is closed',
  );

  @override
  Future<String> get path {
    if (_closed) return Future.error(_cancelled);
    return _path ??= _prepare();
  }

  Future<String> _prepare() async {
    try {
      final path = await rust.FerryxBackend.guard(
        () => rust.preparePreviewFile(id: _id),
      );
      if (_closed) throw _cancelled;
      return path;
    } on Object {
      if (_closed) throw _cancelled;
      rethrow;
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      // Sync cancellation must not wait behind occupied bridge workers.
      rust.cancelPreviewFile(id: _id);
      await rust.FerryxBackend.guard(() => rust.closePreviewFile(id: _id));
    } finally {
      _onClosed(this);
    }
  }
}
