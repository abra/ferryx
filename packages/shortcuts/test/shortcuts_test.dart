import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shortcuts/shortcuts.dart';

void main() {
  group('Chord labels', () {
    test('macOS glyphs, Ctrl+… elsewhere', () {
      const chord = Chord(LogicalKeyboardKey.keyK, primary: true, shift: true);
      expect(chord.label(TargetPlatform.macOS), '⇧⌘K');
      expect(chord.label(TargetPlatform.windows), 'Ctrl+Shift+K');
      expect(chord.label(TargetPlatform.linux), 'Ctrl+Shift+K');
      const f5 = Chord(LogicalKeyboardKey.f5, shift: true);
      expect(f5.label(TargetPlatform.macOS), '⇧F5');
      expect(f5.label(TargetPlatform.windows), 'Shift+F5');
    });
  });

  group('ChordCodec', () {
    test('round-trips chords', () {
      for (final chord in [
        const Chord(LogicalKeyboardKey.keyA, primary: true),
        const Chord(LogicalKeyboardKey.f7, shift: true),
        const Chord(LogicalKeyboardKey.enter, control: true, alt: true),
        const Chord(LogicalKeyboardKey.backquote, shift: true),
      ]) {
        expect(ChordCodec.decode(ChordCodec.encode(chord)), chord);
      }
      expect(ChordCodec.decode('nonsense'), isNull);
    });

    test('overrides rebind commands by name', () {
      final map = ShortcutMap.forUser(
        TargetPlatform.macOS,
        overrides: {
          AppCommand.copyTo.name: [
            ChordCodec.encode(
              const Chord(LogicalKeyboardKey.keyC, primary: true),
            ),
          ],
          AppCommand.moveTo.name: const [],
          'unknownCommand': ['keyX'],
        },
      );
      expect(map.chordsFor(AppCommand.copyTo), [
        const Chord(LogicalKeyboardKey.keyC, primary: true),
      ]);
      expect(map.chordsFor(AppCommand.moveTo), isEmpty);
    });
  });

  group('ShortcutMap', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      test('no chord does two things in one place on $platform', () {
        final map = ShortcutMap.defaults(platform);
        // The scopes whose keys reach the same handlers: the viewer is a
        // window of its own, whose inner shortcuts win over the global ones.
        const together = [
          {CommandScope.global, CommandScope.panel},
          {CommandScope.lists, CommandScope.dialogs},
          {CommandScope.viewer, CommandScope.dialogs},
        ];
        for (final scopes in together) {
          final seen = <Chord, AppCommand>{};
          for (final entry in map.bindings.entries) {
            if (!scopes.contains(entry.key.scope)) continue;
            for (final chord in entry.value) {
              final other = seen[chord];
              expect(
                other,
                isNull,
                reason:
                    '${chord.label(platform)} is both $other and '
                    '${entry.key} within $scopes on $platform',
              );
              seen[chord] = entry.key;
            }
          }
        }
      });
    }

    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      test(
        'with Vim keys no chord does two things in the panel on $platform',
        () {
          final map = ShortcutMap.forUser(platform, vimMotions: true);
          final seen = <Chord, AppCommand>{};
          final prefixes = <LogicalKeyboardKey>{};
          for (final entry in map.bindings.entries) {
            if (!const {
              CommandScope.global,
              CommandScope.panel,
            }.contains(entry.key.scope)) {
              continue;
            }
            for (final chord in entry.value) {
              final other = seen[chord];
              expect(
                other,
                isNull,
                reason:
                    '${chord.label(platform)} is both $other and ${entry.key}',
              );
              seen[chord] = entry.key;
              if (chord.prefix != null) prefixes.add(chord.prefix!);
            }
          }
          // A prefix key must not be a plain chord of the same scope.
          for (final prefix in prefixes) {
            expect(
              seen[Chord(prefix)],
              isNull,
              reason:
                  '${Chord.keyLabel(prefix, platform)} is a prefix and a chord',
            );
          }
          for (final command in AppCommand.values.where((c) => c.isVimOnly)) {
            final bound =
                map.chordsFor(command).isNotEmpty ||
                (platform != TargetPlatform.macOS &&
                    const {
                      AppCommand.vimHalfPageDown,
                      AppCommand.vimHalfPageUp,
                    }.contains(command));
            expect(bound, isTrue, reason: '$command has no Vim chord');
            expect(
              ShortcutMap.defaults(platform).chordsFor(command),
              isEmpty,
              reason: '$command is bound without Vim keys',
            );
          }
        },
      );
    }

    test('Vim labels read as Vim writes them', () {
      final map = ShortcutMap.forUser(TargetPlatform.macOS, vimMotions: true);
      expect(
        map.labelOf(AppCommand.moveDown, TargetPlatform.macOS, vim: true),
        'j',
      );
      expect(
        map.labelOf(AppCommand.moveFirst, TargetPlatform.macOS, vim: true),
        'gg',
      );
      expect(
        map.labelOf(AppCommand.moveLast, TargetPlatform.macOS, vim: true),
        'G',
      );
      expect(
        map.labelOf(AppCommand.previousTab, TargetPlatform.macOS, vim: true),
        'gT',
      );
      expect(
        map.labelOf(
          AppCommand.vimHalfPageDown,
          TargetPlatform.macOS,
          vim: true,
        ),
        '⌃d',
      );
      expect(
        map.labelOf(AppCommand.vimSearch, TargetPlatform.macOS, vim: true),
        '/',
      );
      expect(
        map.labelOf(
          AppCommand.selectWithExtension,
          TargetPlatform.macOS,
          vim: true,
        ),
        '*',
      );
      expect(
        map.labelOf(AppCommand.copyTo, TargetPlatform.macOS, vim: true),
        'F5',
      );
      expect(map.labelOf(AppCommand.moveDown, TargetPlatform.macOS), '↓');
    });

    test('the orthodox function keys are in place', () {
      final map = ShortcutMap.defaults(TargetPlatform.macOS);
      expect(map.labelOf(AppCommand.copyTo, TargetPlatform.macOS), 'F5');
      expect(map.labelOf(AppCommand.moveTo, TargetPlatform.macOS), 'F6');
      expect(
        map.labelOf(AppCommand.createDirectory, TargetPlatform.macOS),
        'F7',
      );
      expect(map.labelOf(AppCommand.deleteItems, TargetPlatform.macOS), 'F8');
      expect(map.labelOf(AppCommand.compress, TargetPlatform.macOS), 'F9');
      expect(
        map.labelOf(AppCommand.internalViewer, TargetPlatform.macOS),
        'F3',
      );
      expect(map.labelOf(AppCommand.moveToTrash, TargetPlatform.macOS), '⌘⌫');
      expect(
        ShortcutMap.defaults(
          TargetPlatform.windows,
        ).labelOf(AppCommand.moveToTrash, TargetPlatform.windows),
        'Del',
      );
    });

    test('every command has an entry, bound or not', () {
      final map = ShortcutMap.defaults(TargetPlatform.macOS);
      for (final command in AppCommand.values) {
        expect(
          map.bindings.containsKey(command),
          isTrue,
          reason: '$command is missing from the defaults',
        );
      }
    });

    test('toShortcuts limits itself to the scopes asked for', () {
      final map = ShortcutMap.defaults(TargetPlatform.macOS);
      final global = map.toShortcuts(
        TargetPlatform.macOS,
        scopes: const {CommandScope.global},
      );
      final intents = global.values.whereType<CommandIntent>();
      expect(
        intents.every((i) => i.command.scope == CommandScope.global),
        isTrue,
      );
      expect(intents.any((i) => i.command == AppCommand.moveDown), isFalse);
      final panel = map.toShortcuts(
        TargetPlatform.macOS,
        scopes: const {CommandScope.panel},
      );
      final enter = panel.values.whereType<CommandIntent>().firstWhere(
        (i) => i.command == AppCommand.enterItem,
      );
      expect(enter.yieldsToControls, isTrue);
    });
  });

  testWidgets('dispatch bubbles from inner to outer scopes', (tester) async {
    final reached = <String>[];
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: CommandShortcuts(
          shortcuts:
              ShortcutMap.defaults(
                TargetPlatform.macOS,
              ).toShortcuts(
                TargetPlatform.macOS,
                scopes: const {CommandScope.global},
              ),
          child: CommandHandlers(
            handlers: {
              AppCommand.refresh: () => reached.add('outer refresh'),
              AppCommand.copyTo: () => reached.add('outer copy'),
            },
            child: CommandHandlers(
              handlers: {AppCommand.copyTo: () => reached.add('inner copy')},
              child: Focus(focusNode: focus, child: const SizedBox()),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    expect(reached, ['inner copy', 'outer refresh']);
    focus.dispose();
  });
}
