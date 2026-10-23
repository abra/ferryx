import 'dart:convert';

import 'side_storage.dart';

/// A short most-recently-used list of names (the commands the palette ran
/// last), the newest first, kept under its own key in a [SideStorage].
/// A write per use: the list changes as often as the user picks from it.
class RecentItems {
  RecentItems._(this._storage, this.key, this.capacity, this._items);

  /// Reads the list under [key]; an unreadable value starts it empty.
  static Future<RecentItems> load(
    SideStorage storage, {
    required String key,
    int capacity = 8,
  }) async {
    final items = <String>[];
    try {
      final raw = await storage.read(key);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) items.addAll(decoded.whereType<String>());
      }
    } on FormatException {
      // A damaged value is replaced on the next write.
    }
    return RecentItems._(
      storage,
      key,
      capacity,
      items.take(capacity).toList(),
    );
  }

  /// The key the palette's commands are kept under.
  static const commandsKey = 'ferryx.recentCommands';

  // ─── Network ───

  /// The key the addresses Connect to Server reached lately (never with
  /// a password) are kept under.
  static const serversKey = 'ferryx.recentServers';

  final SideStorage _storage;
  final String key;
  final int capacity;
  final List<String> _items;

  /// The newest first.
  List<String> get items => List.unmodifiable(_items);

  /// [item] was used: it moves to the front; the oldest beyond [capacity]
  /// drops off.
  Future<void> record(String item) async {
    _items
      ..remove(item)
      ..insert(0, item);
    if (_items.length > capacity) _items.removeRange(capacity, _items.length);
    try {
      await _storage.write(key, jsonEncode(_items));
    } on Object {
      // Kept in memory for the session; the next write tries again.
    }
  }
}
