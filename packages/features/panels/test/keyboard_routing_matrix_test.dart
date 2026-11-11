import 'package:component_library/component_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support/workspace_harness.dart';

Future<void> _pressChord(
  WidgetTester tester,
  Chord chord,
  TargetPlatform platform,
) async {
  final name = platform == TargetPlatform.macOS
      ? 'macos'
      : platform == TargetPlatform.windows
      ? 'windows'
      : 'linux';
  if (chord.prefix case final prefix?) {
    await tester.sendKeyEvent(
      prefix,
      platform: name,
      character: prefix.keyLabel.toLowerCase(),
    );
    await tester.pump();
  }
  final activator = chord.toActivator(platform);
  final modifiers = [
    if (activator.meta) LogicalKeyboardKey.metaLeft,
    if (activator.control) LogicalKeyboardKey.controlLeft,
    if (activator.alt) LogicalKeyboardKey.altLeft,
    if (activator.shift) LogicalKeyboardKey.shiftLeft,
  ];
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier, platform: name);
  }
  final key = chord.shift
      ? Chord.shiftedKeys[chord.key] ?? chord.key
      : chord.key;
  final label = key == LogicalKeyboardKey.space ? ' ' : key.keyLabel;
  final character = label.runes.length == 1
      ? chord.shift
            ? label.toUpperCase()
            : label.toLowerCase()
      : null;
  await tester.sendKeyEvent(
    chord.key,
    // The raw simulator omits apostrophe on Windows/Linux; its logical
    // event is identical. Modifiers and the app's desktop map still vary.
    platform: chord.key == LogicalKeyboardKey.quoteSingle ? 'macos' : name,
    character: character,
    physicalKey: chord.key == LogicalKeyboardKey.quoteSingle
        ? PhysicalKeyboardKey.quote
        : null,
  );
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier, platform: name);
  }
  await tester.pump();
}

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    for (final vim in [false, true]) {
      testWidgets(
        '${platform.name}, Vim=$vim: every available file-panel chord reaches its command',
        (tester) async {
          final h = WorkspaceHarness(platform: platform);
          await h.setUp(vim: vim);
          addTearDown(h.tearDown);
          await h.pump(
            tester,
            style: platform == TargetPlatform.macOS
                ? AppPlatformStyle.macos
                : platform == TargetPlatform.windows
                ? AppPlatformStyle.windows
                : AppPlatformStyle.gnome,
          );
          final target = tester
              .widget<PanelView>(find.byType(PanelView).first)
              .focusNode;
          final available = commandsAt(target.context!);
          final reached = <AppCommand>[];
          CommandDispatcherAction.debugReached = (command) {
            reached.add(command);
            return true;
          };
          addTearDown(() {
            CommandDispatcherAction.debugReached = null;
            KeySequenceState.clear();
          });
          var checked = 0;
          for (final entry in h.shortcutMap.bindings.entries) {
            if (!available.contains(entry.key) ||
                !{
                  CommandScope.global,
                  CommandScope.panel,
                }.contains(entry.key.scope)) {
              continue;
            }
            for (final chord in entry.value) {
              KeySequenceState.clear();
              reached.clear();
              await _pressChord(tester, chord, platform);
              expect(reached, [
                entry.key,
              ], reason: '${entry.key}: ${chord.label(platform)} (Vim=$vim)');
              checked++;
            }
          }
          expect(checked, greaterThan(100));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
