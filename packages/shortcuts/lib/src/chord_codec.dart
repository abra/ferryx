import 'package:flutter/services.dart';

import 'app_command.dart';
import 'chord.dart';
import 'shortcut_map.dart';

/// Serialises chords for preferences: `primary+shift+k`, `alt+arrowUp`,
/// and `KeyD,KeyD` for a two-key sequence (prefix first).
///
/// Keys are stored by their debug name (stable across Flutter versions),
/// with the numeric id as a fallback for keys without one.
abstract final class ChordCodec {
  static String encode(Chord chord) {
    final parts = <String>[
      if (chord.primary) 'primary',
      if (chord.control) 'control',
      if (chord.alt) 'alt',
      if (chord.shift) 'shift',
      _keyName(chord.key),
    ];
    final prefix = chord.prefix;
    final body = parts.join('+');
    return prefix == null ? body : '${_keyName(prefix)},$body';
  }

  static Chord? decode(String encoded) {
    final comma = encoded.indexOf(',');
    LogicalKeyboardKey? prefix;
    var body = encoded;
    if (comma != -1) {
      prefix = _keyFromName(encoded.substring(0, comma));
      if (prefix == null) return null;
      body = encoded.substring(comma + 1);
    }
    final parts = body.split('+');
    if (parts.isEmpty) return null;
    final key = _keyFromName(parts.last);
    if (key == null) return null;
    final modifiers = parts.sublist(0, parts.length - 1).toSet();
    return Chord(
      key,
      primary: modifiers.contains('primary'),
      control: modifiers.contains('control'),
      alt: modifiers.contains('alt'),
      shift: modifiers.contains('shift'),
      prefix: prefix,
    );
  }

  /// Applies `command name → encoded chords` overrides to [base].
  static ShortcutMap apply(
    ShortcutMap base,
    Map<String, List<String>> overrides,
  ) {
    var map = base;
    for (final entry in overrides.entries) {
      final command = AppCommand.values
          .where((c) => c.name == entry.key)
          .firstOrNull;
      if (command == null) continue;
      final chords = entry.value.map(decode).whereType<Chord>().toList();
      map = map.rebind(command, chords);
    }
    return map;
  }

  static String _keyName(LogicalKeyboardKey key) {
    final name = key.debugName;
    return name == null || name.isEmpty
        ? 'id:${key.keyId}'
        : name.replaceAll(' ', '');
  }

  static LogicalKeyboardKey? _keyFromName(String name) {
    if (name.startsWith('id:')) {
      final id = int.tryParse(name.substring(3));
      return id == null ? null : LogicalKeyboardKey.findKeyByKeyId(id);
    }
    for (final key in LogicalKeyboardKey.knownLogicalKeys) {
      final debugName = key.debugName;
      if (debugName != null && debugName.replaceAll(' ', '') == name) {
        return key;
      }
    }
    return null;
  }
}
