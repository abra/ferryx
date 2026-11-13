import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/src/panel/vim_command_line.dart';
import 'package:shortcuts/shortcuts.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Future<List<String>> Function(String) complete,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Scaffold(
          body: VimCommandLine(
            shortcutMap: ShortcutMap.forUser(
              TargetPlatform.macOS,
              vimMotions: true,
            ),
            history: const ['first', 'second'],
            onRun: (_) {},
            onCancel: () {},
            complete: complete,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String text(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).controller.text;
  Future<void> tab(WidgetTester tester, {bool reverse = false}) async {
    if (reverse) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (reverse) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  testWidgets(
    'one pending request serves repeated Tab; Shift+Tab cycles back',
    (tester) async {
      final result = Completer<List<String>>();
      var calls = 0;
      await open(tester, (_) {
        calls++;
        return result.future;
      });
      await tester.enterText(find.byType(AppTextField), 'cd /');
      await tab(tester);
      await tab(tester);
      expect(calls, 1);
      result.complete(['cd /one', 'cd /two', 'cd /three']);
      await tester.pump();
      expect(text(tester), 'cd /two');
      await tab(tester, reverse: true);
      expect(text(tester), 'cd /one');
    },
  );
  testWidgets(
    'late completions never overwrite new text; latest Tab is retried',
    (tester) async {
      final old = Completer<List<String>>(), fresh = Completer<List<String>>();
      final calls = <String>[];
      await open(tester, (query) {
        calls.add(query);
        return calls.length == 1 ? old.future : fresh.future;
      });
      await tester.enterText(find.byType(AppTextField), 'cd /old');
      await tab(tester);
      await tester.enterText(find.byType(AppTextField), 'cd /new');
      await tab(tester);
      old.complete(['cd /old/stale']);
      await tester.pump();
      expect(text(tester), 'cd /new');
      expect(calls, ['cd /old', 'cd /new']);
      fresh.complete(['cd /new/current']);
      await tester.pump();
      expect(text(tester), 'cd /new/current');
    },
  );
  testWidgets('history restores an unfinished draft', (tester) async {
    await open(tester, (_) async => []);
    await tester.enterText(find.byType(AppTextField), 'my draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(text(tester), 'second');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(text(tester), 'my draft');
  });
  testWidgets('completion failure preserves input and offers feedback', (
    tester,
  ) async {
    await open(tester, (_) async => throw StateError('unavailable'));
    await tester.enterText(find.byType(AppTextField), 'cd /');
    await tab(tester);
    await tester.pump();
    expect(text(tester), 'cd /');
    expect(tester.takeException(), isNull);
    expect(
      find.text(
        lookupFerryxLocalizations(const Locale('en')).vimCompletionFailed,
      ),
      findsOneWidget,
    );
  });
}
