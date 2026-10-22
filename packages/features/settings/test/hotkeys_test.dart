import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settings_feature/settings_feature.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support.dart';

void main() {
  testWidgets('records a chord for a command, refuses one in use, resets', (
    tester,
  ) async {
    final service = await testPreferences();
    await pumpScreen(
      tester,
      SettingsScreen(
        preferencesService: service,
        platform: TargetPlatform.macOS,
        version: '0.1.0',
        initialSection: SettingsSection.hotkeys,
        onClose: () {},
      ),
    );
    await tester.enterText(find.byType(AppSearchField).last, 'copy to');
    await tester.pumpAndSettle();
    final row = find.ancestor(
      of: find.text(en.cmdCopyTo),
      matching: find.byType(Container),
    );
    expect(row, findsWidgets);
    expect(find.text('F5'), findsOneWidget);
    final capsBefore = find.byType(AppKeyCaps).evaluate().length;

    // A click focuses the row; Return records a new key for it.
    await tester.tap(find.text(en.cmdCopyTo));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(en.hotkeysRecord), findsOneWidget);

    // ⌘R is Refresh already: a warning, and the key can be taken over.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text(en.hotkeysConflict(en.cmdRefresh)), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, en.hotkeysReassign),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, en.actionSave), findsNothing);

    // ⌃⇧F5 is free.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text(en.hotkeysConflict(en.cmdRefresh)), findsNothing);
    await tester.tap(find.text(en.actionSave));
    await tester.pumpAndSettle();
    expect(service.current.shortcutOverrides[AppCommand.copyTo.name], [
      ChordCodec.encode(
        const Chord(LogicalKeyboardKey.f5, control: true, shift: true),
      ),
    ]);
    // The modifiers are drawn as icons; the cap's text is the key.
    expect(find.text('F5'), findsOneWidget);
    expect(find.byType(AppKeyCaps).evaluate().length, capsBefore);

    // Restore defaults clears every override.
    await tester.tap(find.text(en.hotkeysReset));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.actionReset));
    await tester.pumpAndSettle();
    expect(service.current.shortcutOverrides, isEmpty);
    expect(find.text('F5'), findsOneWidget);
  });

  testWidgets('taking a key in use moves it from the other command, and '
      'Delete removes a key', (tester) async {
    final service = await testPreferences();
    await pumpScreen(
      tester,
      SettingsScreen(
        preferencesService: service,
        platform: TargetPlatform.macOS,
        version: '0.1.0',
        initialSection: SettingsSection.hotkeys,
        onClose: () {},
      ),
    );
    await tester.enterText(find.byType(AppSearchField).last, 'copy to');
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.cmdCopyTo));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.hotkeysReassign));
    await tester.pumpAndSettle();
    const taken = Chord(LogicalKeyboardKey.keyR, primary: true);
    final overrides = service.current.shortcutOverrides;
    expect(overrides[AppCommand.copyTo.name], [ChordCodec.encode(taken)]);
    expect(
      overrides[AppCommand.refresh.name],
      isNot(contains(ChordCodec.encode(taken))),
    );

    // The row still has the focus: Backspace leaves the command unbound.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(service.current.shortcutOverrides[AppCommand.copyTo.name], isEmpty);
    expect(find.text(en.hotkeysUnbound), findsOneWidget);
  });

  test('chordOfEvent reads the modifiers of the platform', () {
    expect(
      chordOfEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          logicalKey: LogicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
        TargetPlatform.macOS,
      ),
      isNull,
    );
    expect(
      chordOfEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
        TargetPlatform.windows,
      ),
      const Chord(LogicalKeyboardKey.keyA),
    );
  });
}
