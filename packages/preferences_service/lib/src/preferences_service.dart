import 'dart:async';

import 'preferences.dart';
import 'preferences_storage.dart';

/// Single source of truth for [Preferences]: loads once, persists edits in
/// order and broadcasts every new snapshot on [stream].
///
/// Save failures are not fatal: the in-memory value is kept so the running
/// session stays consistent; the next launch reads the last good snapshot.
class PreferencesService {
  PreferencesService._(this._storage, this._current);

  final PreferencesStorage _storage;
  final _controller = StreamController<Preferences>.broadcast();
  Preferences _current;
  Future<void> _tail = Future.value();
  bool _dirty = false;
  bool _disposed = false;

  static Future<PreferencesService> create({
    PreferencesStorage? storage,
  }) async {
    final store = storage ?? SharedPreferencesStorage();
    final loaded = await store.load();
    return PreferencesService._(store, loaded ?? const Preferences());
  }

  Preferences get current => _current;

  /// Snapshots after each [update], in order. Does not replay [current].
  Stream<Preferences> get stream => _controller.stream;

  /// Applies [change] to the current snapshot, broadcasts and persists it.
  Future<void> update(Preferences Function(Preferences) change) {
    if (_disposed) return Future.value();
    final next = change(_current);
    if (next == _current) return Future.value();
    _current = next;
    _dirty = true;
    _controller.add(next);
    _save(next);
    return _tail;
  }

  Future<void> _save(Preferences snapshot) {
    // Serialise writes so an older snapshot never overtakes a newer one.
    final save = _tail.then((_) async {
      await _storage.save(snapshot);
      if (identical(snapshot, _current)) _dirty = false;
    });
    _tail = save.catchError((Object _) {});
    return save;
  }

  /// Waits for persistence, retrying a failed write and reporting any error.
  Future<void> flush() async {
    await _tail;
    while (_dirty) {
      await _save(_current);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _tail;
    await _controller.close();
  }
}
