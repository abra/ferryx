import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settings_feature/settings_feature.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support.dart';

void main() {
  testWidgets('lists every bound command by scope and closes on Esc', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => showCheatSheet(
              context,
              shortcutMap: ShortcutMap.defaults(TargetPlatform.macOS),
              platform: TargetPlatform.macOS,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(en.cheatSheetTitle), findsOneWidget);
    expect(find.text(en.scopeGlobal), findsOneWidget);
    expect(find.text(en.cmdCopyTo), findsOneWidget);
    // ⇧F5 draws its ⇧ as an icon, so its cap holds a second "F5".
    expect(find.text('F5'), findsNWidgets(2));
    // A command without a chord is left out.
    expect(find.text(en.cmdGoLibrary), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(en.cheatSheetTitle), findsNothing);
  });

  testWidgets('leaves out the commands this desktop cannot run', (
    tester,
  ) async {
    Future<void> open(ShortcutMap map) async {
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showCheatSheet(
                context,
                shortcutMap: map,
                platform: TargetPlatform.macOS,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await open(ShortcutMap.forUser(TargetPlatform.macOS));
    expect(find.text(en.cmdQuickLook), findsOneWidget);
    expect(find.text(en.cmdShare), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await open(
      ShortcutMap.forUser(
        TargetPlatform.macOS,
        unavailable: const {AppCommand.quickLook, AppCommand.share},
      ),
    );
    expect(find.text(en.cmdQuickLook), findsNothing);
    expect(find.text(en.cmdShare), findsNothing);
    expect(find.text(en.cmdPreview), findsWidgets);
  });
}
