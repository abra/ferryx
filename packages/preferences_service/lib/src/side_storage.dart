import 'package:shared_preferences/shared_preferences.dart';

/// Small values kept beside the preferences, each under a key of its own:
/// data that changes often (the folders visited, the commands run lately)
/// is written on its own and never rewrites the preferences blob.
abstract interface class SideStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// [SideStorage] in the platform's preference store, next to
/// `ferryx.preferences`.
class SharedPreferencesSideStorage implements SideStorage {
  SharedPreferencesSideStorage({SharedPreferencesAsync? backend})
    : _backend = backend ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _backend;

  @override
  Future<String?> read(String key) => _backend.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _backend.setString(key, value);
}

/// Keeps everything in memory and counts the writes; for tests.
class InMemorySideStorage implements SideStorage {
  InMemorySideStorage([Map<String, String>? values]) : values = values ?? {};

  final Map<String, String> values;
  int writes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
    writes++;
  }
}
