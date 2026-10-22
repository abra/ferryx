import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shortcuts/shortcuts.dart';

/// Which keys pressed in the terminal are the window's: its own commands
/// (copy, paste, clear…), its place in the window, and the window's chords
/// no program in a terminal is given (`ShortcutMap.terminalShortcuts`).
/// Every other key is the shell's.
///
/// The emulator reads a key before any `Shortcuts` above it could, so the
/// terminal asks here first and runs the command itself.
class TerminalKeys {
  TerminalKeys(this.map, this.platform)
    : _entries = map.terminalShortcuts(platform).entries.toList();

  final ShortcutMap map;
  final TargetPlatform platform;
  final List<MapEntry<ShortcutActivator, CommandIntent>> _entries;

  /// The command [event] is the chord of, if it is the window's.
  AppCommand? commandFor(KeyEvent event, HardwareKeyboard keyboard) {
    for (final entry in _entries) {
      if (entry.key.accepts(event, keyboard)) return entry.value.command;
    }
    return null;
  }

  bool sameAs(ShortcutMap other, TargetPlatform otherPlatform) =>
      identical(map, other) && platform == otherPlatform;
}
