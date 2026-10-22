import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'preferences.dart';

/// Where a [Preferences] snapshot is persisted.
abstract interface class PreferencesStorage {
  Future<Preferences?> load();

  Future<void> save(Preferences preferences);
}

/// One JSON blob under a single key in `shared_preferences`.
class SharedPreferencesStorage implements PreferencesStorage {
  SharedPreferencesStorage({SharedPreferencesAsync? backend})
    : _backend = backend ?? SharedPreferencesAsync();

  static const String key = 'ferryx.preferences';

  final SharedPreferencesAsync _backend;

  @override
  Future<Preferences?> load() async {
    final raw = await _backend.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return Preferences.fromJson(decoded);
    } on FormatException {
      // A damaged blob is replaced by defaults on the next save.
    }
    return null;
  }

  @override
  Future<void> save(Preferences preferences) =>
      _backend.setString(key, jsonEncode(preferences.toJson()));
}

/// Keeps everything in memory; for tests.
class InMemoryPreferencesStorage implements PreferencesStorage {
  InMemoryPreferencesStorage([this._value]);

  Preferences? _value;
  int saves = 0;

  @override
  Future<Preferences?> load() async => _value;

  @override
  Future<void> save(Preferences preferences) async {
    _value = preferences;
    saves++;
  }
}
