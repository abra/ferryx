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
    _controller.add(next);
    // Serialise writes so an older snapshot never overtakes a newer one.
    _tail = _tail.then((_) => _storage.save(next)).catchError((_) {});
    return _tail;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _tail;
    await _controller.close();
  }
}
