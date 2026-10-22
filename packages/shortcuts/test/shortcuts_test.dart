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
          // The terminal's own keys win over the window's inside it.
          {CommandScope.terminal},
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

  group('Native commands', () {
    const y = LogicalKeyboardKey.keyY;

    test('⌘Y is Quick Look, as in Finder; the preview moves to ⇧⌘Y', () {
      final map = ShortcutMap.defaults(TargetPlatform.macOS);
      expect(map.chordsFor(AppCommand.quickLook), [
        const Chord(y, primary: true),
      ]);
      expect(map.chordsFor(AppCommand.preview), [
        const Chord(y, primary: true, shift: true),
      ]);
      expect(map.labelOf(AppCommand.share, TargetPlatform.macOS), '⇧⌘S');
      expect(
        map.commandFor(const Chord(y, primary: true)),
        AppCommand.quickLook,
      );
    });

    test('an unavailable command loses its chords and is not available', () {
      final map = ShortcutMap.forUser(
        TargetPlatform.linux,
        unavailable: const {AppCommand.quickLook, AppCommand.share},
      );
      expect(map.isAvailable(AppCommand.quickLook), isFalse);
      expect(map.isAvailable(AppCommand.share), isFalse);
      expect(map.isAvailable(AppCommand.preview), isTrue);
      expect(map.chordsFor(AppCommand.quickLook), isEmpty);
      expect(map.chordsFor(AppCommand.share), isEmpty);
      // Ctrl+Y is free again, not a command that would do nothing.
      expect(map.commandFor(const Chord(y, primary: true)), isNull);
      final shortcuts = map.toShortcuts(
        TargetPlatform.linux,
        scopes: const {CommandScope.global},
      );
      expect(
        shortcuts.values.whereType<CommandIntent>().map((i) => i.command),
        isNot(contains(AppCommand.quickLook)),
      );
    });

    test('the overrides cannot bring an unavailable command back', () {
      final map = ShortcutMap.forUser(
        TargetPlatform.windows,
        overrides: {
          AppCommand.share.name: [
            ChordCodec.encode(
              const Chord(LogicalKeyboardKey.keyK, primary: true),
            ),
          ],
        },
        unavailable: const {AppCommand.share},
      );
      expect(map.chordsFor(AppCommand.share), isEmpty);
      expect(map.isAvailable(AppCommand.share), isFalse);
    });

    test('availability survives rebinding and Vim keys', () {
      final map = ShortcutMap.forUser(
        TargetPlatform.macOS,
        vimMotions: true,
        unavailable: const {AppCommand.quickLook},
      ).rebind(AppCommand.refresh, const []);
      expect(map.isAvailable(AppCommand.quickLook), isFalse);
      expect(map.isAvailable(AppCommand.refresh), isTrue);
    });

    test('every command is available by default', () {
      final map = ShortcutMap.forUser(TargetPlatform.macOS);
      expect(AppCommand.values.every(map.isAvailable), isTrue);
    });
  });

  group('Terminal keys', () {
    Set<AppCommand> commandsOf(ShortcutMap map, TargetPlatform platform) => {
      for (final intent in map.terminalShortcuts(platform).values)
        intent.command,
    };

    for (final platform in TargetPlatform.values) {
      test('its own keys and its place in the window on $platform', () {
        final map = ShortcutMap.defaults(platform);
        final commands = commandsOf(map, platform);
        expect(
          commands,
          containsAll([
            ...AppCommand.inScope(CommandScope.terminal),
            ...ShortcutMap.terminalPlacement,
            // Its menu opens from the keyboard too.
            AppCommand.contextMenu,
          ]),
        );
        // A panel's single keys never leave the terminal.
        expect(
          commands.where((c) => c.scope == CommandScope.panel),
          isEmpty,
        );
        for (final command in AppCommand.inScope(CommandScope.terminal)) {
          expect(map.chordsFor(command), isNotEmpty, reason: '$command');
        }
      });
    }

    test('on macOS the window keeps its ⌘ chords, the shell its ⌃ ones', () {
      const mac = TargetPlatform.macOS;
      final commands = commandsOf(ShortcutMap.defaults(mac), mac);
      expect(commands, contains(AppCommand.focusLeftPanel));
      expect(commands, contains(AppCommand.openSettings));
      expect(commands, contains(AppCommand.newTab));
      // ⌃A and ⌃M are the line's start and Return to a shell.
      expect(commands, isNot(contains(AppCommand.fileAttributes)));
      expect(commands, isNot(contains(AppCommand.batchRename)));
      // F5 and Tab are a program's.
      expect(commands, isNot(contains(AppCommand.copyTo)));
    });

    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      test('on $platform Ctrl+letter is the shell\'s, Ctrl+Shift the '
          'window\'s', () {
        final map = ShortcutMap.defaults(platform);
        final commands = commandsOf(map, platform);
        // Ctrl+R, Ctrl+W, Ctrl+D, Ctrl+U: reverse search, delete a word,
        // end of input, kill the line.
        expect(commands, isNot(contains(AppCommand.refresh)));
        expect(commands, isNot(contains(AppCommand.closeTab)));
        expect(commands, isNot(contains(AppCommand.duplicate)));
        expect(commands, isNot(contains(AppCommand.swapPanels)));
        expect(commands, contains(AppCommand.focusLeftPanel));
        expect(commands, contains(AppCommand.newFolder));
        // Inside the terminal Ctrl+Shift+C copies its text, not a path.
        final copy = map
            .terminalShortcuts(platform)
            .entries
            .firstWhere((e) => e.value.command == AppCommand.terminalCopy);
        final first = map
            .terminalShortcuts(platform)
            .entries
            .firstWhere(
              (e) =>
                  e.key is SingleActivator &&
                  (e.key as SingleActivator).trigger ==
                      LogicalKeyboardKey.keyC &&
                  (e.key as SingleActivator).shift,
            );
        expect(first.value.command, copy.value.command);
      });
    }

    test('a chord reaches the window from the terminal by its modifiers', () {
      const k = LogicalKeyboardKey.keyK;
      expect(
        const Chord(k, primary: true).reachesWindowFromTerminal(
          TargetPlatform.macOS,
        ),
        isTrue,
      );
      expect(
        const Chord(k, control: true).reachesWindowFromTerminal(
          TargetPlatform.macOS,
        ),
        isFalse,
      );
      expect(
        const Chord(k, primary: true).reachesWindowFromTerminal(
          TargetPlatform.linux,
        ),
        isFalse,
      );
      expect(
        const Chord(k, primary: true, shift: true).reachesWindowFromTerminal(
          TargetPlatform.linux,
        ),
        isTrue,
      );
      expect(
        const Chord(
          k,
          primary: true,
          shift: true,
          alt: true,
        ).reachesWindowFromTerminal(TargetPlatform.windows),
        isFalse,
      );
      expect(
        const Chord(LogicalKeyboardKey.f5).reachesWindowFromTerminal(
          TargetPlatform.macOS,
        ),
        isFalse,
      );
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

  group('Interface commands', () {
    test('every command has a section; blocks keep their own', () {
      expect(AppCommand.newFolder.section, CommandSection.file);
      expect(AppCommand.findFiles.section, CommandSection.file);
      expect(AppCommand.copyPaths.section, CommandSection.edit);
      expect(AppCommand.refresh.section, CommandSection.view);
      expect(AppCommand.goToFolder.section, CommandSection.go);
      expect(AppCommand.openWith.section, CommandSection.command);
      expect(AppCommand.contextMenu.section, CommandSection.window);
      expect(AppCommand.commandPalette.section, CommandSection.window);
      expect(AppCommand.jumpToFolder.section, CommandSection.go);
      expect(AppCommand.addToShelf.section, CommandSection.edit);
      expect(AppCommand.renameInEditor.section, CommandSection.command);
      expect(AppCommand.quickLook.section, CommandSection.file);
      expect(AppCommand.share.section, CommandSection.file);
      expect(AppCommand.toggleTerminal.section, CommandSection.terminal);
      expect(AppCommand.undo.section, CommandSection.edit);
      expect(AppCommand.extractTo.section, CommandSection.file);
      expect(AppCommand.toggleFlatView.section, CommandSection.view);
      expect(AppCommand.checksums.section, CommandSection.command);
      expect(
        AppCommand.terminalScrollPageDown.section,
        CommandSection.terminal,
      );
      expect(AppCommand.moveDown.section, CommandSection.panel);
      expect(AppCommand.vimReselect.section, CommandSection.vim);
      expect(AppCommand.viewerFind.section, CommandSection.viewer);
      expect(AppCommand.filterList.section, CommandSection.lists);
      expect(AppCommand.dismiss.section, CommandSection.dialogs);
    });

    test('the chords and Vim keys of the palette, the jump, the shelf and '
        'the names editor', () {
      final map = ShortcutMap.forUser(TargetPlatform.macOS, vimMotions: true);
      String? label(AppCommand command, {bool vim = false}) =>
          map.labelOf(command, TargetPlatform.macOS, vim: vim);
      expect(label(AppCommand.commandPalette), '⌘P');
      expect(label(AppCommand.jumpToFolder), '⌘G');
      expect(label(AppCommand.jumpToFolder, vim: true), 'gj');
      expect(label(AppCommand.addToShelf), '⌥⌘S');
      expect(label(AppCommand.addToShelf, vim: true), 'ys');
      expect(label(AppCommand.toggleShelf), '⌃⌘S');
      expect(label(AppCommand.toggleShelf, vim: true), 'gs');
      expect(label(AppCommand.renameInEditor), '⌃⇧M');
      expect(label(AppCommand.renameInEditor, vim: true), 'cn');
      expect(
        ShortcutMap.defaults(
          TargetPlatform.windows,
        ).labelOf(AppCommand.commandPalette, TargetPlatform.windows),
        'Ctrl+P',
      );
    });
  });

  testWidgets('commandsAt answers every command the scopes above handle', (
    tester,
  ) async {
    late BuildContext inner;
    late BuildContext outer;
    await tester.pumpWidget(
      CommandHandlers(
        handlers: {AppCommand.refresh: () {}, AppCommand.copyTo: () {}},
        child: Builder(
          builder: (context) {
            outer = context;
            return CommandHandlers(
              handlers: {AppCommand.moveDown: () {}, AppCommand.copyTo: () {}},
              child: Builder(
                builder: (context) {
                  inner = context;
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      ),
    );
    expect(commandsAt(inner), {
      AppCommand.moveDown,
      AppCommand.copyTo,
      AppCommand.refresh,
    });
    expect(commandsAt(outer), {AppCommand.refresh, AppCommand.copyTo});
  });

  testWidgets('a prefix key is text in a text field, a prefix elsewhere', (
    tester,
  ) async {
    final reached = <AppCommand>[];
    final field = FocusNode();
    final plain = FocusNode();
    final controller = TextEditingController();
    final map = ShortcutMap.forUser(TargetPlatform.macOS, vimMotions: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandShortcuts(
            shortcuts: map.toShortcuts(
              TargetPlatform.macOS,
              scopes: const {CommandScope.global},
            ),
            child: CommandHandlers(
              handlers: {
                AppCommand.jumpToFolder: () => reached.add(
                  AppCommand.jumpToFolder,
                ),
              },
              child: Column(
                children: [
                  TextField(controller: controller, focusNode: field),
                  Focus(focusNode: plain, child: const SizedBox(height: 10)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    field.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    expect(KeySequenceState.pending, isNull);
    plain.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    expect(reached, [AppCommand.jumpToFolder]);
    field.dispose();
    plain.dispose();
    controller.dispose();
  });

  testWidgets('a window sequence whose second key is a panel key completes '
      'from inside the panel', (tester) async {
    final map = ShortcutMap.forUser(TargetPlatform.macOS, vimMotions: true);
    final ran = <AppCommand>[];
    final focus = FocusNode();
    void record(AppCommand command) => ran.add(command);
    await tester.pumpWidget(
      MaterialApp(
        home: CommandShortcuts(
          shortcuts: map.toShortcuts(
            TargetPlatform.macOS,
            scopes: const {CommandScope.global},
          ),
          child: CommandHandlers(
            handlers: {
              for (final command in [
                AppCommand.newTab,
                AppCommand.jumpToFolder,
                AppCommand.goToFolder,
                AppCommand.renameInEditor,
              ])
                command: () => record(command),
            },
            child: CommandShortcuts(
              shortcuts: map.toShortcuts(
                TargetPlatform.macOS,
                scopes: const {CommandScope.panel},
                sequencesOf: const {CommandScope.global},
              ),
              child: CommandHandlers(
                handlers: {
                  for (final command in [
                    AppCommand.vimSearchNext,
                    AppCommand.moveDown,
                    AppCommand.moveFirst,
                    AppCommand.vimCut,
                  ])
                    command: () => record(command),
                },
                child: Focus(
                  focusNode: focus,
                  autofocus: true,
                  child: const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    Future<void> press(List<LogicalKeyboardKey> keys) async {
      for (final key in keys) {
        await tester.sendKeyEvent(key, platform: 'macos');
      }
    }

    const g = LogicalKeyboardKey.keyG;
    const c = LogicalKeyboardKey.keyC;
    const d = LogicalKeyboardKey.keyD;
    await press([g, LogicalKeyboardKey.keyN]);
    await press([g, LogicalKeyboardKey.keyJ]);
    await press([c, d]);
    await press([c, LogicalKeyboardKey.keyN]);
    await press([g, g]);
    await press([d, d]);
    await press([LogicalKeyboardKey.keyN, LogicalKeyboardKey.keyJ]);
    expect(ran, [
      AppCommand.newTab,
      AppCommand.jumpToFolder,
      AppCommand.goToFolder,
      AppCommand.renameInEditor,
      AppCommand.moveFirst,
      AppCommand.vimCut,
      AppCommand.vimSearchNext,
      AppCommand.moveDown,
    ]);
    focus.dispose();
  });

  // ─── Network ───
  group('Connect to Server', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      test(
        "is the window's primary K, the terminal keeps its own on $platform",
        () {
          final map = ShortcutMap.defaults(platform);
          const k = Chord(LogicalKeyboardKey.keyK, primary: true);
          expect(map.chordsFor(AppCommand.connectToServer), [k]);
          expect(map.commandFor(k), AppCommand.connectToServer);
          expect(map.chordsFor(AppCommand.disconnectServer), isEmpty);
          expect(AppCommand.connectToServer.section, CommandSection.go);
          // Inside the terminal its own keys come first, so they win over
          // the window's of the same keys: ⌘K clears on macOS. Elsewhere
          // Ctrl+K is the shell's (kill to the end of the line).
          final inside = [
            for (final entry in map.terminalShortcuts(platform).entries)
              if (entry.key is SingleActivator &&
                  (entry.key as SingleActivator).trigger ==
                      LogicalKeyboardKey.keyK &&
                  !(entry.key as SingleActivator).shift)
                entry.value.command,
          ];
          if (platform == TargetPlatform.macOS) {
            expect(inside.first, AppCommand.terminalClear);
          } else {
            expect(inside, isNot(contains(AppCommand.connectToServer)));
          }
        },
      );
    }
  });
}
