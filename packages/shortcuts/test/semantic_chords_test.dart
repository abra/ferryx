import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shortcuts/shortcuts.dart';

void main() {
  test(
    'custom bindings warn about effective modifiers across nested scopes',
    () {
      final chord = ChordCodec.encode(
        const Chord(LogicalKeyboardKey.keyA, control: true),
      );
      final map = ShortcutMap.forUser(
        TargetPlatform.windows,
        overrides: {
          AppCommand.showPreview.name: [chord],
        },
      );
      expect(
        map.conflicts(TargetPlatform.windows)[AppCommand.showPreview],
        AppCommand.selectAll,
      );
      expect(
        map.conflicts(TargetPlatform.windows)[AppCommand.selectAll],
        AppCommand.showPreview,
      );
      final mac = ShortcutMap.forUser(
        TargetPlatform.macOS,
        overrides: {
          AppCommand.showPreview.name: [chord],
        },
      );
      expect(
        mac.conflicts(TargetPlatform.macOS)[AppCommand.showPreview],
        AppCommand.fileAttributes,
      );
    },
  );

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    for (final vim in [false, true]) {
      test(
        '${platform.name}, Vim=$vim: effective modifiers never alias commands',
        () {
          final map = ShortcutMap.forUser(platform, vimMotions: vim);
          final conflicts = <String>[];
          for (final scopes in const [
            {CommandScope.global, CommandScope.panel},
            {CommandScope.lists, CommandScope.dialogs},
            {CommandScope.viewer, CommandScope.dialogs},
            {CommandScope.terminal},
          ]) {
            final seen = <Object, AppCommand>{};
            for (final entry in map.bindings.entries) {
              if (!scopes.contains(entry.key.scope)) continue;
              for (final chord in entry.value) {
                final a = chord.toActivator(platform);
                final key = (
                  chord.prefix,
                  chord.key,
                  a.control,
                  a.meta,
                  a.alt,
                  a.shift,
                );
                final other = seen[key];
                if (other != null && other != entry.key) {
                  conflicts.add(
                    '${chord.label(platform)}: $other / ${entry.key}',
                  );
                }
                seen[key] = entry.key;
              }
            }
          }
          expect(conflicts, isEmpty);
        },
      );
    }
  }
}
