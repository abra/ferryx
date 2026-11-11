import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'side_storage.dart';

@immutable
class SavedProfile<T> {
  const SavedProfile(this.name, this.value);
  final String name;
  final T value;
}

/// Explicitly saved, named values stored independently of preferences.
/// Writes are serialized and published only after storage accepts them.
class SavedProfiles<T> extends ChangeNotifier {
  SavedProfiles._(this._storage, this.key, this._encode, this._items);

  static const maxItems = 64;
  static const maxNameLength = 80;
  static const maxEncodedLength = 1024 * 1024;

  final SideStorage _storage;
  final String key;
  final Map<String, Object?> Function(T) _encode;
  List<SavedProfile<T>> _items;
  Future<void> _tail = Future.value();
  bool _disposed = false;

  List<SavedProfile<T>> get items => _items;

  static Future<SavedProfiles<T>> load<T>(
    SideStorage storage, {
    required String key,
    required Map<String, Object?> Function(T) encode,
    required T? Function(Map<String, Object?>) decode,
  }) async {
    final raw = await storage.read(key);
    final items = <SavedProfile<T>>[];
    final names = <String>{};
    if (raw != null && raw.length <= maxEncodedLength) {
      try {
        final json = jsonDecode(raw);
        if (json case {'version': 1, 'items': final List<Object?> rows}) {
          for (final row in rows.take(maxItems)) {
            if (row is! Map<String, Object?>) continue;
            final name = row['name'];
            final value = row['value'];
            if (name is! String ||
                !validName(name) ||
                value is! Map<String, Object?>) {
              continue;
            }
            final decoded = decode(value);
            if (decoded == null || !names.add(name.trim().toLowerCase())) {
              continue;
            }
            items.add(SavedProfile(name.trim(), decoded));
          }
        }
      } on FormatException {
        // Corrupt data must not prevent opening the application.
      }
    }
    return SavedProfiles._(storage, key, encode, List.unmodifiable(items));
  }

  static bool validName(String name) =>
      name.trim().isNotEmpty &&
      name.trim().length <= maxNameLength &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name);

  bool contains(String name) => _items.any(
    (item) => item.name.toLowerCase() == name.trim().toLowerCase(),
  );

  Future<void> save(String name, T value, {bool replace = false}) => _change(
    (items) {
      if (!validName(name)) throw ArgumentError.value(name, 'name');
      final kept = name.trim();
      final index = items.indexWhere(
        (item) => item.name.toLowerCase() == kept.toLowerCase(),
      );
      if (index >= 0) {
        if (!replace) throw StateError('A profile with this name exists');
        items[index] = SavedProfile(kept, value);
      } else {
        if (items.length >= maxItems) throw StateError('Profile limit reached');
        items.add(SavedProfile(kept, value));
      }
    },
  );

  Future<void> remove(String name) => _change(
    (items) => items.removeWhere((item) => item.name == name),
  );

  Future<void> rename(String name, String replacement) => _change((items) {
    if (!validName(replacement)) throw ArgumentError.value(replacement, 'name');
    final index = items.indexWhere((item) => item.name == name);
    if (index < 0) return;
    final kept = replacement.trim();
    if (items.indexed.any(
      (item) =>
          item.$1 != index && item.$2.name.toLowerCase() == kept.toLowerCase(),
    )) {
      throw StateError('A profile with this name exists');
    }
    items[index] = SavedProfile(kept, items[index].value);
  });

  Future<void> _change(void Function(List<SavedProfile<T>>) change) {
    final result = _tail.then((_) async {
      if (_disposed) throw StateError('Catalog is closed');
      final next = [..._items];
      change(next);
      final encoded = jsonEncode({
        'version': 1,
        'items': [
          for (final item in next)
            {'name': item.name, 'value': _encode(item.value)},
        ],
      });
      if (encoded.length > maxEncodedLength) {
        throw StateError('Profile storage limit reached');
      }
      await _storage.write(key, encoded);
      _items = List.unmodifiable(next);
      if (!_disposed) notifyListeners();
    });
    _tail = result.catchError((Object _) {});
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
